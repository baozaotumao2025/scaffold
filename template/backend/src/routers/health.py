from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
async def health() -> dict[str, str]:
    """存活探针。"""
    return {"status": "ok"}


@router.get("/ready")
async def ready() -> dict[str, str]:
    """就绪探针：可在此扩展依赖检查（DB 连通等）。"""
    return {"status": "ok"}
