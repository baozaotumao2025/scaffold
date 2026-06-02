---
paths:
  - "agent/**"
---

# Agent DAG 编排与异常体系

PresentationState 聚合根、DAG 节点表、runner 协调器（含 checkpoint 恢复与写入点）以及异常体系与传播规则。

## DAG 编排（dag/）

### PresentationState（domain/state.py，聚合根状态）

> 属领域层：是会话聚合根的状态载体，封装状态机不变量（如合法的 status 迁移），纯逻辑零 IO。

```python
@dataclass
class PresentationState:
    session_id: str
    work_dir: Path
    html_path: Path | None = None
    pptx_path: Path | None = None
    preview_paths: list[Path] = field(default_factory=list)
    image_source: str = ""
    image_api_key: str = ""
    status: Literal[
        "idle", "dialog", "previewing", "generating",
        "screenshotting", "synthesizing", "done", "refining", "error"
    ] = "idle"
    error_message: str | None = None
```

### DAG 节点（dag/nodes.py）

节点签名统一：
```python
async def node_xxx(state: PresentationState, send: Callable, recv_queue: asyncio.Queue) -> PresentationState
```

| 节点 | 触发条件 | 行为 |
|------|---------|------|
| `session_start` | 收到 `start_session` | 创建 work_dir，启动 PTY，skill 检查 |
| `phase1_dialog` | PTY 启动后 | 透传对话消息；用户 `user_input` → 写 stdin |
| `phase2_preview` | 检测到首个预览 HTML | 拦截 3 个 HTML → 推 `style_preview`；`style_pick` → 写 stdin |
| `phase3_generate` | 用户选风格 | 监听 PTY 直到完整 HTML；保存 `slides.html` |
| `screenshot` | `html_ready` 后自动 | Playwright 截图，逐页推 `log` 进度 |
| `synthesize` | `screenshot` 完成 | python-pptx 合成，推 `pptx_ready` |
| `refine_loop` | `done` 状态下收到 `user_input` | 写 PTY stdin → 重进 `phase3_generate` |

### DAG 协调器（dag/runner.py）

`runner.py` 有两个职责：**恢复入口**（连接建立时检查 checkpoint）和**正常流程**（串联所有节点）。

```python
async def run_session(state: PresentationState, send, recv_queue: asyncio.Queue,
                      checkpoint: dict | None = None):
    try:
        # ── 断点恢复入口 ──────────────────────────────────────────────
        if checkpoint:
            resume_status = checkpoint.get("status")

            if resume_status == "done":
                # 完全恢复：直接推送已有结果，无需任何 Gemini 调用
                state.html_path = Path(checkpoint["html_path"])
                state.pptx_path = Path(checkpoint["pptx_path"])
                await send({"type": "html_ready",  "session_id": state.session_id})
                await send({"type": "pptx_ready",  "session_id": state.session_id})
                await send({"type": "done"})
                # 进入 refine 循环等待用户继续
                await _refine_loop(state, send, recv_queue)
                return

            if resume_status in ("screenshotting", "synthesizing"):
                # slides.html 已在磁盘，跳过 Gemini，直接从截图节点恢复
                state.html_path = Path(checkpoint["html_path"])
                state.status = "screenshotting"
                logger.info("Resuming from checkpoint | status={}", resume_status)
                state = await screenshot(state, send)       # ← checkpoint 写入点 A
                state = await synthesize(state, send)       # ← checkpoint 写入点 B
                await send({"type": "done"})
                await _refine_loop(state, send, recv_queue)
                return

            # dialog / generating / error：无法恢复，PTY 已死
            await send({"type": "checkpoint_lost",
                        "message": "上次会话在生成过程中中断，需要重新开始"})

        # ── 正常流程 ──────────────────────────────────────────────────
        state = await session_start(state, send, recv_queue)
        state = await phase1_dialog(state, send, recv_queue)
        state = await phase2_preview(state, send, recv_queue)
        state = await phase3_generate(state, send, recv_queue)
        state = await screenshot(state, send)               # ← checkpoint 写入点 A
        state = await synthesize(state, send)               # ← checkpoint 写入点 B
        await send({"type": "done"})
        await _refine_loop(state, send, recv_queue)

    except AgentException as e:
        logger.error("DAG error | code={} msg={}", e.code, e.message)
        await send({"type": "error", "code": e.code, "message": e.message})
    except Exception as e:
        logger.exception("Unexpected DAG error")
        await send({"type": "error", "code": "INTERNAL_ERROR", "message": str(e)})
    finally:
        cleanup_pty(state)


async def _refine_loop(state, send, recv_queue):
    while True:
        msg = await recv_queue.get()
        if msg["type"] == "user_input":
            state = await refine_loop(state, send, recv_queue, msg["text"])
            state = await screenshot(state, send)           # ← checkpoint 写入点 A
            state = await synthesize(state, send)           # ← checkpoint 写入点 B
            await send({"type": "done"})
```

### Checkpoint 写入点

`screenshot` 和 `synthesize` 节点完成后，通过推送特定消息触发 Backend 写入 DB：

| 写入点 | 节点 | 推送消息（Backend 监听后写 DB） |
|--------|------|---------------------------------|
| A | `screenshot` 完成 | `{"type": "html_ready", "html_path": "..."}` |
| B | `synthesize` 完成 | `{"type": "pptx_ready", "pptx_path": "..."}` |
| — | `done` | `{"type": "done"}` → Backend 将 status 更新为 `"done"` |

**checkpoint 写入由 Backend 负责（监听 Agent 推送的消息），Agent 只负责推送正确的消息。**

## 异常体系（domain/exceptions.py）

异常类型是**领域错误词汇**（统一语言的一部分，且 `code` 对应错误码契约 `error-codes.md`），故归领域层 `domain/exceptions.py`，由 domain 拥有。框架级的 `exception_handler` 注册属接口/基础设施关注点，放 `middleware/error_handler.py`，不污染 domain 的纯净（零框架/IO 依赖）。

### domain/exceptions.py

```python
class AgentException(Exception):
    def __init__(self, code: str, message: str, status_code: int = 500):
        self.code = code
        self.message = message
        self.status_code = status_code

class GeminiStartupError(AgentException):
    def __init__(self):
        super().__init__("GEMINI_STARTUP_ERROR", "Gemini CLI 启动失败")

class GeminiTimeoutError(AgentException):
    def __init__(self, phase: str):
        super().__init__("GEMINI_TIMEOUT", f"Gemini 在 {phase} 阶段超时")

class SkillNotInstalledError(AgentException):
    def __init__(self):
        super().__init__("SKILL_NOT_INSTALLED", "skill 未安装")

class PlaywrightError(AgentException):
    def __init__(self, detail: str):
        super().__init__("PLAYWRIGHT_ERROR", f"截图失败: {detail}")

class HtmlExtractionError(AgentException):
    def __init__(self):
        super().__init__("HTML_EXTRACTION_FAILED", "无法从 Gemini 输出中提取有效 HTML")
```

### 异常传播规则

- DAG 节点内捕获异常 → 更新 `state.status = "error"` → 通过 `send({"type": "error", "message": ...})` 推送给前端 → 抛给 runner
- Runner 捕获 → 记录日志 → 关闭 PTY → 清理资源
- **禁止在节点内静默 swallow 异常**
