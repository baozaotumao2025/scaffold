---
paths:
  - "agent/**"
---

# Agent LLM 驱动层与 API 桥接

厂商无关的 LLM API 抽象、HTTP SDK 集成机制、超时保护与流式响应处理。

## 重要：LLMSession 端口是协议，不是机制

- `LLMSession` Protocol 只定义"能力"（发消息、收推送流、关闭），不规定底层是哪家 SDK
- 本文件描述 API SDK 适配器实现模式（OpenAI / Anthropic 等）
- PTY CLI 路径见 `agent-llm-pty.md`（当前配置未启用）

## LLMSession 协议（domain/ports.py）

API SDK 场景使用**推送式流**（`AsyncIterator`），而非拉取式 `stream_until`：

```python
from typing import Protocol, AsyncIterator

class LLMSession(Protocol):
    async def generate(
        self,
        messages: list[dict],          # [{"role": "user", "content": "..."}]
    ) -> AsyncIterator[str]: ...        # 逐 token 推送
    async def close(self) -> None: ...  # 释放 HTTP 连接池
```

## 适配器结构（llm/）

| 文件 | 职责 |
|------|------|
| `domain/ports.py` | `LLMSession` 协议（端口，接口定义） |
| `llm/<provider>_api.py` | SDK 适配器实现（实现 `LLMSession`） |
| `llm/registry.py` | 按 `Settings.llm_provider` 选择实现 |

无 `pty_bridge.py`，无 `skills/installer.py`——API 模式不需要 PTY 或 skill 安装。

## 适配器实现模式

```python
from typing import AsyncIterator, override
from domain.ports import LLMSession

class OpenAISession(LLMSession):
    def __init__(self, settings) -> None:
        from openai import AsyncOpenAI
        self._client = AsyncOpenAI(
            api_key=settings.llm_api_key,
            base_url=settings.llm_base_url or None,
        )
        self._model = settings.llm_model

    @override
    async def generate(self, messages: list[dict]) -> AsyncIterator[str]:
        stream = await self._client.chat.completions.create(
            model=self._model,
            messages=messages,
            stream=True,
        )
        async for chunk in stream:
            delta = chunk.choices[0].delta.content
            if delta:
                yield delta

    @override
    async def close(self) -> None:
        await self._client.close()
```

Anthropic 适配器同理，将 `AsyncOpenAI` 换为 `AsyncAnthropic`，流式 API 换为 `client.messages.stream`。

## DAG 节点中的调用模式

```python
async def process(state, send, recv_queue):
    try:
        async with asyncio.timeout(settings.process_timeout_seconds):
            chunks: list[str] = []
            async for token in llm_session.generate(state.messages):
                chunks.append(token)
                await send({"type": "llm_token", "text": token})
            result = extract_result("".join(chunks))
            if not result:
                raise OutputValidationError()
    except TimeoutError:
        raise ExternalServiceTimeoutError(phase="process")
```

不需要 ANSI 过滤——API 响应是纯文本，无终端转义码。

## 超时保护

每个 DAG 阶段用 `asyncio.timeout()` 包裹 LLM 调用（示范）：

| 阶段 | 配置项 |
|------|--------|
| intake（收集输入） | `intake_timeout_seconds`（默认 60s） |
| process（LLM 处理） | `process_timeout_seconds`（默认 300s） |

超时后抛 `ExternalServiceTimeoutError`（`domain/exceptions.py`），不静默挂起。

## 连接管理

`LLMSession` 实例在 DAG 节点开始时创建，在 `runner.py` 的 `finally` 块中通过 `await llm_session.close()` 确定性释放 HTTP 连接池，防止连接泄漏。

禁止在节点内手动调用 `close()`——由 runner 统一回收。
