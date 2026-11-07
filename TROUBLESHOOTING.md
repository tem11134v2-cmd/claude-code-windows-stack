# TROUBLESHOOTING

Всё, на что я наступал при сборке этих машин, с фиксами. Собрано из рабочих логов, а не из документации.

> **Claude: если упёрся в ошибку — сначала ищи здесь, потом гугли.** Многие из этих симптомов выглядят не как их причина.

**Разделы:** [Сеть и Proxifier](#сеть-и-proxifier) · [Windows и RDP](#windows-и-rdp) · [PowerShell](#powershell) · [Окружение](#окружение-scoop-mise-path) · [Проекты](#проекты-git-pnpm) · [Claude Code](#claude-code)

---

## Сеть и Proxifier

### N1. Proxifier ловит трафик только одного пользователя

**Симптом.** Под администратором IP правильный (прокси), под вторым пользователем `(Invoke-RestMethod https://api.ipify.org?format=json).ip` показывает реальный IP сервера.

**Причина.** По умолчанию Proxifier перехватывает трафик только своего пользователя.

**Чего это не причина.** Не админских прав. Перехват делает WFP-callout драйвер, один на машину; админ нужен только на его установку, то есть один раз при инсталляции Proxifier. Запущенному GUI права администратора не требуются.

**Решение.** В GUI: `Profile → Advanced → Services and Other Users...` → включить обе галки. Подробности — N2, их там неочевидно найти.

Проверить, что записалось в профиль:

```powershell
Select-String -Path "$env:APPDATA\Proxifier4\Profiles\Default.ppx" -Pattern "ProcessOtherUsers|ProcessServices"
```

---

### N2. В `Profile → Advanced` нет галок «Process other users» и «Windows Services»

**Симптом.** Инструкция говорит включить их в `Profile → Advanced`, а в подменю таких пунктов нет — только Passwords Encryption, DNS and IP Leak Prevention Mode, Handle Direct Connections.

**Причина.** В Proxifier 4 эти два флага вынесены в **отдельный диалог**, а не живут галками в самом меню.

**Решение.** `Profile → Advanced → Services and Other Users...` (отдельный пункт подменю, открывает диалог). Внутри:

- ☑ Applications run by other users on this computer
- ☑ Windows services and other system processes

*Проверено: Proxifier 4, Windows Server 2022.*

---

### N3. Попап «уже запущено в другой сессии»

**Симптом.** Залогинился вторым пользователем, автозапуск Proxifier выдаёт «another instance is already running».

**Причина.** Proxifier — single-instance на всю машину. Первый залогинившийся держит блокировку.

**Решение.** Закрыть попап крестиком — это нормально. Если в профиле включён перехват чужих пользователей (N1), твой трафик защищён первым инстансом. Проверить:

```powershell
(Invoke-RestMethod https://api.ipify.org?format=json).ip
```

---

### N4. Потерян доступ к серверу после настройки Proxifier

**Симптом.** После правки правил RDP больше не подключается.

**Причина.** Завёрнуто в прокси правило для localhost, которое стоит выше дефолтного. Оно единственное держит RDP-соединение.

**Решение.** Зайти через консоль в панели провайдера (у Timeweb, PQ.Hosting и прочих она есть), открыть Proxifier и вернуть localhost-правилу действие Direct.

**Профилактика.** Никогда не трогать это правило. Это самая дорогая ошибка слоя 0.

---

### N5. IP правильный, а DNS — свои

**Симптом.** `whoer.net` показывает нужный IP, но `dnsleaktest.com` выдаёт DNS-серверы твоего настоящего провайдера.

**Причина.** Не включено разрешение имён через прокси.

**Решение.** `Profile → Name Resolution → ✓ Resolve hostnames through proxy`.

---

### N6. Утечка через WebRTC

**Симптом.** `browserleaks.com/webrtc` показывает посторонний IP при правильном IP в остальных тестах.

**Причина.** WebRTC и QUIC ходят по UDP мимо правил.

**Решение.** `Profile → Advanced` → Bypass UDP Traffic переключить на **Block Traffic to All UDP Ports if Matched the Rule**.

---

## Windows и RDP

### W1. Новый пользователь не пускает по RDP: «The logon attempt failed»

**Симптом.** Пользователь создан, пароль точно верный, RDP отвечает отказом. В окне ввода credentials красуется `ИМЯМАШИНЫ\логин` — выглядит правильно.

**Причина (чаще всего).** `mstsc` запущен **внутри самой серверной RDP-сессии** и подключается к адресу из своей истории — то есть к другой машине, где этого пользователя нет.

Надпись `ИМЯМАШИНЫ\` ничего не подтверждает: Windows подставляет к логину без домена имя **локальной** машины, где запущен клиент, а не хоста, куда ты стучишься.

**Диагностика на сервере, где пользователь создан:**

```powershell
# на какой адрес реально приходят RDP-подключения
Get-NetTCPConnection -LocalPort 3389 -State Established | Select-Object LocalAddress,RemoteAddress

# реальные адреса этой машины
Get-NetIPAddress -AddressFamily IPv4

# были ли вообще отказы логона
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625; StartTime=(Get-Date).AddMinutes(-30)}
```

Если событий 4625 для пользователя **нет вообще** — попытки до сервера не доходят. Дело в адресе или клиенте, а не в учётке.

Проверить саму учётку, не трогая её:

```powershell
Add-Type -AssemblyName System.DirectoryServices.AccountManagement
$ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Machine', $env:COMPUTERNAME)
$ctx.ValidateCredentials('<логин>','<пароль>')   # True = пароль валиден
```

**Решение.** Подключаться с локального компьютера, а не изнутри серверной сессии, по адресу из `Get-NetIPAddress`.

---

### W2. Политика паролей отклоняет пароль

**Симптом.** «The password does not meet the password policy requirements».

**Причина.** Политика Windows Server по умолчанию требует от 8 символов с буквами разного регистра и цифрами. Чисто цифровой не пройдёт.

**Решение.** Добавить буквы в обоих регистрах.

---

### W3. RDP-буфер переставляет строки при вставке многострочного блока

**Симптом.** Копируешь многострочный PowerShell-блок с here-string (`@'...'@`), вставляешь в RDP-сессию — получаешь ошибки вида `Cannot bind argument because it is null`, потому что строки пришли **в обратном порядке**.

**Решение.** Либо однострочник через `;`, либо сохранить в `.ps1` и запустить файлом. Все скрипты в этом репозитории вызываются как файлы и этой проблемой не страдают.

---

### W4. Сервер засыпает ночью, фоновая работа останавливается

**Причина.** План электропитания по умолчанию.

**Решение.** `Control Panel → Power Options → High performance`, в расширенных настройках Hard disk / Sleep / Display → Never. Плюс отключить таймауты RDP-сессий через `gpedit.msc` — см. слой 0, §6.

---

### W5. Симлинки не создаются: «operation requires elevation»

**Причина.** Нет права на создание символических ссылок. Нужно для дедупликации `node_modules` в pnpm.

**Решение.**

- Windows 10/11: `Settings → Update & Security → For developers → Developer Mode: On`
- Server 2022 (если опции нет): `secpol.msc → Local Policies → User Rights Assignment → Create symbolic links` → добавить пользователя

---

### W6. Третий пользователь не может подключиться по RDP

**Симптом.** Двое работают, третий получает отказ или предложение выкинуть кого-то из сессии.

**Причина.** Это не настройка, а лицензирование. Встроенный в Windows Server режим Remote Desktop for Administration даёт **две** одновременные удалённые сессии плюс консольную. Третьей не бывает.

**Решение.** Либо роль RD Session Host с лицензиями CAL (отдельные деньги и отдельная настройка), либо второй сервер. Схема в этом репозитории рассчитана на двух человек.

Посмотреть, кто сейчас занимает сессии:

```powershell
query session
```

Политика `Restrict Remote Desktop Services users to a single session` здесь не поможет — она про случай, когда **один** аккаунт хочет две сессии, а не про количество разных людей.

---

## PowerShell

### P1. `Set-ExecutionPolicy` падает внутри скрипта, запущенного с `-ExecutionPolicy Bypass`

**Симптом.** «...the setting is overridden by a policy defined at a more specific scope». С `$ErrorActionPreference = "Stop"` скрипт останавливается.

**Причина.** `Bypass` и так разрешает всё, менять политику не нужно — но команда считает это ошибкой.

**Решение.** Обернуть в try/catch:

```powershell
try { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop } catch { }
```

---

### P2. ParserError на строке вида `"Записал $file:"`

**Симптом.**

```
Variable reference is not valid. ':' was not followed by a valid variable name character.
```

Скрипт не выполняется **вообще** — ни одной строки.

**Причина.** PowerShell читает `$file:` как обращение к PSDrive, по аналогии с `$env:PATH`. Это ошибка парсинга, поэтому падает весь файл целиком.

**Решение.** Обернуть имя переменной в фигурные скобки: `"Записал ${file}:"`.

Проверить синтаксис любого скрипта, не запуская его:

```powershell
$e=$null; [System.Management.Automation.Language.Parser]::ParseFile("путь.ps1",[ref]$null,[ref]$e) | Out-Null; $e
```

---

### P3. Не называй переменную `$pwd`

`$pwd` — зарезервированное имя (текущая рабочая директория). Присваивание сработает, но дальше в скрипте начнутся странности. Любое другое имя.

---

### P4. `reg load` падает с «filename or extension is too long»

**Симптом.** Попытка загрузить чужой `NTUSER.DAT` даёт ложную ошибку про длину пути.

**Причина.** У процесса не активированы привилегии `SeBackupPrivilege` и `SeRestorePrivilege` — даже у администратора они по умолчанию выключены.

**Решение.** Не править реестр другого пользователя из чужой сессии. Дать пользователю скрипт, который он запустит у себя.

---

## Окружение: Scoop, mise, PATH

### E1. Git Bash не находит ничего: `command not found: git / ls / which`

**Симптом.** После правки `.bashrc` Git Bash перестал находить вообще все команды.

**Причина.** PATH содержит `;` вместо `:`. Почти всегда — из-за `eval "$(mise activate bash)"` в `.bashrc`.

**Решение.** Заменить на shims-режим из [`01-workstation/bashrc-snippet.sh`](01-workstation/bashrc-snippet.sh).

Быстрый фикс текущей сессии:

```bash
export PATH="/c/Program Files/Git/usr/bin:/c/Program Files/Git/mingw64/bin:/c/Program Files/Git/cmd:$HOME/scoop/shims:$HOME/AppData/Local/mise/shims:/c/Windows/system32:/c/Windows"
```

---

### E2. `mise --version` молчит после установки

**Симптом.** Команда выполняется, но ничего не выводит. Под администратором на Windows Server.

**Причина.** Scoop-shim не передаёт stdout.

**Решение.** Проверить exe напрямую:

```powershell
& "$env:USERPROFILE\scoop\apps\mise\current\bin\mise.exe" --version
```

Если выводит — прописать прямой путь в User PATH:

```powershell
[Environment]::SetEnvironmentVariable("PATH", "$env:USERPROFILE\scoop\apps\mise\current\bin;" + [Environment]::GetEnvironmentVariable("PATH", "User"), "User")
```

Закрыть все окна PowerShell и открыть заново.

---

### E3. `mise doctor` показывает `shims_on_path: no`

**Это не ошибка.** У mise два режима активации, и в shims-режиме этот пункт всегда `no`. Ориентируйся на строку «No problems found» внизу вывода.

---

### E4. Scoop отказывается ставиться: «Running the installer as administrator is disabled»

**Решение.** Флаг `-RunAsAdmin`:

```powershell
& "$env:USERPROFILE\scoop-install.ps1" -RunAsAdmin
```

---

### E5. `npm`/`node` не найдены сразу после установки Scoop

**Причина.** Scoop добавил пути в User PATH, но текущий процесс PowerShell их не видит.

**Решение.** Обновить PATH в текущей сессии:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
```

