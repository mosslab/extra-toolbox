function Build-LogAnalyticsSignature {
<#
.SYNOPSIS
Builds an authorization signature for Azure Log Analytics API requests.

.DESCRIPTION
This function creates a properly formatted HMAC-SHA256 signature for authenticating requests to the
Azure Log Analytics Data Collector API. It follows the Azure specification for creating shared key
authorization headers.

.PARAMETER WorkspaceId
The ID of the Azure Log Analytics workspace.

.PARAMETER SharedKey
The shared key for the Azure Log Analytics workspace as a SecureString.

.PARAMETER Date
The RFC1123 formatted date string to use in the signature. If not provided, the current UTC date is used.

.PARAMETER ContentLength
The content length of the request body.

.PARAMETER Method
The HTTP method for the request. Default is "POST".

.PARAMETER ContentType
The content type of the request. Default is "application/json".

.PARAMETER Resource
The resource endpoint for the request. Default is "/api/logs".

.EXAMPLE
$secureKey = ConvertTo-SecureString "your-shared-key" -AsPlainText -Force
$signature = Build-LogAnalyticsSignature -WorkspaceId "workspace-id" -SharedKey $secureKey -ContentLength 100

.EXAMPLE
$date = [DateTime]::UtcNow.ToString("r")
$signature = Build-LogAnalyticsSignature -WorkspaceId "workspace-id" -SharedKey $secureKey -Date $date -ContentLength 256 -Method "POST" -ContentType "application/json"

.NOTES
This function implements secure handling of the shared key and follows best practices for
generating signatures for Azure API authentication. It is primarily used by the 
Write-ActivityToLogAnalytics function.

For more information on the signature format, see:
https://docs.microsoft.com/en-us/azure/azure-monitor/logs/data-collector-api
#>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceId,
        
        [Parameter(Mandatory = $true)]
        [securestring]$SharedKey,
        
        [Parameter(Mandatory = $false)]
        [string]$Date = [DateTime]::UtcNow.ToString("r"),
        
        [Parameter(Mandatory = $true)]
        [int]$ContentLength,
        
        [Parameter(Mandatory = $false)]
        [string]$Method = "POST",
        
        [Parameter(Mandatory = $false)]
        [string]$ContentType = "application/json",
        
        [Parameter(Mandatory = $false)]
        [string]$Resource = "/api/logs"
    )
    
    begin {
        $functionName = $MyInvocation.MyCommand.Name
        Write-Verbose "$functionName - Generating Log Analytics signature"
        
        # Initialize variable to track secure string conversion
        $BSTR = [IntPtr]::Zero
    }
    
    process {
        try {
            # Validate parameters
            if ([string]::IsNullOrEmpty($WorkspaceId)) {
                throw "WorkspaceId cannot be null or empty"
            }
            
            if ($null -eq $SharedKey) {
                throw "SharedKey cannot be null"
            }
            
            if ($ContentLength -lt 0) {
                throw "ContentLength must be a non-negative integer"
            }
            
            # X-MS-Date header
            $xHeaders = "x-ms-date:" + $Date
            
            # Create string to sign
            # Format: METHOD\nContentLength\nContentType\nx-ms-date:date\nresource
            $stringToHash = $Method + "`n" + 
                           $ContentLength + "`n" + 
                           $ContentType + "`n" + 
                           $xHeaders + "`n" + 
                           $Resource
            
            Write-Verbose "$functionName - String to hash: $stringToHash"
            
            # Convert string to UTF8 bytes
            $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
            
            # Convert from SecureString to plain text for signing
            # This is necessary but we'll handle the memory securely
            try {
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SharedKey)
                $plainSharedKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                
                # Validate the shared key format (should be base64)
                try {
                    $keyBytes = [Convert]::FromBase64String($plainSharedKey)
                }
                catch {
                    throw "SharedKey is not in valid Base64 format. Please verify your Log Analytics Shared Key."
                }
                
                # Create HMAC-SHA256 hasher
                $hmacsha256 = New-Object System.Security.Cryptography.HMACSHA256
                $hmacsha256.Key = $keyBytes
                
                # Compute the hash
                $calculatedHash = $hmacsha256.ComputeHash($bytesToHash)
                
                # Convert hash to Base64
                $encodedHash = [Convert]::ToBase64String($calculatedHash)
                
                # Create authorization header
                $authorization = 'SharedKey {0}:{1}' -f $WorkspaceId, $encodedHash
                
                return $authorization
            }
            finally {
                # Always clean up the unmanaged resource
                if ($BSTR -ne [IntPtr]::Zero) {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
                }
                
                # Clear the key bytes from memory if they were created
                if ($null -ne $keyBytes) {
                    for ($i = 0; $i -lt $keyBytes.Length; $i++) {
                        $keyBytes[$i] = 0