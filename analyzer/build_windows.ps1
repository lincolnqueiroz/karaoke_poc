param(
    [Parameter(Mandatory=$true)][string]$FFmpegDirectory,
    [string]$ModelCache = '',
    [string]$HuggingFaceCache = '',
    [string]$Python = "$PSScriptRoot\.venv\Scripts\python.exe"
)
$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
$tools = (Resolve-Path -LiteralPath $FFmpegDirectory).Path
foreach ($tool in @('ffmpeg.exe', 'ffprobe.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $tools $tool))) { throw "Ausente: $tool" }
}
if (-not $ModelCache -and -not $HuggingFaceCache) { throw 'Informe ModelCache (TORCH_HOME) ou HuggingFaceCache (HF_HOME), com pesos já baixados.' }
if ($ModelCache) {
    $models = (Resolve-Path -LiteralPath $ModelCache).Path
    if (-not (Test-Path -LiteralPath (Join-Path $models 'hub\checkpoints'))) { throw 'ModelCache deve conter hub\checkpoints.' }
    if (-not (Get-ChildItem -LiteralPath (Join-Path $models 'hub\checkpoints') -File)) { throw 'Cache de pesos vazio.' }
}
if ($HuggingFaceCache) {
    $hfModels = (Resolve-Path -LiteralPath $HuggingFaceCache).Path
    if (-not (Test-Path -LiteralPath (Join-Path $hfModels 'hub\models--adefossez--HTDemucs'))) { throw 'HF_HOME deve conter hub\models--adefossez--HTDemucs.' }
}
$package = Join-Path $repository 'dist\Karaoke'
if (Test-Path -LiteralPath $package) { throw 'dist\Karaoke já existe. Mova a versão anterior antes de gerar outra.' }
$ErrorActionPreference = 'Continue' # Windows PowerShell treats native stderr logs as errors.
& $Python -m PyInstaller --noconfirm --distpath (Join-Path $repository 'build\analyzer-dist') --workpath (Join-Path $repository 'build\pyinstaller') (Join-Path $PSScriptRoot 'karaoke-analyzer.spec')
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) { throw 'Falha no PyInstaller.' }
New-Item -ItemType Directory -Path $package -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repository 'build\analyzer-dist\karaoke-analyzer') -Destination (Join-Path $package 'analyzer') -Recurse
$bundledTools = Join-Path $package 'tools\ffmpeg'
New-Item -ItemType Directory -Path $bundledTools -Force | Out-Null
foreach ($item in Get-ChildItem -LiteralPath $tools -File) {
    if ($item.Extension -in @('.exe', '.dll')) { Copy-Item -LiteralPath $item.FullName -Destination $bundledTools }
}
if ($ModelCache) {
    $bundledModels = Join-Path $package 'models\torch\hub\checkpoints'
    New-Item -ItemType Directory -Path $bundledModels -Force | Out-Null
    Copy-Item -Path (Join-Path $models 'hub\checkpoints\*') -Destination $bundledModels -Recurse
}
if ($HuggingFaceCache) {
    $bundledHF = Join-Path $package 'models\huggingface\hub'
    New-Item -ItemType Directory -Path $bundledHF -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $hfModels 'hub\models--adefossez--HTDemucs') -Destination $bundledHF -Recurse
}
& (Join-Path $package 'analyzer\karaoke-analyzer.exe') --help
if ($LASTEXITCODE -ne 0) { throw 'O executável não passou no teste --help.' }
Write-Output "Analisador preparado em $package. Exporte o Godot para Karaoke.exe nessa pasta."
