function Approve-SelectedDevice {
<#
.SYNOPSIS
Approves a selected quarantined device for a user.

.DESCRIPTION
This function approves a selected quarantined device for a user by updating the ActiveSyncAllowedDeviceIDs
property of the user's CAS mailbox. It includes confirmation prompts and supports both interactive
and non-interactive modes.

.PARAMETER UserId
The identifier of the user for whom you want to approve the device.

.PARAMETER SelectedDevice
The device object to approve.

.PARAMETER Force
Bypasses confirmation prompts when approving devices.

.PARAMETER NonInteractive
Runs the function in non-interactive mode, suitable for automation.

.PARAMETER LogActivities
Enables logging of activities to Log Analytics.

.EXAMPLE
$result = Approve-SelectedDevice -UserId "john.doe@contoso.com" -SelectedDevice $device -Force

.NOTES
This function is intended for internal use by Approve-QuarantinedMobileDevice.
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId,
        
        [Parameter(Mandatory = $true)]
        [PSObject]$SelectedDevice,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [switch]$NonInteractive,
        
        [Parameter(Mandatory = $false)]
        [switch]$LogActivities
    )
    
    $functionName = $MyInvocation.MyCommand.Name
    Write-Verbose "$functionName - Preparing to approve device $($SelectedDevice.DeviceId) for user $UserId"
    
    # Confirm the approval unless Force switch is used
    $confirmMessage = "Do you want to approve the device $($SelectedDevice.DeviceId) ($($SelectedDevice.FriendlyName)) for user $UserId?"
    
    if ($Force -or $NonInteractive -or $PSCmdlet.ShouldProcess($confirmMessage, "Approve Device", "Device Approval Confirmation")) {
        Write-Verbose "$functionName - Approving device $($SelectedDevice.DeviceId) for user $UserId"
        
        try {
            # Approve the device
            Set-CASMailbox $UserId -ActiveSyncAllowedDeviceIDs @{add=$SelectedDevice.DeviceId} -ErrorAction Stop
            $successMessage = "DeviceID $($SelectedDevice.DeviceId) has been approved for user $UserId."
            Write-Host $successMessage -ForegroundColor Green
            
            if ($LogActivities) {
                Write-ActivityLog -Task "Device approval" -UserId $UserId -DeviceId $SelectedDevice.DeviceId -DeviceName $SelectedDevice.FriendlyName -Result "Approved" -Success $true
            }
            
            return [PSCustomObject]@{
                UserId = $UserId
                Status = "Approved"
                Message = $successMessage
                DeviceId = $SelectedDevice.DeviceId
                DeviceName = $SelectedDevice.FriendlyName
                DeviceModel = $SelectedDevice.DeviceModel
                DeviceType = $SelectedDevice.DeviceType
                Success = $true
            }
        }
        catch {
            $errorMessage = "Failed to approve device $($SelectedDevice.DeviceId) for user $UserId: $($_.Exception.Message)"
            Write-Error $errorMessage
            
            if ($LogActivities) {
                Write-ActivityLog -Task "Device approval error" -UserId $UserId -DeviceId $SelectedDevice.DeviceId -DeviceName $SelectedDevice.FriendlyName -Result "Error" -ErrorMessage $_.Exception.Message
            }
            
            return [PSCustomObject]@{
                UserId = $UserId
                Status = "Error"
                Message = $errorMessage
                DeviceId = $SelectedDevice.DeviceId
                DeviceName = $SelectedDevice.FriendlyName
                Success = $false
            }
        }
    }
    else {
        $cancelMessage = "Approval cancelled for DeviceID $($SelectedDevice.DeviceId)."
        Write-Host $cancelMessage -ForegroundColor Yellow
        
        if ($LogActivities) {
            Write-ActivityLog -Task "Device approval" -UserId $UserId -DeviceId $SelectedDevice.DeviceId -DeviceName $SelectedDevice.FriendlyName -Result "Cancelled"
        }
        
        return [PSCustomObject]@{
            UserId = $UserId
            Status = "Cancelled"
            Message = $cancelMessage
            DeviceId = $SelectedDevice.DeviceId
            DeviceName = $SelectedDevice.FriendlyName
            Success = $false
        }
    }
}