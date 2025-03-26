# Entra-Toolbox.psm1

# Get the module path
$modulePath = $PSScriptRoot

# Initialize a collection for public function names to export
$publicFunctions = @()

# Load all private functions first
Write-Verbose "Loading private functions..."

# Check if the Private directory exists
$privatePath = Join-Path -Path $modulePath -ChildPath 'Private'
if (Test-Path -Path $privatePath) {
    # Load helpers first
    $helperPath = Join-Path -Path $privatePath -ChildPath 'Helpers'
    if (Test-Path -Path $helperPath) {
        Get-ChildItem -Path $helperPath -Filter "*.ps1" | ForEach-Object {
            . $_.FullName
            Write-Verbose "Loaded private helper: $($_.BaseName)"
        }
    }
    
    # Load mobile device management functions
    $mdmPath = Join-Path -Path $privatePath -ChildPath 'Device Management'
    if (Test-Path -Path $mdmPath) {
        Get-ChildItem -Path $mdmPath -Filter "*.ps1" | ForEach-Object {
            . $_.FullName
            Write-Verbose "Loaded MDM function: $($_.BaseName)"
        }
    }
    
    # Load role management functions
    $rolePath = Join-Path -Path $privatePath -ChildPath 'Role Management'
    if (Test-Path -Path $rolePath) {
        Get-ChildItem -Path $rolePath -Filter "*.ps1" | ForEach-Object {
            . $_.FullName
            Write-Verbose "Loaded role function: $($_.BaseName)"
        }
    }
    
    # Load any remaining private functions
    Get-ChildItem -Path $privatePath -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
        Write-Verbose "Loaded private function: $($_.BaseName)"
    }
}

# Now load all public functions
Write-Verbose "Loading public functions..."
$publicPath = Join-Path -Path $modulePath -ChildPath 'Public'
if (Test-Path -Path $publicPath) {
    Get-ChildItem -Path $publicPath -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
        $publicFunctions += $_.BaseName
        Write-Verbose "Loaded public function: $($_.BaseName)"
    }
}

# Export only the public functions
Export-ModuleMember -Function $publicFunctions