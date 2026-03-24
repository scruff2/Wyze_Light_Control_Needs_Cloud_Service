[CmdletBinding()]
param(
    [string]$ApkPath = ".\android_apk\base.apk",
    [string]$OutDir = ".\android_apk_decoded",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Get-ApktoolJar {
    $jar = Join-Path $PSScriptRoot "tools\apktool_3.0.1.jar"
    if (-not (Test-Path $jar)) {
        throw "apktool jar not found: $jar"
    }
    return (Resolve-Path $jar).Path
}

$apktoolJar = Get-ApktoolJar
$apkPathResolved = (Resolve-Path $ApkPath).Path
$outDirResolved = Join-Path $PSScriptRoot $OutDir

if ((Test-Path $outDirResolved) -and -not $Force) {
    throw "Output directory already exists: $outDirResolved`nUse -Force after removing or replacing it."
}

if (Test-Path $outDirResolved) {
    Remove-Item -Recurse -Force $outDirResolved
}

Write-Host "== Decompiling APK =="
Write-Host "APK: $apkPathResolved"
Write-Host "Out: $outDirResolved"

& java -jar $apktoolJar d $apkPathResolved -o $outDirResolved --force
if ($LASTEXITCODE -ne 0) {
    throw "apktool decompile failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Decompile complete:"
Write-Host "  $outDirResolved"
