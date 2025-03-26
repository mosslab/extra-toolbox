function Test-ExchangeOnlineConnection {
<#
.SYNOPSIS
Tests the existing Exchange Online connection and establishes a new one if necessary.

.DESCRIPTION
The function Test-ExchangeOnlineConnection checks for an existing Exchange Online connection by assessing its state and token status.
If a connection is not active or if forced via the -Force parameter, a new connection will be established.
The function supports various authentication methods and provides robust error handling.

.PARAMETER Force
Forces a new Exchange Online connection, disregarding any existing connections.

.PARAMETER Credential
Specifies the credential object to use for authentication. If not provided, the function will use the current user's credentials or prompt for authentication.

.PARAMETER CertificateThumbprint
Specifies the Certificate Thumbprint for connecting to Exchange Online. Requires AppId and Organization parameters.

.PARAMETER AppId
Specifies the Application ID for certificate-based authentication.

.PARAMETER Organization
Specifies the organization name for certificate-based authentication.

.PARAMETER MaxRetries
Maximum number of connection retry attempts if the initial connection fails. Defaults to 3.

.PARAMETER LogActivities
Enables logging of connection activities to Log Analytics if the Write-ActivityToLogAnalytics function is available.

.EXAMPLE
Test-ExchangeOnlineConnection -Force
Forces a new Exchange Online connection, even if one already exists.

.EXAMPLE
Test-ExchangeOnlineConnection
Checks for an existing Exchange Online connection and establishes a new one if needed.

.EXAMPLE
Test-ExchangeOnlineConnection -CertificateThumbprint "1234567890ABCDEF" -AppId "your-app-id" -Organization "contoso.onmicrosoft.com"
Connects to Exchange Online using certificate-based authentication.

.NOTES
This function requires the ExchangeOnlineManagement module to be installed.
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Force,

        [Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory=$false)]
        [string]$CertificateThumbprint,

        [Parameter(Mandatory=$false)]
        [string]$AppId,

        [Parameter(Mandatory=$false)]
        [string]$Organization,

        [Parameter(Mandatory=$false)]
        [int]$MaxRetries = 3,

        [Parameter(Mandatory=$false)]
        [switch]$LogActivities
    )

    begin {
        # Check if ExchangeOnlineManagement module is installed
        if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
            $errorMessage = "ExchangeOnlineManagement module is not installed. Please install it using: Install-Module ExchangeOnlineManagement -Scope CurrentUser"
            Write-Error $errorMessage
            throw $errorMessage
        }

        # Initialize logging
        $functionName = $MyInvocation.MyCommand.Name
        Write-Verbose "$functionName - Starting connection validation"

        # Log activity if required
        if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
            $logObject = @{
                Task = "Initializing Exchange Online connection check"
                ForceNewConnection = $Force
                UsingCertificate = -not [string]::IsNullOrEmpty($CertificateThumbprint)
            }
            $logObject | Write-ActivityToLogAnalytics
        }
    }

    process {
        try {
            # Check if we should force a new connection
            if ($Force) {
                Write-Verbose "$functionName - Force parameter used, disconnecting any existing sessions"
                try {
                    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                }
                catch {
                    # Ignore errors on disconnect
                    Write-Verbose "$functionName - No active session to disconnect or error in disconnection"
                }
            }
            else {
                # Check for an existing connection
                $connectionInfo = Get-ConnectionInformation -ErrorAction SilentlyContinue
                
                if ($connectionInfo -and $connectionInfo.Count -gt 0) {
                    $activeConnection = $connectionInfo | Where-Object { $_.State -eq 'Connected' -and $_.TokenStatus -eq 'Active' }
                    
                    if ($activeConnection) {
                        Write-Verbose "$functionName - Active Exchange Online connection found"
                        Write-Host "Connected to Exchange Online." -ForegroundColor Green
                        Write-Output $true
                        return $true
                    }
                    else {
                        Write-Verbose "$functionName - No active Exchange Online connection found, or token is expired"
                    }
                }
                else {
                    Write-Verbose "$functionName - No Exchange Online connection information found"
                }
            }

            # Determine authentication method and prepare connection parameters
            $connectParams = @{}
            
            # Certificate-based auth
            if (-not [string]::IsNullOrEmpty($CertificateThumbprint)) {
                Write-Verbose "$functionName - Using certificate-based authentication"
                
                if ([string]::IsNullOrEmpty($AppId)) {
                    throw "AppId is required when using certificate authentication"
                }
                
                if ([string]::IsNullOrEmpty($Organization)) {
                    throw "Organization is required when using certificate authentication"
                }
                
                $connectParams = @{
                    CertificateThumbprint = $CertificateThumbprint
                    AppId = $AppId
                    Organization = $Organization
                }
            }
            # Credential-based auth
            elseif ($null -ne $Credential) {
                Write-Verbose "$functionName - Using credential-based authentication"
                $connectParams = @{
                    Credential = $Credential
                }
            }
            
            # Add common parameters
            $connectParams['ShowBanner'] = $false
            $connectParams['ShowProgress'] = $true
            $connectParams['ErrorAction'] = 'Stop'

            # Attempt to connect with retry logic
            $attempt = 0
            $connected = $false
            
            while (-not $connected -and $attempt -lt $MaxRetries) {
                $attempt++
                try {
                    Write-Verbose "$functionName - Connection attempt $attempt of $MaxRetries"
                    Connect-ExchangeOnline @connectParams | Out-Null
                    
                    # Verify connection was successful
                    $verifyConnection = Get-ConnectionInformation -ErrorAction Stop
                    if ($null -eq $verifyConnection -or $verifyConnection.Count -eq 0 -or 
                        -not ($verifyConnection | Where-Object { $_.State -eq 'Connected' -and $_.TokenStatus -eq 'Active' })) {
                        throw "Connection verification failed - unable to get active Exchange Online connection"
                    }
                    
                    Write-Verbose "$functionName - Successfully connected to Exchange Online"
                    Write-Host "Connected to Exchange Online." -ForegroundColor Green
                    
                    if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                        $logObject = @{
                            Task = "Completed Exchange Online connection"
                            ConnectionSuccessful = $true
                            AttemptNumber = $attempt
                        }
                        $logObject | Write-ActivityToLogAnalytics
                    }
                    
                    $connected = $true
                    Write-Output $true
                    return $true
                }
                catch {
                    Write-Warning "$functionName - Connection attempt $attempt failed: $($_.Exception.Message)"
                    
                    if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                        $logObject = @{
                            Task = "Exchange Online connection attempt failed"
                            ConnectionSuccessful = $false
                            AttemptNumber = $attempt
                            ErrorMessage = $_.Exception.Message
                        }
                        $logObject | Write-ActivityToLogAnalytics
                    }
                    
                    if ($attempt -ge $MaxRetries) {
                        throw "Failed to connect to Exchange Online after $MaxRetries attempts: $($_.Exception.Message)"
                    }
                    
                    # Exponential backoff
                    $backoffTime = [math]::Pow(2, $attempt)
                    Write-Verbose "$functionName - Retrying in $backoffTime seconds"
                    Start-Sleep -Seconds $backoffTime
                }
            }
        }
        catch {
            Write-Error "$functionName - Critical error: $($_.Exception.Message)"
            Write-Error "$functionName - Stack trace: $($_.ScriptStackTrace)"
            
            if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                $logObject = @{
                    Task = "Exchange Online connection critical error"
                    ErrorMessage = $_.Exception.Message
                    StackTrace = $_.ScriptStackTrace
                }
                $logObject | Write-ActivityToLogAnalytics
            }
            
            Write-Output $false
            return $false
        }
    }
    
    end {
        Write-Verbose "$functionName - Connection operation completed"
    }
}