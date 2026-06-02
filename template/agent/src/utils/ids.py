import uuid


def new_uuid() -> str:
    """生成新的 UUID4 字符串（用于 session_id 等）。"""
    return str(uuid.uuid4())
