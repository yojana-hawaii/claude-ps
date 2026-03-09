<#
.SYNOPSIS
    Reads Active Directory computer objects and projects them into flat DTOs.

.DESCRIPTION
    Retrieves LAPS password metadata, BitLocker recovery info, and all standard
    computer properties. Expensive per-object lookups (LAPS, BitLocker) are
    performed inline via calculated properties so the pipeline stays lazy.
#>

Set-StrictMode -Version Latest

function Get-fnADSyncComputers {
    <#
    .SYNOPSIS   Returns AD computer records.
    .PARAMETER  Enabled   $true/$false/$null (all).
    .PARAMETER  ServersOnly   If $true, filter to OS containing 'server'.
    .PARAMETER  Identity  Specific computer name, or 'all'.
    .PARAMETER  DeltaChangeHours  0 = no delta filter.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()] [nullable[bool]] $Enabled          = $true,
        [Parameter()] [bool]           $ServersOnly       = $false,
        [Parameter()] [string]         $Identity         = 'all',
        [Parameter()] [int]            $DeltaChangeHours = 0
    )

    $filter = _Build-ComputerFilter -Enabled $Enabled -ServersOnly $ServersOnly `
                                    -Identity $Identity -DeltaChangeHours $DeltaChangeHours

    $props = @(
        'DistinguishedName','CanonicalName','sAMAccountName','IPv4Address',
        'OperatingSystem','OperatingSystemVersion','Description',
        'Created','Modified','LastLogonDate','LogonCount','UserAccountControl','Enabled'
    )

    try {
        return Get-ADComputer -Filter $filter -Properties $props |
            Select-Object `
                @{ N='ComputerName';           E={ $_.Name                                          } },
                @{ N='Enabled';                E={ if ($_.Enabled) {1} else {0}                     } },
                @{ N='HasBitlocker';           E={ _Test-Bitlocker $_.DistinguishedName             } },
                @{ N='HasLaps';                E={ _Test-Laps $_.Name                               } },
                DistinguishedName,
                @{ N='OU';                     E={ $_.CanonicalName                                 } },
                sAMAccountName,
                IPV4Address,
                OperatingSystem,
                OperatingSystemVersion,
                @{ N='Description';            E={ $_.Description -replace "'","''"                 } },
                @{ N='CreatedDate';            E={ $_.Created                                       } },
                @{ N='ModifiedDate';           E={ $_.Modified                                      } },
                @{ N='BitLockerPasswordDate';  E={ _Get-BitlockerDate $_.DistinguishedName          } },
                @{ N='LapsExpirationDate';     E={ _Get-LapsExpiration $_.Name                      } },
                LastLogonDate,
                LogonCount,
                UserAccountControl
    }
    catch {
        throw [System.Exception]::new(
            "Get-fnADSyncComputers failed (filter=$filter): $($_.Exception.Message)", $_.Exception)
    }
}

# ──────────────────────────────────────────────
# Private helpers
# ──────────────────────────────────────────────

function _Build-ComputerFilter {
    param([nullable[bool]]$Enabled, [bool]$ServersOnly, [string]$Identity, [int]$DeltaChangeHours)

    if ($Identity -ne 'all') { return "Name -eq '$Identity'" }

    $parts = @()
    if ($ServersOnly) {
        $parts += "OperatingSystem -like '*server*'"
    } else {
        $parts += "OperatingSystem -notlike '*server*'"
    }
    if ($null -ne $Enabled) { $parts += "Enabled -eq '$Enabled'" }
    if ($DeltaChangeHours -gt 0) {
        $since  = (Get-Date).AddHours(-$DeltaChangeHours)
        $parts += "Modified -gt '$since'"
    }
    return $parts -join ' -and '
}

function _Test-Bitlocker ([string]$dn) {
    try {
        $obj = Get-ADObject -Filter "objectClass -eq 'msFVE-RecoveryInformation'" `
                            -SearchBase $dn -ErrorAction SilentlyContinue |
               Select-Object -First 1
        return if ($null -ne $obj) {1} else {0}
    } catch { return 0 }
}

function _Test-Laps ([string]$computerName) {
    try {
        $laps = Get-LapsADPassword -Identity $computerName -ErrorAction SilentlyContinue
        return if ($null -ne $laps) {1} else {0}
    } catch { return 0 }
}

function _Get-BitlockerDate ([string]$dn) {
    try {
        return Get-ADObject -Filter "objectClass -eq 'msFVE-RecoveryInformation'" `
                            -SearchBase $dn -Properties whenCreated -ErrorAction SilentlyContinue |
               Sort-Object whenCreated -Descending |
               Select-Object -First 1 -ExpandProperty whenCreated
    } catch { return $null }
}

function _Get-LapsExpiration ([string]$computerName) {
    try {
        return (Get-LapsADPassword -Identity $computerName -ErrorAction SilentlyContinue).ExpirationTimeStamp
    } catch { return $null }
}

Export-ModuleMember -Function Get-fnADSyncComputers
