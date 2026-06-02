---
paths: ["backend/**", "agent/**", "frontend/**"]
---

# 消息目录（payload 形状）

> 查阅型：各消息 type 的 payload 形状，外层由信封包裹（见 `communication-protocol.md`）。字段一律 snake_case。

> 以下以「订单」为示范业务，仅占位；按项目实际定义自己的消息。

命令（Browser → Backend → Agent）：

```json
{"type": "start_session", "channel": "web"}
{"type": "create_order",  "items": [{"sku": "A-1", "qty": 2}]}
{"type": "submit_order",  "order_id": "..."}
```

事件（Agent → Backend → Browser）：

```json
{"type": "order_created",   "order_id": "...", "status": "pending"}
{"type": "item_priced",     "sku": "A-1", "amount": {"currency": "CNY", "value": 1990}}
{"type": "log",             "message": "正在校验库存 2/3"}
{"type": "order_confirmed", "order_id": "..."}
{"type": "done"}
{"type": "error",           "code": "EXTERNAL_SERVICE_TIMEOUT", "message": "..."}
```
