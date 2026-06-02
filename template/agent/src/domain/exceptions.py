class AgentException(Exception):  # noqa: N818  # 规则约定名为 AgentException
    """Agent 领域异常基类。

    `code` 对应错误码契约（见 .claude/rules/error-codes.md）。属领域层词汇，
    由 domain 拥有；框架级 handler 注册在接口层。
    """

    def __init__(self, code: str, message: str, status_code: int = 500) -> None:
        self.code = code
        self.message = message
        self.status_code = status_code
        super().__init__(message)


class LLMStartupError(AgentException):
    def __init__(self) -> None:
        super().__init__("LLM_STARTUP_ERROR", "LLM 启动/连接失败")


class ExternalServiceTimeoutError(AgentException):
    def __init__(self, phase: str) -> None:
        super().__init__("EXTERNAL_SERVICE_TIMEOUT", f"外部依赖在 {phase} 阶段超时")


class ExternalServiceError(AgentException):
    def __init__(self, detail: str) -> None:
        super().__init__("EXTERNAL_SERVICE_ERROR", f"外部依赖返回错误: {detail}")


class OutputValidationError(AgentException):
    def __init__(self) -> None:
        super().__init__("INVALID_INPUT", "无法从输出中提取有效结果")
