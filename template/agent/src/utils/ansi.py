import re

_ANSI_ESCAPE = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")


def strip_ansi(text: str) -> str:
    """过滤 ANSI 转义码。PTY 驱动的 CLI 输出推送前必须清洗（见 agent-llm-pty.md）。"""
    return _ANSI_ESCAPE.sub("", text)
