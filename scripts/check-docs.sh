#!/usr/bin/env bash
# 校验 README.md 是否记录了 template/ 的架构基座目录，防止文档随模板改动漂移。
# 仅作用于 scaffold 仓库自身（不进生成项目、不属 skill）。
# 用法：./scripts/check-docs.sh    退出码 0=同步 / 1=有未记录目录
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

if [ "$fail" -eq 0 ]; then
  echo "✓ README 已覆盖 template 的架构基座目录与关键产物"
else
  echo ""
  echo "→ 请更新 README.md 的「架构基座」章节与「脚手架内容」文件树后重试。"
  exit 1
fi
