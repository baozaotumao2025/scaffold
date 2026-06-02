#!/usr/bin/env bash
# verify.sh — 检查项目工具链配置是否完整
#
# 用法：
#   ./scripts/verify.sh [OPTIONS] [PROJECT_PATH]
#
# 选项：
#   -h, --help      显示帮助信息
#   -v, --verbose   详细输出（显示所有通过项和跳过项）
#   -s, --strict    严格模式：警告也视为失败
#
# 退出码：
#   0  全部通过（严格模式下无警告且无失败）
#   1  存在失败项
#   2  命令行参数错误

set -euo pipefail

# ── 默认值 ────────────────────────────────────────────────────────────────────
VERBOSE=0
STRICT=0
ROOT="."

# ── 全局计数（按分类） ────────────────────────────────────────────────────────
# 用索引数组而非关联数组（declare -A），以兼容 macOS 自带的 bash 3.2。
CATEGORIES=("根目录" "Backend" "Agent" "Frontend" "Pre-commit 钩子" "Claude 规则文件" "工具链可用性")
CAT_PASS=(); CAT_WARN=(); CAT_FAIL=()
for _i in "${!CATEGORIES[@]}"; do CAT_PASS[$_i]=0; CAT_WARN[$_i]=0; CAT_FAIL[$_i]=0; done
TOTAL_PASS=0
TOTAL_WARN=0
TOTAL_FAIL=0
CURRENT_CAT=""
CURRENT_IDX=-1

# ── 颜色 ──────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_RED='\033[31m'
  C_CYAN='\033[36m';  C_BOLD='\033[1m';    C_RESET='\033[0m'
else
  C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''; C_BOLD=''; C_RESET=''
fi

# ── 帮助 ──────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
${C_BOLD}用法：${C_RESET} $(basename "$0") [OPTIONS] [PROJECT_PATH]

检查项目工具链配置是否符合 scaffold 规范。
不修改任何文件，安全幂等，可重复运行。

${C_BOLD}选项：${C_RESET}
  -h, --help      显示此帮助信息
  -v, --verbose   详细输出（含通过项、跳过项的具体路径）
  -s, --strict    严格模式：警告（WARN）也视为失败，退出码 1

${C_BOLD}参数：${C_RESET}
  PROJECT_PATH    要检查的项目根目录（默认：当前目录）

${C_BOLD}示例：${C_RESET}
  $(basename "$0")                     # 检查当前目录
  $(basename "$0") /path/to/project    # 检查指定目录
  $(basename "$0") -v -s .             # 详细 + 严格模式

${C_BOLD}退出码：${C_RESET}
  0   全部通过（严格模式下无警告）
  1   存在失败项（或严格模式下存在警告）
  2   参数错误
EOF
}

# ── 参数解析 ──────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    usage; exit 0 ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -s|--strict)  STRICT=1; shift ;;
    -vs|-sv)      VERBOSE=1; STRICT=1; shift ;;
    -*)           echo "未知选项: $1" >&2; usage >&2; exit 2 ;;
    *)            ROOT="$1"; shift ;;
  esac
done

ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "路径不存在: $ROOT" >&2; exit 2; }

# ── 输出辅助 ──────────────────────────────────────────────────────────────────
log_pass() {
  TOTAL_PASS=$((TOTAL_PASS + 1))
  [ "$CURRENT_IDX" -ge 0 ] && CAT_PASS[$CURRENT_IDX]=$(( ${CAT_PASS[$CURRENT_IDX]:-0} + 1 ))
  [ "$VERBOSE" -eq 1 ] && printf "  ${C_GREEN}✓${C_RESET} %s\n" "$*"
  return 0
}

log_warn() {
  TOTAL_WARN=$((TOTAL_WARN + 1))
  [ "$CURRENT_IDX" -ge 0 ] && CAT_WARN[$CURRENT_IDX]=$(( ${CAT_WARN[$CURRENT_IDX]:-0} + 1 ))
  printf "  ${C_YELLOW}△${C_RESET} %s\n" "$*"
}

log_fail() {
  TOTAL_FAIL=$((TOTAL_FAIL + 1))
  [ "$CURRENT_IDX" -ge 0 ] && CAT_FAIL[$CURRENT_IDX]=$(( ${CAT_FAIL[$CURRENT_IDX]:-0} + 1 ))
  printf "  ${C_RED}✗${C_RESET} %s\n" "$*"
}

log_skip() {
  [ "$VERBOSE" -eq 1 ] && printf "  ${C_CYAN}–${C_RESET} %s\n" "$*"
  return 0
}

