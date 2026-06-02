# 质量门禁（CI 强制）

> lint / format / type / test 门禁表 + 依赖安全 / 供应链。

提交即跑（`.pre-commit-config.yaml`），CI 再跑一遍（`.github/workflows/ci.yml`）。任一不过禁止合并。

| 语言 | Lint | 格式化 | 类型 | 测试 |
|------|------|--------|------|------|
| Python | ruff check | ruff format | mypy（strict） | pytest |
| TypeScript | eslint | prettier | tsc --noEmit | vitest |

- 安装钩子：`pre-commit install`
- mypy / tsc 必须零 error；ruff / eslint 零 warning
- 配置位置：Python 在各 `pyproject.toml`，TS 在 `frontend/` 的 eslint/prettier/tsconfig
- 架构边界由 import-linter（Python）/ dependency-cruiser（TS）在 CI 强制（见 `architecture.md`）

## 依赖安全 / 供应链

- 锁文件必须提交，CI 用 `--frozen`/`--frozen-lockfile` 安装（拒绝漂移）
- CI 跑依赖审计：Python `uv run pip-audit`，前端 `pnpm audit --audit-level high`
- 启用 Dependabot/Renovate 自动提依赖更新 PR（`.github/dependabot.yml`）
- 新增依赖须评估必要性，优先标准库；不引入无维护/单文件的小众包
