#!/usr/bin/env bash
# retrofit.sh — 对未通过 copier 创建的已有项目补装工具链
#
# 工作方式：用 copier copy 将 scaffold 模版叠加到已有项目。
#   - _skip_if_exists 保护已有 src/ 代码，不会覆盖
#   - 工具安装步骤全部幂等，重复运行安全
#
# 用法：
#   ./scripts/retrofit.sh [OPTIONS] [PROJECT_PATH]
#
# 前置依赖：
#   pip install copier   # 或 uv tool install copier

set -euo pipefail

# ── 默认值 ────────────────────────────────────────────────────────────────────
SCAFFOLD_URL="${SCAFFOLD_URL:-git+https://github.com/your-org/scaffold.git}"
TARGET="."
DRY_RUN=0
FORCE=0
NO_DEPS=0

# ── 步骤状态跟踪 ──────────────────────────────────────────────────────────────
declare -a STEP_NAMES=()
declare -a STEP_STATUS=()   # ok / skip / warn / fail / dry

# ── 颜色 ──────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_RED='\033[31m'
  C_CYAN='\033[36m';  C_BOLD='\033[1m';    C_RESET='\033[0m'
  C_DIM='\033[2m'
else
  C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''; C_BOLD=''; C_RESET=''; C_DIM=''
fi

# ── 帮助 ──────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
${C_BOLD}用法：${C_RESET} $(basename "$0") [OPTIONS] [PROJECT_PATH]

将 scaffold 工具链叠加到已有项目，幂等安全，可重复运行。
已有的 src/ 代码不会被覆盖（copier _skip_if_exists 保护）。

${C_BOLD}选项：${C_RESET}
  -h, --help              显示此帮助信息
  -n, --dry-run           预览所有操作，不实际执行任何命令
  -f, --force             强制覆盖（移除 _skip_if_exists 保护，慎用）
      --no-deps           跳过依赖安装（uv sync / pnpm install），仅运行 copier
      --scaffold URL      指定 scaffold 来源（覆盖 \$SCAFFOLD_URL）

${C_BOLD}环境变量：${C_RESET}
  SCAFFOLD_URL            scaffold 来源（默认：${SCAFFOLD_URL}）

${C_BOLD}参数：${C_RESET}
  PROJECT_PATH            目标项目目录（默认：当前目录）

${C_BOLD}示例：${C_RESET}
  # 补装工具链到当前目录
  $(basename "$0")

  # 预览将执行哪些步骤（不实际运行）
  $(basename "$0") --dry-run /path/to/project

  # 使用本地 scaffold 补装到指定目录
  SCAFFOLD_URL=./scaffold $(basename "$0") /path/to/project

  # 补装后用 verify.sh 验证
  $(basename "$0") . && ./scripts/verify.sh .

${C_BOLD}幂等性：${C_RESET}
  所有步骤均已做存在检查，重复运行不会造成副作用：
  - copier copy 使用 _skip_if_exists 保护已有代码
  - uv sync / pnpm install 天然幂等
  - pre-commit install 在已装时输出 "already installed"
EOF
}

# ── 参数解析 ──────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)       usage; exit 0 ;;
    -n|--dry-run)    DRY_RUN=1; shift ;;
    -f|--force)      FORCE=1; shift ;;
    --no-deps)       NO_DEPS=1; shift ;;
    --scaffold)      SCAFFOLD_URL="$2"; shift 2 ;;
    --scaffold=*)    SCAFFOLD_URL="${1#--scaffold=}"; shift ;;
    -*)              printf "未知选项: %s\n" "$1" >&2; usage >&2; exit 2 ;;
    *)               TARGET="$1"; shift ;;
  esac
done

TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" \
  || { printf "${C_RED}错误：目标路径不存在: %s${C_RESET}\n" "$TARGET" >&2; exit 2; }

# ── 日志辅助 ──────────────────────────────────────────────────────────────────
TS() { date '+%H:%M:%S'; }