section() {
  CURRENT_CAT="$1"
  CURRENT_IDX=-1
  local i
  for i in "${!CATEGORIES[@]}"; do
    [ "${CATEGORIES[$i]}" = "$1" ] && { CURRENT_IDX=$i; break; }
  done
  printf "\n${C_BOLD}[ %s ]${C_RESET}\n" "$1"
}

# ── 检查函数 ──────────────────────────────────────────────────────────────────
# 检查文件或目录是否存在
check() {
  local label="$1" path="$2" severity="${3:-fail}"
  if [ -e "$ROOT/$path" ]; then
    log_pass "$label"
  else
    [ "$severity" = "warn" ] && log_warn "$label — 缺失: $path" || log_fail "$label — 缺失: $path"
  fi
}

# 检查文件中是否包含指定内容
check_contains() {
  local label="$1" path="$2" pattern="$3" severity="${4:-fail}"
  if [ ! -e "$ROOT/$path" ]; then
    log_skip "$label — 文件不存在，跳过内容检查: $path"
    return
  fi
  if grep -q "$pattern" "$ROOT/$path" 2>/dev/null; then
    log_pass "$label"
  else
    [ "$severity" = "warn" ] \
      && log_warn "$label — 未找到 '$pattern' 在 $path" \
      || log_fail "$label — 未找到 '$pattern' 在 $path"
  fi
}

# 检查命令是否可用
check_cmd() {
  local label="$1" cmd="$2" severity="${3:-warn}"
  if command -v "$cmd" &>/dev/null; then
    local ver
    ver=$(${cmd} --version 2>/dev/null | head -1 || echo "版本未知")
    log_pass "$label ($ver)"
  else
    [ "$severity" = "warn" ] && log_warn "$label — 未安装: $cmd" || log_fail "$label — 未安装: $cmd"
  fi
}

# ── 读取 copier 配置（可选）────────────────────────────────────────────────────
COPIER_ANSWERS="$ROOT/.copier-answers.yml"
LLM_PROVIDER=""
DB_TYPE=""
if [ -f "$COPIER_ANSWERS" ]; then
  LLM_PROVIDER=$(grep "^llm_provider:" "$COPIER_ANSWERS" 2>/dev/null | awk '{print $2}' | tr -d "\"'" || true)
  DB_TYPE=$(grep "^database:" "$COPIER_ANSWERS" 2>/dev/null | awk '{print $2}' | tr -d "\"'" || true)
fi

# ── 开始检查 ──────────────────────────────────────────────────────────────────
printf "${C_BOLD}═══ 工具链合规检查: %s ═══${C_RESET}\n" "$ROOT"
[ -n "$LLM_PROVIDER" ] && printf "${C_CYAN}配置来源：.copier-answers.yml  llm_provider=%s  database=%s${C_RESET}\n" \
  "${LLM_PROVIDER:-?}" "${DB_TYPE:-?}"

# ── 根目录 ────────────────────────────────────────────────────────────────────
section "根目录"
check "Git 仓库"            ".git"
check "Pre-commit 配置"     ".pre-commit-config.yaml"
check "Gitignore"           ".gitignore"
check "CLAUDE.md"           "CLAUDE.md"
check "Docker Compose"      "docker-compose.yml" "warn"
check "Copier 答案文件"     ".copier-answers.yml" "warn"

# ── Backend ───────────────────────────────────────────────────────────────────
if [ -d "$ROOT/backend" ]; then
  section "Backend"
  check          "pyproject.toml"          "backend/pyproject.toml"
  check          "uv.lock"                 "backend/uv.lock"
  check          ".env.example"            "backend/.env.example"
  check          "Dockerfile"              "backend/Dockerfile" "warn"
  check_contains "ruff 命名规则 N"         "backend/pyproject.toml" '"N"'
  check_contains "ruff 禁 print T20"       "backend/pyproject.toml" '"T20"'
  check_contains "mypy strict"             "backend/pyproject.toml" "strict = true"
  check_contains "pytest-asyncio 配置"     "backend/pyproject.toml" "asyncio_mode"
  if [ -n "$DB_TYPE" ]; then
    local_driver="aiosqlite"
    [ "$DB_TYPE" = "postgresql" ] && local_driver="asyncpg"
    check_contains "DB driver ($DB_TYPE)"  "backend/pyproject.toml" "$local_driver"
  fi
else
  log_skip "Backend 目录不存在，跳过 Backend 检查"
fi

