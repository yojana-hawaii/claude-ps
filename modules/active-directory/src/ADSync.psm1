<#
.SYNOPSIS
    Orchestrates a full or delta Active Directory → SQL Server sync.

.DESCRIPTION
    Entry point for scheduled tasks, CI/CD pipelines, and manual runs.

    Execution order
    ───────────────
    1. Load config (env vars > config.json > defaults)
    2. Initialise structured logger (bound to a CorrelationId for this run)
    3. Users  : active + inactive
    4. Computers : servers | active workstations | inactive workstations
    5. Groups + Group Members (delta by default)

    Return value
    ────────────
    [PSCustomObject] with per-entity Inserted/Failed counters + overall Success flag.
    Exit code 1 is set when any entity has failures so CI/CD pipelines can gate on it.

.PARAMETER ConfigFilePath
    Optional path to a JSON configuration file.
    If omitted, configuration is resolved from environment variables and defaults.

.PARAMETER DeltaChangeHours
    Override the delta window (hours).  0 = full sync.
    When omitted, the value from config / env is used.

.PARAMETER SkipUsers
    Skip user sync (useful for partial runs).

.PARAMETER SkipComputers
    Skip computer sync.

.PARAMETER SkipGroups
    Skip group and group-member sync.

.PARAMETER WhatIf
    Dry-run: reads AD but does not write to SQL.

.EXAMPLE
    # Full sync using env-var config (typical CI/CD usage)
    Invoke-ADSync

.EXAMPLE
    # Delta sync, last 4 hours, config from file
    Invoke-ADSync -ConfigFilePath '.\config\prod.json' -DeltaChangeHours 4

.EXAMPLE
    # Dry-run to verify AD connectivity
    Invoke-ADSync -WhatIf
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# ── Module imports ──────────────────────────────────────────────────────────
$moduleRoot = $PSScriptRoot

Import-Module "$moduleRoot\Infrastructure\Logger.psm1"       -Force
Import-Module "$moduleRoot\Infrastructure\Config.psm1"       -Force
Import-Module "$moduleRoot\Infrastructure\SqlRepository.psm1" -Force

Import-Module "$moduleRoot\ActiveDirectory\UserReader.psm1"   -Force
Import-Module "$moduleRoot\ActiveDirectory\ComputerReader.psm1" -Force
Import-Module "$moduleRoot\ActiveDirectory\GroupReader.psm1"  -Force

Import-Module "$moduleRoot\SqlRepository\UserWriter.psm1"     -Force
Import-Module "$moduleRoot\SqlRepository\ComputerWriter.psm1" -Force
Import-Module "$moduleRoot\SqlRepository\GroupWriter.psm1"    -Force

# ── Public function ──────────────────────────────────────────────────────────

function Invoke-ADSync {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $ConfigFilePath   = '',
        [int]    $DeltaChangeHours = -1,   # -1 = use config value
        [switch] $SkipUsers,
        [switch] $SkipComputers,
        [switch] $SkipGroups
    )

    # ── 1. Config + Logger ───────────────────────────────────────────────────
    $config = Get-SyncConfig -ConfigFilePath $ConfigFilePath
    if ($DeltaChangeHours -ge 0) { $config.DeltaChangeHours = $DeltaChangeHours }

    $logFile = Join-Path $PSScriptRoot "..\logs\ADSync_$(Get-Date -Format 'yyyyMMddHHmm').log"
    $logDir  = Split-Path $logFile
    if (-not (Test-Path $logDir)) { New-Item $logDir -ItemType Directory | Out-Null }

    $log = New-SyncLogger -LogFilePath $logFile
    & $log.Info "Invoke-ADSync starting | CorrelationId=$($log.CorrelationId) | Delta=$($config.DeltaChangeHours)h | WhatIf=$([bool]$WhatIfPreference)"

    $runStart = [datetime]::UtcNow
    $results  = [ordered]@{}

    # ── 2. Users ─────────────────────────────────────────────────────────────
    if (-not $SkipUsers) {
        & $log.Info "--- USERS ---"
        try {
            $activeUsers   = Get-fnADSyncUsers -Enabled $true
            $inactiveUsers = Get-fnADSyncUsers -Enabled $false
            $allUsers      = @($activeUsers) + @($inactiveUsers)
            & $log.Info "AD query: $($allUsers.Count) user(s) found"

            if (-not $WhatIfPreference) {
                $results.Users = Push-ADSyncUsers -Users $allUsers -Config $config -Logger $log
            } else {
                & $log.Info "WhatIf: skipping SQL write for users"
            }
        }
        catch { & $log.Error "User sync failed" $_.Exception }
    }

    # ── 3. Computers ─────────────────────────────────────────────────────────
    if (-not $SkipComputers) {
        & $log.Info "--- COMPUTERS ---"
        try {
            $servers   = Get-fnADSyncComputers -ServersOnly $true  -Enabled $null
            $activeWS  = Get-fnADSyncComputers -ServersOnly $false -Enabled $true
            $inactiveWS= Get-fnADSyncComputers -ServersOnly $false -Enabled $false
            $allComps  = @($servers) + @($activeWS) + @($inactiveWS)
            & $log.Info "AD query: $($allComps.Count) computer(s) found"

            if (-not $WhatIfPreference) {
                $results.Computers = Push-ADSyncComputers -Computers $allComps -Config $config -Logger $log
            } else {
                & $log.Info "WhatIf: skipping SQL write for computers"
            }
        }
        catch { & $log.Error "Computer sync failed" $_.Exception }
    }

    # ── 4. Groups + Members ───────────────────────────────────────────────────
    if (-not $SkipGroups) {
        & $log.Info "--- GROUPS ---"
        try {
            $groups = @(Get-fnADSyncGroups -DeltaChangeHours $config.DeltaChangeHours)
            & $log.Info "AD query: $($groups.Count) group(s) found"

            if ($groups.Count -gt 0 -and -not $WhatIfPreference) {
                $results.Groups = Push-ADSyncGroups -Groups $groups -Config $config -Logger $log
            }
        }
        catch { & $log.Error "Group sync failed" $_.Exception }

        & $log.Info "--- GROUP MEMBERS ---"
        try {
            $members = @(Get-ADSyncGroupMembers -DeltaChangeHours $config.DeltaChangeHours)
            & $log.Info "AD query: $($members.Count) member row(s) found"

            if ($members.Count -gt 0 -and -not $WhatIfPreference) {
                $results.GroupMembers = Push-ADSyncGroupMembers -GroupMembers $members -Config $config -Logger $log
            }
        }
        catch { & $log.Error "Group-member sync failed" $_.Exception }
    }

    # ── 5. Summary ────────────────────────────────────────────────────────────
    $elapsed   = ([datetime]::UtcNow - $runStart).TotalSeconds
    $anyFailed = $results.Values | Where-Object { $_.Failed -gt 0 }
    $success   = ($null -eq $anyFailed)

    & $log.Info "Invoke-ADSync complete | ElapsedSeconds=$([Math]::Round($elapsed,1)) | Success=$success"

    if (-not $success) {
        & $log.Warn "One or more entities had failures — review log: $logFile"
        $global:LASTEXITCODE = 1
    }

    return [PSCustomObject]@{
        CorrelationId = $log.CorrelationId
        Success       = $success
        ElapsedSeconds= [Math]::Round($elapsed, 1)
        Results       = $results
        LogFile       = $logFile
    }
}

Export-ModuleMember -Function Invoke-ADSync
