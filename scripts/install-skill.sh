#!/usr/bin/env bash
# 把 new-project skill 安装到 ~/.claude/skills/（全局，任意项目可用）。
#
# skill 目录是自包含的（SKILL.md + scripts/verify.sh 都在 .claude/skills/new-project/ 内），
# 安装即整目录拷贝——符合 skill 自包含、可移植的惯例，无需"组装"。
#
# 用法：
#   curl -fsSL https://raw.githubusercontent.com/baozaotumao2025/scaffold/main/scripts/install-skill.sh | bash
# 或在已克隆的仓库内：
#   ./scripts/install-skill.sh
set -euo pipefail

SKILL_NAME="new-project"
DEST="$HOME/.claude/skills/$SKILL_NAME"
RAW_BASE="https://raw.githubusercontent.com/baozaotumao2025/scaffold/main/.claude/skills/$SKILL_NAME"
# skill 自包含的文件清单（新增文件时在此登记）
FILES=("SKILL.md" "scripts/verify.sh")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_SKILL="$SCRIPT_DIR/../.claude/skills/$SKILL_NAME"

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

if [[ -d "$LOCAL_SKILL" ]]; then
  echo "→ 从本地仓库整目录拷贝"
  cp -R "$LOCAL_SKILL/." "$DEST/"
else
  echo "→ 从 GitHub 拉取 skill 文件"
  for f in "${FILES[@]}"; do
    fetch "$RAW_BASE/$f" "$DEST/$f"
  done
fi

chmod +x "$DEST/scripts/verify.sh"

echo "✓ 已安装 skill 到 $DEST"
echo "  在任意项目中打开 Claude Code，输入 /$SKILL_NAME 或描述\"新建项目\"即可触发"
