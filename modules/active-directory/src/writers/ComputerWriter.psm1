<#
.SYNOPSIS
    Persists AD computer DTOs to SQL Server via dbo.spAdComputers.
#>

Set-StrictMode -Version Latest

function Push-ADSyncComputers {
    <#
    .SYNOPSIS   Upserts computer DTOs into SQL Server.
    .PARAMETER  Computers  Array of objects from Get-fnADSyncComputers.
    .PARAMETER  Config     [SyncConfig] instance.
    .PARAMETER  Logger     Logger hashtable from New-SyncLogger.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject[]] $Computers,
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [hashtable] $Logger
    )

    $total    = $Computers.Count
    $inserted = 0
    $failed   = 0

    & $Logger.Info "Push-ADSyncComputers: starting — $total record(s)"

    foreach ($computer in $Computers) {
        $ctx = $null
        try {
            $ctx = New-SqlContext -Config $Config -StoredProcedure 'dbo.spAdComputers'

            $params = [ordered]@{
                '@ComputerName'          = $computer.ComputerName
                '@Enabled'               = $computer.Enabled
                '@HasBitlocker'          = $computer.HasBitlocker
                '@HasLaps'               = $computer.HasLaps
                '@DistinguishedName'     = $computer.DistinguishedName
                '@OU'                    = $computer.OU
                '@sAMAccountName'        = $computer.sAMAccountName
                '@IPV4Address'           = $computer.IPV4Address
                '@OperatingSystem'       = $computer.OperatingSystem
                '@OperatingSystemVersion'= $computer.OperatingSystemVersion
                '@Description'           = $computer.Description
                '@CreatedDate'           = $computer.CreatedDate
                '@ModifiedDate'          = $computer.ModifiedDate
                '@BitLockerPasswordDate' = $computer.BitLockerPasswordDate
                '@LapsExpirationDate'    = $computer.LapsExpirationDate
                '@LastLogonDate'         = $computer.LastLogonDate
                '@LogonCount'            = $computer.LogonCount
                '@UserAccountControl'    = $computer.UserAccountControl
            }

            Invoke-SqlStoredProc -Context $ctx -ParamMap $params | Out-Null
            $inserted++
        }
        catch {
            $failed++
            & $Logger.Error "Push-ADSyncComputers: failed for '$($computer.ComputerName)'" $_.Exception
        }
        finally {
            if ($null -ne $ctx) { $ctx.Dispose() }
        }
    }

    & $Logger.Info "Push-ADSyncComputers: complete — inserted=$inserted failed=$failed"
    return [PSCustomObject]@{ Inserted = $inserted; Failed = $failed }
}

Export-ModuleMember -Function Push-ADSyncComputers
