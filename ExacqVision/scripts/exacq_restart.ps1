<#
.SYNOPSIS
    Monitors and restarts the exacqVisionServer service with retry logic.
    Called by Zabbix Action when the service has been stopped for 10+ minutes.

.DESCRIPTION
    1. Checks if exacqVisionServer is running — exits cleanly if it is
    2. Waits 10 minutes (avoids reacting to brief blips)
    3. Attempts to restart the service up to 3 times with 30-second gaps
    4. Logs every action to a rotating log file
    5. Writes a status flag file for Zabbix to consume

    Exit codes:
        0 — Service running (no action needed or restart succeeded)
        2 — All retries exhausted, service still stopped
    
    Status flag values:
        RUNNING   — Service was already running (no action needed)
        RESTARTED — Service was restarted successfully
        FAILED    — All restart attempts failed

.PARAMETER ServiceName
    Windows service name to monitor/restart (default: exacqVisionServer)
.PARAMETER MaxRetries
    Number of restart attempts (default: 3)
.PARAMETER RetryDelaySeconds
    Seconds between retry attempts (default: 30)
.PARAMETER LogDir
    Directory for log and status files (default: C:\ProgramData\Zabbix\exacqvision)
#>

param(
    [string]$ServiceName = "exacqVisionServer",
    [int]$MaxRetries = 3,
    [int]$RetryDelaySeconds = 30,
    [string]$LogDir = "C:\ProgramData\Zabbix\exacqvision"
)

# ---- Paths ----
$LogFile     = Join-Path $LogDir "exacq_restart.log"
$StatusFile  = Join-Path $LogDir "exacq_restart_status.txt"
$DetailFile  = Join-Path $LogDir "exacq_restart_detail.txt"
$MaxLogSize  = 1MB

# ---- Ensure directories exist ----
if (-not (Test-Path $LogDir)) {
    $null = New-Item -ItemType Directory -Path $LogDir -Force
}

# ---- Rotate log if oversized ----
if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt $MaxLogSize)) {
    $rotated = $LogFile -replace '\.log$', ".bak"
    if (Test-Path $rotated) { Remove-Item $rotated -Force }
    Rename-Item $LogFile $rotated -Force
}

# ---- Helpers ----
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append -Encoding ASCII
}

function Write-Status {
    param([string]$Value)
    $Value | Out-File -FilePath $StatusFile -Encoding ASCII -Force
    Get-Date -Format "yyyy-MM-dd HH:mm:ss" | Out-File -FilePath "$StatusFile.timestamp" -Encoding ASCII -Force
}

Write-Log "=== exacq_restart.ps1 invoked ==="

# ---- Step 1: Does the service exist? ----
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Log "ERROR: Service '$ServiceName' not found on this system."
    Write-Status "NOT_FOUND"
    exit 2
}

# ---- Step 2: Check current state ----
if ($service.Status -eq 'Running') {
    Write-Log "Service is already running. No action needed."
    Write-Status "RUNNING"
    exit 0
}

Write-Log "Service is STOPPED (status: $($service.Status))."
Write-Log "Waiting 10 minutes before acting (in case of brief blip)..."
Write-Status "WAITING"

Start-Sleep -Seconds 600   # 10 minutes

# ---- Step 3: Re-check after wait ----
$service.Refresh()
if ($service.Status -eq 'Running') {
    Write-Log "Service recovered on its own during the 10-minute wait. No action needed."
    Write-Status "RUNNING"
    exit 0
}

Write-Log "Service still stopped after 10-minute wait. Beginning restart attempts..."

# ---- Step 4: Retry loop ----
$success = $false
$attemptDetails = @()

for ($i = 1; $i -le $MaxRetries; $i++) {
    Write-Log "--- Attempt $i of $MaxRetries ---"
    
    try {
        Start-Service -Name $ServiceName -ErrorAction Stop
        Start-Sleep -Seconds 10   # Give it time to fully start
        
        $service.Refresh()
        if ($service.Status -eq 'Running') {
            Write-Log "Attempt $i: SUCCESS — service is now running."
            $success = $true
            $attemptDetails += "Attempt $i: SUCCESS"
            break
        } else {
            Write-Log "Attempt $i: Start completed but service status is $($service.Status)."
            $attemptDetails += "Attempt $i: FAILED (status=$($service.Status))"
        }
    } catch {
        Write-Log "Attempt $i: EXCEPTION — $($_.Exception.Message)"
        $attemptDetails += "Attempt $i: EXCEPTION — $($_.Exception.Message)"
    }
    
    # Wait before next retry (unless this was the last attempt)
    if ($i -lt $MaxRetries) {
        Write-Log "Waiting $RetryDelaySeconds seconds before next attempt..."
        Start-Sleep -Seconds $RetryDelaySeconds
    }
}

# ---- Step 5: Write final status ----
$detailContent = $attemptDetails -join " | "

if ($success) {
    Write-Status "RESTARTED"
    $detailContent | Out-File -FilePath $DetailFile -Encoding ASCII -Force
    Write-Log "RESULT: Service restarted successfully."
    exit 0
} else {
    Write-Status "FAILED"
    $detailContent | Out-File -FilePath $DetailFile -Encoding ASCII -Force
    Write-Log "RESULT: ALL $MaxRetries attempts FAILED. Manual intervention required."
    exit 2
}