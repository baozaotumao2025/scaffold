---
paths:
  - "agent/**"
---

# Agent LLM 驱动层与 PTY 桥接

厂商无关的 LLM CLI 抽象、PTY 伪终端桥接机制、超时保护与输出拦截检测。

## LLM CLI 驱动层（llm/）

厂商无关的抽象。`LLMSession` 端口定义在 `domain/ports.py`，本目录只放适配器实现。DAG 节点只依赖端口，不感知具体厂商。

| 文件 | 职责 |
|------|------|
| `domain/ports.py` | `LLMSession` 协议（端口，接口定义） |
| `pty_bridge.py` | 共享 PTY 机制（所有 CLI 厂商复用） |
| `gemini_cli.py` | `GeminiCliSession`：gemini 命令 + prompt 约定 + 输出提取 |

**扩展新厂商**：新增 `claude_cli.py` 等实现 `LLMSession` 端口即可，PTY 机制无需重写。

> 注意：当前只支持 **PTY 驱动的交互式 CLI**。若未来要接入直接 API 调用（SDK），那是不同机制，应另开 `llm/api/` 子目录，不要塞进 PTY 层。

## LLMSession 协议（domain/ports.py）

```python
class LLMSession(Protocol):
    async def start(self) -> None: ...                       # 启动 CLI 进程
    async def send(self, text: str) -> None: ...             # 写入用户输入
    async def stream_until(self, predicate) -> str: ...      # 流式读取直到满足条件
    async def close(self) -> None: ...                       # 关闭进程，清理资源
```

## PTY 桥接（pty_bridge.py）

### 原理

```
master_fd ──读──► 解析输出 ──► WebSocket 推送
master_fd ──写◄── WebSocket 收到用户输入
slave_fd  ──────► CLI 进程 stdin/stdout（认为自己在真实终端）
```

### 关键实现

**启动进程：**
```python
master_fd, slave_fd = pty.openpty()
proc = await asyncio.create_subprocess_exec(
    'gemini',
    stdin=slave_fd, stdout=slave_fd, stderr=slave_fd,
    env={**os.environ, 'TERM': 'xterm-256color'},
)
os.close(slave_fd)  # 父进程关闭 slave，只用 master
```

**异步读取（事件驱动，非阻塞 fd + add_reader，零线程）：**
```python
os.set_blocking(master_fd, False)
loop.add_reader(master_fd, on_pty_readable)   # 详见「并发模型」章节
```
> 不要用 thread-per-session 的阻塞 `os.read`，会话多时线程池会被打爆。

**ANSI 转义码过滤（推送前必须清洗，实现在 `utils/ansi.py`）：**
```python
ANSI_ESCAPE = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
clean_text = ANSI_ESCAPE.sub('', raw_text)
```

**写入用户输入：**
```python
os.write(master_fd, (user_text + '\n').encode('utf-8'))
```

### 超时保护

每个 DAG 阶段设置独立超时（`asyncio.wait_for`），阶段为示范：

| 阶段 | 超时 |
|------|------|
| intake（收集输入） | 60s |
| process（LLM 处理输出） | 300s |

超时后抛 `ExternalServiceTimeoutError`。

## 输出拦截检测

CLI 输出是流式文本，需按约定标记从中提取结构化结果。下面以提取代码块为例（按你的输出约定替换正则）：

```python
def detect_output(text: str) -> str | None:
    m = re.search(r'```result\s*([\s\S]+?)```', text, re.IGNORECASE)
    return m.group(1).strip() if m else None
```

根据 `state.status` 决定处理：
- `"processing"` → 提取到结果即保存产物，推送 `result_ready`，触发后续节点
