<#
.SYNOPSIS
    Enterprise structured logging using PowerShell's built-in streams + optional file sink.

.DESCRIPTION
    Wraps Write-Information/Warning/Error with a structured [LogEntry] object so every
    log line carries: Timestamp, Level, CallerFunction, CorrelationId, Message, and optional
    exception details.  The CorrelationId ties every record from a single Invoke-ADSync
    run together—ideal for Splunk / ELK / Azure Monitor ingestion.

    Log levels  : DEBUG | INFO | WARN | ERROR
    Output sinks: PowerShell Information stream (always) + optional file sink.
#>

Set-StrictMode -Version Latest

class LogEntry {
    [datetime]  $Timestamp
    [string]    $Level
    [string]    $CorrelationId
    [string]    $CallerFunction
    [string]    $Message
    [string]    $ExceptionMessage
    [string]    $StackTrace

    [string] ToString() {
        $base = "$($this.Timestamp.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')) [$($this.Level.PadRight(5))] [$($this.CorrelationId)] [$($this.CallerFunction)] $($this.Message)"
        if ($this.ExceptionMessage) { $base += " | EX: $($this.ExceptionMessage)" }
        return $base
    }
}

function New-SyncLogger {
    <#
    .SYNOPSIS  Returns a logger hashtable bound to a correlation ID.
    .PARAMETER CorrelationId   Defaults to a new GUID when omitted.
    .PARAMETER LogFilePath     If supplied, entries are also appended to this file.
    .OUTPUTS   [hashtable] with keys: Info, Warn, Error, Debug, CorrelationId
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string] $CorrelationId = [System.Guid]::NewGuid().ToString(),
        [string] $LogFilePath   = ''
    )

    $writeSink = {
        param([LogEntry]$entry)
        $line = $entry.ToString()
        switch ($entry.Level) {
            'WARN'  { Write-Warning  $line }
            'ERROR' { Write-Error    $line -ErrorAction Continue }
            'DEBUG' { Write-Debug    $line }
            default { Write-Information $line -InformationAction Continue }
        }
        if ($script:_logFilePath) {
            Add-Content -Path $script:_logFilePath -Value $line -Encoding UTF8
        }
    }

    # Capture path in module-scope variable so the scriptblock can see it
    $script:_logFilePath = $LogFilePath

    $makeEntry = {
        param([string]$level, [string]$message, [System.Exception]$ex = $null)
        $caller = (Get-PSCallStack)[2].FunctionName   # skip makeEntry + the helper below
        $entry  = [LogEntry]@{
            Timestamp      = [datetime]::UtcNow
            Level          = $level
            CorrelationId  = $CorrelationId
            CallerFunction = $caller
            Message        = $message
        }
        if ($ex) {
            $entry.ExceptionMessage = $ex.Message
            $entry.StackTrace       = $ex.StackTrace
        }
        return $entry
    }

    return @{
        CorrelationId = $CorrelationId

        Info  = { param([string]$msg)
            & $writeSink (& $makeEntry 'INFO'  $msg) }.GetNewClosure()

        Warn  = { param([string]$msg)
            & $writeSink (& $makeEntry 'WARN'  $msg) }.GetNewClosure()

        Error = { param([string]$msg, [System.Exception]$ex = $null)
            & $writeSink (& $makeEntry 'ERROR' $msg $ex) }.GetNewClosure()

        Debug = { param([string]$msg)
            & $writeSink (& $makeEntry 'DEBUG' $msg) }.GetNewClosure()
    }
}

Export-ModuleMember -Function New-SyncLogger
