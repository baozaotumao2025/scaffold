#!/usr/bin/env bash
# 设置本项目提交是否包含 Claude 署名（Co-Authored-By: Claude）。
# 策略存于 git config scaffold.includeClaude，由 commit-msg 门禁强制执行。
# 用法：./scripts/claude-attribution.sh on|off|status
set -euo pipefail

case "${1:-status}" in
  on)
    git config scaffold.includeClaude true
    echo "✓ 本项目提交将【保留】Claude 署名"
    ;;
  off)
    git config scaffold.includeClaude false
    echo "✓ 本项目提交将【移除】Claude 署名（默认）"
    ;;
  status)
    v="$(git config --get scaffold.includeClaude 2>/dev/null || echo 'false（默认，未显式设置）')"
    echo "scaffold.includeClaude = $v"
    ;;
  *)
    echo "用法: $0 on|off|status" >&2
    exit 2
    ;;
esac
