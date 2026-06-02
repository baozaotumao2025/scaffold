---
paths: ["backend/**", "agent/**", "frontend/**"]
---

# 错误码目录（错误契约）

> 错误码是契约的一部分，集中登记，禁止散落定义。

错误码是契约的一部分，前端按 `code` 分支处理，不依赖 `message` 文本。**集中登记，禁止散落定义。**

| code | 含义 | 来源 |
|------|------|------|
| `SESSION_NOT_FOUND` | 会话不存在 | Backend |
| `AGENT_UNAVAILABLE` | Agent 不可用 | Backend |
| `GEMINI_STARTUP_ERROR` | LLM CLI 启动失败 | Agent |
| `GEMINI_TIMEOUT` | LLM CLI 阶段超时 | Agent |
| `SKILL_NOT_INSTALLED` | 幻灯片生成 skill 未装 | Agent |
| `HTML_EXTRACTION_FAILED` | 无法提取有效 HTML | Agent |
| `PLAYWRIGHT_ERROR` | 截图失败 | Agent |
| `CHECKPOINT_LOST` | 断点不可恢复 | Agent |
| `CAPACITY_EXCEEDED` | 并发超额（排队） | Agent |
| `INVALID_INPUT` | 输入校验失败 | Backend/Agent |
| `INTERNAL_ERROR` | 未分类内部错误 | 任意 |

- 命名：`大类_具体`，全大写蛇形；新增错误码必须先登记到此表
- code 字面值散落在各服务的异常类（backend `src/exceptions/base.py` 的 `AppException` 子类、agent `src/domain/exceptions.py` 的 `AgentException` 子类）。**本表是单一来源**，异常类的 `code` 与本表对齐**靠 review 把关**，不做代码生成（多数 code 服务私有、跨线共享少，生成机制收益不抵复杂度）。改 code 先改本表，再改对应异常类。
- `GEMINI_*` 等历史命名沿用现有 code 字面值（契约稳定性优先），其语义已泛化为"LLM CLI"，不随当前厂商变化
