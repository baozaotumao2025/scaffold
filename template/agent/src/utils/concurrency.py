import asyncio


def make_session_semaphore(max_concurrent: int) -> asyncio.Semaphore:
    """全局会话并发上限信号量。

    每个会话持有 LLM 子进程/连接等昂贵资源，必须封顶（见 agent-concurrency.md）。
    超出上限的会话应排队，并向前端反馈位置。
    """
    return asyncio.Semaphore(max_concurrent)
