<#
.SYNOPSIS
    Persists AD user DTOs to SQL Server via dbo.spAdUser.
#>

Set-StrictMode -Version Latest

function Push-ADSyncUsers {
    <#
    .SYNOPSIS   Upserts a collection of user DTOs into SQL Server.
    .PARAMETER  Users    Array of objects from Get-fnADSyncUsers.
    .PARAMETER  Config   [SyncConfig] instance.
    .PARAMETER  Logger   Logger hashtable from New-SyncLogger.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject[]] $Users,
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [hashtable] $Logger
    )

    $total    = $Users.Count
    $inserted = 0
    $failed   = 0

    & $Logger.Info "Push-ADSyncUsers: starting — $total record(s)"

    foreach ($user in $Users) {
        $ctx = $null
        try {
            $ctx = New-SqlContext -Config $Config -StoredProcedure 'dbo.spAdUser'

            $params = [ordered]@{
                '@CanonicalName'        = $user.CanonicalName
                '@sAMAccountName'       = $user.sAMAccountName
                '@userPrincipalName'    = $user.userPrincipalName
                '@FirstName'            = $user.FirstName
                '@LastName'             = $user.LastName
                '@DisplayName'          = $user.DisplayName
                '@EmailAddress'         = $user.EmailAddress
                '@DistinguishedName'    = $user.DistinguishedName
                '@StreetAddress'        = $user.StreetAddress
                '@HomePhone'            = $user.HomePhone
                '@MobilePhone'          = $user.MobilePhone
                '@OfficePhone'          = $user.OfficePhone
                '@Fax'                  = $user.Fax
                '@Company'              = $user.Company
                '@Department'           = $user.Department
                '@Title'                = $user.Title
                '@Description'          = $user.Description
                '@AccountExpirationDate'= $user.AccountExpirationDate
                '@Enabled'              = $user.Enabled
                '@LastLogonDate'        = $user.LastLogonDate
                '@CreatedDate'          = $user.CreatedDate
                '@ModifiedDate'         = $user.ModifiedDate
                '@PasswordNeverExpires' = $user.PasswordNeverExpires
                '@PasswordExpired'      = $user.PasswordExpired
                '@PasswordLastSetDate'  = $user.PasswordLastSetDate
                '@ScriptPath'           = $user.ScriptPath
                '@LogonCount'           = $user.LogonCount
                '@EmployeeId'           = $user.EmployeeId
                '@Manager'              = $user.Manager
            }

            Invoke-SqlStoredProc -Context $ctx -ParamMap $params | Out-Null
            $inserted++
        }
        catch {
            $failed++
            & $Logger.Error "Push-ADSyncUsers: failed for '$($user.sAMAccountName)'" $_.Exception
        }
        finally {
            if ($null -ne $ctx) { $ctx.Dispose() }
        }
    }

    & $Logger.Info "Push-ADSyncUsers: complete — inserted=$inserted failed=$failed"
    return [PSCustomObject]@{ Inserted = $inserted; Failed = $failed }
}

Export-ModuleMember -Function Push-ADSyncUsers
