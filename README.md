# scaffold · new-project skill

> 一个 **Claude Code Skill**：在任意项目里对 Claude 说一句"帮我新建项目"，即可生成含完整质量门禁（pre-commit、CI、Docker、Claude 规则）的 FastAPI + React 工程骨架，并随选型自动裁剪规则文件。

## 🚀 安装（推荐）

一条命令装到全局，**任意项目可用**，无需克隆本仓库：

```bash
curl -fsSL https://raw.githubusercontent.com/baozaotumao2025/scaffold/main/scripts/install-skill.sh | bash
```

## 用法

安装后，在 Claude Code 中任选一种方式：

```
/new-project                          # 交互式问卷，逐步选服务/数据库
/new-project my-app                   # 指定项目名，其余交互确认
/new-project my-rules --preset principles   # 仅生成 10 个原理层规则，无服务代码
```

或者**直接用自然语言**——Claude 会自动识别并触发 skill：

> 「帮我新建一个全栈项目，要 FastAPI + React，数据库用 postgresql」

可用 preset：`principles`（仅规则）· `fullstack` · `fullstack-ai` · `api-only`。

> 模板由 copier 从 GitHub 实时拉取。`verify.sh` 在仓库根 `scripts/` 单一维护，安装时由 `install-skill.sh` 组装进 skill，使安装后的 skill 自包含。

---

## 核心设计

### 两层规则体系

脚手架内置的 Claude Code 规则文件分为两层，职责不同：

| 层级 | 规则文件 | 加载方式 | 说明 |
|------|---------|---------|------|
| **原理层** | `architecture.md` / `ddd.md` / `design-discipline.md` 等 10 个 | 全局恒加载 | 六边形架构、DDD、SOLID、TDD 等通用原则，换项目不变 |
| **落地层** | `backend*.md` / `agent*.md` / `frontend*.md` | 按 `paths` 按需加载 | 原理在本项目具体服务中的落地约束，**随选型生成** |

落地层规则根据问卷答案**动态生成或选择**，而非固定复制：

```
问卷选择                           生成的落地层规则
────────────────────────────────────────────────────────────────────
include_agent=true
  llm_provider=gemini-cli     →  agent.md + agent-concurrency.md
                                 + agent-llm-pty.md（PTY/CLI 规范）
  llm_provider=openai-api     →  agent.md + agent-concurrency.md
                                 + agent-llm-api.md（API 流式规范）
  llm_provider=anthropic-api  →  同上（agent-llm-api.md）

include_agent=false            →  所有 agent*.md 全部排除

database=sqlite                →  backend-db.md（SQLite + WAL 模式）
database=postgresql            →  backend-db.md（asyncpg + 连接池 + pg 迁移注意）

include_backend=false          →  所有 backend*.md 排除
include_frontend=false         →  所有 frontend*.md 排除
────────────────────────────────────────────────────────────────────
```

---

## 四层质量护栏（左移，编码即查错）

同一套规则（ruff/mypy 读 `pyproject.toml`，eslint/prettier 读各自配置）贯穿四层，越靠前越早发现，到 commit 时基本只是确认：

| 层 | 时机 | 机制 | 是否默认生成 |
|----|------|------|------|
| **1 编辑器 LSP** | 边打字 | `.vscode/settings.json` + `extensions.json`：保存自动格式化/修复、实时标红 | ✅ 始终 |
| **2 watch 监听** | 一保存 | `.vscode/tasks.json`：打开项目自动起 `tsc --watch` / `ruff --watch` | 开关 `vscode_auto_watch` |
| **3 pre-commit** | git commit | `.pre-commit-config.yaml`：ruff/mypy/eslint/tsc/gitleaks | ✅ 始终 |
| **4 CI** | push / PR | `.github/workflows/ci.yml` | ✅ 始终 |

关于 `.vscode/`：

- **只影响当前项目**（工作区级），不碰你的 VSCode 全局配置；个人偏好（主题/字号）仍走全局。
- 是**团队级规则**，随 scaffold 演进——`copier update` 走 3-way 合并推送改进，仅改了同一行才提示冲突。
- 首次用 watch 需在命令面板执行一次 **"Tasks: Allow Automatic Tasks"** 授权。

---

## 脚手架内容

