<#
.SYNOPSIS
    Loads and validates run-time configuration.

.DESCRIPTION
    Configuration is resolved in priority order (highest wins):
      1. Environment variables  (CI/CD / secrets manager integration)
      2. JSON config file       ($ConfigFilePath)
      3. Hard-coded defaults    (safe fallback for dev)

    Required keys : SqlServer, Database
    Optional keys : CommandTimeoutSeconds (default 30), DeltaChangeHours (default 48)
#>

Set-StrictMode -Version Latest

class SyncConfig {
    [string] $SqlServer
    [string] $Database
    [int]    $CommandTimeoutSeconds = 30
    [int]    $DeltaChangeHours      = 48
    [bool]   $UseTVP                = $true   # table-valued parameter bulk insert

    [void] Validate() {
        if ([string]::IsNullOrWhiteSpace($this.SqlServer)) { throw "Config: SqlServer is required." }
        if ([string]::IsNullOrWhiteSpace($this.Database))  { throw "Config: Database is required."  }
        if ($this.CommandTimeoutSeconds -lt 0)              { throw "Config: CommandTimeoutSeconds must be >= 0." }
    }
}

function Get-SyncConfig {
    <#
    .SYNOPSIS  Returns a validated [SyncConfig] instance.
    .PARAMETER ConfigFilePath   Path to a JSON config file.  Optional.
    #>
    [CmdletBinding()]
    [OutputType([SyncConfig])]
    param(
        [string] $ConfigFilePath = ''
    )

    $cfg = [SyncConfig]::new()

    # --- Layer 2: JSON file ---
    if ($ConfigFilePath -and (Test-Path $ConfigFilePath)) {
        $json = Get-Content $ConfigFilePath -Raw | ConvertFrom-Json
        if ($json.SqlServer)              { $cfg.SqlServer              = $json.SqlServer }
        if ($json.Database)               { $cfg.Database               = $json.Database }
        if ($json.CommandTimeoutSeconds)  { $cfg.CommandTimeoutSeconds  = $json.CommandTimeoutSeconds }
        if ($json.DeltaChangeHours)       { $cfg.DeltaChangeHours       = $json.DeltaChangeHours }
        if ($null -ne $json.UseTVP)       { $cfg.UseTVP                 = $json.UseTVP }
    }

    # --- Layer 1: Environment variables (highest priority) ---
    if ($env:ADSYNC_SQL_SERVER)   { $cfg.SqlServer = $env:ADSYNC_SQL_SERVER }
    if ($env:ADSYNC_DATABASE)     { $cfg.Database  = $env:ADSYNC_DATABASE  }
    if ($env:ADSYNC_DELTA_HOURS)  { $cfg.DeltaChangeHours = [int]$env:ADSYNC_DELTA_HOURS }

    $cfg.Validate()
    return $cfg
}

Export-ModuleMember -Function Get-SyncConfig