log_info()  { printf "${C_DIM}[%s]${C_RESET} ${C_CYAN}[INFO]${C_RESET}  %s\n"  "$(TS)" "$*"; }
log_ok()    { printf "${C_DIM}[%s]${C_RESET} ${C_GREEN}[OK]${C_RESET}    %s\n" "$(TS)" "$*"; }
log_skip()  { printf "${C_DIM}[%s]${C_RESET} ${C_YELLOW}[SKIP]${C_RESET}  %s\n" "$(TS)" "$*"; }
log_warn()  { printf "${C_DIM}[%s]${C_RESET} ${C_YELLOW}[WARN]${C_RESET}  %s\n" "$(TS)" "$*"; }
log_error() { printf "${C_DIM}[%s]${C_RESET} ${C_RED}[ERROR]${C_RESET} %s\n"   "$(TS)" "$*" >&2; }
log_dry()   { printf "${C_DIM}[%s]${C_RESET} ${C_CYAN}[DRY]${C_RESET}   %s\n" "$(TS)" "$*"; }

record_step() {
  STEP_NAMES+=("$1")
  STEP_STATUS+=("$2")
}

# 执行命令（dry-run 时只打印）
run_cmd() {
  local desc="$1"; shift
  if [ "$DRY_RUN" -eq 1 ]; then
    log_dry "$desc: $*"
  else
    log_info "$desc: $*"
    if ! "$@"; then
      log_error "$desc 失败（退出码 $?）"
      return 1
    fi
  fi
}

# 检查命令是否存在，不存在时返回 1（不会因 set -e 退出）
require_cmd() {
  local cmd="$1" install_hint="${2:-}"
  if command -v "$cmd" &>/dev/null; then
    local ver
    ver=$("$cmd" --version 2>/dev/null | head -1 || echo "版本未知")
    log_info "$cmd 已安装: $ver"
    return 0
  else
    if [ -n "$install_hint" ]; then
      log_warn "$cmd 未安装。安装方式: $install_hint"
    else
      log_warn "$cmd 未安装，将跳过相关步骤"
    fi
    return 1
  fi
}

# ── 前置检查 ──────────────────────────────────────────────────────────────────
printf "\n${C_BOLD}═══ Retrofit: %s ═══${C_RESET}\n" "$TARGET"
[ "$DRY_RUN" -eq 1 ] && printf "${C_YELLOW}${C_BOLD}⚠ DRY-RUN 模式：不执行任何实际操作${C_RESET}\n"
[ "$FORCE"   -eq 1 ] && printf "${C_YELLOW}${C_BOLD}⚠ FORCE 模式：将覆盖已有配置文件${C_RESET}\n"
printf "\n"

log_info "scaffold 来源: $SCAFFOLD_URL"
log_info "目标目录: $TARGET"
printf "\n"

printf "${C_BOLD}[ 前置依赖检查 ]${C_RESET}\n"
HAS_COPIER=0;    require_cmd copier   "pip install copier 或 uv tool install copier" && HAS_COPIER=1    || true
HAS_UV=0;        require_cmd uv       "curl -LsSf https://astral.sh/uv/install.sh | sh"  && HAS_UV=1        || true
HAS_PNPM=0;      require_cmd pnpm     "npm install -g pnpm"                               && HAS_PNPM=1      || true
HAS_PC=0;        require_cmd pre-commit "pip install pre-commit"                           && HAS_PC=1        || true

