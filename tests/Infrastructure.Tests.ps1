<#
.SYNOPSIS
    Pester v5 tests — Infrastructure layer (Logger, Config, SqlRepository)
    Run with: Invoke-Pester .\tests\Infrastructure.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $srcRoot = Join-Path $PSScriptRoot '..\src'
    Import-Module "$srcRoot\Infrastructure\Logger.psm1"        -Force
    Import-Module "$srcRoot\Infrastructure\Config.psm1"        -Force
    Import-Module "$srcRoot\Infrastructure\SqlRepository.psm1" -Force
}

# ── Logger ───────────────────────────────────────────────────────────────────

Describe 'New-SyncLogger' {

    Context 'CorrelationId' {
        It 'auto-generates a GUID when none supplied' {
            $log = New-SyncLogger
            $log.CorrelationId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        }

        It 'preserves a caller-supplied CorrelationId' {
            $id  = 'test-run-001'
            $log = New-SyncLogger -CorrelationId $id
            $log.CorrelationId | Should -Be $id
        }
    }

    Context 'Returned hashtable shape' {
        It 'exposes Info, Warn, Error, Debug scriptblocks' {
            $log = New-SyncLogger
            $log.Info  | Should -BeOfType [scriptblock]
            $log.Warn  | Should -BeOfType [scriptblock]
            $log.Error | Should -BeOfType [scriptblock]
            $log.Debug | Should -BeOfType [scriptblock]
        }
    }

    Context 'Info writes to Information stream' {
        It 'emits a record on the Information stream' {
            $log      = New-SyncLogger -CorrelationId 'ci-test'
            $captured = & { & $log.Info 'hello test' } 6>&1
            $captured | Should -Not -BeNullOrEmpty
            ($captured -join '') | Should -BeLike '*hello test*'
        }
    }

    Context 'File sink' {
        It 'appends to the log file when LogFilePath is supplied' {
            $tmp = [System.IO.Path]::GetTempFileName()
            $log = New-SyncLogger -LogFilePath $tmp
            & $log.Info 'file sink test'
            Get-Content $tmp | Should -BeLike '*file sink test*'
            Remove-Item $tmp -Force
        }
    }
}

# ── Config ────────────────────────────────────────────────────────────────────

Describe 'Get-SyncConfig' {

    Context 'Environment variable override' {
        BeforeEach {
            $env:ADSYNC_SQL_SERVER = 'env-server'
            $env:ADSYNC_DATABASE   = 'env-db'
        }
        AfterEach {
            Remove-Item Env:\ADSYNC_SQL_SERVER -ErrorAction SilentlyContinue
            Remove-Item Env:\ADSYNC_DATABASE   -ErrorAction SilentlyContinue
        }

        It 'reads SqlServer and Database from env vars' {
            $cfg = Get-SyncConfig
            $cfg.SqlServer | Should -Be 'env-server'
            $cfg.Database  | Should -Be 'env-db'
        }
    }

    Context 'JSON file' {
        It 'reads values from a valid JSON config file' {
            $tmp = [System.IO.Path]::GetTempFileName() + '.json'
            @{ SqlServer = 'json-server'; Database = 'json-db'; DeltaChangeHours = 12 } |
                ConvertTo-Json | Set-Content $tmp
            # Env vars must not shadow the file for this test
            Remove-Item Env:\ADSYNC_SQL_SERVER -ErrorAction SilentlyContinue
            Remove-Item Env:\ADSYNC_DATABASE   -ErrorAction SilentlyContinue

            $cfg = Get-SyncConfig -ConfigFilePath $tmp
            $cfg.SqlServer        | Should -Be 'json-server'
            $cfg.DeltaChangeHours | Should -Be 12
            Remove-Item $tmp -Force
        }
    }

    Context 'Validation' {
        It 'throws when SqlServer is missing' {
            Remove-Item Env:\ADSYNC_SQL_SERVER -ErrorAction SilentlyContinue
            Remove-Item Env:\ADSYNC_DATABASE   -ErrorAction SilentlyContinue
            { Get-SyncConfig } | Should -Throw
        }
    }
}

# ── SqlRepository helpers ────────────────────────────────────────────────────

Describe 'Add-SqlParameter' {

    It 'sets DBNull for $null values' {
        # Create an in-memory SqlCommand stub via a mock connection
        $mockConn = [System.Data.SqlClient.SqlConnection]::new()
        $cmd = [System.Data.SqlClient.SqlCommand]::new()

        Add-SqlParameter -Command $cmd -Name '@TestParam' `
                         -DbType ([System.Data.SqlDbType]::NVarChar) -Value $null -Size 100

        $cmd.Parameters['@TestParam'].Value | Should -Be ([System.DBNull]::Value)
    }

    It 'sets DBNull for empty string values' {
        $cmd = [System.Data.SqlClient.SqlCommand]::new()
        Add-SqlParameter -Command $cmd -Name '@EmptyParam' `
                         -DbType ([System.Data.SqlDbType]::NVarChar) -Value '' -Size 100
        $cmd.Parameters['@EmptyParam'].Value | Should -Be ([System.DBNull]::Value)
    }

    It 'preserves non-null values' {
        $cmd = [System.Data.SqlClient.SqlCommand]::new()
        Add-SqlParameter -Command $cmd -Name '@Val' `
                         -DbType ([System.Data.SqlDbType]::NVarChar) -Value 'hello' -Size 100
        $cmd.Parameters['@Val'].Value | Should -Be 'hello'
    }
}
