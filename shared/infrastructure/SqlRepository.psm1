<#
.SYNOPSIS
    SQL Server connectivity: connection factory, TVP bulk-insert, and safe disposal.

.DESCRIPTION
    - New-SqlCommandContext   : opens a connection, returns a disposable context object
    - Invoke-SqlStoredProc    : executes a stored procedure with named parameters
    - Invoke-SqlTVPBulkInsert : pushes a DataTable into a stored proc via TVP (fast path)
    - Close-SqlContext        : safe disposal (idempotent, tolerates already-closed)

    Design notes
    - One connection per stored-proc call is intentional: keeps the surface area small,
      avoids leaked connections, and is safe under parallel pipelines.
    - Integrated Security only.  Secrets (SQL auth) must be injected via env vars and
      the connection string extended here.
#>

Set-StrictMode -Version Latest

class SqlContext : System.IDisposable {
    [System.Data.SqlClient.SqlConnection]  $Connection
    [System.Data.SqlClient.SqlCommand]     $Command
    [bool] $IsDisposed = $false

    SqlContext([string]$connectionString, [string]$storedProcedure, [int]$timeoutSeconds) {
        $this.Connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
        $this.Connection.Open()
        $this.Command             = $this.Connection.CreateCommand()
        $this.Command.CommandType = [System.Data.CommandType]::StoredProcedure
        $this.Command.CommandText = $storedProcedure
        $this.Command.CommandTimeout = $timeoutSeconds
    }

    [void] Dispose() {
        if (-not $this.IsDisposed) {
            if ($this.Command)    { $this.Command.Dispose()    }
            if ($this.Connection) { $this.Connection.Dispose() }
            $this.IsDisposed = $true
        }
    }
}

function New-SqlContext {
    <#
    .SYNOPSIS  Opens a SQL connection and returns a [SqlContext].
    .PARAMETER Config           [SyncConfig] instance.
    .PARAMETER StoredProcedure  Fully-qualified SP name (e.g. 'dbo.spAdUsers').
    #>
    [CmdletBinding()]
    [OutputType([SqlContext])]
    param(
        [Parameter(Mandatory)] $Config,          # [SyncConfig]
        [Parameter(Mandatory)] [string] $StoredProcedure
    )

    $cs = "Server=$($Config.SqlServer);Initial Catalog=$($Config.Database);Integrated Security=True;Application Name=ADSync;"
    return [SqlContext]::new($cs, $StoredProcedure, $Config.CommandTimeoutSeconds)
}

function Add-SqlParameter {
    <#
    .SYNOPSIS  Fluent helper — adds a typed parameter to a SqlCommand.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Data.SqlClient.SqlCommand] $Command,
        [Parameter(Mandatory)] [string]  $Name,
        [Parameter(Mandatory)] [System.Data.SqlDbType] $DbType,
        [Parameter(Mandatory)] $Value,
        [int] $Size = -1
    )

    $p = if ($Size -gt 0) {
        [System.Data.SqlClient.SqlParameter]::new($Name, $DbType, $Size)
    } else {
        [System.Data.SqlClient.SqlParameter]::new($Name, $DbType)
    }
    # Cleanly handle PowerShell $null → DBNull
    $p.Value = if ($null -eq $Value -or ($Value -is [string] -and $Value -eq '')) {
        [System.DBNull]::Value
    } else {
        $Value
    }
    $Command.Parameters.Add($p) | Out-Null
}

function Invoke-SqlStoredProc {
    <#
    .SYNOPSIS  Executes a stored procedure using the provided context.
               Returns the rows-affected count.
    .PARAMETER Context    [SqlContext] (caller owns lifecycle).
    .PARAMETER ParamMap   Ordered hashtable: @{ '@Name' = value; ... }
    .PARAMETER TypeMap    Hashtable: @{ '@Name' = [System.Data.SqlDbType]::Xxx }  optional
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [SqlContext] $Context,
        [Parameter(Mandatory)] [System.Collections.Specialized.OrderedDictionary] $ParamMap,
        [hashtable] $TypeMap = @{}
    )

    foreach ($key in $ParamMap.Keys) {
        $dbType = if ($TypeMap.ContainsKey($key)) { $TypeMap[$key] } else { [System.Data.SqlDbType]::NVarChar }
        $size   = if ($dbType -eq [System.Data.SqlDbType]::NVarChar) { 500 } else { -1 }
        Add-SqlParameter -Command $Context.Command -Name $key -DbType $dbType -Value $ParamMap[$key] -Size $size
    }

    return $Context.Command.ExecuteNonQuery()
}

Export-ModuleMember -Function New-SqlContext, Add-SqlParameter, Invoke-SqlStoredProc
