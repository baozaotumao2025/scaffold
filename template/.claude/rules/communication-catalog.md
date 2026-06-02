---
paths: ["backend/**", "agent/**", "frontend/**"]
---

# 消息目录（payload 形状）

> 查阅型：各消息 type 的 payload 形状，外层由信封包裹（见 `communication-protocol.md`）。字段一律 snake_case。

命令（Browser → Backend → Agent）：

```json
{"type": "start_session", "language": "中文", "image_source": "unsplash", "image_api_key": "xxx"}
{"type": "user_input",    "text": "深圳科技政策解读"}
{"type": "style_pick",    "index": 2}
```

事件（Agent → Backend → Browser）：

```json
{"type": "gemini_message", "text": "请问你的 PPT 主旨是什么？"}
{"type": "style_preview",  "index": 1, "preview_url": "/api/v1/preview/{sid}/preview_1.html"}
{"type": "log",            "message": "📸 截图第 3/10 页"}
{"type": "html_ready",     "session_id": "..."}
{"type": "pptx_ready",     "session_id": "..."}
{"type": "done"}
{"type": "error",          "code": "GEMINI_TIMEOUT", "message": "..."}
```
