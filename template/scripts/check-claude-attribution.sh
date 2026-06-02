#!/usr/bin/env bash
# commit-msg 门禁：按 scaffold.includeClaude 策略处理 Claude 署名。
# 由 pre-commit 在 commit-msg 阶段调用，参数 $1 为提交信息文件。
#   off（默认）：剥除 Co-Authored-By: Claude 行
#   on        ：保留（./scripts/claude-attribution.sh on）
set -euo pipefail

msg_file="${1:?用法: check-claude-attribution.sh <commit-msg-file>}"
include="$(git config --get scaffold.includeClaude 2>/dev/null || echo false)"
[ "$include" = "true" ] && exit 0

if grep -qiE 'co-authored-by:.*claude' "$msg_file"; then
  tmp="$(mktemp)"
  grep -viE 'co-authored-by:.*claude' "$msg_file" >"$tmp"
  mv "$tmp" "$msg_file"
  echo "🛡  已移除 Claude 署名（scaffold.includeClaude=false；保留请运行 ./scripts/claude-attribution.sh on）"
fi
exit 0
