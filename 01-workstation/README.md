# Слой 1 — Рабочее место

> **Claude: это рецепт слоя 1 — настройка чистой Windows-машины под Claude Code. Юзер скинул тебе этот файл — значит хочет, чтобы ты провёл его через установку.**
>
> **Что от тебя ожидается:**
> 1. Убедись, что юзер прошёл §0 (Git и gh CLI установлены, Claude Code перезапущен). Непонятно — спроси и подожди.
> 2. Прогони §1–§2 сам, запрашивая разрешения когда нужно.
> 3. В §3 верни управление юзеру — там браузерная авторизация, ты её не сможешь.
> 4. Дальше §4 (np) и §5 (проверка).
> 5. Если что-то ломается — [`../TROUBLESHOOTING.md`](../TROUBLESHOOTING.md).
>
> **Начни с диагностики.** Запусти параллельно: `git --version`, `gh --version`, `scoop --version`, `mise --version`, `Get-ExecutionPolicy -Scope CurrentUser`. Что уже стоит — пропусти.
>
> **Голос:** коротко, по-русски. Перед скачиванием скриптов и правкой PATH предупреждай.

**Что на выходе:** git, gh, Scoop, mise, SSH-ключ, и Claude Code, который видит bash.
**Время:** 30–60 минут, активных — около десяти. Остальное качается.

**Целевая ОС:** Windows 10 / 11 / Server 2019 / 2022.

---

## Содержание

