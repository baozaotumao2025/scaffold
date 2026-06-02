from pathlib import Path


def expand(path: str) -> Path:
    """展开 ~ 与环境变量，返回绝对 Path。"""
    return Path(path).expanduser().resolve()


def ensure_dir(path: Path) -> Path:
    """确保目录存在（含父级），返回该目录。"""
    path.mkdir(parents=True, exist_ok=True)
    return path


def session_dir(work_dir: str, session_id: str) -> Path:
    """某会话的独立工作目录 {work_dir}/{session_id}/，不存在则创建。"""
    return ensure_dir(expand(work_dir) / session_id)


def safe_within(work_dir: str, candidate: str) -> Path:
    """校验 candidate 解析后仍在 work_dir 内（防路径穿越），否则抛 ValueError。"""
    root = expand(work_dir)
    target = (root / candidate).resolve()
    if not target.is_relative_to(root):
        raise ValueError(f"路径越界: {candidate}")
    return target
