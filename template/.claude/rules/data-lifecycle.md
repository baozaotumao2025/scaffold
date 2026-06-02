---
paths: ["backend/**", "agent/**"]
---

# 数据生命周期与清理

> 工作目录 TTL + 磁盘预算 + 日志轮转 + DB 保留。不允许无界增长。

工作目录和日志会无限堆积，**必须有清理策略，不允许无界增长**。

| 数据 | 保留策略 | 执行方 |
|------|---------|--------|
| `{WORK_DIR}/{uuid}/`（会话产出的中间/结果文件） | TTL 默认 24h；总磁盘超阈值（默认 5GB）按 LRU 清理 | Agent 后台定时任务（每小时扫一次） |
| SQLite 会话记录 | 保留 30 天，过期软删除→定期硬删 | Backend 定时任务 |
| 日志文件 | loguru `rotation="100 MB"` + `retention="14 days"` + `compression="zip"` | 各服务 logging 配置 |

- 清理任务幂等、可重入；删除前校验路径在 workDir 内（防穿越）
- 配置项：`SESSION_TTL_HOURS`、`MAX_DISK_GB`、`DB_RETENTION_DAYS`、`LOG_RETENTION_DAYS`
- 会话结束（done/error）后，临时中间文件可立即清理，仅保留最终结果文件

## 数据存储概览（示范）

| 层 | 存储 | 内容 |
|----|------|------|
| Backend | SQLite（`{WORK_DIR}/app.db`） | 会话记录（id、状态、时间戳等） |
| Agent | 文件系统（`{WORK_DIR}/{session_id}/`） | 会话产出的中间文件与最终结果 |
| Frontend | localStorage | 客户端本地配置（如第三方 API Key） |
