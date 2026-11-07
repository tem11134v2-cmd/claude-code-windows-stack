# Общий загрузчик конфига. Подключается из любого скрипта:
#   . "$PSScriptRoot\lib\config.ps1"

$LayerRoot  = (Get-Item "$PSScriptRoot\..\..").FullName
$ConfigPath = Join-Path $LayerRoot "config.json"

if (-not (Test-Path $ConfigPath)) {
    throw @"
config.json не найден: $ConfigPath

Сначала выполни:
    Copy-Item "$LayerRoot\config.example.json" "$ConfigPath"

Потом отредактируй $ConfigPath под эту машину.
"@
}

$Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
