import time
from collections.abc import Awaitable, Callable

from loguru import logger
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response


class AccessLogMiddleware(BaseHTTPMiddleware):
    """结构化记录每个 HTTP 请求：method / path / status / 耗时。"""

    async def dispatch(
        self, request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        start = time.perf_counter()
        response = await call_next(request)
        duration_ms = round((time.perf_counter() - start) * 1000, 2)
        logger.info(
            "access | method={} path={} status={} duration_ms={}",
            request.method,
            request.url.path,
            response.status_code,
            duration_ms,
        )
        return response