# ── Agent ─────────────────────────────────────────────────────────────────────
if [ -d "$ROOT/agent" ]; then
  section "Agent"
  check          "pyproject.toml"           "agent/pyproject.toml"
  check          "uv.lock"                  "agent/uv.lock"
  check          ".env.example"             "agent/.env.example"
  check          "Dockerfile"               "agent/Dockerfile" "warn"
  check_contains "ruff 命名规则 N"          "agent/pyproject.toml" '"N"'
  check_contains "ruff 禁 print T20"        "agent/pyproject.toml" '"T20"'
  check_contains "mypy strict"              "agent/pyproject.toml" "strict = true"
  check_contains "pytest-asyncio 配置"      "agent/pyproject.toml" "asyncio_mode"
  if [ -n "$LLM_PROVIDER" ]; then
    case "$LLM_PROVIDER" in
      gemini-cli)    : ;;  # pty 是标准库，无需额外包
      openai-api)    check_contains "openai SDK"    "agent/pyproject.toml" "openai" ;;
      anthropic-api) check_contains "anthropic SDK" "agent/pyproject.toml" "anthropic" ;;
    esac
  fi
else
  log_skip "Agent 目录不存在，跳过 Agent 检查"
fi

# ── Frontend ──────────────────────────────────────────────────────────────────
if [ -d "$ROOT/frontend" ]; then
  section "Frontend"
  check          "package.json"          "frontend/package.json"
  check          "pnpm-lock.yaml"        "frontend/pnpm-lock.yaml"
  check          ".env.example"          "frontend/.env.example"
  check          "tsconfig.json"         "frontend/tsconfig.json"
  check          "vite.config.ts"        "frontend/vite.config.ts"
  check          "vitest.config.ts"      "frontend/vitest.config.ts" "warn"
  check          "eslint.config.js"      "frontend/eslint.config.js"
  check_contains "禁 console.log"        "frontend/eslint.config.js" "no-console"
  check_contains "命名约定规则"          "frontend/eslint.config.js" "naming-convention"
  check_contains "TypeScript strict"     "frontend/tsconfig.json"    '"strict": true'
else
  log_skip "Frontend 目录不存在，跳过 Frontend 检查"
fi

# ── Pre-commit 钩子 ───────────────────────────────────────────────────────────
if [ -f "$ROOT/.pre-commit-config.yaml" ]; then
  section "Pre-commit 钩子"
  check_contains "Conventional Commits" ".pre-commit-config.yaml" "conventional-pre-commit"
  check_contains "ruff lint/format"     ".pre-commit-config.yaml" "ruff"
  check_contains "防密钥泄漏"           ".pre-commit-config.yaml" "detect-private-key"
  check_contains "gitleaks"             ".pre-commit-config.yaml" "gitleaks" "warn"
  check          "Git hooks 已安装"     ".git/hooks/pre-commit" "warn"
fi

# ── Claude 规则文件 ───────────────────────────────────────────────────────────
if [ -d "$ROOT/.claude/rules" ]; then
  section "Claude 规则文件"
  RULES_DIR="$ROOT/.claude/rules"

  # 全局规则（原理层，始终期望存在）
  GLOBAL_RULES=(architecture.md ddd.md design-discipline.md communication-protocol.md
                testing-tdd.md quality-gates.md security.md config.md
                git-workflow.md conventions.md)
  for r in "${GLOBAL_RULES[@]}"; do
    check "全局规则: $r" ".claude/rules/$r"
  done

  # Backend 落地层规则
  if [ -d "$ROOT/backend" ]; then
    check "Backend 规则: backend.md"          ".claude/rules/backend.md"
    check "Backend 规则: backend-db.md"       ".claude/rules/backend-db.md"
    check "Backend 规则: backend-concurrency.md" ".claude/rules/backend-concurrency.md"
  fi

  # Agent 落地层规则
  if [ -d "$ROOT/agent" ]; then
    check "Agent 规则: agent.md"               ".claude/rules/agent.md"
    check "Agent 规则: agent-dag.md"           ".claude/rules/agent-dag.md"
    check "Agent 规则: agent-concurrency.md"   ".claude/rules/agent-concurrency.md"
    check "Agent 规则: agent-extension-points.md" ".claude/rules/agent-extension-points.md"

    # LLM 驱动层规则：按 llm_provider 检查正确的变体
    if [ -z "$LLM_PROVIDER" ] || [ "$LLM_PROVIDER" = "gemini-cli" ]; then
      check "Agent LLM 驱动规则: agent-llm-pty.md" ".claude/rules/agent-llm-pty.md"
      if [ -f "$RULES_DIR/agent-llm-api.md" ]; then
        log_warn "Agent LLM 驱动规则冲突 — agent-llm-api.md 不应与 gemini-cli 共存"
      fi
    else
      check "Agent LLM 驱动规则: agent-llm-api.md" ".claude/rules/agent-llm-api.md"
      if [ -f "$RULES_DIR/agent-llm-pty.md" ]; then
        log_warn "Agent LLM 驱动规则冲突 — agent-llm-pty.md 不应与 $LLM_PROVIDER 共存"
      fi
    fi
  fi

  # Frontend 落地层规则
  if [ -d "$ROOT/frontend" ]; then
    check "Frontend 规则: frontend.md"         ".claude/rules/frontend.md"
    check "Frontend 规则: frontend-runtime.md" ".claude/rules/frontend-runtime.md"
  fi

  # 跨服务规则
  if [ -d "$ROOT/backend" ] && [ -d "$ROOT/agent" ]; then
    check "跨服务规则: data-lifecycle.md"      ".claude/rules/data-lifecycle.md"
    check "跨服务规则: communication-catalog.md" ".claude/rules/communication-catalog.md" "warn"
    check "跨服务规则: error-codes.md"         ".claude/rules/error-codes.md" "warn"
  fi
