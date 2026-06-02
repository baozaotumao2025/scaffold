---
paths: ["frontend/**"]
---

# frontend-runtime

前端运行时规范：错误处理三层防线、日志、WebSocket 消息验证、页面交互状态流。

## 错误处理三层防线

### 1. 组件级 ErrorBoundary（捕获渲染异常）

```tsx
// components/ErrorBoundary.tsx
class ErrorBoundary extends React.Component {
  componentDidCatch(error: Error) {
    logger.error('Component error', { error: error.message })
    toast.error('页面渲染出错，请刷新重试')
  }
  render() {
    return this.state.hasError ? <FallbackUI /> : this.props.children
  }
}
```

### 2. WebSocket 消息验证失败（Zod parse 异常）

```typescript
// hooks/useWebSocket.ts
try {
  const msg = wsMessageSchema.parse(JSON.parse(event.data))
  dispatch(msg)
} catch (e) {
  // 验证失败：记录日志，不更新状态，不崩溃
  logger.warn('Invalid WS message', { raw: event.data, error: e })
}
```

### 3. 全局未捕获异常

```typescript
// main.tsx
window.addEventListener('unhandledrejection', (event) => {
  logger.error('Unhandled promise rejection', { reason: event.reason })
  toast.error('发生未知错误，请检查网络后重试')
})
```

### 错误展示规则

| 错误类型 | 展示方式 |
|---------|---------|
| WebSocket 连接失败 | Toast（error）+ 重连提示 |
| 外部服务超时/失败 | 系统消息气泡 + Toast |
| 文件下载失败 | Toast（error） |
| 组件渲染崩溃 | ErrorBoundary fallback UI |

## 日志规范（utils/logger）

使用轻量前端日志库或自封装（dev 输出 console，prod 静默或上报）：

```typescript
// utils/logger.ts
const logger = {
  info: (msg: string, ctx?: object) => {
    if (import.meta.env.DEV) console.info(`[INFO] ${msg}`, ctx)
  },
  warn: (msg: string, ctx?: object) => {
    console.warn(`[WARN] ${msg}`, ctx)
  },
  error: (msg: string, ctx?: object) => {
    console.error(`[ERROR] ${msg}`, ctx)
    // prod 环境可接入 Sentry / 自建上报
  },
}
```

**禁止在组件/hooks 中直接使用 `console.log`，统一用 `logger`。**

## WebSocket 消息验证

收到消息必须先 Zod 验证（`safeParse`）再更新 store，验证失败不崩溃只记录：

```typescript
const msg = wsMessageSchema.safeParse(JSON.parse(event.data))
if (!msg.success) {
  logger.warn('Invalid WS message', { error: msg.error.flatten() })
  return
}
dispatch(msg.data)
```

## 页面交互状态流

下面是**示范**状态流（订单），按你的业务替换状态与展示：

```
idle ──► editing ──► submitting ──► processing ──► done
                                                     │
                                            revising ◄┘
```

| 状态 | 展示内容 |
|------|---------|
| `idle` | 初始引导 |
| `editing` | 表单录入（OrderForm） |
| `submitting` | 提交中（ProgressBar） |
| `processing` | 服务端处理中（ProgressBar + 日志） |
| `done` | 结果展示 + 操作入口（可触发 revising） |
| `error` | 错误提示 + 重试按钮 |
