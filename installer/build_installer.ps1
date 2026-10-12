param(
    [string]$PackageDirectory = "$PSScriptRoot\..\dist\releases\v0.1\Karaoke",
    [string]$Compiler = ''
)
$ErrorActionPreference = 'Stop'
$package = (Resolve-Path -LiteralPath $PackageDirectory).Path
foreach ($required in @('Karaoke.exe', 'Karaoke.pck', 'analyzer\karaoke-analyzer.exe', 'tools\ffmpeg\ffmpeg.exe', 'tools\ffmpeg\ffprobe.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $package $required))) { throw "Missing package file: $required" }
}
if (-not $Compiler) {
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) { $Compiler = $command.Source }
    foreach ($candidate in @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe", "$env:ProgramFiles\Inno Setup 7\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe")) {
        if (-not $Compiler -and (Test-Path -LiteralPath $candidate)) { $Compiler = $candidate }
    }
    if (-not $Compiler) {
        $installed = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like 'Inno Setup*' -and $_.InstallLocation }
        foreach ($entry in $installed) {
            $candidate = Join-Path $entry.InstallLocation 'ISCC.exe'
            if (-not $Compiler -and (Test-Path -LiteralPath $candidate)) { $Compiler = $candidate }
        }
    }
}
if (-not $Compiler -or -not (Test-Path -LiteralPath $Compiler)) {
    throw 'Inno Setup 6/7 compiler was not found. Install it from https://jrsoftware.org/isdl.php or provide -Compiler.'
}
& $Compiler "/DPackageRoot=$package" (Join-Path $PSScriptRoot 'karaoke.iss')
if ($LASTEXITCODE -ne 0) { throw "Installer compilation failed: $LASTEXITCODE" }
Write-Output 'Installer files: dist/releases/v0.1/installer. Distribute Setup.exe and all .bin files together.'
