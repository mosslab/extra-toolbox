function Write-ActivityLog {
<#
.SYNOPSIS
Helper function to log activities to Log Analytics.

.DESCRIPTION
This function serves as a wrapper around Write-ActivityToLogAnalytics to simplify the logging
of activities with standardized parameters and error handling.

.PARAMETER Task
Specifies the task or activity being performed.

.PARAMETER UserId
Specifies the user ID related to the activity.

.PARAMETER DeviceId
Specifies the device ID related to the activity, if applicable.

.PARAMETER DeviceName
Specifies the device name related to the activity, if applicable.

.PARAMETER Result
Specifies the result of the activity (Success, Error, Cancelled, etc.).

.PARAMETER Success
Indicates whether the activity was successful.

.PARAMETER ErrorMessage
Specifies the error message if the activity failed.

.PARAMETER StackTrace
Specifies the stack trace if the activity failed with an exception.

.EXAMPLE
Write-ActivityLog -Task "Device approval" -UserId "john.doe@contoso.com" -DeviceId "AppleABCD1234" -Result "Approved" -Success $true

.NOTES
This function is intended for internal use by Approve-QuarantinedMobileDevice and its supporting functions.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Task,
        
        [Parameter(Mandatory = $false)]
        [string]$UserId,
        
        [Parameter(Mandatory = $false)]
        [string]$DeviceId,
        
        [Parameter(Mandatory = $false)]
        [string]$DeviceName,
        
        [Parameter(Mandatory = $false)]
        [string]$Result,
        
        [Parameter(Mandatory = $false)]
        [bool]$Success,
        
        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage,
        
        [Parameter(Mandatory = $false)]
        [string]$StackTrace
    )
    
    try {
        # Check if Write-ActivityToLogAnalytics is available
        if (-not (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
            Write-Verbose "Write-ActivityToLogAnalytics function is not available. Skipping logging."
            return
        }
        
        # Create log object
        $logObject = @{
            Task = $Task
            Timestamp = Get-Date
            Source = "Approve-QuarantinedMobileDevice"
        }
        
        # Add optional parameters if provided
        if (-not [string]::IsNullOrEmpty($UserId)) { $logObject.UserId = $UserId }
        if (-not [string]::IsNullOrEmpty($DeviceId)) { $logObject.DeviceId = $DeviceId }
        if (-not [string]::IsNullOrEmpty($DeviceName)) { $logObject.DeviceName = $DeviceName }
        if (-not [string]::IsNullOrEmpty($Result)) { $logObject.Result = $Result }
        if ($null -ne $Success) { $logObject.Success = $Success }
        if (-not [string]::IsNullOrEmpty($ErrorMessage)) { $logObject.ErrorMessage = $ErrorMessage }
        if (-not [string]::IsNullOrEmpty($StackTrace)) { $logObject.StackTrace = $StackTrace }
        
        # Send to Log Analytics
        $logObject | Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue
    }
    catch {
        # We don't want logging failures to impact the main functionality
        Write-Verbose "Error in Write-ActivityLog: $($_.Exception.Message)"
    }
}