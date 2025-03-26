# Entra-Toolbox.psm1
#
# This is the main module file for the Entra-Toolbox PowerShell module.
# It handles loading all public and private functions in the module structure.

#region Module Setup

# Get the module path
$modulePath = $PSScriptRoot

# Initialize a collection for public function names to export
$publicFunctions = @()

# Force TLS 1.2 for all web requests
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Unblock all script files to prevent security warnings
Get-ChildItem -Path $modulePath -Recurse -Include "*.ps1" | Unblock-File -ErrorAction SilentlyContinue

#region Import Private Functions

# Check if the Private directory exists
$privatePath = Join-Path -Path $modulePath -ChildPath 'Private'
if (Test-Path -Path $privatePath) {
    Write-Verbose "Importing private functions from: $privatePath"
    
    # First import helper functions
    $helperPath = Join-Path -Path $privatePath -ChildPath 'Helpers'
    if (Test-Path -Path $helperPath) {
        foreach ($file in (Get-ChildItem -Path $helperPath -Filter "*.ps1" -File -ErrorAction SilentlyContinue)) {
            try {
                . $file.FullName
                Write-Verbose "Imported private helper function: $($file.BaseName)"
            } 
            catch {
                Write-Error "Failed to import private helper function $($file.FullName): $_"
            }
        }
    }
    
    # Import role management functions
    $roleMgmtPath = Join-Path -Path $privatePath -ChildPath 'Role-Management'
    if (Test-Path -Path $roleMgmtPath) {
        foreach ($file in (Get-ChildItem -Path $roleMgmtPath -Filter "*.ps1" -File -ErrorAction SilentlyContinue)) {
            try {
                . $file.FullName
                Write-Verbose "Imported private role management function: $($file.BaseName)"
            } 
            catch {
                Write-Error "Failed to import private role management function $($file.FullName): $_"
            }
        }
    }
    
    # Import mobile device management functions
    $mdmPath = Join-Path -Path $privatePath -ChildPath 'Mobile-Device-Management'
    if (Test-Path -Path $mdmPath) {
        foreach ($file in (Get-ChildItem -Path $mdmPath -Filter "*.ps1" -File -ErrorAction SilentlyContinue)) {
            try {
                . $file.FullName
                Write-Verbose "Imported private mobile device management function: $($file.BaseName)"
            } 
            catch {
                Write-Error "Failed to import private mobile device management function $($file.FullName): $_"
            }
        }
    }
    
    # Import any remaining private functions at the root of Private
    foreach ($file in (Get-ChildItem -Path $privatePath -Filter "*.ps1" -File -ErrorAction SilentlyContinue)) {
        try {
            . $file.FullName
            Write-Verbose "Imported private function: $($file.BaseName)"
        } 
        catch {
            Write-Error "Failed to import private function $($file.FullName): $_"
        }
    }
}
else {
    Write-Verbose "Private functions directory not found. Continuing with public functions only."
}

#endregion Import Private Functions

#region Import Public Functions

# Check if the Public directory exists
$publicPath = Join-Path -Path $modulePath -ChildPath 'Public'
if (Test-Path -Path $publicPath) {
    Write-Verbose "Importing public functions from: $publicPath"
    
    foreach ($file in (Get-ChildItem -Path $publicPath -Filter "*.ps1" -File -ErrorAction SilentlyContinue)) {
        try {
            . $file.FullName
            $publicFunctions += $file.BaseName
            Write-Verbose "Imported public function: $($file.BaseName)"
        } 
        catch {
            Write-Error "Failed to import public function $($file.FullName): $_"
        }
    }
}
else {
    # Fallback to legacy flat structure if Public directory doesn't exist
    Write-Verbose "Public directory not found. Falling back to flat structure."
    
    foreach ($file in (Get-ChildItem -Path $modulePath -Filter "*.ps1" -File -ErrorAction SilentlyContinue)) {
        # Skip build, publish, and test scripts
        if ($file.Name -notmatch '^(build|publish|pester|test)') {
            try {
                . $file.FullName
                $publicFunctions += $file.BaseName
                Write-Verbose "Imported function from flat structure: $($file.BaseName)"
            } 
            catch {
                Write-Error "Failed to import function $($file.FullName): $_"
            }
        }
    }
}

#endregion Import Public Functions

# If no public functions were found, check the module manifest
if ($publicFunctions.Count -eq 0) {
    $manifestPath = Join-Path -Path $modulePath -ChildPath "$((Split-Path -Path $modulePath -Leaf)).psd1"
    if (Test-Path -Path $manifestPath) {
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        if ($null -ne $manifest -and $null -ne $manifest.FunctionsToExport) {
            $publicFunctions = $manifest.FunctionsToExport
            Write-Verbose "Imported function names from module manifest: $($publicFunctions -join ', ')"
        }
    }
}

#endregion Module Setup

# Export public functions
Export-ModuleMember -Function $publicFunctions

# Export-ModuleMember -Alias *