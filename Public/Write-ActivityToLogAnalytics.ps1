Function Write-ActivityToLogAnalytics {
<#
.SYNOPSIS
Writes PowerShell activity output to an Azure Log Analytics Workspace.

.DESCRIPTION
This function takes a PSObject as input and writes it to an Azure Log Analytics Workspace.
The table name in the Log Analytics Workspace will be set to match the calling function's name.
Enhanced error handling, credential security, and throttling capabilities are included.

.PARAMETER InputObject
The PSObject containing the output or activity details you wish to send to the Azure Log Analytics Workspace.

.PARAMETER WorkspaceID
The ID of the Azure Log Analytics workspace. If not provided, the function will try to retrieve it from the 
secure credential store or environment variable.

.PARAMETER SharedKey
The shared key for the Azure Log Analytics workspace as a SecureString. If not provided, the function will try 
to retrieve it from the secure credential store or environment variable.

.PARAMETER CustomTableName
Overrides the automatic table name generation and uses this value instead.
Must be a valid Log Analytics table name (alphanumeric characters only).

.PARAMETER IncludeComputerInfo
When enabled, automatically adds computer name, operating system, and IP address to the log entry.

.PARAMETER RetryCount
Number of retry attempts if the Log Analytics API call fails. Default is 3.

.PARAMETER ThrottleLimit
Maximum number of API calls per minute to prevent throttling. Default is 100.

.PARAMETER DoNotThrow
Prevents the function from throwing terminating errors. Non-terminating errors will still be written.

.EXAMPLE
$logData = @{
    Action = "UserCreated"
    Username = "john.doe@contoso.com"
    Department = "IT"
}
$logData | Write-ActivityToLogAnalytics

.EXAMPLE
Write-ActivityToLogAnalytics -InputObject $logData -CustomTableName "UserManagement" -IncludeComputerInfo

.NOTES
For secure credential storage, use:
- On Windows: Windows Credential Manager with a generic credential named "AzureLogAnalytics"
- On other platforms: SecretManagement module with a secret named "AzureLogAnalytics"

Format for stored credential:
- Username: WorkspaceID
- Password: SharedKey

Alternatively, set environment variables:
- On Windows: setx WorkspaceID "your-workspace-id" (Admin PowerShell)
- On Windows: setx SharedKey "your-shared-key" (Admin PowerShell)
- On Linux/macOS: export WorkspaceID="your-workspace-id"
- On Linux/macOS: export SharedKey="your-shared-key"

This function implements throttling to prevent exceeding Log Analytics API limits.
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("Object")]
        [PSObject]$InputObject,
        
        [Parameter(Mandatory = $false)]
        [string]$WorkspaceID,
        
        [Parameter(Mandatory = $false)]
        [securestring]$SharedKey,
        
        [Parameter(Mandatory = $false)]
        [ValidatePattern("^[a-zA-Z0-9_]+$")]
        [string]$CustomTableName,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeComputerInfo,
        
        [Parameter(Mandatory = $false)]
        [int]$RetryCount = 3,
        
        [Parameter(Mandatory = $false)]
        [int]$ThrottleLimit = 100,
        
        [Parameter(Mandatory = $false)]
        [switch]$DoNotThrow
    )

    Begin {
        # Initialize function
        $functionName = $MyInvocation.MyCommand.Name
        Write-Verbose "$functionName - Starting log analytics write operation"
        
        # Static storage for API call tracking (for throttling)
        if (-not [System.Runtime.CompilerServices.RuntimeHelpers]::GetObjectValue([PSCustomObject]::new()).PSObject.Properties.Name.Contains("LogAnalyticsApiCalls")) {
            $script:LogAnalyticsApiCalls = @()
        }
        
        # Retrieve credentials - first try parameters, then credential store, then environment variables
        if ([string]::IsNullOrEmpty($WorkspaceID)) {
            # Try to get from credential store
            try {
                # Try Windows Credential Manager first
                if ($IsWindows -or $null -eq $IsWindows) {  # $null check for older PowerShell
                    try {
                        Add-Type -AssemblyName System.Security
                        $cred = [System.Net.CredentialCache]::DefaultNetworkCredentials
                        
                        # Look for the credential in Windows Credential Manager
                        $credential = Get-StoredCredential -Target "AzureLogAnalytics" -ErrorAction Stop
                        if ($credential) {
                            $WorkspaceID = $credential.UserName
                            $SharedKey = $credential.Password
                        }
                    }
                    catch {
                        Write-Verbose "$functionName - Unable to retrieve from Windows Credential Manager: $($_.Exception.Message)"
                    }
                }
                
                # Try SecretManagement module if available
                if ([string]::IsNullOrEmpty($WorkspaceID) -and (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretManagement)) {
                    try {
                        $secret = Get-Secret -Name "AzureLogAnalytics" -ErrorAction Stop
                        if ($secret -is [PSCredential]) {
                            $WorkspaceID = $secret.UserName
                            $SharedKey = $secret.Password
                        }
                        elseif ($secret -is [hashtable] -or $secret -is [PSCustomObject]) {
                            $WorkspaceID = $secret.WorkspaceID
                            $SharedKey = ConvertTo-SecureString $secret.SharedKey -AsPlainText -Force
                        }
                    }
                    catch {
                        Write-Verbose "$functionName - Unable to retrieve from SecretManagement: $($_.Exception.Message)"
                    }
                }
                
                # Fall back to environment variables
                if ([string]::IsNullOrEmpty($WorkspaceID)) {
                    $WorkspaceID = [Environment]::GetEnvironmentVariable('WorkspaceID')
                    
                    if ([string]::IsNullOrEmpty($WorkspaceID)) {
                        throw "WorkspaceID not found in parameters, credential store, or environment variables"
                    }
                    
                    if ($null -eq $SharedKey) {
                        $sharedKeyString = [Environment]::GetEnvironmentVariable('SharedKey')
                        if ([string]::IsNullOrEmpty($sharedKeyString)) {
                            throw "SharedKey not found in parameters, credential store, or environment variables"
                        }
                        $SharedKey = ConvertTo-SecureString $sharedKeyString -AsPlainText -Force
                    }
                }
            }
            catch {
                $errorMsg = "Error retrieving Log Analytics credentials: $($_.Exception.Message)"
                Write-Error $errorMsg
                if (-not $DoNotThrow) {
                    throw $errorMsg
                }
                return
            }
        }
        
        # Get the table name from the calling function or use custom name
        if (-not [string]::IsNullOrEmpty($CustomTableName)) {
            $tableName = $CustomTableName
        }
        else {
            # Get the calling function name to use as the table name
            $callerInfo = (Get-PSCallStack)[1]
            $callingFunctionName = $callerInfo.Command
            
            # If called from a script, use script name instead
            if ([string]::IsNullOrEmpty($callingFunctionName) -or $callingFunctionName -eq "<ScriptBlock>") {
                if ($callerInfo.ScriptName) {
                    $callingFunctionName = [System.IO.Path]::GetFileNameWithoutExtension($callerInfo.ScriptName)
                }
                else {
                    $callingFunctionName = "PowerShellActivity"
                }
            }
            
            # Replace invalid characters with '_'
            $tableName = $callingFunctionName -replace '[^a-zA-Z0-9]', '_'
            
            # If it doesn't start with a letter, prepend 'A'
            $tableName = $tableName -replace '^([^a-zA-Z])', 'A$1'
            
            # Ensure it's not too long for Log Analytics
            if ($tableName.Length -gt 64) {
                $tableName = $tableName.Substring(0, 64)
            }
        }
        
        Write-Verbose "$functionName - Using table name: $tableName"
        
        # Initialize throttling check
        $oneMinuteAgo = [DateTime]::UtcNow.AddMinutes(-1)
        $script:LogAnalyticsApiCalls = $script:LogAnalyticsApiCalls | Where-Object { $_ -gt $oneMinuteAgo }
        $currentCallCount = $script:LogAnalyticsApiCalls.Count
        
        if ($currentCallCount -ge $ThrottleLimit) {
            $waitTime = 60 - ([DateTime]::UtcNow - $script:LogAnalyticsApiCalls[0]).TotalSeconds
            if ($waitTime -gt 0) {
                Write-Warning "$functionName - API throttling limit reached ($ThrottleLimit calls/minute). Waiting $([math]::Ceiling($waitTime)) seconds."
                Start-Sleep -Seconds ([math]::Ceiling($waitTime))
            }
        }
    }

    Process {
        try {
            # Make a copy of the input object to avoid modifying the original
            $logObject = $InputObject.PSObject.Copy()
            
            # Add timestamp if it doesn't exist
            if (-not $logObject.PSObject.Properties.Name.Contains("TimeGenerated")) {
                $logObject | Add-Member -MemberType NoteProperty -Name "TimeGenerated" -Value ([DateTime]::UtcNow.ToString("o")) -Force
            }
            
            # Add machine information if requested
            if ($IncludeComputerInfo) {
                $logObject | Add-Member -MemberType NoteProperty -Name "MachineName" -Value $env:COMPUTERNAME -Force
                $logObject | Add-Member -MemberType NoteProperty -Name "ExecutingUser" -Value $env:USERNAME -Force
                
                # Add OS information
                try {
                    if ($IsWindows -or $null -eq $IsWindows) {  # $null check for older PowerShell
                        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
                        if ($osInfo) {
                            $logObject | Add-Member -MemberType NoteProperty -Name "OSVersion" -Value $osInfo.Version -Force
                            $logObject | Add-Member -MemberType NoteProperty -Name "OSCaption" -Value $osInfo.Caption -Force
                        }
                    }
                    else {
                        $osInfo = if ($IsMacOS) { "macOS" } elseif ($IsLinux) { "Linux" } else { "Unknown" }
                        $logObject | Add-Member -MemberType NoteProperty -Name "OSPlatform" -Value $osInfo -Force
                    }
                }
                catch {
                    Write-Verbose "$functionName - Unable to retrieve OS information: $($_.Exception.Message)"
                }
                
                # Add IP address
                try {
                    $ipAddresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
                                    Where-Object { $_.IPAddress -ne "127.0.0.1" } | 
                                    Select-Object -ExpandProperty IPAddress)
                    if ($ipAddresses.Count -gt 0) {
                        $logObject | Add-Member -MemberType NoteProperty -Name "IPAddresses" -Value ($ipAddresses -join ", ") -Force
                    }
                }
                catch {
                    Write-Verbose "$functionName - Unable to retrieve IP information: $($_.Exception.Message)"
                }
            }
            
            # Convert to JSON
            $json = $logObject | ConvertTo-Json -Depth 10 -Compress
            $utf8Body = [System.Text.Encoding]::UTF8.GetBytes($json)
            
            # Build the request
            $method = "POST"
            $contentType = "application/json"
            $resource = "/api/logs"
            $rfc1123date = [DateTime]::UtcNow.ToString("r")
            $contentLength = $utf8Body.Length
            $signature = Build-LogAnalyticsSignature -WorkspaceId $WorkspaceID -SharedKey $SharedKey -Date $rfc1123date -ContentLength $contentLength -Method $method -ContentType $contentType -Resource $resource
            
            $uri = "https://$WorkspaceID.ods.opinsights.azure.com$resource`?api-version=2016-04-01"
            
            $headers = @{
                "Authorization" = $signature
                "Log-Type" = $tableName
                "x-ms-date" = $rfc1123date
                "time-generated-field" = "TimeGenerated"
            }
            
            # Send request with retry logic
            $attempt = 0
            $success = $false
            
            while (-not $success -and $attempt -lt $RetryCount) {
                $attempt++
                try {
                    # Track API call for throttling
                    $script:LogAnalyticsApiCalls += [DateTime]::UtcNow
                    
                    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $utf8Body -UseBasicParsing -ErrorAction Stop
                    
                    if ($response.StatusCode -eq 200) {
                        Write-Verbose "$functionName - Successfully sent log to Log Analytics workspace"
                        $success = $true
                    }
                    else {
                        throw "Received status code $($response.StatusCode)"
                    }
                }
                catch {
                    if ($attempt -ge $RetryCount) {
                        $errorMsg = "Failed to send log to Log Analytics after $RetryCount attempts: $($_.Exception.Message)"
                        Write-Error $errorMsg
                        if (-not $DoNotThrow) {
                            throw $errorMsg
                        }
                        return
                    }
                    
                    # Exponential backoff
                    $backoffTime = [math]::Pow(2, $attempt)
                    Write-Warning "$functionName - Attempt $attempt failed: $($_.Exception.Message). Retrying in $backoffTime seconds."
                    Start-Sleep -Seconds $backoffTime
                }
            }
        }
        catch {
            $errorMsg = "Error in Log Analytics processing: $($_.Exception.Message)"
            Write-Error $errorMsg
            if (-not $DoNotThrow) {
                throw $errorMsg
            }
        }
    }
    
    End {
        Write-Verbose "$functionName - Log Analytics write operation completed"
    }
}

