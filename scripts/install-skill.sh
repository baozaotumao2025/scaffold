#!/usr/bin/env bash
# 把 new-project skill 安装到 ~/.claude/skills/（全局，任意项目可用）。
#
# 单一源原则：verify.sh 只在仓库根 scripts/ 维护一份，
# 本脚本在安装时把它和 SKILL.md 组装进 ~/.claude/skills/new-project/，
# 使安装后的 skill 自包含（无需仓库即可运行验证）。
#
# 用法：
#   curl -fsSL https://raw.githubusercontent.com/baozaotumao2025/scaffold/main/scripts/install-skill.sh | bash
# 或在已克隆的仓库内：
#   ./scripts/install-skill.sh
set -euo pipefail

SKILL_NAME="new-project"
DEST="$HOME/.claude/skills/$SKILL_NAME"
RAW_BASE="https://raw.githubusercontent.com/baozaotumao2025/scaffold/main"
SKILL_MD_URL="$RAW_BASE/.claude/skills/$SKILL_NAME/SKILL.md"
VERIFY_URL="$RAW_BASE/scripts/verify.sh"

# 在仓库内运行时优先用本地文件，否则从 GitHub 拉取
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_SKILL_MD="$SCRIPT_DIR/../.claude/skills/$SKILL_NAME/SKILL.md"
LOCAL_VERIFY="$SCRIPT_DIR/verify.sh"

fetch() {  # fetch <url> <dest>
  if command -v curl &>/dev/null; then
    curl -fsSL "$1" -o "$2"
  elif command -v wget &>/dev/null; then
    wget -qO "$2" "$1"
  else
    echo "错误：需要 curl 或 wget" >&2
    exit 1
  fi
}

mkdir -p "$DEST/scripts"

if [[ -f "$LOCAL_SKILL_MD" && -f "$LOCAL_VERIFY" ]]; then
  echo "→ 从本地仓库组装安装"
  cp "$LOCAL_SKILL_MD" "$DEST/SKILL.md"
  cp "$LOCAL_VERIFY"   "$DEST/scripts/verify.sh"
else
  echo "→ 从 GitHub 组装安装"
  fetch "$SKILL_MD_URL" "$DEST/SKILL.md"
  fetch "$VERIFY_URL"   "$DEST/scripts/verify.sh"
fi

chmod +x "$DEST/scripts/verify.sh"

echo "✓ 已安装 skill 到 $DEST"
echo "  在任意项目中打开 Claude Code，输入 /$SKILL_NAME 或描述\"新建项目\"即可触发"
