# ─────────────────────────────────────────────────────────────────────────────
# Claude Code Windows stack — рабочее окружение Git Bash
# Положить в ~/.bashrc (C:\Users\<user>\.bashrc)
# ─────────────────────────────────────────────────────────────────────────────

# Windows иногда подсовывает PATH с разделителями ';'. Git Bash такого не понимает.
PATH=${PATH//;/:}

# mise в режиме shims.
#
# ⚠️ НИКОГДА не пиши здесь eval "$(mise activate bash)".
# На Windows эта команда возвращает PATH с разделителями ';', и Git Bash
# перестаёт находить вообще всё — git, ls, which. Выглядит как «сломалась
# система», а это одна строка в конфиге. Только shims, только так:
export PATH="$HOME/AppData/Local/mise/shims:$PATH"
export MISE_SHELL=bash

# Scoop
export PATH="$HOME/scoop/shims:$PATH"

# ~/bin — туда ставится np
export PATH="$HOME/bin:$PATH"

# Настройки np (необязательно — см. 03-projects/README.md)
# export NP_OWNER="your-github-login"
# export NP_TEMPLATE="your-org/your-template-repo"
# export NP_PROJECTS="$HOME/projects"