function Build-LogAnalyticsSignature {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceId,
        
        [Parameter(Mandatory = $true)]
        [securestring]$SharedKey,
        
        [Parameter(Mandatory = $true)]
        [string]$Date,
        
        [Parameter(Mandatory = $true)]
        [int]$ContentLength,
        
        [Parameter(Mandatory = $true)]
        [string]$Method,
        
        [Parameter(Mandatory = $true)]
        [string]$ContentType,
        
        [Parameter(Mandatory = $true)]
        [string]$Resource
    )
    
    try {
        # Convert from SecureString to plain text for signing
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SharedKey)
        $plainSharedKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        
        $xHeaders = "x-ms-date:" + $Date
        $stringToHash = $Method + "`n" + $ContentLength + "`n" + $ContentType + "`n" + $xHeaders + "`n" + $Resource
        
        $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
        $keyBytes = [Convert]::FromBase64String($plainSharedKey)
        
        $hmacsha256 = New-Object System.Security.Cryptography.HMACSHA256
        $hmacsha256.Key = $keyBytes
        $calculateHash = $hmacsha256.ComputeHash($bytesToHash)
        $encodedHash = [Convert]::ToBase64String($calculateHash)
        $authorization = 'SharedKey {0}:{1}' -f $WorkspaceId, $encodedHash
        
        return $authorization
    }
    catch {
        throw "Failed to generate Log Analytics signature: $($_.Exception.Message)"
    }
    finally {
        # Clean up the unmanaged resource
        if ($BSTR -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }
    }
}

