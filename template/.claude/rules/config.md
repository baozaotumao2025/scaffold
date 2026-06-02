# 配置管理

> .env 规约 + 命名映射坑 + API 文档开关。每个服务用 `.env` 注入配置，**不硬编码、不提交密钥**。

- `{服务}/.env.example` 提交 git（模板）；`{服务}/.env` gitignore（含密钥）
- backend/agent：`pydantic-settings` 读 `.env`，启动即校验类型，fail-fast
- frontend：Vite 读 `.env`，**仅 `VITE_` 前缀变量**注入浏览器
- 优先级：环境变量 > `.env` 文件 > 代码默认值

## 命名映射（关键坑 —— 无需自定义 alias_generator）

`.env` 用 **SCREAMING_SNAKE_CASE**（`AGENT_WS_URL`）；Settings 字段用 **snake_case**（`agent_ws_url`）。字段已是 snake_case，`agent_ws_url` ↔ `AGENT_WS_URL` 正是 **pydantic-settings 默认映射**。**不要引入任何自定义 `alias_generator`** —— 旧版 `to_screaming_snake` 桥接函数已删除。

```python
class Settings(BaseSettings):
    agent_ws_url: str = "ws://localhost:8001"
    enable_api_docs: bool = True          # dev 默认开，prod 关
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")
    # 无 alias_generator：AGENT_WS_URL → agent_ws_url 为默认行为
```

## API 文档（Swagger / OpenAPI）

- FastAPI 由 `.env` 的 `ENABLE_API_DOCS` 控制 `/docs` `/redoc` `/openapi.json`：**dev true，prod false**（关闭时三者设 `None`）
- 主要用于 backend；agent 内部 WS 服务可直接关
- 外部可替换依赖（LLM CLI 命令、skill 来源/路径）也经 `.env` 注入，不硬编码（见 `architecture.md`、`agent.md`）
