param(
    [string]$BulbIp = "10.0.0.50",
    [string]$BulbMac = "A1-B2-C3-D4-E5-F6",
    [int[]]$Ports = @(80, 443, 554, 6668, 6669, 8883, 1883, 8008, 8009),
    [string]$CaptureDir = ".\captures",
    [switch]$StartCapture,
    [switch]$StopCapture
)

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "== $Title =="
}

function Ensure-CaptureDir {
    if (-not (Test-Path -LiteralPath $CaptureDir)) {
        New-Item -ItemType Directory -Path $CaptureDir | Out-Null
    }
}

function Invoke-NativeOrThrow {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,
        [string]$FailureMessage = "Command failed.",
        [int[]]$AllowedExitCodes = @(0)
    )

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()

    try {
        $process = Start-Process -FilePath $ArgumentList[0] `
            -ArgumentList $ArgumentList[1..($ArgumentList.Length - 1)] `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $exitCode = $process.ExitCode
        $stdout = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
    } finally {
        Remove-Item -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrPath -ErrorAction SilentlyContinue
    }

    if ($stdout) {
        $stdout.TrimEnd() | Write-Host
    }

    if ($stderr) {
        $stderr.TrimEnd() | Write-Host
    }

    if ($AllowedExitCodes -notcontains $exitCode) {
        throw "$FailureMessage Exit code: $exitCode"
    }
}

function Start-BulbCapture {
    if (-not (Test-IsAdministrator)) {
        throw "pktmon requires an elevated PowerShell session. Re-run PowerShell as Administrator."
    }

    Ensure-CaptureDir

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $captureRoot = (Resolve-Path -LiteralPath $CaptureDir).Path
    $etlPath = Join-Path $captureRoot "wyze-bulb-$stamp.etl"
    $statePath = Join-Path $captureRoot "last_capture.txt"

    Write-Section "Starting pktmon capture"
    Invoke-NativeOrThrow -ArgumentList @("pktmon", "stop") -FailureMessage "Failed to stop existing pktmon session." -AllowedExitCodes @(0, 1)
    Invoke-NativeOrThrow -ArgumentList @("pktmon", "filter", "remove") -FailureMessage "Failed to remove existing pktmon filters."
    Invoke-NativeOrThrow -ArgumentList @("pktmon", "filter", "add", "WyzeBulb", "-i", $BulbIp) -FailureMessage "Failed to add pktmon filter."
    Invoke-NativeOrThrow -ArgumentList @("pktmon", "start", "--capture", "--pkt-size", "0", "--file-name", $etlPath) -FailureMessage "Failed to start pktmon capture."

    Set-Content -LiteralPath $statePath -Value $etlPath -Encoding ascii

    Write-Host "Capture started:"
    Write-Host "  ETL: $etlPath"
    Write-Host ""
    Write-Host "Now perform the offline-control test in the Wyze app."
}

function Stop-BulbCapture {
    if (-not (Test-IsAdministrator)) {
        throw "pktmon requires an elevated PowerShell session. Re-run PowerShell as Administrator."
    }

    $captureRoot = (Resolve-Path -LiteralPath $CaptureDir).Path
    $statePath = Join-Path $captureRoot "last_capture.txt"
    if (-not (Test-Path -LiteralPath $statePath)) {
        throw "No capture state file found at $statePath"
    }

    $etlPath = (Get-Content -LiteralPath $statePath -Raw).Trim()
    if (-not (Test-Path -LiteralPath $etlPath)) {
        throw "Recorded ETL path does not exist: $etlPath"
    }

    $pcapPath = [System.IO.Path]::ChangeExtension($etlPath, ".pcapng")

    Write-Section "Stopping pktmon capture"
    Invoke-NativeOrThrow -ArgumentList @("pktmon", "stop") -FailureMessage "Failed to stop pktmon capture."
    Invoke-NativeOrThrow -ArgumentList @("pktmon", "etl2pcap", $etlPath, "--out", $pcapPath) -FailureMessage "Failed to convert ETL to PCAPNG."

    Write-Host "Capture stopped:"
    Write-Host "  ETL:    $etlPath"
    Write-Host "  PCAPNG: $pcapPath"
}

if ($StartCapture -and $StopCapture) {
    throw "Use either -StartCapture or -StopCapture, not both."
}

if ($StartCapture) {
    Start-BulbCapture
    return
}

if ($StopCapture) {
    Stop-BulbCapture
    return
}

Write-Section "Interface"
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -like "10.0.0.*" } |
    Select-Object IPAddress, InterfaceAlias, PrefixLength |
    Format-Table -Auto

Write-Section "Neighbor"
$neighbor = Get-NetNeighbor -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -eq $BulbIp } |
    Select-Object IPAddress, LinkLayerAddress, State, InterfaceAlias

if ($neighbor) {
    $neighbor | Format-Table -Auto
} else {
    Write-Host "No neighbor entry found for $BulbIp"
}

Write-Section "Ping"
$ping = Test-NetConnection -ComputerName $BulbIp -InformationLevel Detailed
$ping |
    Select-Object ComputerName, RemoteAddress, InterfaceAlias, SourceAddress, PingSucceeded, PingReplyDetails |
    Format-List

Write-Section "Known TCP Ports"
foreach ($port in $Ports) {
    $open = Test-NetConnection -ComputerName $BulbIp -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
    "{0}: {1}" -f $port, $open
}

Write-Section "Expected MAC"
Write-Host "Configured bulb MAC: $BulbMac"
