#!/usr/bin/env bash
# np — New Project: разворачивает проект на подготовленной машине.
#
# Usage:
#   np new <site>                    # Сценарий A: новый проект из твоего шаблона
#   np clone <site>                  # Сценарий B: клон твоего существующего репо
#   np collab <owner>/<repo>         # Сценарий C: чужой репо, ты коллаборатор
#
# Examples:
#   np new clinic-landing
#   np clone migrator
#   np collab some-org/their-project
#
# Optional:
#   --owner <login>     Переопределить GitHub-владельца (для `new` и `clone`)
#   --no-deps           Только клон, без mise install / pnpm install
#   -h, --help          Справка
#
# Настройка через переменные окружения (положи в ~/.bashrc):
#   NP_OWNER      GitHub-логин по умолчанию. Если пусто — берётся из `gh auth`.
#   NP_TEMPLATE   Репо-шаблон для `np new`, например "my-org/my-next-template".
#                 Без него сценарий A работать не будет — это нормально,
#                 пока у тебя нет своего шаблона.
#   NP_PROJECTS   Куда класть проекты. По умолчанию ~/projects.

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────
DEFAULT_OWNER="${NP_OWNER:-$(gh api user --jq .login 2>/dev/null || echo '')}"
TEMPLATE_REPO="${NP_TEMPLATE:-}"
PROJECTS_DIR="${NP_PROJECTS:-$HOME/projects}"

# Colors for output (works in Git Bash MinTTY)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
say()   { echo -e "${BLUE}▸${RESET} $*"; }
ok()    { echo -e "${GREEN}✓${RESET} $*"; }
warn()  { echo -e "${YELLOW}⚠${RESET} $*"; }
err()   { echo -e "${RED}✗${RESET} $*" >&2; }
die()   { err "$1"; exit 1; }

usage() {
  cat <<'EOF'
np — разворачивает проект на подготовленной машине

USAGE
  np new <site>                  Новый проект из шаблона ($NP_TEMPLATE)
  np clone <site>                Клон твоего существующего репо
  np collab <owner>/<repo>       Чужой репо (ты коллаборатор)

OPTIONS
  --owner <login>                Переопределить GitHub-владельца
  --no-deps                      Только клон, без установки зависимостей
  -h, --help                     Эта справка

ENVIRONMENT
  NP_OWNER                       GitHub-логин по умолчанию
  NP_TEMPLATE                    Репо-шаблон для `np new`
  NP_PROJECTS                    Куда класть проекты (по умолчанию ~/projects)

EXAMPLES
  np new clinic-landing
  np clone migrator
  np collab some-org/their-project
EOF
}

# Convert /c/Users/... → C:\Users\... for clean Windows-path output
to_windows_path() {
  local p="$1"
  if [[ "$p" =~ ^/([a-zA-Z])/(.*)$ ]]; then
    local drive="${BASH_REMATCH[1]^^}"
    local rest="${BASH_REMATCH[2]//\//\\}"
    echo "${drive}:\\${rest}"
  else
    echo "$p"
  fi
}

# Print final ready-to-paste banner
print_ready_banner() {
  local site_path="$1"
  local win_path
  win_path=$(to_windows_path "$site_path")

  echo
  echo -e "${GREEN}─────────────────────────────────────────────────────────────${RESET}"
  echo -e "${GREEN}${BOLD}  ✅ Project ready: ${site_path}${RESET}"
  echo -e "${GREEN}─────────────────────────────────────────────────────────────${RESET}"
  echo
  echo -e "${BOLD}Next steps:${RESET}"
  echo
  echo -e "  ${BOLD}1.${RESET} Открой Claude Code → ${BOLD}Select folder${RESET} →"
  echo -e "     ${BLUE}${win_path}${RESET}"
  echo
  echo -e "  ${BOLD}2.${RESET} Первое сообщение в новой сессии:"
  echo
  echo -e "     ${YELLOW}Прочитай README.md и CLAUDE.md в этой папке.${RESET}"
  echo -e "     ${YELLOW}Расскажи, что это за проект и на каком он этапе.${RESET}"
  echo
  echo -e "${GREEN}─────────────────────────────────────────────────────────────${RESET}"
  echo
}

# Print collab-specific reminders
print_collab_reminders() {
  echo
  echo -e "${YELLOW}${BOLD}⚠ Режим коллаборатора — что помнить:${RESET}"
  echo "  • Прямой push в main скорее всего закрыт — работай через ветки и PR"
  echo "  • Доступа к секретам окружения и к .env владельца у тебя нет"
  echo "  • Новый секрет добавляет владелец у себя в настройках репозитория"
  echo
}

# Print clone-specific reminders (your own repo)
print_clone_reminders() {
  echo
  echo -e "${YELLOW}${BOLD}⚠ Что НЕ приезжает вместе с git:${RESET}"
  echo "  • .env.production — он в .gitignore. Забери со старой машины или с прода."
  echo "    Для локальной разработки обычно можно работать и без него."
  echo "  • SSH-доступ к боевому серверу — публичный ключ этой машины"
  echo "    (~/.ssh/id_ed25519.pub) надо добавить в authorized_keys деплой-юзера."
  echo
}

