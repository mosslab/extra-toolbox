function Test-WriteToLogAnalytics {
<#
.SYNOPSIS
Tests writing arbitrary text to an Azure Log Analytics Workspace.

.DESCRIPTION
This function sends a test message to an Azure Log Analytics workspace to verify connectivity and configuration.
It creates a standardized test log entry and uses the Write-ActivityToLogAnalytics function to send it.
The test includes diagnostic information to help identify connectivity or authentication issues.

.PARAMETER Text
The text string that you wish to send to the Azure Log Analytics Workspace.

.PARAMETER WorkspaceID
The ID of the Azure Log Analytics workspace. If not provided, the function will try to retrieve it from the 
secure credential store or environment variable.

.PARAMETER SharedKey
The shared key for the Azure Log Analytics workspace as a SecureString. If not provided, the function will try 
to retrieve it from the secure credential store or environment variable.

.PARAMETER IncludeNetworkTest
Performs additional network connectivity tests to the Log Analytics ingestion endpoint.

.PARAMETER ReturnDetailedResults
Returns a detailed object with test results instead of just showing the output.

.EXAMPLE
Test-WriteToLogAnalytics -Text "This is a test message."
Sends a basic test message to Log Analytics using default credentials.

.EXAMPLE
Test-WriteToLogAnalytics -Text "Connection test" -IncludeNetworkTest -ReturnDetailedResults
Performs a comprehensive test with network connectivity validation and returns detailed results.

.EXAMPLE
$secureKey = ConvertTo-SecureString "your-shared-key" -AsPlainText -Force
Test-WriteToLogAnalytics -Text "Credential test" -WorkspaceID "your-workspace-id" -SharedKey $secureKey
Tests Log Analytics connectivity with explicitly provided credentials.

.NOTES
This function requires the Write-ActivityToLogAnalytics function to be available.
If the function fails, check:
1. Workspace ID and Shared Key are correct
2. Network connectivity to *.ods.opinsights.azure.com
3. Date and time are correctly set on the local system (for API authentication)
#>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    Param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Text,
        
        [Parameter(Mandatory = $false)]
        [string]$WorkspaceID,
        
        [Parameter(Mandatory = $false)]
        [securestring]$SharedKey,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeNetworkTest,
        
        [Parameter(Mandatory = $false)]
        [switch]$ReturnDetailedResults
    )

    begin {
        $functionName = $MyInvocation.MyCommand.Name
        Write-Verbose "$functionName - Starting Log Analytics connectivity test"
        
        # Verify Write-ActivityToLogAnalytics function exists
        if (-not (Get-Command -Name Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
            $errorMessage = "Required function 'Write-ActivityToLogAnalytics' is not available. Please ensure it is loaded."
            Write-Error $errorMessage
            
            if ($ReturnDetailedResults) {
                return [PSCustomObject]@{
                    Success = $false
                    Message = $errorMessage
                    ErrorDetails = "Missing dependency: Write-ActivityToLogAnalytics"
                    Timestamp = Get-Date
                }
            }
            return $false
        }
        
        # Setup test results
        $testResults = [PSCustomObject]@{
            Success = $true
            Message = "Test completed successfully"
            ErrorDetails = $null
            NetworkTests = $null
            LogEntry = $null
            Timestamp = Get-Date
        }
    }

    process {
        try {
            # Perform network tests if requested
            if ($IncludeNetworkTest) {
                Write-Verbose "$functionName - Performing network connectivity tests"
                $networkTests = @{}
                
                # DNS resolution test
                try {
                    $targetDomain = if (-not [string]::IsNullOrEmpty($WorkspaceID)) {
                        "$WorkspaceID.ods.opinsights.azure.com"
                    } else {
                        "ods.opinsights.azure.com"
                    }
                    
                    $dnsResult = Resolve-DnsName -Name $targetDomain -ErrorAction Stop
                    $networkTests['DNSResolution'] = [PSCustomObject]@{
                        Success = $true
                        Target = $targetDomain
                        IPAddresses = $dnsResult.IPAddress -join ', '
                    }
                }
                catch {
                    $networkTests['DNSResolution'] = [PSCustomObject]@{
                        Success = $false
                        Target = $targetDomain
                        Error = $_.Exception.Message
                    }
                }
                
                # Connection test
                try {
                    $testConnection = Test-NetConnection -ComputerName $targetDomain -Port 443 -ErrorAction Stop
                    $networkTests['ConnectionTest'] = [PSCustomObject]@{
                        Success = $testConnection.TcpTestSucceeded
                        Target = $targetDomain
                        Port = 443
                        LatencyMS = $testConnection.PingReplyDetails.RoundtripTime
                    }
                }
                catch {
                    $networkTests['ConnectionTest'] = [PSCustomObject]@{
                        Success = $false
                        Target = $targetDomain
                        Port = 443
                        Error = $_.Exception.Message
                    }
                }
                
                $testResults.NetworkTests = $networkTests
            }
            
            # Create a log object with test data
            $testRunId = [guid]::NewGuid().ToString()
            $logObject = [PSCustomObject]@{
                TestMessage = $Text
                TestType = "Log Analytics Connectivity Test"
                TestRunId = $testRunId
                Timestamp = Get-Date
                MachineName = $env:COMPUTERNAME
                UserName = $env:USERNAME
                PowerShellVersion = $PSVersionTable.PSVersion.ToString()
                OSVersion = [System.Environment]::OSVersion.VersionString
            }
            
            # Track the test entry
            $testResults.LogEntry = $logObject
            
            # Build parameters for Write-ActivityToLogAnalytics
            $params = @{
                InputObject = $logObject
                CustomTableName = "TestLog"
                DoNotThrow = $true
            }
            
            if (-not [string]::IsNullOrEmpty($WorkspaceID)) {
                $params['WorkspaceID'] = $WorkspaceID
            }
            
            if ($null -ne $SharedKey) {
                $params['SharedKey'] = $SharedKey
            }
            
            # Send the test message and capture any error output
            $errorOutput = $null
            $success = $true
            
            # Redirect errors to a variable while still displaying them
            $tempErrorAction = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            
            try {
                $originalErrors = $Error.Count
                $logObject | Write-ActivityToLogAnalytics @params
                
                # Check if new errors were added
                if ($Error.Count -gt $originalErrors) {
                    $errorOutput = $Error[0].Exception.Message
                    $success = $false
                }
            }
            catch {
                $errorOutput = $_.Exception.Message
                $success = $false
            }
            finally {
                $ErrorActionPreference = $tempErrorAction
            }
            
            # Update test results
            $testResults.Success = $success
            
            if (-not $success) {
                $testResults.Message = "Test message failed to send to Log Analytics"
                $testResults.ErrorDetails = $errorOutput
            }
            
            # Display results to user
            if ($success) {
                Write-Host "Test message sent to Log Analytics: $Text" -ForegroundColor Green
                Write-Host "Test ID: $testRunId - Check for this ID in your Log Analytics workspace." -ForegroundColor Cyan
            }
            else {
                Write-Host "Failed to send test message to Log Analytics." -ForegroundColor Red
                Write-Host "Error: $errorOutput" -ForegroundColor Red
                
                if ($IncludeNetworkTest) {
                    if (-not $networkTests['DNSResolution'].Success) {
                        Write-Host "DNS resolution failed for Log Analytics endpoint. Check network connectivity." -ForegroundColor Yellow
                    }
                    elseif (-not $networkTests['ConnectionTest'].Success) {
                        Write-Host "TCP connection test failed. Check firewall settings for outbound HTTPS." -ForegroundColor Yellow
                    }
                }
            }
        }
        catch {
            $errorMessage = "Error performing Log Analytics test: $($_.Exception.Message)"
            Write-Error $errorMessage
            
            $testResults.Success = $false
            $testResults.Message = "Test failed with exception"
            $testResults.ErrorDetails = $errorMessage
        }
    }

    end {
        Write-Verbose "$functionName - Completed Log Analytics connectivity test"
        
        if ($ReturnDetailedResults) {
            return $testResults
        }
        
        return $testResults.Success
    }
}