---

### E6. PATH снова ломается после перезапуска Git Bash

**Причина.** Что-то модифицирует PATH с `;` в одном из `.bashrc` / `.bash_profile` / `.profile`.

**Решение.** Проверить все три файла, оставить только содержимое сниппета.

---

## Проекты: git, pnpm

### G1. Скрипты падают с `bad interpreter: /usr/bin/env bash^M`

**Симптом.** Любой `.sh` в проекте не запускается. Выглядит как мистика.

**Причина.** CRLF в shebang. При установке Git была выбрана опция `Checkout Windows-style` вместо `as-is`.

**Решение.** Починить глобально и перечитать рабочее дерево:

```bash
git config --global core.autocrlf input
cd <проект>
git rm --cached -r .
git reset --hard
```

Надёжнее — переклонировать репозиторий после смены настройки.

**Профилактика.** При установке Git выбрать **Checkout as-is, commit Unix-style line endings**.

---

### G2. `pnpm install` ругается `ERR_PNPM_IGNORED_BUILDS`

**Не ошибка**, несмотря на красный текст. pnpm 11+ по умолчанию блокирует postinstall-скрипты пакетов.

**Решение.**

```bash
pnpm approve-builds
```

В меню: `a` (выбрать все) → Enter → `y` → Enter. Без этого нативные биндинги не соберутся, и Next.js упадёт на обработке изображений.

