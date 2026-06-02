# 全局约定

> 命名规范 + 禁 print/console + 注释 + 包管理概览。

## 命名规范（已定）

不是"全部 snake"：各随语言生态，边界（wire）统一为 snake。

| 范围 | 命名 | 强制 |
|------|------|------|
| Python（backend+agent） | snake_case 变量/函数、PascalCase 类、UPPER_SNAKE 常量 | ruff `N`（pep8-naming） |
| 前端 TS | camelCase 变量/函数、PascalCase 组件/类型 | eslint naming-convention |
| 通信线 JSON 契约 | snake_case | 契约源 Pydantic（snake），后端零映射 |

- Python 字段 `agent_ws_url` ↔ 环境变量 `AGENT_WS_URL` 为 pydantic-settings 默认映射，**无需 `alias_generator`**（见 `config.md`）
- 旧文档中"Python camelCase"与 `to_screaming_snake` 描述已作废，一律按上表

## 禁 print / console

- 禁止 `print()`（Python）和 `console.log()`（TS）：统一用各层 logger
- Python 用 `from loguru import logger`，禁用 stdlib `logging`
- ruff `T20`（Python）/ eslint `no-console`（TS，允许 warn/error）强制

## 注释

- 不写无意义注释；WHY 不明显时才写注释

## 其他约定

- 每次会话/请求使用独立 UUID 工作目录：`{WORK_DIR}/{uuid}/`（`WORK_DIR` 经 .env 注入）

## 包管理概览

| 目录 | 工具 | 锁文件 |
|------|------|--------|
| `backend/` | uv | `uv.lock` |
| `agent/` | uv | `uv.lock` |
| `frontend/` | pnpm | `pnpm-lock.yaml` |

锁文件必须提交 git，保证环境一致性。CI 用 `--frozen`/`--frozen-lockfile` 安装。各目录详细命令见对应服务规则。