Function Test-WriteToLogAnalytics {
<#
.SYNOPSIS
Tests writing arbitrary text to an Azure Log Analytics Workspace.

.DESCRIPTION
This function takes arbitrary text as input and writes it to an Azure Log Analytics Workspace.
The table name in the Log Analytics Workspace will be set to 'TestLog'.

.PARAMETER Text
The text string that you wish to send to the Azure Log Analytics Workspace.

.PARAMETER WorkspaceID
The ID of the Azure Log Analytics workspace. If not provided, the function will try to retrieve it from the 
secure credential store or environment variable.

.PARAMETER SharedKey
The shared key for the Azure Log Analytics workspace as a SecureString. If not provided, the function will try 
to retrieve it from the secure credential store or environment variable.

.EXAMPLE
Test-WriteToLogAnalytics -Text "This is a test message."

.NOTES
Make sure to set your WorkspaceID and SharedKey using secure methods described in Write-ActivityToLogAnalytics.
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string]$Text,
        
        [Parameter(Mandatory = $false)]
        [string]$WorkspaceID,
        
        [Parameter(Mandatory = $false)]
        [securestring]$SharedKey
    )

    # Create a log object with the test text
    $logObject = [PSCustomObject]@{
        TestMessage = $Text
        Timestamp = Get-Date
        TestRunId = [guid]::NewGuid().ToString()
    }

    # Pass parameters to Write-ActivityToLogAnalytics
    $params = @{
        InputObject = $logObject
        CustomTableName = "TestLog"
        IncludeComputerInfo = $true
    }
    
    if (-not [string]::IsNullOrEmpty($WorkspaceID)) {
        $params['WorkspaceID'] = $WorkspaceID
    }
    
    if ($null -ne $SharedKey) {
        $params['SharedKey'] = $SharedKey
    }
    
    $logObject | Write-ActivityToLogAnalytics @params
    
    Write-Host "Test message sent to Log Analytics: $Text" -ForegroundColor Green
}