---

### G3. `pnpm install` падает с `ERR_PNPM_NO_PKG_MANIFEST`

**Причина.** В проекте нет `package.json` — это пустой шаблон, который ещё не инициализирован.

**Решение.** Не ставить зависимости. Открыть проект новой сессией Claude Code и попросить инициализировать. См. слой 3, §5.

---

### G4. `gh repo create --clone` склонировал не туда

**Причина.** Флаг `--clone` клонирует в **текущую** папку, а команда выполнена не из папки проектов.

**Решение.**

```bash
mv ~/projects/<не-та-папка>/<site> ~/projects/<site>
cd ~/projects/<site> && git status && git remote -v
```

**Профилактика.** Всегда `cd ~/projects` перед командой. В `np` это учтено.

---

### G5. `np collab` ругается «Нет доступа к репозиторию»

**Причина.** Приглашение от владельца не принято.

**Решение.** Открыть https://github.com/notifications под своим аккаунтом, найти приглашение, Accept invitation, повторить команду.

---

### G6. `pnpm dev` падает с `Cannot find module 'next'`

**Причина.** `pnpm install` не дошёл до конца — Ctrl+C или сетевой сбой.

**Решение.** Повторить `pnpm install`. Если падает уже на установке с ошибками `node-gyp` — нужны Build Tools: `scoop install vs_buildtools`.

