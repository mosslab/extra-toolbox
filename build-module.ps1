[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ModuleVersion = "1.0.0",
    
    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = "output",
    
    [Parameter(Mandatory = $false)]
    [string]$ModuleName = "Entra-Toolbox"
)

function Initialize-BuildEnvironment {
    [CmdletBinding()]
    param()
    
    # Create output directory if it doesn't exist
    if (-not (Test-Path -Path $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }
    else {
        # Clean up output directory
        Get-ChildItem -Path $OutputDirectory -Recurse | Remove-Item -Force -Recurse
    }
    
    # Create module directory in output
    $moduleDir = Join-Path -Path $OutputDirectory -ChildPath $ModuleName
    New-Item -Path $moduleDir -ItemType Directory -Force | Out-Null
    
    return $moduleDir
}

function Copy-SourceFiles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )
    
    # Copy PS1 files
    Get-ChildItem -Path "*.ps1" -Exclude "build*.ps1", "publish*.ps1", "pester*.ps1" | 
        Copy-Item -Destination $DestinationPath -Force
    
    # Copy module file
    Copy-Item -Path "$ModuleName.psm1" -Destination $DestinationPath -Force
    
    # Copy README, LICENSE
    Copy-Item -Path "README.md" -Destination $DestinationPath -Force
    Copy-Item -Path "LICENSE" -Destination $DestinationPath -Force
}

function New-ModuleManifest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModulePath
    )
    
    # Get public function names
    $publicFunctions = Get-ChildItem -Path "*.ps1" -Exclude "build*.ps1", "publish*.ps1", "pester*.ps1", "Test-*.ps1" |
        ForEach-Object { $_.BaseName }
    
    # Create module manifest
    $manifestParams = @{
        Path = Join-Path -Path $ModulePath -ChildPath "$ModuleName.psd1"
        RootModule = "$ModuleName.psm1"
        ModuleVersion = $ModuleVersion
        GUID = '85b8fab7-d763-4a95-81f1-26ec0649a481'  # Generate a new GUID for your module
        Author = 'Duncan'
        CompanyName = 'Your Company'
        Copyright = '(c) 2025 Duncan. All rights reserved.'
        Description = 'PowerShell toolbox for Microsoft Entra ID administration'
        PowerShellVersion = '5.1'
        FunctionsToExport = $publicFunctions
        CmdletsToExport = @()
        VariablesToExport = @()
        AliasesToExport = @()
        RequiredModules = @(
            @{ModuleName = 'Microsoft.Graph'; ModuleVersion = '2.10.0'},
            @{ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0'}
        )
        Tags = @('Entra', 'AzureAD', 'Microsoft365', 'Administration', 'Security')
        ProjectUri = 'https://github.com/yourusername/entra-toolbox'
        LicenseUri = 'https://github.com/yourusername/entra-toolbox/blob/main/LICENSE'
    }
    
    New-ModuleManifest @manifestParams
}

function Update-ModuleHelp {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModulePath
    )
    
    # Create help directory
    $helpDir = Join-Path -Path $ModulePath -ChildPath "en-US"
    New-Item -Path $helpDir -ItemType Directory -Force | Out-Null
    
    # Generate module help (if needed)
    # New-MarkdownHelp -Module $ModuleName -OutputFolder $helpDir -Force
}

# Main script execution
try {
    Write-Host "Starting build process for $ModuleName module version $ModuleVersion" -ForegroundColor Green
    
    # Initialize build environment
    $moduleDir = Initialize-BuildEnvironment
    Write-Host "Initialized build environment at $moduleDir" -ForegroundColor Green
    
    # Copy source files
    Copy-SourceFiles -DestinationPath $moduleDir
    Write-Host "Copied source files to output directory" -ForegroundColor Green
    
    # Create module manifest
    New-ModuleManifest -ModulePath $moduleDir
    Write-Host "Created module manifest" -ForegroundColor Green
    
    # Update module help
    # Update-ModuleHelp -ModulePath $moduleDir
    # Write-Host "Generated module help" -ForegroundColor Green
    
    Write-Host "Build completed successfully" -ForegroundColor Green
}
catch {
    Write-Error "Build failed: $_"
    throw
}
