<#
.SYNOPSIS
    Pester v5 tests — ActiveDirectory reader layer
    All AD cmdlets are mocked so tests run without a real domain controller.
    Run with: Invoke-Pester .\tests\ActiveDirectory.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $srcRoot = Join-Path $PSScriptRoot '..\src'
    Import-Module "$srcRoot\ActiveDirectory\UserReader.psm1"    -Force
    Import-Module "$srcRoot\ActiveDirectory\ComputerReader.psm1" -Force
    Import-Module "$srcRoot\ActiveDirectory\GroupReader.psm1"   -Force
}

# ── User Reader ───────────────────────────────────────────────────────────────

Describe 'Get-fnADSyncUsers' {

    BeforeAll {
        # Minimal AD user stub
        $stubUser = [PSCustomObject]@{
            CanonicalName       = 'domain.local/Users/jdoe'
            sAMAccountName      = 'jdoe'
            userPrincipalName   = 'jdoe@domain.local'
            GivenName           = 'John'
            Surname             = 'Doe'
            DisplayName         = 'John Doe'
            EmailAddress        = 'jdoe@domain.local'
            DistinguishedName   = 'CN=jdoe,OU=Users,DC=domain,DC=local'
            StreetAddress       = $null
            HomePhone           = $null
            MobilePhone         = $null
            OfficePhone         = $null
            Fax                 = $null
            Company             = 'Acme'
            Department          = 'IT'
            Title               = 'Engineer'
            Description         = "Test user"
            AccountExpires      = 0
            Enabled             = $true
            LastLogonDate       = (Get-Date)
            whenCreated         = (Get-Date).AddYears(-1)
            whenChanged         = (Get-Date)
            PasswordNeverExpires= $false
            PasswordExpired     = $false
            PasswordLastSet     = (Get-Date).AddDays(-30)
            ScriptPath          = $null
            LogonCount          = 42
            EmployeeId          = 'EMP001'
            Manager             = $null
        }
    }

    Context 'Happy path — single enabled user' {
        BeforeEach {
            Mock Get-ADUser { return $stubUser } -ModuleName UserReader
        }

        It 'returns one record' {
            $result = Get-fnADSyncUsers -Enabled $true
            @($result).Count | Should -Be 1
        }

        It 'maps GivenName to FirstName' {
            $result = Get-fnADSyncUsers -Enabled $true
            $result.FirstName | Should -Be 'John'
        }

        It 'maps Surname to LastName' {
            $result = Get-fnADSyncUsers -Enabled $true
            $result.LastName | Should -Be 'Doe'
        }

        It 'returns null AccountExpirationDate for never-expiring accounts (0)' {
            $result = Get-fnADSyncUsers -Enabled $true
            $result.AccountExpirationDate | Should -BeNullOrEmpty
        }
    }

    Context 'Filter building' {
        It 'passes Enabled filter to Get-ADUser' {
            Mock Get-ADUser { return @() } -ModuleName UserReader
            Get-fnADSyncUsers -Enabled $false | Out-Null
            Should -Invoke Get-ADUser -ModuleName UserReader -Times 1 `
                -ParameterFilter { $Filter -like "*Enabled*false*" }
        }

        It 'uses identity filter when Identity is specified' {
            Mock Get-ADUser { return @() } -ModuleName UserReader
            Get-fnADSyncUsers -Identity 'jdoe' | Out-Null
            Should -Invoke Get-ADUser -ModuleName UserReader -Times 1 `
                -ParameterFilter { $Filter -like "*jdoe*" }
        }
    }

    Context 'Error handling' {
        It 'throws a descriptive exception when Get-ADUser fails' {
            Mock Get-ADUser { throw 'AD unavailable' } -ModuleName UserReader
            { Get-fnADSyncUsers } | Should -Throw '*Get-fnADSyncUsers failed*'
        }
    }
}

# ── Computer Reader ───────────────────────────────────────────────────────────

