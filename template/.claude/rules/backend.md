---
paths: ["backend/**"]
---

# backend

FastAPI 服务（port 8000）的技术栈、目录、分层、路由、中间件与配置规范。

## 概览

职责：WebSocket 代理层 + 文件服务 + 会话持久化。
**Backend 不连接任何 LLM**——所有大模型交互都在 Agent。Backend 只做 WebSocket 代理 + 数据持久化。

## 技术栈

| 库 | 用途 |
|----|------|
| FastAPI + uvicorn | Web 框架 + ASGI 服务器 |
| SQLAlchemy 2.x (async) | ORM |
| SQLite | 轻量数据库（单文件，无需独立服务） |
| Alembic | 数据库迁移 |
| loguru | 结构化日志 |
| pydantic-settings | 环境变量管理 |
| websockets | Agent WebSocket 客户端 |
| pytest + httpx + pytest-asyncio | 测试 |

## 包管理（uv）

```bash
uv add fastapi uvicorn "sqlalchemy[asyncio]" aiosqlite alembic loguru pydantic-settings websockets pytest httpx pytest-asyncio
uv run python -m src.main          # 运行服务
uv run pytest                      # 运行测试
```

关键文件：`pyproject.toml`（依赖声明）、`uv.lock`（锁文件，必须提交 git）、`alembic.ini`（迁移配置）

## 目录结构

```
backend/
├── alembic.ini                  # Alembic 入口配置
├── alembic/
│   ├── env.py                   # 迁移环境（导入所有 Model）
│   └── versions/                # 自动生成的迁移脚本
├── src/
│   ├── main.py                  # FastAPI app 实例、启动/关闭事件
│   ├── domain/                  # 领域层，纯逻辑，零框架/IO 依赖
│   │   ├── entities.py          # Session 聚合根（纯 Python dataclass，含状态机方法）
│   │   ├── value_objects.py     # SessionStatus（StrEnum，含 can_recover 规则）
│   │   └── ports.py             # SessionRepository Protocol（仓储端口）
│   ├── routers/
│   │   ├── ws.py                # WebSocket 代理 /ws/{session_id}
│   │   └── files.py             # 文件下载 + 预览路由
│   ├── services/
│   │   ├── agent_client.py      # 连接 Agent WebSocket
│   │   └── session_service.py   # 会话用例编排（依赖 SessionRepository 端口）
│   ├── schemas/
│   │   ├── messages.py          # Pydantic WebSocket 消息模型
│   │   └── session.py           # Pydantic 会话读写 schema（与 ORM 解耦）
│   ├── middleware/
│   │   ├── request_id.py        # 每个请求注入唯一 X-Request-Id
│   │   ├── access_log.py        # 请求/响应结构化日志
│   │   └── error_handler.py     # 全局未捕获异常 → 标准错误响应
│   ├── exceptions/
│   │   ├── base.py              # AppException 基类
│   │   └── handlers.py          # FastAPI exception_handler 注册
│   ├── db/
│   │   ├── base.py              # async_engine、AsyncSessionLocal、Base 声明基类
│   │   ├── models.py            # SessionRecord ORM 映射（纯持久化，无业务逻辑）
│   │   └── repositories.py      # SQLAlchemySessionRepository（实现 SessionRepository 端口）
│   ├── utils/                   # 横切纯函数工具（无业务逻辑、无状态）
│   │   ├── ids.py               # request_id / uuid 生成
│   │   └── timing.py            # 计时、超时上下文管理器
│   └── core/
│       ├── config.py            # Settings（pydantic-settings）
│       ├── deps.py              # FastAPI 依赖注入（get_db、get_session_repo、get_settings）
│       └── logging.py           # loguru 初始化、sink 配置
└── tests/
    ├── conftest.py              # 测试 DB（in-memory SQLite）、app fixture
    ├── test_session_entity.py   # Session 领域实体单元测试（classicist，不 mock）
    ├── test_ws.py
    ├── test_files.py
    └── test_session_service.py
```

## 分层映射（六边形架构）

backend 是支撑域，遵循六边形架构，依赖恒向内：

| 层 | 目录 | 职责 |
|----|------|------|
| 接口适配器 | `routers/` | WS/HTTP 入站适配，仅转译协议 |
| 应用（用例） | `services/` | 会话用例编排，依赖 `SessionRepository` 端口 |
| 领域 | `domain/` | `Session` 聚合根、`SessionStatus` 值对象、`SessionRepository` 端口；纯逻辑零 IO |
| 基础设施 | `db/repositories.py`、`agent_client` | 实现 `SessionRepository` 端口、出站适配 |

## 路由层规范

- 路由函数只做：参数校验 + 调用 service + 返回响应
- 禁止在路由函数中写业务 if/else
- 所有 DB 操作必须通过 `session_service`，禁止在路由层直接操作 DB
- REST 路由统一挂 `/api/v1` 前缀（下载/预览等）；WS 消息带 `v` 字段（见根「协议版本化」）
- 会话记录保留 `DB_RETENTION_DAYS`（默认 30 天），`lifespan` 定时任务软删→硬删过期记录

