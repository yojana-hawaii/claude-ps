<#
.SYNOPSIS
    Reads Active Directory groups and their members into flat DTOs.

.DESCRIPTION
    - Get-fnADSyncGroups       : returns group metadata records
    - Get-ADSyncGroupMembers : returns membership rows (group → member)

    Both functions support a delta mode (DeltaChangeHours) so that recurring
    scheduled runs only process objects changed since the last run.
#>

Set-StrictMode -Version Latest

function Get-fnADSyncGroups {
    <#
    .SYNOPSIS   Returns AD group records.
    .PARAMETER  DeltaChangeHours   0 = all groups, N = changed in last N hours.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()] [int] $DeltaChangeHours = 48
    )

    $filter = _Build-GroupFilter -DeltaChangeHours $DeltaChangeHours

    $props = @(
        'CanonicalName','sAMAccountName','Name','mail','DistinguishedName',
        'Description','whenCreated','whenChanged','GroupCategory','GroupScope'
    )

    try {
        return Get-ADGroup -Filter $filter -Properties $props |
            Select-Object `
                CanonicalName,
                sAMAccountName,
                Name,
                mail,
                DistinguishedName,
                Description,
                @{ N='CreatedDate';  E={ $_.whenCreated } },
                @{ N='ModifiedDate'; E={ $_.whenChanged } },
                GroupCategory,
                GroupScope
    }
    catch {
        throw [System.Exception]::new(
            "Get-fnADSyncGroups failed: $($_.Exception.Message)", $_.Exception)
    }
}

function Get-ADSyncGroupMembers {
    <#
    .SYNOPSIS   Returns membership rows for groups changed within DeltaChangeHours.
    .PARAMETER  DeltaChangeHours   0 = all groups, N = changed in last N hours.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()] [int] $DeltaChangeHours = 48
    )

    $filter = _Build-GroupFilter -DeltaChangeHours $DeltaChangeHours

    try {
        $groups = Get-ADGroup -Filter $filter -Properties sAMAccountName,DistinguishedName

        # Streaming assignment — no intermediate array allocation
        return foreach ($group in $groups) {
            $grpSam = $group.sAMAccountName
            Get-ADGroupMember -Identity $group.DistinguishedName -ErrorAction SilentlyContinue |
                ForEach-Object {
                    [PSCustomObject]@{
                        GroupSamAccountName = $grpSam
                        Username            = $_.sAMAccountName
                        ObjectClass         = $_.objectClass
                    }
                }
        }
    }
    catch {
        throw [System.Exception]::new(
            "Get-ADSyncGroupMembers failed: $($_.Exception.Message)", $_.Exception)
    }
}

# ──────────────────────────────────────────────
# Private helpers
# ──────────────────────────────────────────────

function _Build-GroupFilter {
    param([int]$DeltaChangeHours)
    if ($DeltaChangeHours -le 0) { return '*' }
    $since = (Get-Date).AddHours(-$DeltaChangeHours)
    return "whenChanged -gt '$since'"
}

Export-ModuleMember -Function Get-fnADSyncGroups, Get-ADSyncGroupMembers
