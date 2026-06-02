---
paths: ["backend/**", "agent/**"]
---

# 数据生命周期与清理

> 工作目录 TTL + 磁盘预算 + 日志轮转 + DB 保留。不允许无界增长。

工作目录和日志会无限堆积，**必须有清理策略，不允许无界增长**。

| 数据 | 保留策略 | 执行方 |
|------|---------|--------|
| `~/ppt-gen/{uuid}/`（HTML+截图+PPTX） | TTL 默认 24h；总磁盘超阈值（默认 5GB）按 LRU 清理 | Agent 后台定时任务（每小时扫一次） |
| SQLite 会话记录 | 保留 30 天，过期软删除→定期硬删 | Backend 定时任务 |
| 日志文件 | loguru `rotation="100 MB"` + `retention="14 days"` + `compression="zip"` | 各服务 logging 配置 |

- 清理任务幂等、可重入；删除前校验路径在 workDir 内（防穿越）
- 配置项：`SESSION_TTL_HOURS`、`MAX_DISK_GB`、`DB_RETENTION_DAYS`、`LOG_RETENTION_DAYS`
- 会话结束（done/error）后，临时中间文件（preview_*.html）可立即清理，仅保留 slides.html + result.pptx

## 数据存储概览

| 层 | 存储 | 内容 |
|----|------|------|
| Backend | SQLite（`~/ppt-gen/ppt_gen.db`） | 会话记录（id、topic、style、status、时间戳） |
| Agent | 文件系统（`~/ppt-gen/{session_id}/`） | slides.html、preview_*.html、截图、result.pptx |
| Frontend | localStorage | 图片源配置（Unsplash/Pexels API Key） |
