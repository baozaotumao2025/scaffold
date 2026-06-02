# 通信协议与交互规约

> 传输选型 + 命令/事件分离 + 消息信封 + 语义保证 + 形式化 + 协议版本化。线上 JSON 契约字段一律 **snake_case**。各消息 payload 形状见 `communication-catalog.md`（按 paths 加载）。

## 传输层选型

| 通道 | 传输 | 适用 | 理由 |
|------|------|------|------|
| 交互 / 流式 | WebSocket | FE↔BE、BE↔Agent | 长连接、双向、服务端持续推流 |
| 幂等资源获取 | REST `/api/v1` | 下载 / 预览 | 无状态、可缓存、可重试 |

## 交互范式：异步事件驱动 + 命令/事件分离（CQRS 式消息）

- **命令（Command）**：客户端→服务端，表达*意图*，可被拒绝（示范：`start_session` / `create_order` / `submit_order`）
- **事件（Event）**：服务端→客户端，陈述*已发生的事实*，单向广播（示范：`order_created` / `item_priced` / `order_confirmed` / `done` / `error`）
- 命令与事件语义不混用

### 命令幂等（Idempotency，强制）

投递是 at-most-once，但断连/重连/前端重发会让同一命令到达多次，故**所有命令必须可安全重复执行**——重复执行的副作用等价于执行一次。这是命令的**后置条件契约**（属 DbC，见 `design-discipline.md`），非可选优化。

- **幂等键**：命令以 `correlation_id` 作幂等键去重；服务端对已处理的 `correlation_id` 直接回放上次结果，不重复触发副作用（不重复起会话 / 不重复扣资源 / 不重复落库）。
- **天然幂等优先**：能用「设置为目标态」就不用「增量变更」。`submit_order`（置为已提交态）是幂等 ✅；任何"追加一次""+1"式语义需显式去重。
- **REST 幂等**：`/download` `/preview` 为只读 GET，天然幂等可重试可缓存（见传输层选型）。
- **校验点**：命令处理入口先查幂等键，再执行；新增命令时在 PR 说明其幂等策略（天然幂等 / 键去重）。

## 消息信封（Envelope）

所有消息统一外层结构，`type` 为判别式（discriminated union），决定 `payload` 形状。**外层与 payload 字段一律 snake_case。**

```json
{
  "v": 1,                       // 协议版本
  "type": "order_created",      // 判别式
  "correlation_id": "uuid",     // 全链路追踪 id
  "ts": "2026-05-31T08:00:00Z", // 发出时间（ISO-8601）
  "payload": { ... }            // 与 type 对应的强类型体
}
```

## 语义保证

- **有序性**：同一连接内有序（WS 保证）；跨连接无序
- **投递**：至多一次（at-most-once）；断连恢复靠 Checkpoint，不靠消息重放
- **背压**：超并发上限的会话排队，以 `CAPACITY_EXCEEDED` 事件告知位置
- **错误**：统一 `error` 事件，`code` 取自「错误码目录」（见 `error-codes.md`），前端按 `code` 分支
- **版本**：见下「协议版本化」

## 协议版本化

- 破坏性变更升信封 `v`；旧版本保留一个过渡期再下线
- 前端按 `v` 兼容处理；不兼容的 `v` 直接以 `INVALID_INPUT` 拒绝

## 形式化与一致性（契约单一来源，防漂移）

WebSocket 消息协议是三层共享契约。**禁止在 Pydantic 和 Zod 两处各写一遍**——会漂移。

- 契约单一来源：`backend/src/schemas/messages.py`（Pydantic 判别联合，字段 snake_case）
- 前端类型由契约**生成**，不手写：`pnpm gen:types` 用 `pydantic2ts` / openapi 导出 TS 类型到 `frontend/src/types/messages.ts`
- 前端 Zod schema 与生成的类型保持同源（`z.infer` 校验一致性）
- 可导出 **AsyncAPI** 文档作为对外形式化规约
- 后端代理**透明转发** BE↔Agent，不改写信封
- 改协议流程：改 Pydantic → 跑生成 → 前端编译报错处即需同步的点

## 消息目录

各消息 type 的 payload 形状见 `communication-catalog.md`（查阅型，按 paths 加载）。