Describe 'Get-fnADSyncComputers' {

    BeforeAll {
        $stubComp = [PSCustomObject]@{
            Name                   = 'PC001'
            DistinguishedName      = 'CN=PC001,OU=Computers,DC=domain,DC=local'
            CanonicalName          = 'domain.local/Computers/PC001'
            sAMAccountName         = 'PC001$'
            IPv4Address            = '10.0.0.1'
            OperatingSystem        = 'Windows 11 Pro'
            OperatingSystemVersion = '10.0 (22621)'
            Description            = 'Dev workstation'
            Created                = (Get-Date).AddYears(-1)
            Modified               = (Get-Date)
            LastLogonDate          = (Get-Date)
            LogonCount             = 1000
            UserAccountControl     = 4096
            Enabled                = $true
        }
    }

    Context 'Happy path' {
        BeforeEach {
            Mock Get-ADComputer   { return $stubComp } -ModuleName ComputerReader
            Mock Get-LapsADPassword { return $null }   -ModuleName ComputerReader
            Mock Get-ADObject     { return $null }     -ModuleName ComputerReader
        }

        It 'maps Name to ComputerName' {
            $result = Get-fnADSyncComputers -Enabled $true
            $result.ComputerName | Should -Be 'PC001'
        }

        It 'maps Enabled=true to 1' {
            $result = Get-fnADSyncComputers -Enabled $true
            $result.Enabled | Should -Be 1
        }

        It 'returns HasLaps=0 when Get-LapsADPassword returns null' {
            $result = Get-fnADSyncComputers -Enabled $true
            $result.HasLaps | Should -Be 0
        }
    }

    Context 'Server filter' {
        It 'includes server OS filter when ServersOnly=$true' {
            Mock Get-ADComputer { return @() } -ModuleName ComputerReader
            Get-fnADSyncComputers -ServersOnly $true | Out-Null
            Should -Invoke Get-ADComputer -ModuleName ComputerReader -Times 1 `
                -ParameterFilter { $Filter -like "*server*" }
        }
    }
}

# ── Group Reader ──────────────────────────────────────────────────────────────

Describe 'Get-fnADSyncGroups' {

    BeforeAll {
        $stubGroup = [PSCustomObject]@{
            CanonicalName     = 'domain.local/Groups/IT-Admins'
            sAMAccountName    = 'IT-Admins'
            Name              = 'IT-Admins'
            mail              = 'it-admins@domain.local'
            DistinguishedName = 'CN=IT-Admins,OU=Groups,DC=domain,DC=local'
            Description       = 'IT Administrators'
            whenCreated       = (Get-Date).AddYears(-2)
            whenChanged       = (Get-Date)
            GroupCategory     = 'Security'
            GroupScope        = 'Global'
        }
    }

    Context 'Happy path' {
        BeforeEach {
            Mock Get-ADGroup { return $stubGroup } -ModuleName GroupReader
        }

        It 'maps whenCreated to CreatedDate' {
            $result = Get-fnADSyncGroups -DeltaChangeHours 0
            $result.CreatedDate | Should -Not -BeNullOrEmpty
        }

        It 'uses wildcard filter when DeltaChangeHours is 0' {
            Get-fnADSyncGroups -DeltaChangeHours 0 | Out-Null
            Should -Invoke Get-ADGroup -ModuleName GroupReader -Times 1 `
                -ParameterFilter { $Filter -eq '*' }
        }
    }
}

Describe 'Get-ADSyncGroupMembers' {

    BeforeAll {
        $stubGroup = [PSCustomObject]@{
            sAMAccountName    = 'IT-Admins'
            DistinguishedName = 'CN=IT-Admins,OU=Groups,DC=domain,DC=local'
        }
        $stubMember = [PSCustomObject]@{
            sAMAccountName = 'jdoe'
            objectClass    = 'user'
        }
    }

    Context 'Happy path' {
        BeforeEach {
            Mock Get-ADGroup       { return $stubGroup  } -ModuleName GroupReader
            Mock Get-ADGroupMember { return $stubMember } -ModuleName GroupReader
        }

        It 'returns a membership row with correct GroupSamAccountName' {
            $result = Get-ADSyncGroupMembers -DeltaChangeHours 0
            $result.GroupSamAccountName | Should -Be 'IT-Admins'
        }

        It 'returns a membership row with correct Username' {
            $result = Get-ADSyncGroupMembers -DeltaChangeHours 0
            $result.Username | Should -Be 'jdoe'
        }
    }
}
