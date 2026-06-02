from collections.abc import Awaitable, Callable

from loguru import logger
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from ..utils.ids import new_uuid


class RequestIdMiddleware(BaseHTTPMiddleware):
    """为每个请求注入 X-Request-Id，并绑定到 loguru 上下文，贯穿全链路日志。"""

    async def dispatch(
        self, request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        request_id = request.headers.get("X-Request-Id") or new_uuid()
        request.state.request_id = request_id
        with logger.contextualize(request_id=request_id):
            response = await call_next(request)
        response.headers["X-Request-Id"] = request_id
        return response
