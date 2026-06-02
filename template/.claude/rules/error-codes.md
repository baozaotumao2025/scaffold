---
paths: ["backend/**", "agent/**", "frontend/**"]
---

# 错误码目录（错误契约）

> 错误码是契约的一部分，集中登记，禁止散落定义。

错误码是契约的一部分，前端按 `code` 分支处理，不依赖 `message` 文本。**集中登记，禁止散落定义。**

下表为**示范**（订单域 + 通用基础设施码），按项目实际增删：

| code | 含义 | 来源 |
|------|------|------|
| `SESSION_NOT_FOUND` | 会话不存在 | Backend |
| `AGENT_UNAVAILABLE` | Agent 不可用 | Backend |
| `ORDER_NOT_FOUND` | 订单不存在 | Backend |
| `ORDER_STATE_INVALID` | 订单状态不允许此操作 | Backend/Agent |
| `LLM_STARTUP_ERROR` | LLM 启动/连接失败 | Agent |
| `EXTERNAL_SERVICE_TIMEOUT` | 外部依赖超时 | Agent |
| `EXTERNAL_SERVICE_ERROR` | 外部依赖返回错误 | Agent |
| `CHECKPOINT_LOST` | 断点不可恢复 | Agent |
| `CAPACITY_EXCEEDED` | 并发超额（排队） | Agent |
| `INVALID_INPUT` | 输入校验失败 | Backend/Agent |
| `INTERNAL_ERROR` | 未分类内部错误 | 任意 |

- 命名：`大类_具体`，全大写蛇形；新增错误码必须先登记到此表
- code 字面值散落在各服务的异常类（backend `src/exceptions/base.py` 的 `AppException` 子类、agent `src/domain/exceptions.py` 的 `AgentException` 子类）。**本表是单一来源**，异常类的 `code` 与本表对齐**靠 review 把关**，不做代码生成（多数 code 服务私有、跨线共享少，生成机制收益不抵复杂度）。改 code 先改本表，再改对应异常类。
- 外部依赖类错误码（`LLM_*` / `EXTERNAL_SERVICE_*`）与具体厂商解耦，换提供商不改 code。