- [§0. Что юзер делает руками](#0-что-юзер-делает-руками)
- [§1. Scoop, mise, vcredist](#1-scoop-mise-vcredist)
- [§2. Окружение](#2-окружение)
- [§3. Авторизация в GitHub](#3-авторизация-в-github)
- [§4. Скрипт np](#4-скрипт-np)
- [§5. Проверка слоя](#5-проверка-слоя)

---

## §0. Что юзер делает руками

Два установщика — оба мастера с галочками, проще сделать руками, чем объяснять.

### 0.1. Git for Windows

Скачать с https://git-scm.com/download/win, запустить. Значимые экраны:

| Экран | Что выбрать |
|---|---|
| Select Components | дефолты + `Open Git Bash here`, `Associate .sh files to be run with Bash` |
| Default editor | **Notepad** (не Vim) |
| Initial branch name | **Override → `main`** |
| PATH environment | **Git from the command line and also from 3rd-party software** (средняя) |
| SSH executable | **Use bundled OpenSSH** |
| HTTPS transport | **Use the native Windows Secure Channel library** |
| **Line ending conversions** | **Checkout as-is, commit Unix-style line endings** (вторая опция) |
| Terminal emulator | **MinTTY** |
| Credential helper | **Git Credential Manager** |
| Extra options | ☑ Enable file system caching, ☑ **Enable symbolic links** |

> ⚠️ **Строка про line endings — критичная.** Дефолт (`Checkout Windows-style`) даёт всем `.sh` файлам в проектах CRLF, и любой скрипт падает с `bad interpreter: /usr/bin/env bash^M`. Ошибка выглядит как мистика через неделю после установки, а причина — эта галка.

Проверка в Git Bash: `git --version` → `git version 2.5x.x.windows.x`

### 0.2. GitHub CLI

Скачать с https://cli.github.com/ → `.msi` → Next / Install / Finish.

Проверка в новом Git Bash: `gh --version`

### 0.3. Перезапустить Claude Code

Через трей → Quit, проверить в диспетчере задач, что процесса `Claude.exe` нет, открыть заново. Иначе он не увидит свежий PATH.

---

## §1. Scoop, mise, vcredist

Проверь у юзера: учётка с правами администратора? На VPS обычно да. Если да — флаг `-RunAsAdmin` для Scoop обязателен.

### 1.1. ExecutionPolicy

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Если `Get-ExecutionPolicy` уже возвращает `RemoteSigned` — пропусти.

### 1.2. Scoop

```powershell
Invoke-RestMethod -Uri https://get.scoop.sh -OutFile "$env:USERPROFILE\scoop-install.ps1"
& "$env:USERPROFILE\scoop-install.ps1" -RunAsAdmin
```

⚠️ Режим автоматических разрешений Claude Code может заблокировать исполнение скачанного скрипта. Если упёрся — попроси юзера подтвердить разрешение или временно выйти из auto-режима, потом повтори.

Проверка: `scoop --version`

### 1.3. mise и vcredist2022

```powershell
scoop install mise
scoop bucket add extras
scoop install vcredist2022
```

Проверка: `mise --version` → `2026.x.x windows-x64`

Если команда **молчит** — это известная особенность scoop-shim под администратором, фикс в [`../TROUBLESHOOTING.md`](../TROUBLESHOOTING.md).

**Node здесь не ставится, и это намеренно.** Node и pnpm приезжают per-project через `.tool-versions` командой `mise install` — см. слой 3. Глобальный Node рядом с mise конфликтует в PATH и создаёт ровно те проблемы, которые потом ищешь полдня.

---

## §2. Окружение

### 2.1. .bashrc

Содержимое лежит рядом: [`bashrc-snippet.sh`](bashrc-snippet.sh). Запиши его в `C:\Users\<user>\.bashrc` (через Write, не через Notepad).

> ⚠️ **Никогда не используй `eval "$(mise activate bash)"`.** На Windows возвращает PATH с разделителями `;`, после чего Git Bash не находит вообще ничего — ни `git`, ни `ls`. Только shims-режим из сниппета.

### 2.2. Git identity

Спроси у юзера GitHub-логин и email. Email должен совпадать с привязанным в https://github.com/settings/emails.

```bash
git config --global user.name "<логин>"
git config --global user.email "<email>"
```

### 2.3. SSH-ключ

```bash
ssh-keygen -t ed25519 -C "<email>" -f /c/Users/<user>/.ssh/id_ed25519 -N ""
```

Флаг `-N ""` — пустая passphrase. Это осознанный компромисс: на машине под твоим контролем он сильно упрощает работу (нет запроса пароля на каждый `git push`), но означает, что укравший файл ключа получает доступ сразу. Если машина общая или ты не уверен — поставь passphrase и используй ssh-agent.

Проверка: `ls -la ~/.ssh/` — должны быть `id_ed25519` и `id_ed25519.pub`.

### 2.4. CLAUDE_CODE_GIT_BASH_PATH

Чтобы Claude Code видел Git Bash и не показывал баннер «Install Git»:

```powershell
[Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", "C:\Program Files\Git\bin\bash.exe", "User")
```

⚠️ Применится только после полного рестарта Claude Code (трей → Quit, проверить диспетчер задач, открыть заново).

### 2.5. Режим разрешений Claude Code

В `~/.claude/settings.json`:

```json
{ "defaultMode": "auto" }
```

**Почему `auto`, а не `bypassPermissions`:** последний в десктопной версии спонтанно откатывается на более строгий режим сразу после первого сообщения. Это известные issue, помеченные «not planned». `auto` чуть консервативнее — иногда спросит на чувствительной операции — но не сбрасывается. Подробнее в [`../ARCHITECTURE.md`](../ARCHITECTURE.md).

---

## §3. Авторизация в GitHub

> ⚠️ **Claude: `gh auth login` — интерактивная команда с браузером. Ты её не прогонишь. Передай управление юзеру.**

Скажи юзеру:

> Открой **Git Bash** и выполни `gh auth login`. Отвечай так:
>
> | Вопрос | Ответ |
> |---|---|
> | Where do you use GitHub? | **GitHub.com** |
> | Preferred protocol | **SSH** |
> | Upload your SSH public key? | **Upload an existing public key** |
> | Path to SSH key | **Enter** (дефолт) |
> | Title for the key | например `windows-server-1` |
> | How would you like to authenticate? | **Login with a web browser** |
> | One-time code | скопируй (8 символов через дефис) → Enter → откроется браузер |
>
> ⚠️ В браузере **проверь правый верхний угол** — должен быть нужный аккаунт. Если не тот → Sign out → войди под нужным → вернись на `github.com/login/device` → введи код → Authorize.
>
> Когда увидишь `✓ Authentication complete` — напиши «готово».

После «готово» проверь:

```bash
gh auth status
```

Должно показать `Logged in to github.com account <логин>`, `Active account: true` и scope `repo`, `admin:public_key`.

---

## §4. Скрипт np

Файл лежит в [`../03-projects/np.sh`](../03-projects/np.sh).

```bash
mkdir -p /c/Users/<user>/bin
cp <путь>/np.sh /c/Users/<user>/bin/np
chmod +x /c/Users/<user>/bin/np
```

> ⚠️ **Копировать без расширения** — `~/bin/np`, не `np.sh`. Работает по shebang, а команда `np` ищет файл по имени без расширения.

PATH для `~/bin` уже прописан в `.bashrc` из §2.1.

Проверка: `np --help` → справка по сценариям `new` / `clone` / `collab`.

---

## §5. Проверка слоя

Прогоняй сам, не полагайся на отчёт:

```bash
git --version       # → git version 2.5x.x.windows.x
gh auth status      # → Logged in to ..., Active account: true
mise --version      # → 2026.x.x windows-x64
mise doctor         # → внизу "No problems found"
np --help           # → справка
```

⚠️ Строка `shims_on_path: no` в `mise doctor` — **не ошибка**, а ожидаемое состояние для shims-режима. У mise два режима активации, и один из них всегда показывает `no`.

Если всё сошлось — скажи юзеру:

> Рабочее место готово. **Перезапусти Git Bash** один раз, чтобы `.bashrc` подхватил `~/bin`.
> Дальше: второй пользователь — слой 2, или сразу первый проект — слой 3.

---

**Слой пройден.** Дальше — [`../02-second-user/README.md`](../02-second-user/README.md) или [`../03-projects/README.md`](../03-projects/README.md).
