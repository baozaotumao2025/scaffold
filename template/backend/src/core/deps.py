"""FastAPI 依赖注入装配点。

业务 service / repository 的依赖在此组装：路由依赖端口，端口实现在边界注入。
功能开发时把 get_xxx_repo / get_xxx_service 加在这里（见 .claude/rules/backend.md）。
"""

from ..infrastructure.db.base import get_db

__all__ = ["get_db"]
