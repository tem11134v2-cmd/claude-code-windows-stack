# Переносит профиль Proxifier новому пользователю и ставит автозапуск.
#
# ЗАПУСКАТЬ ПОД РАБОЧИМ ПОЛЬЗОВАТЕЛЕМ после первого входа по RDP. Идемпотентно.
#
# Профиль (.ppx) ты экспортируешь сам из настроенного Proxifier:
#   Proxifier -> File -> Export Profile
# и указываешь путь в config.json -> proxifier.profilePath.
#
# Лицензия и учётные данные прокси через этот скрипт НЕ переносятся —
# их здесь нет и быть не должно.

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\config.ps1"

$profilePath = $Config.proxifier.profilePath
$dest        = "$env:APPDATA\Proxifier4\Profiles"

Write-Host "[1/2] Профиль Proxifier..."

if ([string]::IsNullOrWhiteSpace($profilePath)) {
    Write-Host "  proxifier.profilePath пуст — пропускаю."
    Write-Host "  Настроишь профиль руками по 00-server/README.md, §4."
} elseif (-not (Test-Path $profilePath)) {
    Write-Host "  ВНИМАНИЕ: файл не найден: $profilePath"
    Write-Host "  Проверь путь в config.json или настрой профиль руками."
} else {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item $profilePath (Join-Path $dest "Default.ppx") -Force
    Write-Host "  Скопирован в $dest\Default.ppx"
}

Write-Host ""
Write-Host "[2/2] Автозапуск при входе пользователя..."

$exe = "C:\Program Files (x86)\Proxifier\Proxifier.exe"
if (-not (Test-Path $exe)) {
    Write-Host "  ВНИМАНИЕ: Proxifier не найден по пути $exe"
    Write-Host "  Установи его и перезапусти скрипт."
} else {
    Set-ItemProperty `
        -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -Name "Proxifier" `
        -Value "`"$exe`" aut"
    Write-Host "  Прописан."
}

Write-Host ""
Write-Host "─────────────────────────────────────────────────────────────"
Write-Host "ДАЛЬШЕ РУКАМИ — это галочки в GUI, скриптом не делается:"
Write-Host ""
Write-Host "1. Лицензия. Help -> Registration."
Write-Host "   Если просит ключ — введи и ОБЯЗАТЕЛЬНО поставь галку"
Write-Host "   'for all users of this computer'. Иначе каждый новый"
Write-Host "   пользователь будет видеть триал."
Write-Host ""
Write-Host "2. Перехват чужого трафика. Profile -> Advanced ->"
Write-Host "   'Services and Other Users...' (это отдельный диалог,"
Write-Host "   а не галки прямо в меню). Внутри включить:"
Write-Host "     - Applications run by other users on this computer"
Write-Host "     - Windows services and other system processes"
Write-Host ""
Write-Host "   Без этого твой трафик пойдёт мимо прокси, когда первым"
Write-Host "   залогинится другой пользователь."
Write-Host ""
Write-Host "3. Если увидишь попап 'уже запущено в другой сессии' —"
Write-Host "   это нормально, закрой крестиком. Трафик защищён тем"
Write-Host "   инстансом, который стартовал первым."
Write-Host "─────────────────────────────────────────────────────────────"
Write-Host ""
Write-Host "Проверка (должен быть IP прокси, а не сервера):"
Write-Host '  (Invoke-RestMethod https://api.ipify.org?format=json).ip'