if [ "$HAS_COPIER" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  log_error "copier 是必须依赖，无法继续。请先安装：pip install copier"
  exit 1
fi
printf "\n"

# ── 步骤 1：Copier 模版叠加 ───────────────────────────────────────────────────
printf "${C_BOLD}[ 步骤 1/5 ] Copier 模版叠加${C_RESET}\n"
COPIER_ARGS=(--trust)
[ "$FORCE" -eq 0 ] && COPIER_ARGS+=(--overwrite) || COPIER_ARGS+=(--overwrite --skip-if-exists)

if [ "$DRY_RUN" -eq 1 ]; then
  log_dry "copier copy ${COPIER_ARGS[*]} \"$SCAFFOLD_URL\" \"$TARGET\""
  record_step "Copier 模版叠加" "dry"
else
  log_info "运行 copier copy，src/ 代码不会被覆盖..."
  if copier copy "${COPIER_ARGS[@]}" "$SCAFFOLD_URL" "$TARGET"; then
    log_ok "Copier 模版叠加完成"
    record_step "Copier 模版叠加" "ok"
  else
    log_error "Copier 模版叠加失败"
    record_step "Copier 模版叠加" "fail"
    printf "\n${C_RED}致命错误，终止后续步骤${C_RESET}\n"
    exit 1
  fi
fi
printf "\n"

# ── 步骤 2：Backend uv sync ───────────────────────────────────────────────────
printf "${C_BOLD}[ 步骤 2/5 ] Backend 依赖 (uv sync)${C_RESET}\n"
if [ "$NO_DEPS" -eq 1 ]; then
  log_skip "--no-deps 已设置，跳过"
  record_step "Backend uv sync" "skip"
elif [ ! -f "$TARGET/backend/pyproject.toml" ]; then
  log_skip "backend/ 不存在，跳过"
  record_step "Backend uv sync" "skip"
elif [ "$HAS_UV" -eq 0 ]; then
  log_warn "uv 未安装，跳过 backend uv sync"
  record_step "Backend uv sync" "warn"
else
  if run_cmd "backend uv sync" uv sync --frozen --directory "$TARGET/backend"; then
    log_ok "backend 依赖安装完成（--frozen 保证锁文件一致）"
    record_step "Backend uv sync" "ok"
  else
    log_warn "backend uv sync 失败，继续其余步骤"
    record_step "Backend uv sync" "warn"
  fi
fi
printf "\n"

# ── 步骤 3：Agent uv sync ─────────────────────────────────────────────────────
printf "${C_BOLD}[ 步骤 3/5 ] Agent 依赖 (uv sync)${C_RESET}\n"
if [ "$NO_DEPS" -eq 1 ]; then
  log_skip "--no-deps 已设置，跳过"
  record_step "Agent uv sync" "skip"
elif [ ! -f "$TARGET/agent/pyproject.toml" ]; then
  log_skip "agent/ 不存在，跳过"
  record_step "Agent uv sync" "skip"
elif [ "$HAS_UV" -eq 0 ]; then
  log_warn "uv 未安装，跳过 agent uv sync"
  record_step "Agent uv sync" "warn"
else
  if run_cmd "agent uv sync" uv sync --frozen --directory "$TARGET/agent"; then
    log_ok "agent 依赖安装完成"
    record_step "Agent uv sync" "ok"
  else
    log_warn "agent uv sync 失败，继续其余步骤"
    record_step "Agent uv sync" "warn"
  fi
fi
printf "\n"

# ── 步骤 4：Frontend pnpm install ────────────────────────────────────────────
printf "${C_BOLD}[ 步骤 4/5 ] Frontend 依赖 (pnpm install)${C_RESET}\n"
if [ "$NO_DEPS" -eq 1 ]; then
  log_skip "--no-deps 已设置，跳过"
  record_step "Frontend pnpm install" "skip"
elif [ ! -f "$TARGET/frontend/package.json" ]; then
  log_skip "frontend/ 不存在，跳过"
  record_step "Frontend pnpm install" "skip"
elif [ "$HAS_PNPM" -eq 0 ]; then
  log_warn "pnpm 未安装，跳过 frontend pnpm install"
  record_step "Frontend pnpm install" "warn"
else
  if run_cmd "pnpm install" pnpm install --frozen-lockfile --dir "$TARGET/frontend"; then
    log_ok "frontend 依赖安装完成（--frozen-lockfile 保证锁文件一致）"
    record_step "Frontend pnpm install" "ok"
  else
    log_warn "pnpm install 失败，继续其余步骤"
    record_step "Frontend pnpm install" "warn"
  fi
fi
printf "\n"

# ── 步骤 5：Pre-commit 钩子安装 ───────────────────────────────────────────────
printf "${C_BOLD}[ 步骤 5/5 ] Pre-commit 钩子安装${C_RESET}\n"
if [ ! -f "$TARGET/.pre-commit-config.yaml" ]; then
  log_skip ".pre-commit-config.yaml 不存在，跳过"
  record_step "Pre-commit 钩子" "skip"
elif [ "$HAS_PC" -eq 0 ]; then
  log_warn "pre-commit 未安装，跳过钩子安装"
  record_step "Pre-commit 钩子" "warn"
elif [ ! -d "$TARGET/.git" ]; then
  log_warn "非 Git 仓库（.git 不存在），跳过钩子安装"
  record_step "Pre-commit 钩子" "warn"
else
  # 幂等检查：钩子是否已安装
  if [ "$DRY_RUN" -eq 0 ] && [ -f "$TARGET/.git/hooks/pre-commit" ]; then
    log_skip "pre-commit 钩子已存在，幂等跳过（使用 --force 强制重装）"
    record_step "Pre-commit 钩子" "skip"
  else
    PC_OK=1
    run_cmd "pre-commit install" pre-commit install --allow-missing-config \
      -C "$TARGET" || PC_OK=0
    run_cmd "pre-commit install commit-msg" pre-commit install \
      --hook-type commit-msg --allow-missing-config -C "$TARGET" || PC_OK=0
    if [ "$PC_OK" -eq 1 ]; then
      log_ok "pre-commit 钩子安装完成（pre-commit + commit-msg）"
      record_step "Pre-commit 钩子" "ok"
    else
      log_warn "pre-commit 钩子安装部分失败"
      record_step "Pre-commit 钩子" "warn"
    fi
  fi
fi
printf "\n"

# ── 汇总 ──────────────────────────────────────────────────────────────────────
SUMMARY_OK=0; SUMMARY_SKIP=0; SUMMARY_WARN=0; SUMMARY_FAIL=0; SUMMARY_DRY=0

for s in "${STEP_STATUS[@]}"; do
  case "$s" in
    ok)   SUMMARY_OK=$((SUMMARY_OK+1))   ;;
    skip) SUMMARY_SKIP=$((SUMMARY_SKIP+1)) ;;
    warn) SUMMARY_WARN=$((SUMMARY_WARN+1)) ;;
    fail) SUMMARY_FAIL=$((SUMMARY_FAIL+1)) ;;
    dry)  SUMMARY_DRY=$((SUMMARY_DRY+1))  ;;
  esac
