<#
.SYNOPSIS
    Scheduled-task entry point.  Copy to deployment share and call from Task Scheduler.

.DESCRIPTION
    Loads ADSync module and runs a delta sync.
    All configuration is supplied via environment variables (injected by the task
    run-as account or a secrets manager) or config.json in the same directory.

    Exit codes
    ──────────
    0 = success (all entities synced without failures)
    1 = partial failure (check log for details)
    2 = fatal / unhandled error
#>

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

try {
    $here = $PSScriptRoot

    # Structured transcript for Task Scheduler event log visibility
    $logDir = Join-Path $here 'logs'
    if (-not (Test-Path $logDir)) { New-Item $logDir -ItemType Directory | Out-Null }
    $transcript = Join-Path $logDir "ADSync_$(Get-Date -Format 'yyyyMMddHHmm').txt"
    Start-Transcript -Path $transcript -Append

    # Import the module
    Import-Module "$here\src\ADSync.psm1" -Force

    # Config file sits alongside this script (copy config.example.json → config.json)
    $configFile = Join-Path $here 'config.json'

    $result = Invoke-ADSync -ConfigFilePath $configFile

    Write-Host "Sync result: Success=$($result.Success) | Elapsed=$($result.ElapsedSeconds)s | CorrelationId=$($result.CorrelationId)"
    Write-Host "Log: $($result.LogFile)"

    exit $(if ($result.Success) { 0 } else { 1 })
}
catch {
    Write-Error "Fatal error in Run-ADSync.ps1: $_"
    exit 2
}
finally {
    Stop-Transcript
}