---

### G7. `ssh -T git@github.com` → Permission denied (publickey)

**Диагностика:**

```bash
ls -la ~/.ssh/id_ed25519          # файл есть?
ssh-add -l                        # ключ в агенте?
ssh -vT git@github.com            # смотреть строки Offering / Authentications
```

**Частые причины:** ключ не в стандартном пути; публичный ключ не добавлен на GitHub; агент не запущен.

**Решение:**

```powershell
Get-Service ssh-agent | Set-Service -StartupType Automatic -Status Running
ssh-add ~/.ssh/id_ed25519
```

Плюс проверить GitHub → Settings → SSH and GPG keys.

---

### G8. Порты конфликтуют между проектами

**Симптом.** Несколько `pnpm dev` параллельно — Next.js перебирает 3000 → 3001 → 3002, и ты уже не помнишь, кто где.

**Решение.** Прописать каждому проекту свой порт в `package.json`:

```json
"dev": "next dev -p 3000"
```

---

## Claude Code

### C1. Режим `bypassPermissions` сбрасывается на `acceptEdits`

**Симптом.** Включил свободный режим, при первом же сообщении сессия откатывается, выскакивает предупреждение.

**Причина.** Известный баг Claude Code Desktop, затронул macOS и Windows. В трекере Anthropic помечен **«not planned»** — чинить не будут.

**Решение.** Использовать режим `auto` — чуть консервативнее, но стабилен. Если свободный режим критичен — работать через CLI вместо десктопа.

---

### C2. Claude Code перезаписывает свой конфиг при правке

**Симптом.** Добавил MCP-сервер в конфиг, через несколько секунд правка пропала.

**Причина.** Приложение периодически сбрасывает своё состояние в файл, затирая твою правку.

**Решение.** Перед правкой **полностью закрыть** Claude Code: правый клик в трее → Quit (не крестик на окне), проверить в диспетчере задач, что процесса нет. Потом править.

---

### C3. Claude Code не видит `mise` / `node` / `pnpm` при работе через bash

**Причина.** Встроенный shell не всегда читает `~/.bashrc`, или получает PATH в Windows-формате.

**Решение.** В начале сессии:

```bash
export PATH="$HOME/AppData/Local/mise/shims:$HOME/scoop/shims:$PATH"
```

Надёжнее — добавить `%LOCALAPPDATA%\mise\shims` в User PATH через `sysdm.cpl`.

---

### C4. Claude упирается в блокировку при скачивании скриптов

**Симптом.** Отказ выполнить скачивание или запуск скачанного скрипта (установка Scoop).

**Причина.** Режим автоматических разрешений.

**Решение.** Подтвердить разрешение вручную или временно выйти из auto-режима, затем попросить повторить команду.

---

### C5. MCP-сервер не появился после правки конфига

**Причина в девяти случаях из десяти.** Неверный путь к Python в конфиге.

**Решение.** Проверить, что файл по указанному пути существует. Путь к venv — через `uv tool dir`. На Windows не использовать лаунчер `.exe` из `~/.local/bin`, указывать Python из venv напрямую с `-m`.

---

## Нашёл что-то новое?

Заводи issue по шаблону:

```
## Симптом
Что увидел, дословно — текст ошибки целиком.

## Контекст
Версия Windows, какой слой, что делал до этого.

## Причина
Если докопался.

## Решение
Что помогло.
```
