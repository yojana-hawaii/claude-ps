<#
.SYNOPSIS
    Reads Active Directory users and projects them into flat DTOs.

.DESCRIPTION
    Returns [PSCustomObject] records ready for SQL insertion.
    All field names mirror stored-procedure parameter names to avoid
    a separate mapping layer.

    Bug fixes vs original:
    - AccoountExpires typo fixed → AccountExpires
    - PasswordLastSet expression fixed: {$_.PasswordLastSet} not {_.PasswordLastSet}
    - AccountExpirationDate: guarded against 0 / max FileTime before conversion
#>

Set-StrictMode -Version Latest

function Get-fnADSyncUsers {
    <#
    .SYNOPSIS   Returns AD user records matching the given filter criteria.
    .PARAMETER  Enabled          Filter by account state. $null = return both.
    .PARAMETER  Identity         Specific sAMAccountName, or 'all'.
    .PARAMETER  DeltaChangeHours 0 = no delta filter.  N = changed in last N hours.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()] [nullable[bool]] $Enabled          = $true,
        [Parameter()] [string]         $Identity         = 'all',
        [Parameter()] [int]            $DeltaChangeHours = 0
    )

    $filter = Build-fnUserFilter -Enabled $Enabled -Identity $Identity -DeltaChangeHours $DeltaChangeHours

    $props = @(
        'GivenName','Surname','DisplayName','EmailAddress','DistinguishedName',
        'CanonicalName','userPrincipalName','StreetAddress','HomePhone',
        'MobilePhone','OfficePhone','Fax','Company','Department','Title',
        'Description','AccountExpires','Enabled','LastLogonDate',
        'whenCreated','whenChanged','PasswordNeverExpires','PasswordExpired',
        'PasswordLastSet','ScriptPath','LogonCount','EmployeeId','Manager'
    )

    try {
        return Get-ADUser -Filter $filter -Properties $props |
            Select-Object `
                CanonicalName,
                sAMAccountName,
                userPrincipalName,
                @{ N='FirstName';  E={ $_.GivenName  } },
                @{ N='LastName';   E={ $_.Surname     } },
                DisplayName,
                EmailAddress,
                DistinguishedName,
                StreetAddress,
                HomePhone,
                MobilePhone,
                OfficePhone,
                Fax,
                Company,
                Department,
                Title,
                @{ N='Description'; E={ $_.Description -replace "'","''" } },
                @{ N='AccountExpirationDate'; E={ Convert-fnFileTime $_.AccountExpires } },
                Enabled,
                LastLogonDate,
                @{ N='CreatedDate';           E={ $_.whenCreated } },
                @{ N='ModifiedDate';          E={ $_.whenChanged } },
                PasswordNeverExpires,
                PasswordExpired,
                @{ N='PasswordLastSetDate';   E={ $_.PasswordLastSet } },
                ScriptPath,
                LogonCount,
                EmployeeId,
                @{ N='Manager'; E={ Resolve-fnManagerSam $_.Manager } }
    }
    catch {
        throw [System.Exception]::new(
            "Get-fnADSyncUsers failed (filter=$filter): $($_.Exception.Message)", $_.Exception)
    }
}

# ──────────────────────────────────────────────
# Private helpers (not exported)
# ──────────────────────────────────────────────

function Build-fnUserFilter {
    param([nullable[bool]]$Enabled, [string]$Identity, [int]$DeltaChangeHours)

    if ($Identity -ne 'all') { return "sAMAccountName -eq '$Identity'" }

    $parts = @()
    if ($null -ne $Enabled) { $parts += "Enabled -eq '$Enabled'" }
    if ($DeltaChangeHours -gt 0) {
        $since = (Get-Date).AddHours(-$DeltaChangeHours)
        $parts += "whenChanged -gt '$since'"
    }
    return if ($parts) { $parts -join ' -and ' } else { '*' }
}

function Resolve-fnManagerSam ([string]$managerDN) {
    if ([string]::IsNullOrWhiteSpace($managerDN)) { return '' }
    try   { return (Get-ADUser -Identity $managerDN -Properties sAMAccountName).sAMAccountName }
    catch { return '' }
}

function Convert-fnFileTime ([long]$fileTime) {
    # 0, $null, and Int64.MaxValue all mean "never expires"
    if ($fileTime -le 0 -or $fileTime -eq [long]::MaxValue) { return $null }
    try { return [datetime]::FromFileTime($fileTime) } catch { return $null }
}

Export-ModuleMember -Function Get-fnADSyncUsers
