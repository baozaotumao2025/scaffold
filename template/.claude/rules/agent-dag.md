---
paths:
  - "agent/**"
---

# Agent DAG 编排与异常体系

SessionState 聚合根、DAG 节点表、runner 协调器（含 checkpoint 恢复与写入点）以及异常体系与传播规则。

> 下文以一条「会话→LLM 处理→结果」的通用流水线作示范，仅占位；节点与状态按你的业务替换，DAG 结构、checkpoint 与异常规则不变。

## DAG 编排（dag/）

### SessionState（domain/state.py，聚合根状态）

> 属领域层：是会话聚合根的状态载体，封装状态机不变量（如合法的 status 迁移），纯逻辑零 IO。

```python
@dataclass
class SessionState:
    session_id: str
    work_dir: Path
    input_payload: dict | None = None
    result_path: Path | None = None
    status: Literal[
        "idle", "intake", "processing", "validating",
        "finalizing", "done", "revising", "error"
    ] = "idle"
    error_message: str | None = None
```

### DAG 节点（dag/nodes.py）

节点签名统一：
```python
async def node_xxx(state: SessionState, send: Callable, recv_queue: asyncio.Queue) -> SessionState
```

| 节点 | 触发条件 | 行为 |
|------|---------|------|
| `session_start` | 收到 `start_session` | 创建 work_dir，启动 LLM 会话（PTY 或 API），就绪检查 |
| `intake` | 会话就绪后 | 收集/校验输入；用户 `user_input` → 转交 LLM |
| `process` | 输入就绪 | 调 LLM 产出结果，流式推 `log` 进度 |
| `validate` | `process` 完成 | 业务规则校验产出，不合规则回错误或重试 |
| `finalize` | `validate` 通过 | 落地最终结果文件，推 `result_ready` |
| `revise_loop` | `done` 状态下收到 `user_input` | 转交 LLM → 重进 `process` |

### DAG 协调器（dag/runner.py）

`runner.py` 有两个职责：**恢复入口**（连接建立时检查 checkpoint）和**正常流程**（串联所有节点）。

```python
async def run_session(state: SessionState, send, recv_queue: asyncio.Queue,
                      checkpoint: dict | None = None):
    try:
        # ── 断点恢复入口 ──────────────────────────────────────────────
        if checkpoint:
            resume_status = checkpoint.get("status")

            if resume_status == "done":
                # 完全恢复：直接推送已有结果，无需任何 LLM 调用
                state.result_path = Path(checkpoint["result_path"])
                await send({"type": "result_ready", "session_id": state.session_id})
                await send({"type": "done"})
                # 进入 revise 循环等待用户继续
                await _revise_loop(state, send, recv_queue)
                return

            if resume_status in ("validating", "finalizing"):
                # 中间产物已在磁盘，跳过 LLM，直接从校验节点恢复
                state.result_path = Path(checkpoint["result_path"])
                state.status = "validating"
                logger.info("Resuming from checkpoint | status={}", resume_status)
                state = await validate(state, send)         # ← checkpoint 写入点 A
                state = await finalize(state, send)          # ← checkpoint 写入点 B
                await send({"type": "done"})
                await _revise_loop(state, send, recv_queue)
                return

            # intake / processing / error：无法恢复，LLM 会话已死
            await send({"type": "checkpoint_lost",
                        "message": "上次会话在处理过程中中断，需要重新开始"})

        # ── 正常流程 ──────────────────────────────────────────────────
        state = await session_start(state, send, recv_queue)
        state = await intake(state, send, recv_queue)
        state = await process(state, send, recv_queue)
        state = await validate(state, send)                 # ← checkpoint 写入点 A
        state = await finalize(state, send)                 # ← checkpoint 写入点 B
        await send({"type": "done"})
        await _revise_loop(state, send, recv_queue)

    except AgentException as e:
        logger.error("DAG error | code={} msg={}", e.code, e.message)
        await send({"type": "error", "code": e.code, "message": e.message})
    except Exception as e:
        logger.exception("Unexpected DAG error")
        await send({"type": "error", "code": "INTERNAL_ERROR", "message": str(e)})
    finally:
        cleanup_session(state)


async def _revise_loop(state, send, recv_queue):
    while True:
        msg = await recv_queue.get()
        if msg["type"] == "user_input":
            state = await revise_loop(state, send, recv_queue, msg["text"])
            state = await validate(state, send)             # ← checkpoint 写入点 A
            state = await finalize(state, send)             # ← checkpoint 写入点 B
            await send({"type": "done"})
```

### Checkpoint 写入点

`validate` 和 `finalize` 节点完成后，通过推送特定消息触发 Backend 写入 DB：

| 写入点 | 节点 | 推送消息（Backend 监听后写 DB） |
|--------|------|---------------------------------|
| A | `validate` 完成 | `{"type": "validated", "result_path": "..."}` |
| B | `finalize` 完成 | `{"type": "result_ready", "result_path": "..."}` |
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

class LLMStartupError(AgentException):
    def __init__(self):
        super().__init__("LLM_STARTUP_ERROR", "LLM 启动/连接失败")

class ExternalServiceTimeoutError(AgentException):
    def __init__(self, phase: str):
        super().__init__("EXTERNAL_SERVICE_TIMEOUT", f"外部依赖在 {phase} 阶段超时")

class ExternalServiceError(AgentException):
    def __init__(self, detail: str):
        super().__init__("EXTERNAL_SERVICE_ERROR", f"外部依赖返回错误: {detail}")

class OutputValidationError(AgentException):
    def __init__(self):
        super().__init__("INVALID_INPUT", "无法从输出中提取有效结果")
```

### 异常传播规则

- DAG 节点内捕获异常 → 更新 `state.status = "error"` → 通过 `send({"type": "error", "message": ...})` 推送给前端 → 抛给 runner
- Runner 捕获 → 记录日志 → 关闭 LLM 会话 → 清理资源
- **禁止在节点内静默 swallow 异常**
