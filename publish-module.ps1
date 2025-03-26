[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = "output",
    
    [Parameter(Mandatory = $false)]
    [string]$ModuleName = "Entra-Toolbox",
    
    [Parameter(Mandatory = $false)]
    [string]$RepositoryName = "PSGallery",
    
    [Parameter(Mandatory = $false)]
    [switch]$Local,
    
    [Parameter(Mandatory = $false)]
    [string]$LocalRepositoryPath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
)

function Publish-ToRepository {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModulePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Repository
    )
    
    try {
        # Get API key from environment or credential store
        $apiKey = $env:PS_GALLERY_API_KEY
        
        if ([string]::IsNullOrEmpty($apiKey)) {
            if (Get-Command -Name Get-Secret -ErrorAction SilentlyContinue) {
                try {
                    $secret = Get-Secret -Name "PSGalleryApiKey" -ErrorAction Stop
                    $apiKey = if ($secret -is [PSCredential]) {
                        $secret.GetNetworkCredential().Password
                    }
                    else {
                        $secret
                    }
                }
                catch {
                    Write-Warning "Could not retrieve API key from Secret Management: $_"
                }
            }
        }
        
        if ([string]::IsNullOrEmpty($apiKey)) {
            throw "No API key found. Set PS_GALLERY_API_KEY environment variable or store it using SecretManagement."
        }
        
        # Publish the module
        $publishParams = @{
            Path = $ModulePath
            Repository = $Repository
            NuGetApiKey = $apiKey
            ErrorAction = 'Stop'
        }
        
        Publish-Module @publishParams
        Write-Host "Successfully published $ModuleName to $Repository repository" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to publish module to repository: $_"
        throw
    }
}

function Publish-ToLocal {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModulePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )
    
    try {
        # Create destination directory if it doesn't exist
        $moduleDestination = Join-Path -Path $Destination -ChildPath $ModuleName
        
        if (Test-Path -Path $moduleDestination) {
            Remove-Item -Path $moduleDestination -Recurse -Force
        }
        
        # Copy module files
        Copy-Item -Path $ModulePath -Destination $Destination -Recurse -Force
        
        Write-Host "Successfully copied $ModuleName to local modules directory: $moduleDestination" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to copy module to local directory: $_"
        throw
    }
}

# Main script execution
try {
    Write-Host "Starting publish process for $ModuleName module" -ForegroundColor Green
    
    $modulePath = Join-Path -Path $OutputDirectory -ChildPath $ModuleName
    
    if (-not (Test-Path -Path $modulePath)) {
        throw "Module not found at path: $modulePath. Please run build-module.ps1 first."
    }
    
    # Get module version
    $moduleManifestPath = Join-Path -Path $modulePath -ChildPath "$ModuleName.psd1"
    $moduleInfo = Test-ModuleManifest -Path $moduleManifestPath
    $moduleVersion = $moduleInfo.Version
    
    Write-Host "Publishing $ModuleName module version $moduleVersion" -ForegroundColor Green
    
    if ($Local) {
        # Publish to local repository
        Publish-ToLocal -ModulePath $modulePath -Destination $LocalRepositoryPath
    }
    else {
        # Publish to PowerShell Gallery or custom repository
        Publish-ToRepository -ModulePath $modulePath -Repository $RepositoryName
    }
    
    Write-Host "Publish completed successfully" -ForegroundColor Green
}
catch {
    Write-Error "Publish failed: $_"
    throw
}
