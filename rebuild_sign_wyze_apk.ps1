[CmdletBinding()]
param(
    [string]$DecodedDir = ".\android_apk_decoded",
    [string]$BuildDir = ".\android_build",
    [string]$UnsignedApkName = "wyze-instrumented-unsigned.apk",
    [string]$AlignedApkName = "wyze-instrumented-aligned.apk",
    [string]$SignedApkName = "wyze-instrumented-signed.apk"
)

$ErrorActionPreference = "Stop"

function Get-RequiredPath {
    param(
        [string]$Path,
        [string]$Label
    )
    if (-not (Test-Path $Path)) {
        throw "$Label not found: $Path"
    }
    return (Resolve-Path $Path).Path
}

function Get-LatestBuildTool {
    $root = Join-Path $env:LOCALAPPDATA "Android\Sdk\build-tools"
    if (-not (Test-Path $root)) {
        throw "Android build-tools directory not found: $root"
    }
    $dir = Get-ChildItem $root -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $dir) {
        throw "No Android build-tools versions found under: $root"
    }
    return $dir.FullName
}

$apktoolJar = Get-RequiredPath (Join-Path $PSScriptRoot "tools\apktool_3.0.1.jar") "apktool jar"
$decodedDirResolved = Get-RequiredPath (Join-Path $PSScriptRoot $DecodedDir) "Decoded directory"
$buildDirResolved = Join-Path $PSScriptRoot $BuildDir
$buildTools = Get-LatestBuildTool
$zipalign = Get-RequiredPath (Join-Path $buildTools "zipalign.exe") "zipalign"
$apksigner = Get-RequiredPath (Join-Path $buildTools "apksigner.bat") "apksigner"
$debugKeystore = Join-Path $env:USERPROFILE ".android\debug.keystore"
$debugKeystoreResolved = Get-RequiredPath $debugKeystore "Android debug keystore"

New-Item -ItemType Directory -Force -Path $buildDirResolved | Out-Null

$unsignedApk = Join-Path $buildDirResolved $UnsignedApkName
$alignedApk = Join-Path $buildDirResolved $AlignedApkName
$signedApk = Join-Path $buildDirResolved $SignedApkName

foreach ($path in @($unsignedApk, $alignedApk, $signedApk)) {
    if (Test-Path $path) {
        Remove-Item -Force $path
    }
}

Write-Host "== Rebuilding APK =="
Write-Host "Decoded dir: $decodedDirResolved"
Write-Host "Unsigned APK: $unsignedApk"

& java -jar $apktoolJar b $decodedDirResolved -o $unsignedApk --copy-original
if ($LASTEXITCODE -ne 0) {
    throw "apktool build failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "== Aligning APK =="
& $zipalign -f -p 4 $unsignedApk $alignedApk
if ($LASTEXITCODE -ne 0) {
    throw "zipalign failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "== Signing APK =="
& $apksigner sign --ks $debugKeystoreResolved --ks-key-alias androiddebugkey --ks-pass pass:android --key-pass pass:android --out $signedApk $alignedApk
if ($LASTEXITCODE -ne 0) {
    throw "apksigner failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "== Verifying Signature =="
& $apksigner verify --verbose $signedApk
if ($LASTEXITCODE -ne 0) {
    throw "apksigner verify failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Build complete:"
Write-Host "  Unsigned: $unsignedApk"
Write-Host "  Aligned : $alignedApk"
Write-Host "  Signed  : $signedApk"