else
  log_warn ".claude/rules/ 目录不存在 — Claude 规则文件未部署"
fi

# ── 工具链可用性（信息性，不影响退出码）─────────────────────────────────────
section "工具链可用性"
check_cmd "uv"          "uv"         "warn"
check_cmd "pnpm"        "pnpm"       "warn"
check_cmd "pre-commit"  "pre-commit" "warn"
check_cmd "copier"      "copier"     "warn"
if [ -d "$ROOT/agent" ]; then
  check_cmd "playwright" "playwright" "warn"
fi

# ── 汇总 ──────────────────────────────────────────────────────────────────────
printf "\n${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
printf "${C_BOLD}%-22s %6s %6s %6s${C_RESET}\n" "分类" "通过" "警告" "失败"
printf "───────────────────────────────────────────────────────────────\n"
for i in "${!CATEGORIES[@]}"; do
  cat="${CATEGORIES[$i]}"
  p=${CAT_PASS[$i]:-0}; w=${CAT_WARN[$i]:-0}; f=${CAT_FAIL[$i]:-0}
  [ $((p + w + f)) -eq 0 ] && continue
  wc="${C_RESET}"; fc="${C_RESET}"
  [ "$w" -gt 0 ] && wc="${C_YELLOW}"
  [ "$f" -gt 0 ] && fc="${C_RED}"
  printf "%-22s ${C_GREEN}%6d${C_RESET} ${wc}%6d${C_RESET} ${fc}%6d${C_RESET}\n" \
    "$cat" "$p" "$w" "$f"
done
printf "───────────────────────────────────────────────────────────────\n"
wc="${C_RESET}"; fc="${C_RESET}"
[ "$TOTAL_WARN" -gt 0 ] && wc="${C_YELLOW}"
[ "$TOTAL_FAIL" -gt 0 ] && fc="${C_RED}"
printf "${C_BOLD}%-22s ${C_GREEN}%6d${C_RESET} ${wc}%6d${C_RESET} ${fc}%6d${C_RESET}${C_BOLD}${C_RESET}\n" \
  "合计" "$TOTAL_PASS" "$TOTAL_WARN" "$TOTAL_FAIL"
printf "${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"

# 最终判定
if [ "$TOTAL_FAIL" -gt 0 ]; then
  printf "\n${C_RED}${C_BOLD}✗ %d 项失败，项目尚不合规${C_RESET}\n" "$TOTAL_FAIL"
  [ "$TOTAL_WARN" -gt 0 ] && printf "${C_YELLOW}△ %d 项警告（非阻塞）${C_RESET}\n" "$TOTAL_WARN"
  exit 1
elif [ "$STRICT" -eq 1 ] && [ "$TOTAL_WARN" -gt 0 ]; then
  printf "\n${C_YELLOW}${C_BOLD}△ 严格模式：%d 项警告视为失败${C_RESET}\n" "$TOTAL_WARN"
  exit 1
elif [ "$TOTAL_WARN" -gt 0 ]; then
  printf "\n${C_GREEN}${C_BOLD}✓ 核心检查全部通过${C_RESET}  ${C_YELLOW}△ %d 项警告（建议修复）${C_RESET}\n" "$TOTAL_WARN"
  exit 0
else
  printf "\n${C_GREEN}${C_BOLD}✓ 全部 %d 项通过，项目完全合规${C_RESET}\n" "$TOTAL_PASS"
  exit 0
fi
