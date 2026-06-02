#!/usr/bin/env bash
# scaffold 仓库自身的一致性检查（不进生成项目、不属 skill）：
#   1) README 是否记录了 template/ 的架构基座目录（防文档漂移）
#   2) skill 自包含的 verify.sh 是否与根 scripts/verify.sh 同步（防两份漂移）
# 用法：./scripts/check-docs.sh    退出码 0=一致 / 1=有问题
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$ROOT/README.md"
fail=0

check_service_layers() {
  local svc="$1" srcdir="$ROOT/template/$svc/src"
  [ -d "$srcdir" ] || return 0
  for d in "$srcdir"/*/; do
    [ -d "$d" ] || continue
    local name
    name="$(basename "$d")"
    if ! grep -q "$name" "$README"; then
      echo "✗ template/$svc/src/$name/ 未在 README 记录"
      fail=1
    fi
  done
}

for svc in backend agent frontend; do
  check_service_layers "$svc"
done

# 顶层关键产物也应在 README 出现
for entry in ".vscode" ".claude/commands" ".copier-answers.yml" "pnpm-workspace.yaml"; do
  if [ -e "$ROOT/template/$entry" ] && ! grep -q "$(basename "$entry")" "$README"; then
    echo "✗ template/$entry 未在 README 记录"
    fail=1
  fi
done

# ── skill 自包含校验：两份 verify.sh 必须一致 ──────────────────────────────
ROOT_VERIFY="$ROOT/scripts/verify.sh"
SKILL_VERIFY="$ROOT/.claude/skills/new-project/scripts/verify.sh"
if [ -f "$ROOT_VERIFY" ] && [ -f "$SKILL_VERIFY" ]; then
  if ! cmp -s "$ROOT_VERIFY" "$SKILL_VERIFY"; then
    echo "✗ scripts/verify.sh 与 skill 内副本不一致"
    echo "  改了 scripts/verify.sh 后需同步：cp scripts/verify.sh .claude/skills/new-project/scripts/verify.sh"
    fail=1
  fi
else
  echo "✗ verify.sh 缺失（根或 skill 内）"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "✓ README 覆盖 template 架构基座目录；skill verify.sh 与根一致"
else
  echo ""
  echo "→ 修复上述问题后重试（文档更新 / 同步 verify.sh）。"
  exit 1
fi
