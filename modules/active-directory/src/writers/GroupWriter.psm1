<#
.SYNOPSIS
    Persists AD group and group-member DTOs to SQL Server.
#>

Set-StrictMode -Version Latest

function Push-ADSyncGroups {
    <#
    .SYNOPSIS   Upserts group DTOs into SQL Server via dbo.spAdGroups.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject[]] $Groups,
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [hashtable] $Logger
    )

    $total    = $Groups.Count
    $inserted = 0
    $failed   = 0

    & $Logger.Info "Push-ADSyncGroups: starting — $total record(s)"

    foreach ($group in $Groups) {
        $ctx = $null
        try {
            $ctx = New-SqlContext -Config $Config -StoredProcedure 'dbo.spAdGroups'

            $params = [ordered]@{
                '@CanonicalName'     = $group.CanonicalName
                '@sAMAccountName'    = $group.sAMAccountName
                '@name'              = $group.Name
                '@mail'              = $group.mail
                '@DistinguishedName' = $group.DistinguishedName
                '@Description'       = $group.Description
                '@CreatedDate'       = $group.CreatedDate
                '@ModifiedDate'      = $group.ModifiedDate
                '@GroupCategory'     = $group.GroupCategory
                '@GroupScope'        = $group.GroupScope
            }

            Invoke-SqlStoredProc -Context $ctx -ParamMap $params | Out-Null
            $inserted++
        }
        catch {
            $failed++
            & $Logger.Error "Push-ADSyncGroups: failed for '$($group.sAMAccountName)'" $_.Exception
        }
        finally {
            if ($null -ne $ctx) { $ctx.Dispose() }
        }
    }

    & $Logger.Info "Push-ADSyncGroups: complete — inserted=$inserted failed=$failed"
    return [PSCustomObject]@{ Inserted = $inserted; Failed = $failed }
}

function Push-ADSyncGroupMembers {
    <#
    .SYNOPSIS   Upserts group-member rows into SQL Server via dbo.spAdGroupMembers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject[]] $GroupMembers,
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [hashtable] $Logger
    )

    $total    = $GroupMembers.Count
    $inserted = 0
    $failed   = 0

    & $Logger.Info "Push-ADSyncGroupMembers: starting — $total record(s)"

    foreach ($gm in $GroupMembers) {
        $ctx = $null
        try {
            $ctx = New-SqlContext -Config $Config -StoredProcedure 'dbo.spAdGroupMembers'

            $params = [ordered]@{
                '@GroupSamAccountName' = $gm.GroupSamAccountName
                '@Username'            = $gm.Username
                '@ObjectClass'         = $gm.ObjectClass
            }

            Invoke-SqlStoredProc -Context $ctx -ParamMap $params | Out-Null
            $inserted++
        }
        catch {
            $failed++
            & $Logger.Error "Push-ADSyncGroupMembers: failed for '$($gm.Username)' in '$($gm.GroupSamAccountName)'" $_.Exception
        }
        finally {
            if ($null -ne $ctx) { $ctx.Dispose() }
        }
    }

    & $Logger.Info "Push-ADSyncGroupMembers: complete — inserted=$inserted failed=$failed"
    return [PSCustomObject]@{ Inserted = $inserted; Failed = $failed }
}

Export-ModuleMember -Function Push-ADSyncGroups, Push-ADSyncGroupMembers