# Common post-clone setup: mise + pnpm
install_deps() {
  local site_dir="$1"

  cd "$site_dir"

  say "Installing toolchain via mise..."
  mise install

  if [[ ! -f "$site_dir/package.json" ]]; then
    warn "package.json не найден — пропускаю pnpm install"
    say "Это нормально для пустого шаблона: зависимости появятся после инициализации проекта."
    return 0
  fi

  say "Installing project dependencies (1-3 min)..."
  pnpm install

  say "Approving build scripts (sharp, msw и подобные)..."
  pnpm approve-builds || warn "approve-builds пропущен — при необходимости запусти вручную"

  ok "Dependencies installed"
}

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight checks
# ─────────────────────────────────────────────────────────────────────────────
preflight() {
  command -v gh >/dev/null 2>&1   || die "gh CLI не найден. Установи с https://cli.github.com/"
  command -v git >/dev/null 2>&1  || die "git не найден. Установи Git for Windows."
  command -v mise >/dev/null 2>&1 || die "mise не найден. Установи: scoop install mise"
  command -v pnpm >/dev/null 2>&1 || warn "pnpm пока не в PATH (поставится через mise)."

  if ! gh auth status >/dev/null 2>&1; then
    die "Не залогинен в GitHub. Выполни: gh auth login"
  fi

  mkdir -p "$PROJECTS_DIR"
}

# ─────────────────────────────────────────────────────────────────────────────
# Scenarios
# ─────────────────────────────────────────────────────────────────────────────

# Scenario A: new from template
cmd_new() {
  local site="$1"
  local owner="${2:-$DEFAULT_OWNER}"
  local target="$PROJECTS_DIR/$site"

  [[ -z "$site" ]]  && die "Usage: np new <site>"
  [[ -z "$owner" ]] && die "Не определён GitHub-владелец. Задай NP_OWNER или используй --owner."
  [[ -d "$target" ]] && die "Директория уже существует: $target"

  if [[ -z "$TEMPLATE_REPO" ]]; then
    die "Шаблон не настроен. Задай NP_TEMPLATE, например:
    export NP_TEMPLATE=\"my-org/my-next-template\"
  Либо используй 'np clone' для существующего репозитория."
  fi

  say "Создаю репо из шаблона: $owner/$site ← $TEMPLATE_REPO"
  cd "$PROJECTS_DIR"
  gh repo create "$owner/$site" \
    --template "$TEMPLATE_REPO" \
    --private \
    --clone

  ok "Репо создан и склонирован: $target"

  if [[ "${SKIP_DEPS:-0}" != "1" ]]; then
    install_deps "$target"
  fi

  print_ready_banner "$target"
}

# Scenario B: clone your own existing repo
cmd_clone() {
  local site="$1"
  local owner="${2:-$DEFAULT_OWNER}"
  local target="$PROJECTS_DIR/$site"

  [[ -z "$site" ]]  && die "Usage: np clone <site>"
  [[ -z "$owner" ]] && die "Не определён GitHub-владелец. Задай NP_OWNER или используй --owner."
  [[ -d "$target" ]] && die "Директория уже существует: $target"

  say "Клонирую: $owner/$site"
  cd "$PROJECTS_DIR"
  gh repo clone "$owner/$site"

  ok "Репо склонирован: $target"

  if [[ "${SKIP_DEPS:-0}" != "1" ]]; then
    install_deps "$target"
  fi

  print_clone_reminders
  print_ready_banner "$target"
}

# Scenario C: clone someone else's repo (collaborator)
cmd_collab() {
  local repo="$1"

  [[ -z "$repo" ]] && die "Usage: np collab <owner>/<repo>"
  [[ "$repo" != */* ]] && die "Нужен формат <owner>/<repo>, получено: $repo"

  local site="${repo##*/}"
  local target="$PROJECTS_DIR/$site"

  [[ -d "$target" ]] && die "Директория уже существует: $target"

  if ! gh repo view "$repo" >/dev/null 2>&1; then
    die "Нет доступа к $repo — сначала прими приглашение на https://github.com/notifications"
  fi

  say "Клонирую репо коллаборатора: $repo"
  cd "$PROJECTS_DIR"
  gh repo clone "$repo"

  ok "Репо склонирован: $target"

  if [[ "${SKIP_DEPS:-0}" != "1" ]]; then
    install_deps "$target"
  fi

  print_collab_reminders
  print_ready_banner "$target"
}

# ─────────────────────────────────────────────────────────────────────────────
# Argument parsing
# ─────────────────────────────────────────────────────────────────────────────
SKIP_DEPS=0
OWNER_OVERRIDE=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --owner) OWNER_OVERRIDE="$2"; shift 2 ;;
    --no-deps) SKIP_DEPS=1; shift ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

[[ ${#POSITIONAL[@]} -lt 1 ]] && { usage; exit 1; }

SUBCOMMAND="${POSITIONAL[0]}"
ARG1="${POSITIONAL[1]:-}"

# ─────────────────────────────────────────────────────────────────────────────
# Dispatch
# ─────────────────────────────────────────────────────────────────────────────
preflight

case "$SUBCOMMAND" in
  new)    cmd_new    "$ARG1" "${OWNER_OVERRIDE:-$DEFAULT_OWNER}" ;;
  clone)  cmd_clone  "$ARG1" "${OWNER_OVERRIDE:-$DEFAULT_OWNER}" ;;
  collab) cmd_collab "$ARG1" ;;
  *)      err "Неизвестная команда: $SUBCOMMAND"; usage; exit 1 ;;
esac
