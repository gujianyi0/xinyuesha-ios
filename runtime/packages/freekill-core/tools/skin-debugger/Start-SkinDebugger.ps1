param([string]$GameRoot)
$ErrorActionPreference = 'Stop'
if (-not $GameRoot) {
    $GameRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
}
$taskExecutable = Join-Path $GameRoot 'FreeKill.exe'
if (-not (Test-Path -LiteralPath $taskExecutable -PathType Leaf)) {
    throw 'FreeKill.exe not found. Install this tool in freekill-core/tools/skin-debugger, or specify -GameRoot.'
}
# Reuse the game's built-in Spine engine and graphics backend in a separate window.
Start-Process -FilePath $taskExecutable -ArgumentList @('--skin-debugger') -WorkingDirectory $GameRoot
