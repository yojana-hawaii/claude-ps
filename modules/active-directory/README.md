

# active-directory module


## Quick Start

### 1. Configure

```bash
# Option A: Environment variables (recommended for CI/CD / secrets managers)
$env:ADSYNC_SQL_SERVER = 'sqlserver01.domain.local'
$env:ADSYNC_DATABASE   = 'ActiveDirectory'

# Option B: JSON file
Copy-Item config.example.json config.json
# Edit config.json
```

### 2. Run

```powershell
Import-Module .\src\ADSync.psm1

# Full sync
Invoke-ADSync

# Delta sync — last 4 hours
Invoke-ADSync -DeltaChangeHours 4

# Dry-run (reads AD, skips SQL writes)
Invoke-ADSync -WhatIf

# Skip computers
Invoke-ADSync -SkipComputers
```

### 3. Return value

```powershell
$result = Invoke-ADSync
$result.Success        # $true / $false
$result.ElapsedSeconds # e.g. 47.3
$result.CorrelationId  # ties all log lines for this run together
$result.LogFile        # absolute path to structured log
$result.Results        # per-entity @{ Users=@{Inserted=N;Failed=0} ... }
```

---

## Running Tests

```powershell
# Install Pester 5
Install-Module Pester -RequiredVersion 5.5.0 -Force

# All tests
Invoke-Pester .\tests -Output Detailed

# With coverage
$cfg = New-PesterConfiguration
$cfg.CodeCoverage.Enabled = $true
$cfg.CodeCoverage.Path    = '.\src'
Invoke-Pester -Configuration $cfg
```

No domain controller or SQL Server required — all external cmdlets are mocked.

---

## Logging

Every run produces a structured log file at `logs\ADSync_<yyyyMMddHHmm>.log`:

```
2025-03-07T14:01:00.123Z [INFO ] [a1b2-...] [Invoke-ADSync] Invoke-ADSync starting | CorrelationId=a1b2-... | Delta=48h
2025-03-07T14:01:00.456Z [INFO ] [a1b2-...] [Push-ADSyncUsers] Push-ADSyncUsers: starting — 1247 record(s)
2025-03-07T14:01:12.789Z [WARN ] [a1b2-...] [Push-ADSyncUsers] Push-ADSyncUsers: failed for 'svc_broken' | EX: Timeout
```

The `CorrelationId` field lets you grep/filter all records for a single run in
Splunk, ELK, or Azure Monitor.

---

## SQL Server Stored Procedures Expected

The module calls these stored procedures (UPSERT / MERGE recommended):

| Procedure | Entity |
|-----------|--------|
| `dbo.spAdUser` | Users |
| `dbo.spAdComputers` | Computers |
| `dbo.spAdGroups` | Groups |
| `dbo.spAdGroupMembers` | Group Members |

---

## Bug Fixes vs Original

| Bug | Fix |
|-----|-----|
| `$_.AccoountExpires` typo | Corrected to `$_.AccountExpires` |
| `{_.PasswordLastSet}` missing `$` | Fixed to `{$_.PasswordLastSet}` |
| `AccountExpirationDate` blowing up on 0/MaxValue FileTime | Guarded in `_Convert-FileTime` |
| `continue` used outside a loop in `catch` blocks | Removed; errors now counted and logged |
| Parameter index fragility in `Invoke-sp*` functions | Replaced with named `[ordered]` dictionary |
| No null-to-DBNull conversion | `Add-SqlParameter` handles `$null` → `[DBNull]::Value` |
| Connections not always disposed on exception | `[SqlContext] : IDisposable` + `finally { $ctx.Dispose() }` |
