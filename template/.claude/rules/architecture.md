# 架构总览

> 三层架构、通信链路、限界上下文、六边形分层与依赖方向。

## 三层架构

```
frontend/   React + Vite + TypeScript + Tailwind
backend/    FastAPI（port 8000）—— WebSocket 代理 + 会话持久化
agent/      FastAPI（port 8001）—— LLM CLI PTY 桥接 + DAG 编排
```

Backend 是纯代理层，不持有 AI 业务逻辑。所有交互编排在 Agent。

## 通信链路概览

```
Browser
  ↕  WebSocket  ws://localhost:8000/ws/{session_id}
Backend (port 8000)
  ↕  WebSocket  ws://localhost:8001/ws/{session_id}
Agent (port 8001)
  ↕  pty.openpty()
LLM CLI（加载所配置的幻灯片生成 skill）
```

- LLM CLI（当前适配器为 Gemini CLI）与所加载的 skill 都是**可替换的外部依赖**，不在领域内硬编码。CLI 命令、skill 来源（仓库/路径）与安装路径均经配置注入（见 `config.md`、`agent.md`），换 CLI 或换 skill 不触动领域逻辑。

## 限界上下文（Bounded Context）

| 上下文 | 载体 | 子域 |
|--------|------|------|
| 生成编排 Generation | agent | 核心域（Core） |
| 会话管理 SessionMgmt | backend | 支撑域（Supporting） |
| 交互表现 Presentation | frontend | 通用域（Generic） |

- 上下文间**仅经消息契约集成**（即 Shared Kernel，见「通信协议与交互规约」）
- LLM CLI 为外部系统，`agent/llm/` 适配器充当**防腐层（Anti-Corruption Layer）**，把终端协议翻译为领域语言，隔离外部模型对领域的侵蚀

## 分层（六边形，依赖恒向内）

领域层不依赖任何框架/IO：

```
infrastructure  适配器：pty / playwright / pptx / db / ws
      │  实现端口（依赖倒置）
application     用例编排：DAG runner+nodes、backend services
      │  依赖
domain          实体 / 值对象 / 领域服务 / 端口定义；纯逻辑，零 IO
```

## 依赖方向（低耦合的硬规则）

依赖只能单向流动，**禁止反向或跨层依赖**：

```
Backend:   routers → services → domain.ports ← db.repositories   # 依赖倒置：服务依赖端口，db 适配器实现端口；domain 不依赖任何框架
Agent:     main(接口) → dag(application) → domain   # 适配器(llm/providers/export/storage)实现 domain 端口
           依赖恒向内指向 domain；domain 不依赖任何外层与框架
Frontend:  pages → hooks → services/store         # components 不碰 store/网络
```

- 上层依赖下层，下层**绝不**反向 import 上层
- `utils/` 是叶子层，谁都可依赖它，它不依赖任何业务模块
- 依赖方向由 import-linter（Python）/ dependency-cruiser（TS）在 CI 强制
