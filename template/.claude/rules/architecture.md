# 架构总览

> 三层架构、通信链路、限界上下文、六边形分层与依赖方向。

> 下文以「订单」为示范业务，仅占位；新项目替换为自己的领域，分层与依赖规则不变。

## 三层架构

```
frontend/   React + Vite + TypeScript + Tailwind
backend/    FastAPI（port 8000）—— WebSocket 代理 + 会话/状态持久化
agent/      FastAPI（port 8001）—— LLM 服务：CLI PTY 桥接或 API 调用 + DAG 编排
```

Backend 是纯代理/接入层，不持有核心业务逻辑。重业务编排放在领域层（backend services 或 agent）。

## 通信链路概览

```
Browser
  ↕  WebSocket  ws://localhost:8000/ws/{session_id}
Backend (port 8000)
  ↕  WebSocket  ws://localhost:8001/ws/{session_id}   ← 仅含 agent 时
Agent (port 8001)
  ↕  pty.openpty() 或 HTTP
外部 LLM（CLI 适配器如 Gemini CLI，或 API SDK）
```

- 外部 LLM（CLI 命令或 API）与所加载的能力都是**可替换的外部依赖**，不在领域内硬编码。命令、来源与密钥均经配置注入（见 `config.md`、`agent.md`），换提供商不触动领域逻辑。

## 限界上下文（Bounded Context，示范）

| 上下文 | 载体 | 子域 |
|--------|------|------|
| 核心业务（示范：订单处理） | backend / agent | 核心域（Core） |
| 会话/连接管理 | backend | 支撑域（Supporting） |
| 交互表现 | frontend | 通用域（Generic） |

- 上下文间**仅经消息契约集成**（即 Shared Kernel，见「通信协议与交互规约」）
- 外部系统（LLM、第三方 API）由适配器充当**防腐层（Anti-Corruption Layer）**，把外部协议翻译为领域语言，隔离外部对领域的侵蚀

## 分层（六边形，依赖恒向内）

领域层不依赖任何框架/IO：

```
infrastructure  适配器：pty / 外部 API / 导出 / db / ws
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
