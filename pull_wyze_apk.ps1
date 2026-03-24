param(
    [string]$AdbPath = "$env:USERPROFILE\AppData\Local\Android\Sdk\platform-tools\adb.exe",
    [string]$PackageName = "com.hualai",
    [string]$OutputDir = ".\android_apk"
)

$ErrorActionPreference = "Stop"

function Require-File {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Name not found: $Path"
    }
}

Require-File -Path $AdbPath -Name "adb"

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$outputRoot = (Resolve-Path -LiteralPath $OutputDir).Path

$devices = & $AdbPath devices
$hasAuthorizedDevice = $false
foreach ($line in $devices) {
    if ($line -match '^\S+\s+device$') {
        $hasAuthorizedDevice = $true
        break
    }
}

if (-not $hasAuthorizedDevice) {
    throw "No authorized Android device detected by adb."
}

$versionInfo = & $AdbPath shell dumpsys package $PackageName
if (-not $versionInfo) {
    throw "Unable to read package info for $PackageName"
}

$versionName = (($versionInfo | Select-String 'versionName=' | Select-Object -First 1).ToString() -replace '.*versionName=', '').Trim()
$versionCode = (($versionInfo | Select-String 'versionCode=' | Select-Object -First 1).ToString() -replace '.*versionCode=', '').Trim()
$firstInstallTime = (($versionInfo | Select-String 'firstInstallTime=' | Select-Object -First 1).ToString() -replace '.*firstInstallTime=', '').Trim()
$lastUpdateTime = (($versionInfo | Select-String 'lastUpdateTime=' | Select-Object -First 1).ToString() -replace '.*lastUpdateTime=', '').Trim()

$paths = & $AdbPath shell pm path $PackageName
if (-not $paths) {
    throw "No APK paths returned for $PackageName"
}

$metadataPath = Join-Path $outputRoot "package_info.txt"
@(
    "Package: $PackageName"
    "VersionName: $versionName"
    "VersionCode: $versionCode"
    "FirstInstallTime: $firstInstallTime"
    "LastUpdateTime: $lastUpdateTime"
    ""
    "APK Paths:"
    $paths
) | Set-Content -LiteralPath $metadataPath -Encoding ascii

foreach ($line in $paths) {
    $remotePath = ($line -replace '^package:', '').Trim()
    $fileName = [System.IO.Path]::GetFileName($remotePath)
    $localPath = Join-Path $outputRoot $fileName
    & $AdbPath pull $remotePath $localPath
}

Write-Host "Pulled APK files to: $outputRoot"
Write-Host "Metadata: $metadataPath"