### RESTful 资源命名规范

| 项 | 规范 |
|----|------|
| 资源 | 名词复数：`/api/v1/sessions`、`/api/v1/sessions/{session_id}/export` |
| 路径段 | 小写 + kebab-case，不放动词（动作用 HTTP method） |
| 方法 | GET 读 / POST 建 / PUT 全量改 / PATCH 局部改 / DELETE 删 |
| JSON 字段 | snake_case |
| 版本 | `/api/v1` 前缀 |
| 状态码 | 语义化 200/201/204/4xx/5xx |

例：`GET /api/v1/sessions/{session_id}/export`。路径/字段命名靠 review + 可选 spectral（OpenAPI lint）；HTTP 语义靠 review。

### Swagger / OpenAPI 文档

- FastAPI 自动生成 `/docs`（Swagger UI）、`/redoc`、`/openapi.json`
- 由 `.env` 的 `ENABLE_API_DOCS` 控制：dev 默认开，prod 关（`docs_url=None` 等）
- Settings 字段 `enable_api_docs: bool = True`，映射环境变量 `ENABLE_API_DOCS`

## 中间件（middleware/）

### request_id.py

每个请求（含 WebSocket 握手）注入 `X-Request-Id`，传入 loguru 上下文，在所有日志条目中携带，便于全链路追踪。

### access_log.py

记录每个 HTTP 请求的结构化日志（method、path、status_code、duration_ms、request_id）。WebSocket 连接记录 connect / disconnect 事件。

### error_handler.py

捕获所有未处理异常，返回统一错误结构：

```json
{
  "error": {
    "code": "INTERNAL_ERROR",
    "message": "服务器内部错误",
    "request_id": "xxx"
  }
}
```

生产环境不暴露堆栈信息；开发环境在日志中完整记录。

异常体系（exceptions/）：业务错误必须抛 `AppException` 子类（携带 `code`/`message`/`status_code`），禁止在路由层直接 raise HTTPException。在 `main.py` 注册 `app.add_exception_handler(AppException, app_exception_handler)` 与 `app.add_exception_handler(Exception, global_exception_handler)`。

## 配置（core/config.py）

配置项见 `.env.example`（提交 git 的模板）；真实配置放 `.env`（gitignore）。`.env` 用 SCREAMING_SNAKE，Settings 字段用 snake_case；env 映射（`agent_ws_url` ↔ `AGENT_WS_URL`）为 pydantic-settings 默认行为，无需 alias_generator。

```python
class Settings(BaseSettings):
    env: Literal["dev", "prod"] = "dev"
    agent_ws_url: str = "ws://localhost:8001"
    work_dir: Path = Path.home() / "app-data"
    database_url: str = f"sqlite+aiosqlite:///{Path.home()}/app-data/app.db"
    port: int = 8000
    log_level: str = "DEBUG"
    enable_api_docs: bool = True

    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8",
    )
```

- 缺失/类型错误在启动时即报错（fail-fast）
- 优先级：环境变量 > `.env` > 默认值
- 敏感配置只从环境读取，`.env` 不提交 git

## WebSocket 代理核心

重连入口（routers/ws.py）：

```python
@router.websocket("/ws/{session_id}")
async def ws_proxy(ws: WebSocket, session_id: str, repo: SessionRepository = Depends(get_session_repo)):
    await ws.accept()
    checkpoint = await session_service.load_checkpoint(repo, session_id)
    # 将 checkpoint 信息附在 start_session 消息中转发给 Agent
    async with agent_client.connect(session_id, checkpoint=checkpoint) as agent_ws:
        await asyncio.gather(forward_to_agent(ws, agent_ws), forward_to_browser(agent_ws, ws))
```

详见 `backend-concurrency.md`（双向转发 + Task 管理）与 `backend-db.md`（checkpoint）。

## 日志规范（core/logging.py）

loguru，两个 sink：stderr（dev 人类可读彩色）+ `{WORK_DIR}/logs/backend.log`（JSON 每行一条，所有环境）。文件 sink 配 `rotation="100 MB"`、`retention="14 days"`、`compression="zip"`。级别 `DEBUG`(dev)/`INFO`(prod)。每条日志必须携带 `request_id`（loguru contextualize 注入）。禁止 `print()` 与 stdlib `logging`，统一 `from loguru import logger`。

## 测试规范

- **领域实体（classicist）**：`test_session_entity.py` 直接实例化 `Session`，验证状态机方法与不变量，零 mock，零 IO
- **service 层（mockist）**：`test_session_service.py` mock `SessionRepository` 端口，验证用例编排（状态流转调用顺序）
- **集成（真实 DB）**：`conftest.py` 提供 in-memory SQLite + `SQLAlchemySessionRepository`；`test_ws.py` mock Agent WS，验证消息原样转发
- checkpoint 测试：验证不同 status 下重连时返回正确的 `Session` 数据，`can_recover()` 结果符合预期
- 每次 CI 前自动运行 `alembic upgrade head`（针对测试 DB）
