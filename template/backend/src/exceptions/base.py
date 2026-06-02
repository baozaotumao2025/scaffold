class AppException(Exception):  # noqa: N818  # 规则约定名为 AppException（见 backend.md）
    """业务异常基类。

    `code` 对应错误码契约（见 .claude/rules/error-codes.md），前端按 code 分支处理。
    禁止在路由层直接 raise HTTPException——抛 AppException 子类，
    由 error_handler 统一转译。
    """

    def __init__(self, code: str, message: str, status_code: int = 500) -> None:
        self.code = code
        self.message = message
        self.status_code = status_code
        super().__init__(message)


class InvalidInputError(AppException):
    def __init__(self, message: str = "输入校验失败") -> None:
        super().__init__("INVALID_INPUT", message, status_code=400)


class InternalError(AppException):
    def __init__(self, message: str = "服务器内部错误") -> None:
        super().__init__("INTERNAL_ERROR", message, status_code=500)
