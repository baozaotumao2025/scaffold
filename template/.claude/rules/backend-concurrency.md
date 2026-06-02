---
paths: ["backend/**"]
---

# backend-concurrency

Backend 并发模型：WebSocket 双向转发的 Task 管理 + SQLite 并发处理。

Backend 是纯异步 I/O 代理，无 CPU 密集工作，无需进程池。关注点在两处：双向转发的任务管理、SQLite 并发。

## 1. WebSocket 双向转发

每个连接 = 两个 Task（上行 / 下行），并联运行；任一侧断开必须取消另一侧，避免 Task 泄漏：

```python
@router.websocket("/ws/{session_id}")
async def ws_proxy(ws: WebSocket, session_id: str, repo: SessionRepository = Depends(get_session_repo)):
    await ws.accept()
    await session_service.get_or_create(repo, session_id)
    checkpoint = await session_service.load_checkpoint(repo, session_id)
    async with agent_client.connect(session_id, checkpoint=checkpoint) as agent_ws:
        to_agent = asyncio.create_task(forward_to_agent(ws, agent_ws))
        to_browser = asyncio.create_task(forward_to_browser(agent_ws, ws, repo))  # 转发同时写 checkpoint
        done, pending = await asyncio.wait(
            {to_agent, to_browser}, return_when=asyncio.FIRST_COMPLETED
        )
        for task in pending:           # 一侧结束，取消另一侧
            task.cancel()
```

## 2. SQLite 并发

SQLite 默认串行写，并发下易触发 `database is locked`。引擎连接时必须开 WAL + busy_timeout：

```python
# db/base.py —— connect 时执行
@event.listens_for(engine.sync_engine, "connect")
def set_sqlite_pragma(dbapi_conn, _):
    cursor = dbapi_conn.cursor()
    cursor.execute("PRAGMA journal_mode=WAL")    # 读写不互斥
    cursor.execute("PRAGMA busy_timeout=5000")   # 锁等待 5s 而非立即报错
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()
```

- 一个请求/连接一个 `AsyncSession`（`get_db` 作用域），**禁止跨 Task 共享 Session**
- 本工作负载写入量低，WAL 足够；若未来高并发，迁移到 Postgres（仅换 `database_url` 与 driver，ORM 不变）