```
scaffold/
├── copier.yml                           ← 问卷变量 + 条件排除逻辑
├── README.md
├── .claude/skills/new-project/
│   └── SKILL.md                         ← skill 元数据 + 生成指令（verify.sh 安装时组装）
├── scripts/
│   ├── verify.sh                        ← 工具链合规检查（幂等只读，单一源）
│   ├── install-skill.sh                 ← 把 skill 安装到 ~/.claude/skills/
│   └── retrofit.sh                      ← 补装工具链到已有项目
└── template/
    ├── .copier-answers.yml.jinja        ← 记录模板版本+答案，供 copier update
    ├── .pre-commit-config.yaml.jinja    ← 按服务条件生成 hooks（含 gitleaks）
    ├── .github/workflows/ci.yml.jinja   ← 按服务条件生成 CI jobs
    ├── .vscode/                         ← 编辑器实时护栏（始终生成）
    │   ├── settings.json.jinja          ← 保存自动格式化/修复（按服务裁剪）
    │   ├── extensions.json.jinja        ← 推荐扩展（ruff/eslint/mypy…）
    │   └── tasks.json.jinja             ← 自动 watch（仅 vscode_auto_watch=true）
    ├── docker-compose.yml.jinja
    ├── CLAUDE.md.jinja                  ← 项目说明参数化
    ├── .claude/rules/
    │   ├── # 原理层（10 个，静态，始终复制）
    │   ├── architecture.md / ddd.md / design-discipline.md ...
    │   │
    │   ├── # 落地层：静态但条件复制（按服务选择）
    │   ├── agent-dag.md                 ← DAG 模式（不随 LLM 选型变）
    │   ├── agent-extension-points.md    ← 扩展点模式（不随 LLM 选型变）
    │   ├── agent-llm-pty.md             ← LLM CLI/PTY 规范（仅 gemini-cli）
    │   ├── agent-llm-api.md             ← LLM API/SDK 规范（非 gemini-cli）
    │   ├── backend.md / backend-concurrency.md
    │   ├── frontend.md / frontend-runtime.md
    │   ├── communication-catalog.md / error-codes.md / observability.md
    │   │
    │   └── # 落地层：动态渲染（.jinja，内容随选型变化）
    │       ├── agent.md.jinja           ← 技术栈表 / 依赖 / 目录 / 配置 / 测试
    │       ├── agent-concurrency.md.jinja  ← PTY 并发节 vs API 并发节
    │       └── backend-db.md.jinja      ← SQLite 配置 vs PostgreSQL 配置
    ├── backend/  pyproject.toml / Dockerfile / .env.example / src/
    ├── agent/    同上
    └── frontend/ package.json / pnpm-workspace.yaml / tsconfig / eslint / prettier / vitest / vite
```

---

## 进阶：不装 skill，直接用 copier

> 以下面向 CI、脚本，或不使用 Claude Code 的场景。日常使用推荐上面的 skill 方式。

前置依赖：

```bash
pip install copier        # 或 uv tool install copier
```

### 交互式问卷

```bash
copier copy git+https://github.com/baozaotumao2025/scaffold.git my-new-project
```

问卷包含以下选择：

| 变量 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `project_name` | str | My Awesome Service | 项目显示名称 |
| `project_slug` | str | 自动派生 | snake_case 包名 |
| `org_name` | str | my-org | GitHub 组织名 |
| `description` | str | — | 一行项目描述 |
| `include_backend` | bool | true | 包含 FastAPI backend |
| `include_agent` | bool | false | 包含 LLM Agent 服务 |
| `include_frontend` | bool | true | 包含 React + Vite 前端 |
| `backend_port` | int | 8000 | Backend 端口 |
| `agent_port` | int | 8001 | Agent 端口 |
| `frontend_port` | int | 5173 | 前端端口 |
| `python_version` | choice | 3.12 | 3.11 / 3.12 / 3.13 |
| `database` | choice | sqlite | `sqlite` / `postgresql` |
| `node_version` | choice | 22 | 20 / 22 |
| `llm_provider` | choice | gemini-cli | `gemini-cli` / `openai-api` / `anthropic-api` / `custom` |
| `vscode_auto_watch` | bool | false | VSCode 打开项目自动启动 watch 任务（编码即时查错） |

