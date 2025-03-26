function Select-QuarantinedDevice {
<#
.SYNOPSIS
Prompts the user to select a quarantined device from a list.

.DESCRIPTION
This function displays an interactive interface for selecting a quarantined device from a list.
It supports both GridView and console-based selection methods, with fallback mechanisms if GridView is not available.

.PARAMETER QuarantinedDevices
An array of quarantined devices to select from.

.PARAMETER LogActivities
Enables logging of activities to Log Analytics.

.EXAMPLE
$selectedDevice = Select-QuarantinedDevice -QuarantinedDevices $devices

.NOTES
This function is intended for internal use by Approve-QuarantinedMobileDevice.
#>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject[]]$QuarantinedDevices,
        
        [Parameter(Mandatory = $false)]
        [switch]$LogActivities
    )
    
    $functionName = $MyInvocation.MyCommand.Name
    Write-Verbose "$functionName - Prompting user to select a device"
    
    try {
        # Let the user select a device using Out-GridView (preferred method)
        try {
            $selectedDevice = $QuarantinedDevices | Out-GridView -Title "Select a Device to Approve" -PassThru -ErrorAction Stop
            
            # Check if a device was selected
            if (-not $selectedDevice) {
                Write-Host "No device selected. Exiting..." -ForegroundColor Yellow
                
                if ($LogActivities) {
                    Write-ActivityLog -Task "Device selection" -Result "No device selected"
                }
                
                return $null
            }
            
            return $selectedDevice
        }
        catch {
            # GridView not available, fallback to console selection
            if ($_.Exception.Message -like "*Out-GridView*") {
                Write-Warning "Out-GridView is not available in this environment. Falling back to console selection."
                return Select-DeviceFromConsole -QuarantinedDevices $QuarantinedDevices -LogActivities:$LogActivities
            }
            else {
                throw $_
            }
        }
    }
    catch {
        $errorMessage = "Error during device selection: $($_.Exception.Message)"
        Write-Error $errorMessage
        
        if ($LogActivities) {
            Write-ActivityLog -Task "Device selection" -Result "Error" -ErrorMessage $errorMessage
        }
        
        throw $_
    }
}

function Select-DeviceFromConsole {
<#
.SYNOPSIS
Fallback function for console-based device selection.

.DESCRIPTION
This function provides a console-based interface for selecting a device when GridView is not available.

.PARAMETER QuarantinedDevices
An array of quarantined devices to select from.

.PARAMETER LogActivities
Enables logging of activities to Log Analytics.

.EXAMPLE
$selectedDevice = Select-DeviceFromConsole -QuarantinedDevices $devices

.NOTES
This function is intended for internal use by Select-QuarantinedDevice.
#>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject[]]$QuarantinedDevices,
        
        [Parameter(Mandatory = $false)]
        [switch]$LogActivities
    )
    
    Write-Host "Enter the number of the device you want to approve:" -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $QuarantinedDevices.Count; $i++) {
        Write-Host "[$i] $($QuarantinedDevices[$i].DeviceId) - $($QuarantinedDevices[$i].FriendlyName) - $($QuarantinedDevices[$i].DeviceModel)"
    }
    
    $selection = Read-Host "Enter device number (or 'q' to quit)"
    
    if ($selection -eq 'q' -or [string]::IsNullOrEmpty($selection)) {
        Write-Host "Operation cancelled. Exiting..." -ForegroundColor Yellow
        
        if ($LogActivities) {
            Write-ActivityLog -Task "Device selection" -Result "Selection cancelled"
        }
        
        return $null
    }
    
    try {
        $selectedIndex = [int]::Parse($selection)
        if ($selectedIndex -ge 0 -and $selectedIndex -lt $QuarantinedDevices.Count) {
            return $QuarantinedDevices[$selectedIndex]
        }
        else {
            Write-Error "Invalid selection. Please enter a number between 0 and $($QuarantinedDevices.Count - 1)"
            return $null
        }
    }
    catch {
        Write-Error "Invalid input. Please enter a numeric value."
        return $null
    }
}