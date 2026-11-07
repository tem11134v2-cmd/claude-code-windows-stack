# Создаёт рабочего пользователя, добавляет в Administrators и Remote Desktop Users,
# выдаёт права на папку проектов.
#
# ЗАПУСКАТЬ ПОД АДМИНИСТРАТОРОМ. Идемпотентно — можно перезапускать.
#
# Пароль нигде не хранится: запрашивается здесь и передаётся как SecureString.

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\config.ps1"

$name     = $Config.user.name
$projects = $Config.paths.projects

Write-Host "[1/3] Проверяю, есть ли пользователь '$name'..."

$exists = $null
try { $exists = Get-LocalUser -Name $name -ErrorAction Stop } catch { }

if ($exists) {
    Write-Host "  Пользователь уже существует — оставляю как есть."
} else {
    Write-Host ""
    Write-Host "  Задай пароль для нового пользователя '$name'."
    Write-Host "  Требования политики Windows: минимум 8 символов, заглавные, строчные и цифры."
    Write-Host "  Чисто цифровой пароль будет отклонён."
    Write-Host ""

    # Не называть переменную $pwd — это зарезервированное имя в PowerShell
    # (текущая рабочая директория).
    $securePwd = Read-Host "  Пароль для $name" -AsSecureString

    try {
        New-LocalUser -Name $name `
                      -Password $securePwd `
                      -FullName $name `
                      -Description "Work user for Claude Code stack" `
                      -PasswordNeverExpires `
                      -ErrorAction Stop | Out-Null
        Write-Host "  Создан."
    } catch {
        throw "Не удалось создать пользователя: $($_.Exception.Message)`nЧаще всего причина — пароль не проходит политику сложности."
    } finally {
        if ($securePwd) { $securePwd.Dispose() }
    }
}

Write-Host ""
Write-Host "[2/3] Добавляю в Administrators и Remote Desktop Users..."
Write-Host "      (Administrators — для удобства: ставить софт и менять настройки системы."
Write-Host "       Proxifier админских прав у рабочего пользователя НЕ требует, см. ARCHITECTURE.md)"

foreach ($group in @("Administrators", "Remote Desktop Users")) {
    try {
        Add-LocalGroupMember -Group $group -Member $name -ErrorAction Stop
        Write-Host "  Добавлен в $group"
    } catch {
        if ($_.Exception.Message -match "already a member|уже является") {
            Write-Host "  Уже в $group"
        } else {
            throw
        }
    }
}

Write-Host ""
Write-Host "[3/3] Выдаю права на папку проектов..."

if (Test-Path $projects) {
    & icacls.exe $projects /grant "${name}:(OI)(CI)F" /T | Out-Null
    Write-Host "  $projects -> полный доступ"
} else {
    Write-Host "  $projects пока не существует — пропускаю (создастся позже)"
}

& icacls.exe $LayerRoot /grant "${name}:(OI)(CI)F" /T | Out-Null
Write-Host "  $LayerRoot -> полный доступ"

Write-Host ""
Write-Host "Готово. Теперь зайди по RDP под '$name' и продолжай с 02-proxifier.ps1."