> `llm_provider` 仅在 `include_agent=true` 时出现。

### 静默生成（CI / 脚本中）

```bash
# 全栈 + OpenAI API + PostgreSQL
copier copy git+https://github.com/baozaotumao2025/scaffold.git my-project \
  --data project_name="My Service" \
  --data include_backend=true \
  --data include_agent=true \
  --data include_frontend=true \
  --data database=postgresql \
  --data llm_provider=openai-api

# 仅 API（backend only，SQLite）
copier copy git+https://github.com/baozaotumao2025/scaffold.git my-api \
  --data include_backend=true \
  --data include_agent=false \
  --data include_frontend=false

# 本地模板调试
copier copy ./scaffold /tmp/test-project
```

---

## 模板更新（推送给已有项目）

```bash
cd my-existing-project

# 复用上次答案，自动三路合并
copier update --defaults

# 修改某个答案（如切换数据库）
copier update --data database=postgresql

# 查看更新预览（不实际写入）
copier update --defaults --pretend
```

`.copier-answers.yml` 由 Copier 自动维护，记录模板版本和答案，**不要手动修改**。

---

## 工具脚本

### `verify.sh` — 合规检查

检查项目工具链配置是否符合 scaffold 规范。**只读幂等，不修改任何文件，可重复运行。**

```
用法：./scripts/verify.sh [OPTIONS] [PROJECT_PATH]

选项：
  -h, --help      显示帮助信息
  -v, --verbose   详细输出（显示所有通过项和跳过项）
  -s, --strict    严格模式：警告（△）也视为失败，退出码 1

退出码：
  0  全部通过（严格模式下无警告）
  1  存在失败项
  2  参数错误
```

```bash
# 检查当前目录
./scripts/verify.sh

# 详细模式（显示每项通过/跳过的路径）
./scripts/verify.sh -v

# 严格模式（CI 中使用，警告也阻断）
./scripts/verify.sh -s /path/to/project

# 详细 + 严格（组合简写）
./scripts/verify.sh -vs .
```

**智能检查内容：**

- 自动读取 `.copier-answers.yml` 获取 `llm_provider` 和 `database` 配置
- 按存在的目录（`backend/` / `agent/` / `frontend/`）决定检查哪些服务
- **LLM 驱动规则互斥验证**：`gemini-cli` 时检查 `agent-llm-pty.md` 存在且 `agent-llm-api.md` 不存在（反之同理），两个同时存在时输出 WARN
- Claude 规则文件完整性检查（全局规则 + 对应落地层规则）
- 工具链可用性检查（uv / pnpm / pre-commit / copier 版本）

**汇总输出示例：**

```
═══════════════════════════════════════════════════════════════
分类                   通过   警告   失败
根目录                    6      1      0
Backend                   8      0      0
Agent                     7      0      0
Frontend                  9      0      0
Pre-commit 钩子           4      0      0
Claude 规则文件          18      0      0
工具链可用性              4      0      0
───────────────────────────────────────────────────────────────
合计                     56      1      0
═══════════════════════════════════════════════════════════════
✓ 核心检查全部通过  △ 1 项警告（建议修复）
```

---

### `retrofit.sh` — 补装工具链到已有项目

对未经 copier 创建的已有项目，叠加 scaffold 模板。**全部步骤幂等，重复运行安全。**

```
用法：./scripts/retrofit.sh [OPTIONS] [PROJECT_PATH]

选项：
  -h, --help          显示帮助信息
  -n, --dry-run       预览所有操作，不实际执行任何命令
  -f, --force         强制覆盖配置文件（移除 _skip_if_exists 保护，慎用）
      --no-deps       跳过依赖安装，仅运行 copier copy
      --scaffold URL  指定 scaffold 来源（覆盖 $SCAFFOLD_URL）

环境变量：
  SCAFFOLD_URL        scaffold 来源（默认：git+https://github.com/baozaotumao2025/scaffold.git）
```

