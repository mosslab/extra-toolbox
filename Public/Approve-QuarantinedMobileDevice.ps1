function Approve-QuarantinedMobileDevice {
<#
.SYNOPSIS
Connects to Exchange Online and approves a quarantined device for a given user.

.DESCRIPTION
The function checks and connects to Exchange Online using the "Test-ExchangeOnlineConnection" function.
After connecting, it retrieves a list of quarantined devices for the provided user and allows for approval.
The function supports both interactive and non-interactive modes, making it suitable for automation.

.PARAMETER UserId
The identifier of the user for whom you want to approve a quarantined device.

.PARAMETER DeviceId
The specific device ID to approve. If not specified, the function will operate in interactive mode.

.PARAMETER Force
Bypasses confirmation prompts when approving devices.

.PARAMETER NonInteractive
Runs the function in non-interactive mode, suitable for automation. Requires DeviceId to be specified.

.PARAMETER LogActivities
Enables logging of device approval activities to Log Analytics if the Write-ActivityToLogAnalytics function is available.

.EXAMPLE
Approve-QuarantinedMobileDevice -UserId "john.doe@contoso.com"
Shows a list of quarantined devices for the user and prompts for selection and confirmation.

.EXAMPLE
Approve-QuarantinedMobileDevice -UserId "john.doe@contoso.com" -DeviceId "AppleABCD1234" -Force
Approves the specified device for the user without confirmation.

.EXAMPLE
Approve-QuarantinedMobileDevice -UserId "john.doe@contoso.com" -NonInteractive -DeviceId "AppleABCD1234"
Approves the specified device in non-interactive mode, suitable for automation.

.NOTES
Ensure you have appropriate permissions to manage devices in Exchange Online.
This function requires the ExchangeOnlineManagement module to be installed.
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$UserId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$DeviceId,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$NonInteractive,

        [Parameter(Mandatory = $false)]
        [switch]$LogActivities
    )

    begin {
        # Initialize logging
        $functionName = $MyInvocation.MyCommand.Name
        Write-Verbose "$functionName - Starting quarantined device approval process"
        
        # Validate parameter combination
        if ($NonInteractive -and [string]::IsNullOrEmpty($DeviceId)) {
            $errorMessage = "DeviceId parameter is required when using NonInteractive mode"
            Write-Error $errorMessage
            throw $errorMessage
        }
        
        # Log activity if configured
        if ($LogActivities) {
            $logParams = @{
                Task = "Initializing quarantined device approval"
                UserId = $UserId
                DeviceId = if ([string]::IsNullOrEmpty($DeviceId)) { "Not specified" } else { $DeviceId }
                Mode = if ($NonInteractive) { "Non-Interactive" } else { "Interactive" }
            }
            
            Write-ActivityLog @logParams
        }
    }

    process {
        try {
            # Ensure connection to Exchange Online
            Write-Verbose "$functionName - Validating Exchange Online connection"
            $connectionResult = Test-ExchangeOnlineConnection
            
            if (-not $connectionResult) {
                throw "Failed to establish connection to Exchange Online"
            }

            # Get quarantined devices
            $quarantinedDevices = Get-QuarantinedDevices -UserId $UserId
            if ($null -eq $quarantinedDevices -or $quarantinedDevices.Count -eq 0) {
                return [PSCustomObject]@{
                    UserId = $UserId
                    Status = "NoDevicesFound"
                    Message = "No quarantined devices found for user"
                    DeviceId = $null
                    Success = $false
                }
            }

            # Select device based on mode (interactive or specific device)
            if ([string]::IsNullOrEmpty($DeviceId)) {
                # Using ShouldProcess for the initial device selection
                $selectionTarget = "User $($UserId)"
                if ($PSCmdlet.ShouldProcess($selectionTarget, "Select a quarantined device to approve")) {
                    $selectedDevice = Select-QuarantinedDevice -QuarantinedDevices $quarantinedDevices
                    if ($null -eq $selectedDevice) {
                        return [PSCustomObject]@{
                            UserId = $UserId
                            Status = "Cancelled"
                            Message = "No device selected by user"
                            DeviceId = $null
                            Success = $false
                        }
                    }
                } else {
                    return [PSCustomObject]@{
                        UserId = $UserId
                        Status = "Cancelled"
                        Message = "Operation cancelled by user"
                        DeviceId = $null
                        Success = $false
                    }
                }
            } 
            else {
                $selectedDevice = Find-DeviceById -QuarantinedDevices $quarantinedDevices -DeviceId $DeviceId
                if ($null -eq $selectedDevice) {
                    $errorMessage = "Device with ID '$DeviceId' not found in quarantined devices for user $UserId"
                    Write-Error $errorMessage
                    
                    if ($LogActivities) {
                        Write-ActivityLog -Task "Device selection" -UserId $UserId -DeviceId $DeviceId -Result "Device not found" -ErrorMessage $errorMessage
                    }
                    
                    return [PSCustomObject]@{
                        UserId = $UserId
                        Status = "Error"
                        Message = $errorMessage
                        DeviceId = $DeviceId
                        Success = $false
                    }
                }
            }

            # Construct the message for ShouldProcess/confirmation
            $confirmMessage = "Do you want to approve the device $($selectedDevice.DeviceId) ($($selectedDevice.FriendlyName)) for user $UserId?"
            
            # Now use ShouldProcess for the actual approval action
            if ($Force -or $NonInteractive -or $PSCmdlet.ShouldProcess($confirmMessage, "Approve Device", "Device Approval Confirmation")) {
                # Prepare for approval
                Write-Verbose "$functionName - Approving device $($selectedDevice.DeviceId) for user $UserId"
                
                try {
                    # Approve the device
                    Set-CASMailbox $UserId -ActiveSyncAllowedDeviceIDs @{add=$selectedDevice.DeviceId} -ErrorAction Stop
                    $successMessage = "DeviceID $($selectedDevice.DeviceId) has been approved for user $UserId."
                    Write-Host $successMessage -ForegroundColor Green
                    
                    if ($LogActivities) {
                        Write-ActivityLog -Task "Device approval" -UserId $UserId -DeviceId $selectedDevice.DeviceId -DeviceName $selectedDevice.FriendlyName -Result "Approved" -Success $true
                    }
                    
                    return [PSCustomObject]@{
                        UserId = $UserId
                        Status = "Approved"
                        Message = $successMessage
                        DeviceId = $selectedDevice.DeviceId
                        DeviceName = $selectedDevice.FriendlyName
                        DeviceModel = $selectedDevice.DeviceModel
                        DeviceType = $selectedDevice.DeviceType
                        Success = $true
                    }
                }
                catch {
                    $errorMessage = "Failed to approve device $($selectedDevice.DeviceId) for user $UserId $($_.Exception.Message)"
                    Write-Error $errorMessage
                    
                    if ($LogActivities) {
                        Write-ActivityLog -Task "Device approval error" -UserId $UserId -DeviceId $selectedDevice.DeviceId -DeviceName $selectedDevice.FriendlyName -Result "Error" -ErrorMessage $_.Exception.Message
                    }
                    
                    return [PSCustomObject]@{
                        UserId = $UserId
                        Status = "Error"
                        Message = $errorMessage
                        DeviceId = $selectedDevice.DeviceId
                        DeviceName = $selectedDevice.FriendlyName
                        Success = $false
                    }
                }
            }
            else {
                $cancelMessage = "Approval cancelled for DeviceID $($selectedDevice.DeviceId)."
                Write-Host $cancelMessage -ForegroundColor Yellow
                
                if ($LogActivities) {
                    Write-ActivityLog -Task "Device approval" -UserId $UserId -DeviceId $selectedDevice.DeviceId -DeviceName $selectedDevice.FriendlyName -Result "Cancelled"
                }
                
                return [PSCustomObject]@{
                    UserId = $UserId
                    Status = "Cancelled"
                    Message = $cancelMessage
                    DeviceId = $selectedDevice.DeviceId
                    DeviceName = $selectedDevice.FriendlyName
                    Success = $false
                }
            }
        }
        catch {
            $errorMessage = "An error occurred while processing device approval: $($_.Exception.Message)"
            Write-Error $errorMessage
            Write-Error $_.ScriptStackTrace
            
            if ($LogActivities) {
                Write-ActivityLog -Task "Device approval critical error" -UserId $UserId -ErrorMessage $_.Exception.Message -StackTrace $_.ScriptStackTrace
            }
            
            return [PSCustomObject]@{
                UserId = $UserId
                Status = "CriticalError"
                Message = $errorMessage
                DeviceId = if (-not [string]::IsNullOrEmpty($DeviceId)) { $DeviceId } else { $null }
                Success = $false
            }
        }
    }
    
    end {
        Write-Verbose "$functionName - Device approval operation completed"
    }
}