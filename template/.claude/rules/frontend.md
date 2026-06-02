---
paths: ["frontend/**"]
---

# frontend

React + Vite + TypeScript + Tailwind 前端的技术栈、目录、各层职责边界、TS 规范与测试规范。

> 下文以「订单」交互为示范，仅占位；组件/状态命名替换为你的业务，分层与边界规则不变。实时交互界面经 WebSocket 展示服务端推送的状态变化。

## 技术栈

| 库 | 用途 |
|----|------|
| React 18 + Vite | 构建工具 + UI 框架 |
| TypeScript（strict mode） | 类型安全 |
| Tailwind CSS v3 | 样式（禁止自定义 CSS，全用 utility class） |
| Zustand | 全局状态管理 |
| TanStack Query v5 | 服务端状态（REST 请求） |
| Zod | 运行时 WebSocket 消息验证 |
| sonner | Toast 通知（错误/成功提示） |
| Vitest + Testing Library | 单元测试 |

## 包管理（pnpm）

```bash
pnpm add zustand @tanstack/react-query zod sonner
pnpm dev          # 开发服务器 http://localhost:5173
pnpm build        # 构建
pnpm test         # vitest（watch 模式）
pnpm test:run     # 单次运行（CI 用）
pnpm typecheck    # tsc --noEmit
```

关键文件：`package.json`、`pnpm-lock.yaml`（锁文件，必须提交 git）、`vite.config.ts`、`tsconfig.json`

## 环境配置（.env）

配置项见 `.env.example`（提交 git）；真实配置放 `.env`（gitignore）。

- **只有 `VITE_` 前缀的变量**才会被注入浏览器端代码，通过 `import.meta.env.VITE_XXX` 读取
- **前端变量对用户完全可见，严禁放任何密钥**（图片源 API Key 走 localStorage，不进 .env）

```typescript
const wsUrl = import.meta.env.VITE_BACKEND_WS_URL   // ws://localhost:8000
```

## 目录结构

```
frontend/
├── src/
│   ├── components/              # 纯 UI 组件（无业务逻辑，无直接 store 读写）
│   │   ├── OrderForm.tsx        # 录入/编辑表单（示范）
│   │   ├── OrderList.tsx        # 列表展示
│   │   ├── StatusBadge.tsx      # 状态标识
│   │   ├── ProgressBar.tsx      # 处理进度条
│   │   ├── ErrorBoundary.tsx    # React 错误边界（组件级异常）
│   │   └── Toast.tsx            # 全局 Toast 容器（sonner Toaster）
│   ├── pages/                   # 页面级组件（组合 components，接入 hooks）
│   │   └── OrderPage.tsx
│   ├── hooks/                   # 自定义 Hook（业务逻辑与副作用）
│   │   ├── useWebSocket.ts      # WebSocket 生命周期管理
│   │   └── useOrder.ts          # 会话状态机（dispatch + 状态衍生）
│   ├── services/                # 外部通信封装（纯函数，无 React 依赖）
│   │   └── wsClient.ts          # WebSocket send/receive，消息序列化
│   ├── store/                   # Zustand store
│   │   └── orderStore.ts        # session、messages、orders、status
│   ├── types/                   # TypeScript 类型（只定义，不实现）
│   │   └── messages.ts          # WsMessage、OrderDTO、SessionStatus 等
│   ├── schemas/                 # Zod schema（运行时验证，与 types 一一对应）
│   │   └── messages.ts          # wsMessageSchema、createOrderSchema 等
│   ├── utils/                   # 纯函数工具（无副作用）
│   │   └── format.ts            # 纯函数格式化（金额/日期等）
│   └── main.tsx                 # 入口：挂载 ErrorBoundary + Toaster
└── tests/
    ├── components/
    ├── hooks/
    └── schemas/
```

## 各层职责边界

| 层 | 可以做 | 不可以做 |
|----|--------|---------|
| `components/` | 渲染 props，emit 回调 | 直接读 store、发 WebSocket |
| `pages/` | 组合 components，调用 hooks | 包含复杂业务逻辑 |
| `hooks/` | 读写 store，调用 services | 返回 JSX |
| `services/` | 网络通信、序列化 | 读 store，使用 React API |
| `store/` | 持有状态，提供 actions | 包含副作用 |

## TypeScript 规范

- 开启 `strict: true`
- 命名：camelCase 变量/函数、PascalCase 组件/类型
- 禁止 `any`（用 `unknown` + 类型守卫）
- 所有 Zustand action 必须有明确返回类型
- Zod schema 与 TypeScript 类型通过 `z.infer<>` 保持同源，禁止手写重复类型
- **`types/messages.ts` 由后端 Pydantic 契约生成**（`pnpm gen:types`），禁止手改；改协议从后端改起（见根 CLAUDE.md「契约管理」）
- 线上 JSON 契约字段为 snake_case，故生成类型的 DTO 字段为 snake_case；前端自身内部标识符仍用 camelCase

## 测试规范

- 组件测试：Testing Library，测行为不测实现（不 query class/id，用 role/label）
- Hook 测试：`renderHook` + mock `wsClient`
- Schema 测试：Zod parse 合法/非法用例各覆盖
- ErrorBoundary 测试：注入 throw 的子组件，验证 fallback 渲染
- 覆盖率目标：hooks 和 schemas 100%，组件 > 70%
