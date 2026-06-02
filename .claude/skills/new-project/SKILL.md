---
name: "new-project"
description: "使用 scaffold copier 模板一键生成含完整质量门禁的 FastAPI + React 项目。当用户需要从零搭建新项目、初始化工程脚手架、创建新服务、bootstrap 新代码库，或需要带 pre-commit/CI/Docker/Claude 规则的标准化项目骨架时使用。支持按需选择 backend(FastAPI) / frontend(React+Vite) / agent(LLM) 服务、sqlite 或 postgresql 数据库、以及 LLM provider，并自动裁剪 Claude Code 规则文件（原理层 + 落地层）。不适用于：已有项目的局部改造、单文件重构、或非新建场景。"
dependencies: ["copier"]
---

# new-project

## Overview

一条命令生成带有完整质量门禁（pre-commit、CI、Docker、Claude Code 规则）的 FastAPI + React 项目，并随选型自动裁剪 Claude Code 落地层规则。模板从 GitHub 拉取，无需本地克隆 scaffold 仓库。

## Instructions

### 第一步：收集参数

若用户未提供足够信息，**一次性**询问以下内容（不要逐个问）：

| 参数 | 说明 | 默认值 |
|------|------|--------|
| 项目目录名 | 生成到哪个文件夹 | my-project |
| 是否包含 backend | FastAPI 服务 | true |
| 是否包含 frontend | React + Vite | true |
| 是否包含 agent | LLM Agent 服务 | false |
| 数据库 | sqlite / postgresql | sqlite |
| LLM provider | 仅 agent=true 时问 | gemini-cli |

若用户输入包含 `--preset`，直接套用以下预设，跳过问卷：

| Preset | 等价配置 |
|--------|---------|
| `principles` | 三服务全 false — 仅复制原理层规则，无服务代码 |
| `fullstack` | backend+frontend，sqlite |
| `fullstack-ai` | backend+frontend+agent，postgresql，openai-api |
| `api-only` | 仅 backend，sqlite |

### 第二步：执行生成

```bash
copier copy git+https://github.com/baozaotumao2025/scaffold.git <项目目录> \
  --data project_name="<显示名称>" \
  --data include_backend=<true/false> \
  --data include_agent=<true/false> \
  --data include_frontend=<true/false> \
  --data database=<sqlite/postgresql> \
  --data llm_provider=<provider>
```

> `llm_provider` 仅在 `include_agent=true` 时添加。

### 第三步：验证

使用本 skill 自带的验证脚本（自包含，无需依赖生成项目内的工具）：

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/verify.sh -v <项目目录>
```

验证失败时，逐条输出修复建议，不要静默跳过。

### 第四步：汇报

输出生成的服务组合、规则文件列表，以及 verify.sh 汇总结果。

## Resources

- 模板仓库：`git+https://github.com/baozaotumao2025/scaffold.git`
- 验证脚本：`${CLAUDE_SKILL_DIR}/scripts/verify.sh`（只读幂等，可重复运行）
- 规则说明：见 scaffold 仓库 `README.md` — "两层规则体系" 一节