done

printf "${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
printf "${C_BOLD}Retrofit 步骤汇总: %s${C_RESET}\n" "$TARGET"
printf "───────────────────────────────────────────────────────────────\n"
printf "${C_BOLD}%-30s %s${C_RESET}\n" "步骤" "状态"
printf "───────────────────────────────────────────────────────────────\n"
for i in "${!STEP_NAMES[@]}"; do
  name="${STEP_NAMES[$i]}"; status="${STEP_STATUS[$i]}"
  case "$status" in
    ok)   icon="${C_GREEN}✓ 完成${C_RESET}"   ;;
    skip) icon="${C_CYAN}– 跳过${C_RESET}"    ;;
    warn) icon="${C_YELLOW}△ 警告${C_RESET}"  ;;
    fail) icon="${C_RED}✗ 失败${C_RESET}"     ;;
    dry)  icon="${C_CYAN}◌ 预览${C_RESET}"    ;;
  esac
  printf "%-30s %b\n" "$name" "$icon"
done
printf "───────────────────────────────────────────────────────────────\n"
printf "完成: ${C_GREEN}%d${C_RESET}  跳过: ${C_CYAN}%d${C_RESET}  警告: ${C_YELLOW}%d${C_RESET}  失败: ${C_RED}%d${C_RESET}\n" \
  "$SUMMARY_OK" "$SUMMARY_SKIP" "$SUMMARY_WARN" "$SUMMARY_FAIL"
printf "${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"

# ── 后续建议 ──────────────────────────────────────────────────────────────────
printf "\n${C_BOLD}后续步骤：${C_RESET}\n"
[ "$DRY_RUN"      -eq 1 ] && printf "  1. 移除 --dry-run 后重新运行以实际执行\n"
[ "$SUMMARY_WARN" -gt 0 ] && printf "  • 检查上方警告项，手动安装缺失工具后重新运行\n"
printf "  • 运行 ${C_CYAN}./scripts/verify.sh %s${C_RESET} 验证最终结果\n" "$TARGET"
[ "$DRY_RUN" -eq 0 ] && [ -d "$TARGET/.git" ] && \
  printf "  • 运行 ${C_CYAN}(cd %s && pre-commit run --all-files)${C_RESET} 验证 hooks\n" "$TARGET"

printf "\n"

# ── 退出码 ────────────────────────────────────────────────────────────────────
[ "$SUMMARY_FAIL" -gt 0 ] && exit 1 || exit 0
