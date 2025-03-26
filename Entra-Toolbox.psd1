@{
    # Script module or binary module file associated with this manifest
    RootModule = 'Entra-Toolbox.psm1'
    ModuleVersion = '1.1.0'
    CompatiblePSEditions = @('Desktop', 'Core')
    
    # ID used to uniquely identify this module
    GUID = '85b8fab7-d763-4a95-81f1-26ec0649a481'
    Author = 'Duncan Moss'
    CompanyName = 'EndpointWorks'
    Copyright = '(c) 2025 EndpointWorks. All rights reserved.'
    Description = 'A comprehensive set of tools for Microsoft Entra ID administration, designed for IT Support teams.'
    PowerShellVersion = '5.1'

    RequiredModules = @(
        @{ModuleName = 'Microsoft.Graph'; ModuleVersion = '2.10.0'},
        @{ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0'}
    )
    
    # Functions to export from this module, for best performance, do not use wildcards
    FunctionsToExport = @(
        # Primary Functions
        'Test-MgGraphConnection', 
        'Test-ExchangeOnlineConnection', 
        'Approve-QuarantinedMobileDevice',
        'New-TemporaryAccessPassForUser',
        'Get-EntraPrivilegedRoleMembers',
        
        # Log Analytics Functions
        'Write-ActivityToLogAnalytics',
        'Test-WriteToLogAnalytics'
    )
    
    # Cmdlets to export from this module, for best performance, do not use wildcards
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    DscResourcesToExport = @()
    
    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            Tags = @('Entra', 'AzureAD', 'Microsoft365', 'Administration', 'Security', 'MobileDevice', 'PIM', 'TemporaryAccess')
            LicenseUri = 'https://github.com/mosslab/entra-toolbox/blob/main/LICENSE'
            ProjectUri = 'https://github.com/mosslab/entra-toolbox'
            ReleaseNotes = @'
                # Version 1.1.0
                - Restructured module using modular design patterns
                - Enhanced security features including secure credential handling
                - Improved error handling and logging
                - Added comprehensive Pester tests
                - Fixed ShouldProcess implementation
                - Added network testing for Log Analytics connectivity
                - Implemented more robust Azure Log Analytics integration
                - Improved mobile device management capabilities

                # Version 1.0.0
                - Initial release with core functionality
'@
            
            # Prerelease string of this module
            # Prerelease = ''
            
            # Flag to indicate whether the module requires explicit user acceptance for installation
            # RequireLicenseAcceptance = $false
            
            # External dependent modules of this module
            # ExternalModuleDependencies = @()
        }
    }
    
    # HelpInfo URI of this module
    # HelpInfoURI = ''
    
    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''
}