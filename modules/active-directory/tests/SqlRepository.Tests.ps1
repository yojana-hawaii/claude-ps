<#
.SYNOPSIS
    Pester v5 tests — SqlRepository writer layer
    SQL cmdlets are mocked so no live database is required.
    Run with: Invoke-Pester .\tests\SqlRepository.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $srcRoot = Join-Path $PSScriptRoot '..\src'
    Import-Module "$srcRoot\Infrastructure\Logger.psm1"        -Force
    Import-Module "$srcRoot\Infrastructure\Config.psm1"        -Force
    Import-Module "$srcRoot\Infrastructure\SqlRepository.psm1" -Force
    Import-Module "$srcRoot\SqlRepository\UserWriter.psm1"     -Force
    Import-Module "$srcRoot\SqlRepository\ComputerWriter.psm1" -Force
    Import-Module "$srcRoot\SqlRepository\GroupWriter.psm1"    -Force

    # Shared mocks
    $env:ADSYNC_SQL_SERVER = 'mock-server'
    $env:ADSYNC_DATABASE   = 'mock-db'

    $script:Config = Get-SyncConfig
    $script:Log    = New-SyncLogger -CorrelationId 'test'
}

AfterAll {
    Remove-Item Env:\ADSYNC_SQL_SERVER -ErrorAction SilentlyContinue
    Remove-Item Env:\ADSYNC_DATABASE   -ErrorAction SilentlyContinue
}

# ── User Writer ───────────────────────────────────────────────────────────────

Describe 'Push-ADSyncUsers' {

    Context 'Successful insert' {
        BeforeEach {
            Mock New-SqlContext      { return [PSCustomObject]@{ Command = $null; Dispose = {} } } `
                 -ModuleName UserWriter
            Mock Invoke-SqlStoredProc { return 1 } -ModuleName UserWriter
        }

        It 'returns Inserted=1 and Failed=0 for a single valid user' {
            $user = [PSCustomObject]@{
                CanonicalName='x'; sAMAccountName='jdoe'; userPrincipalName='jdoe@d.local'
                FirstName='J'; LastName='D'; DisplayName='J D'; EmailAddress='j@d.local'
                DistinguishedName='CN=jdoe'; StreetAddress=$null; HomePhone=$null
                MobilePhone=$null; OfficePhone=$null; Fax=$null; Company='Acme'
                Department='IT'; Title='Dev'; Description=''; AccountExpirationDate=$null
                Enabled=$true; LastLogonDate=$null; CreatedDate=(Get-Date)
                ModifiedDate=(Get-Date); PasswordNeverExpires=$false; PasswordExpired=$false
                PasswordLastSetDate=$null; ScriptPath=$null; LogonCount=1
                EmployeeId='001'; Manager=''
            }

            $result = Push-ADSyncUsers -Users @($user) -Config $script:Config -Logger $script:Log
            $result.Inserted | Should -Be 1
            $result.Failed   | Should -Be 0
        }
    }

    Context 'SQL failure' {
        BeforeEach {
            Mock New-SqlContext      { return [PSCustomObject]@{ Command = $null; Dispose = {} } } `
                 -ModuleName UserWriter
            Mock Invoke-SqlStoredProc { throw 'SQL error' } -ModuleName UserWriter
        }

        It 'increments Failed and does not throw' {
            $user = [PSCustomObject]@{ sAMAccountName = 'bad-user' }
            { $result = Push-ADSyncUsers -Users @($user) -Config $script:Config -Logger $script:Log
              $result.Failed | Should -Be 1 } | Should -Not -Throw
        }
    }
}

# ── Group Writer ──────────────────────────────────────────────────────────────

Describe 'Push-ADSyncGroups' {

    BeforeEach {
        Mock New-SqlContext      { return [PSCustomObject]@{ Command = $null; Dispose = {} } } `
             -ModuleName GroupWriter
        Mock Invoke-SqlStoredProc { return 1 } -ModuleName GroupWriter
    }

    It 'returns Inserted=2 for two groups' {
        $groups = @(
            [PSCustomObject]@{ CanonicalName='c1'; sAMAccountName='g1'; Name='g1'
                mail=''; DistinguishedName='dn1'; Description=''; CreatedDate=(Get-Date)
                ModifiedDate=(Get-Date); GroupCategory='Security'; GroupScope='Global' },
            [PSCustomObject]@{ CanonicalName='c2'; sAMAccountName='g2'; Name='g2'
                mail=''; DistinguishedName='dn2'; Description=''; CreatedDate=(Get-Date)
                ModifiedDate=(Get-Date); GroupCategory='Security'; GroupScope='Global' }
        )
        $result = Push-ADSyncGroups -Groups $groups -Config $script:Config -Logger $script:Log
        $result.Inserted | Should -Be 2
    }
}

Describe 'Push-ADSyncGroupMembers' {

    BeforeEach {
        Mock New-SqlContext      { return [PSCustomObject]@{ Command = $null; Dispose = {} } } `
             -ModuleName GroupWriter
        Mock Invoke-SqlStoredProc { return 1 } -ModuleName GroupWriter
    }

    It 'returns Inserted=1 for one member row' {
        $gm = [PSCustomObject]@{
            GroupSamAccountName = 'IT-Admins'
            Username            = 'jdoe'
            ObjectClass         = 'user'
        }
        $result = Push-ADSyncGroupMembers -GroupMembers @($gm) -Config $script:Config -Logger $script:Log
        $result.Inserted | Should -Be 1
    }
}
