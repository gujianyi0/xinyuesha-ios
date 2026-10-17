#requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$FreeKillSource,
    [Parameter(Mandatory)][string]$QtRoot,
    [Parameter(Mandatory)][string]$CompilerBin,
    [string]$CMake = 'cmake',
    [string]$BuildDirectory = (Join-Path $env:TEMP 'freekill-skin-inspector-build'),
    [int]$Jobs = 4
)
$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath($FreeKillSource)
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'src/ui/spine/spinebackend.h'))) {
    throw 'FreeKill client source directory with multi-version Spine backends is required.'
}
$env:Path = "$CompilerBin;$QtRoot/bin;$env:Path"
$nativeSource = Join-Path $PSScriptRoot 'native'
& $CMake -S $nativeSource -B $BuildDirectory -G 'MinGW Makefiles' "-DCMAKE_PREFIX_PATH=$QtRoot" "-DFREEKILL_SOURCE_DIR=$sourceRoot" '-DCMAKE_BUILD_TYPE=Release'
if ($LASTEXITCODE -ne 0) { throw 'Inspector configure failed.' }
& $CMake --build $BuildDirectory --parallel $Jobs
if ($LASTEXITCODE -ne 0) { throw 'Inspector build failed.' }
$destination = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Fk/Tools/SkinDebugger/native/SkinInspector'))
New-Item -ItemType Directory -Force -Path $destination | Out-Null
Copy-Item -LiteralPath (Join-Path $BuildDirectory 'module/skininspector.dll'), (Join-Path $BuildDirectory 'module/qmldir') -Destination $destination -Force
# Include the original adapter/runtime notices alongside the built module.
$noticeFiles = @(Join-Path $sourceRoot 'LICENSE')
$noticeFiles += Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'src/spine-versions') -Recurse -File -Filter '*license*' | Select-Object -ExpandProperty FullName
$notices = $noticeFiles | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | ForEach-Object { "`n--- $([IO.Path]::GetRelativePath($sourceRoot, $_)) ---`n" + [IO.File]::ReadAllText($_) }
foreach ($version in 21,34,35,36,37,38,40,41,42) {
    $runtimeHeader = Join-Path $sourceRoot "src/spine-versions/spine-c-$version/include/spine/spine.h"
    $headerText = [IO.File]::ReadAllText($runtimeHeader)
    $notices += "`n--- Spine runtime $version ---`n" + $headerText.Substring(0, $headerText.IndexOf('*/') + 2)
}
$noticeText = [regex]::Replace(($notices -join "`n"), '(?m)[ \t]+(?=\r?$)', '')
[IO.File]::WriteAllText((Join-Path $destination 'THIRD-PARTY-NOTICES.txt'), $noticeText, [Text.UTF8Encoding]::new($false))
Write-Host "Inspector ready: $destination"
