param([Parameter(Mandatory=$true)][string]$SetupExecutable)
$ErrorActionPreference = 'Stop'
$repository = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testRoot = Join-Path $repository 'workspace\environment-check\v0.1 installer smoke'
$installRoot = Join-Path $testRoot 'Installed Karaoke'
$setup = (Resolve-Path -LiteralPath $SetupExecutable).Path
if (Test-Path -LiteralPath $installRoot) { throw "Test directory already exists: $installRoot" }
if (-not $installRoot.StartsWith((Join-Path $repository 'workspace\'), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Installer smoke test must remain inside the project workspace.'
}
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$savedAppData = $env:APPDATA
$savedLocalAppData = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $testRoot 'profile\roaming'
    $env:LOCALAPPDATA = Join-Path $testRoot 'profile\local'
    New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
    $userData = Join-Path $env:APPDATA 'Godot\app_userdata\Karaoke PoC'
    New-Item -ItemType Directory -Path (Join-Path $userData 'songs') -Force | Out-Null
    $marker = Join-Path $userData 'songs\preserve-marker.txt'
    Set-Content -LiteralPath $marker -Value 'preserve user songs'
    $settings = Join-Path $userData 'settings.cfg'
    Set-Content -LiteralPath $settings -Value "[microphone]`ndevice=`"Default`"`ngain_db=12.0"
    $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOICONS', '/TASKS=', "/DIR=`"$installRoot`"", "/LOG=`"$testRoot\install.log`"")
    $process = Start-Process -FilePath $setup -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Installation failed: $($process.ExitCode). See $testRoot\install.log" }
    foreach ($required in @('Karaoke.exe', 'Karaoke.pck', 'analyzer\karaoke-analyzer.exe', 'tools\ffmpeg\ffmpeg.exe', 'models', 'unins000.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $installRoot $required))) { throw "Missing installed component: $required" }
    }
    $process = Start-Process -FilePath (Join-Path $installRoot 'Karaoke.exe') -ArgumentList @('--headless', '--quit-after', '120') -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $testRoot 'startup.out.txt') -RedirectStandardError (Join-Path $testRoot 'startup.err.txt')
    if ($process.ExitCode -ne 0) { throw "Installed game startup failed: $($process.ExitCode)" }
    $helper = Join-Path $installRoot 'analyzer\karaoke-analyzer.exe'
    & $helper --help | Out-File -FilePath (Join-Path $testRoot 'analyzer-help.txt') -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw 'Installed analyzer --help failed.' }
    $process = Start-Process -FilePath (Join-Path $installRoot 'unins000.exe') -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$testRoot\uninstall.log`"") -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Uninstall failed: $($process.ExitCode)" }
    if (Test-Path -LiteralPath (Join-Path $installRoot 'Karaoke.exe')) { throw 'Uninstall left the game executable behind.' }
    if (-not (Test-Path -LiteralPath $marker) -or -not (Test-Path -LiteralPath $settings)) { throw 'Uninstall removed user data.' }
    Write-Output 'Installer smoke test PASS: install, game startup, analyzer help, uninstall and user-data preservation.'
} finally {
    $env:APPDATA = $savedAppData
    $env:LOCALAPPDATA = $savedLocalAppData
}
