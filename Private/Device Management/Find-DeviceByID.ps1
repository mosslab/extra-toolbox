function Find-DeviceById {
<#
.SYNOPSIS
Finds a specific device by ID in a collection of quarantined devices.

.DESCRIPTION
This function searches a collection of quarantined devices for a device with the specified ID.
It returns the device object if found, or null if not found.

.PARAMETER QuarantinedDevices
An array of quarantined devices to search.

.PARAMETER DeviceId
The device ID to search for.

.EXAMPLE
$device = Find-DeviceById -QuarantinedDevices $devices -DeviceId "AppleABCD1234"

.NOTES
This function is intended for internal use by Approve-QuarantinedMobileDevice.
#>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject[]]$QuarantinedDevices,
        
        [Parameter(Mandatory = $true)]
        [string]$DeviceId
    )
    
    $functionName = $MyInvocation.MyCommand.Name
    Write-Verbose "$functionName - Searching for device with ID: $DeviceId"
    
    try {
        $device = $QuarantinedDevices | Where-Object { $_.DeviceId -eq $DeviceId }
        
        if ($null -eq $device) {
            Write-Verbose "$functionName - Device with ID '$DeviceId' not found in quarantined devices"
            return $null
        }
        
        Write-Verbose "$functionName - Found device: $($device.FriendlyName) ($($device.DeviceModel))"
        return $device
    }
    catch {
        Write-Error "Error searching for device with ID '$DeviceId': $($_.Exception.Message)"
        throw $_
    }
}