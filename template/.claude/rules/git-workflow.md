# Git 工作流与提交规范

> Conventional Commits + 分支保护 + PR + SemVer。

- **提交信息**：Conventional Commits（`feat:` `fix:` `refactor:` `test:` `docs:` `chore:`），commit-msg 钩子校验
- **分支**：主干保护，禁止直推；功能走 `feat/xxx` 分支 + PR
- **PR 合并前**：CI 全绿 + 至少一人 review；squash 合并保持历史线性
- **版本**：语义化版本（SemVer），变更记入 `CHANGELOG.md`
- 密钥不入库：gitleaks + detect-private-key 在 PC·CI 全量扫描；`.env` 由 `.gitignore` 排除