```bash
# 补装工具链到当前目录
./scripts/retrofit.sh

# 先预览将执行哪些步骤（不实际运行）
./scripts/retrofit.sh --dry-run /path/to/project

# 使用本地 scaffold（开发调试）
SCAFFOLD_URL=./scaffold ./scripts/retrofit.sh /path/to/project

# 使用远程 scaffold，仅运行 copier（跳过 uv/pnpm）
./scripts/retrofit.sh --scaffold git+https://github.com/baozaotumao2025/scaffold.git --no-deps .

# 补装后立即验证
./scripts/retrofit.sh . && ./scripts/verify.sh .
```

**幂等性保证：**

| 步骤 | 幂等机制 |
|------|---------|
| Copier 模版叠加 | `_skip_if_exists` 保护 `src/` 代码不被覆盖 |
| `uv sync` | `--frozen` 保证锁文件一致；已安装时仅校验，不重装 |
| `pnpm install` | `--frozen-lockfile` 保证锁文件一致 |
| Pre-commit 安装 | 检测 `.git/hooks/pre-commit` 已存在时 SKIP，`--force` 才重装 |

**步骤汇总输出示例：**

```
═══════════════════════════════════════════════════════════════
Retrofit 步骤汇总: /path/to/project
───────────────────────────────────────────────────────────────
步骤                           状态
Copier 模版叠加                ✓ 完成
Backend uv sync                ✓ 完成
Agent uv sync                  – 跳过
Frontend pnpm install          ✓ 完成
Pre-commit 钩子                – 跳过（已安装，幂等）
───────────────────────────────────────────────────────────────
完成: 3  跳过: 2  警告: 0  失败: 0
═══════════════════════════════════════════════════════════════

后续步骤：
  • 运行 ./scripts/verify.sh /path/to/project 验证最终结果
```

---

## 典型组合示例

```bash
# 1. 全栈 AI 项目（默认 gemini-cli PTY 模式）
copier copy ./scaffold /tmp/test-full \
  --data include_backend=true --data include_agent=true --data include_frontend=true

# 2. 全栈 AI 项目（OpenAI API 模式，生成 agent-llm-api.md 而非 agent-llm-pty.md）
copier copy ./scaffold /tmp/test-openai \
  --data include_backend=true --data include_agent=true --data include_frontend=true \
  --data llm_provider=openai-api --data database=postgresql

# 3. 仅 API 服务（无前端，无 agent）
copier copy ./scaffold /tmp/test-api \
  --data include_backend=true --data include_agent=false --data include_frontend=false

# 4. 验证生成结果（详细模式）
./scripts/verify.sh -v /tmp/test-full
```

---

## 发布到团队

```bash
cd my-scaffold
git init && git add . && git commit -m "chore: initial scaffold"

git remote add origin git@github.com:baozaotumao2025/scaffold.git
git push -u origin main

# 打版本 tag（copier update 按 tag 追踪）
git tag v1.0.0 && git push --tags
```

之后团队成员只需：

```bash
pip install copier
copier copy git+https://github.com/baozaotumao2025/scaffold.git my-project
```

---

## 贡献模板

1. 修改 `template/` 下的 `.jinja` 文件或静态规则文件
2. 本地测试：`copier copy . /tmp/test && cd /tmp/test && pre-commit run --all-files`
3. 用 `verify.sh` 验证生成项目合规性：`./scripts/verify.sh -v /tmp/test`
4. 打 semver tag：`git tag v1.1.0 && git push --tags`
5. 已有项目运行 `copier update --defaults` 三路合并收到更新

### 添加新的 LLM provider 支持

1. 在 `copier.yml` 的 `llm_provider.choices` 中增加新选项
2. 在 `template/.claude/rules/agent.md.jinja` 中添加对应 `{% elif llm_provider == '...' %}` 分支
3. 在 `template/.claude/rules/agent-concurrency.md.jinja` 中视需要添加分支
4. 若新 provider 使用不同机制（非 API SDK），按需新建对应规则文件并在 `copier.yml` 的 `_exclude` 中添加互斥条件
5. 更新 `scripts/verify.sh` 中 `agent/pyproject.toml` 的 SDK 包名检查

### 添加新的数据库支持

1. 在 `copier.yml` 的 `database.choices` 中增加新选项
2. 在 `template/.claude/rules/backend-db.md.jinja` 中添加对应 `{% elif database == '...' %}` 分支
3. 在 `scripts/verify.sh` 的 `local_driver` 映射中添加新数据库的驱动包名
