#Requires -Version 5.1
@{
    ModuleVersion     = '2.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'Enterprise IT'
    CompanyName       = 'Your Company'
    Description       = 'Active Directory to SQL Server synchronisation module'
    PowerShellVersion = '5.1'
    RequiredModules   = @('ActiveDirectory')

    FunctionsToExport = @(
        'Invoke-ADSync',
        'Get-fnADSyncUsers',
        'Get-fnADSyncComputers',
        'Get-fnADSyncGroups',
        'Get-ADSyncGroupMembers'
    )

    PrivateData = @{
        PSData = @{
            Tags       = @('ActiveDirectory', 'SQL', 'Sync', 'Enterprise')
            ProjectUri = 'https://github.com/your-org/ad-sync'
        }
    }
}
