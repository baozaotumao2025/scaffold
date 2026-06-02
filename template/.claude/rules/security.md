# 安全基线

> 路径穿越、命令注入、上传、CORS、限流、密钥的硬约束。

| 风险 | 约束 |
|------|------|
| 路径穿越 | `/preview` `/download` 必须校验 session_id 为合法 UUID，且 resolve 后路径仍在 workDir 内（`utils/files.py`） |
| 命令注入 | 子进程一律用 argv 列表，**禁止 `shell=True`**；用户输入只作为参数传入 |
| 文件上传 | 仅 `.md`，限制大小（默认 5MB），读取后按文本处理 |
| CORS | Backend 仅允许前端来源（配置项，非 `*`） |
| 限流 | 复用 Agent 并发信号量，超额排队（非无限接收） |
| 密钥 | 只走 `.env` / localStorage；`detect-private-key` 钩子防误提交 |

- 路径穿越在 CI 由 semgrep 自定义规则辅助检测（用户输入拼路径未经 workDir 校验）
- 命令注入由 ruff `S`（bandit：S602/603/604/605）在 PC·CI 检测
- 密钥不入库由 gitleaks + detect-private-key 全量扫描
