function Build-LogAnalyticsSignature {
    <#
    .SYNOPSIS
    Builds an authorization signature for Azure Log Analytics API requests.
    
    .DESCRIPTION
    This function creates a properly formatted HMAC-SHA256 signature for authenticating requests to the
    Azure Log Analytics Data Collector API. It implements the shared key authorization scheme required
    by the Azure Monitor HTTP Data Collector API.
    
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
    This function securely handles credentials and follows the Azure Monitor HTTP Data Collector API authentication requirements:
    https://docs.microsoft.com/en-us/azure/azure-monitor/logs/data-collector-api
    #>
        [CmdletBinding()]
        [OutputType([string])]
        param (
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$WorkspaceId,
            
            [Parameter(Mandatory = $true)]
            [ValidateNotNull()]
            [securestring]$SharedKey,
            
            [Parameter(Mandatory = $false)]
            [ValidateNotNullOrEmpty()]
            [string]$Date = [DateTime]::UtcNow.ToString("r"),
            
            [Parameter(Mandatory = $true)]
            [ValidateRange(0, [int]::MaxValue)]
            [int]$ContentLength,
            
            [Parameter(Mandatory = $false)]
            [ValidateSet("GET", "POST", "PUT", "DELETE")]
            [string]$Method = "POST",
            
            [Parameter(Mandatory = $false)]
            [ValidateNotNullOrEmpty()]
            [string]$ContentType = "application/json",
            
            [Parameter(Mandatory = $false)]
            [ValidateNotNullOrEmpty()]
            [string]$Resource = "/api/logs"
        )
        
        begin {
            $functionName = $MyInvocation.MyCommand.Name
            Write-Verbose "$functionName - Generating Log Analytics signature"
            
            # Initialize variables for secure string handling
            $BSTR = [IntPtr]::Zero
            $plainSharedKey = $null
            $keyBytes = $null
            $hmacsha256 = $null
        }
        
        process {
            try {
                # Create string to sign
                # Format: METHOD\nContentLength\nContentType\nx-ms-date:date\nresource
                $xHeaders = "x-ms-date:" + $Date
                $stringToHash = $Method + "`n" + 
                               $ContentLength + "`n" + 
                               $ContentType + "`n" + 
                               $xHeaders + "`n" + 
                               $Resource
                
                Write-Verbose "$functionName - String to hash: $stringToHash"
                
                # Convert string to UTF8 bytes
                $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
                
                # Convert from SecureString to plain text for signing (temporary and secure handling)
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
                    
                    Write-Verbose "$functionName - Successfully generated authorization signature"
                    return $authorization
                }
                finally {
                    # Clean up the unmanaged resources and sensitive data in memory
                    
                    # Zero out and free BSTR memory if allocated
                    if ($BSTR -ne [IntPtr]::Zero) {
                        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
                    }
                    
                    # Clear the key bytes from memory if they were created
                    if ($null -ne $keyBytes) {
                        for ($i = 0; $i -lt $keyBytes.Length; $i++) {
                            $keyBytes[$i] = 0
                        }
                    }
                    
                    # Overwrite the plain text key if it was created
                    if ($null -ne $plainSharedKey) {
                        $plainSharedKey = "0" * $plainSharedKey.Length
                        # Let .NET GC handle string disposal
                        [System.GC]::Collect()
                    }
                    
                    # Dispose of the HMAC object
                    if ($null -ne $hmacsha256) {
                        $hmacsha256.Dispose()
                    }
                }
            }
            catch {
                $errorMessage = "Failed to generate Log Analytics signature: $($_.Exception.Message)"
                Write-Error $errorMessage
                throw $_
            }
        }
        
        end {
            Write-Verbose "$functionName - Signature generation completed"
        }
    }
    