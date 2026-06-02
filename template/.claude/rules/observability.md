---
paths: ["backend/**", "agent/**", "frontend/**"]
---

# 可观测性

> correlation_id 全链路 + 结构化日志 + 健康探针。

- **correlation_id 贯穿全链路**：前端生成 → WS header/首帧带上 → Backend（作 request_id）→ Agent（随 session_id 一起进日志）。三层日志可用同一 id 串联检索。
- **结构化日志**：JSON 每行一条（见各服务 logging 章节）

| 层 | 文件 | 格式 |
|----|------|------|
| Backend | `{WORK_DIR}/logs/backend.log` | JSON，每行一条，含 request_id |
| Agent | `{WORK_DIR}/logs/agent.log` | JSON，每行一条，含 session_id |
| Frontend | console（dev）/ 可接 Sentry（prod） | 结构化对象 |

- **探针**：每个服务暴露 `GET /health`（存活）与 `GET /ready`（依赖就绪，如 Agent 检查外部依赖可用）
- 禁止 `print()` / `console.log()`，统一用各层 logger（见 `conventions.md`）
