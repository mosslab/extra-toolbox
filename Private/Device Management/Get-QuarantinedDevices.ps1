function Get-QuarantinedDevices {
<#
.SYNOPSIS
Retrieves quarantined mobile devices for a specific user.

.DESCRIPTION
This function retrieves a list of quarantined mobile devices for the specified user from Exchange Online.
It returns all devices that have a DeviceAccessState of "Quarantined".

.PARAMETER UserId
The identifier of the user for whom you want to retrieve quarantined devices.

.PARAMETER LogActivities
Enables logging of activities to Log Analytics.

.EXAMPLE
$quarantinedDevices = Get-QuarantinedDevices -UserId "user@domain.com"

.NOTES
This function is intended for internal use by Approve-QuarantinedMobileDevice.
#>
    [CmdletBinding()]
    [OutputType([PSObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId,
        
        [Parameter(Mandatory = $false)]
        [switch]$LogActivities
    )
    
    $functionName = $MyInvocation.MyCommand.Name
    Write-Verbose "$functionName - Retrieving quarantined devices for user $UserId"
    
    try {
        # $quarantinedDevices = Get-MobileDevice -Mailbox $UserId -Filter "DeviceAccessState -eq 'Quarantined'" -ErrorAction Stop
        $quarantinedDevices = Get-MobileDevice -Mailbox $UserId | Where-Object { $_.DeviceAccessState -eq 'Quarantined' }
        
        if ($null -eq $quarantinedDevices -or $quarantinedDevices.Count -eq 0) {
            Write-Host "No quarantined devices found for user $UserId." -ForegroundColor Yellow
            
            if ($LogActivities) {
                Write-ActivityLog -Task "Quarantined device check" -UserId $UserId -Result "No devices found"
            }
            
            return $null
        }

        Write-Host "Quarantined devices for user $UserId" -ForegroundColor Cyan
        $quarantinedDevices | Format-Table DeviceId, FriendlyName, DeviceModel, DeviceType, DeviceOS
        
        return $quarantinedDevices
    }
    catch {
        $errorMessage = "Error retrieving quarantined devices for user $UserId`: $($_.Exception.Message)"
        Write-Error $errorMessage
        
        if ($LogActivities) {
            Write-ActivityLog -Task "Quarantined device retrieval" -UserId $UserId -Result "Error" -ErrorMessage $errorMessage
        }
        
        throw $_
    }
}