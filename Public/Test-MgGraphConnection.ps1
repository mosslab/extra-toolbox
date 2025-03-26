function Test-MgGraphConnection {
<#
.SYNOPSIS
Tests the existing Microsoft Graph connection and establishes a new one if necessary.

.DESCRIPTION
The function Test-MgGraphConnection checks for an existing Microsoft Graph connection.
If a connection is not found or if forced via the -Force parameter, it will establish a new connection using provided credentials.
The function supports various authentication methods including interactive, client secret, and certificate-based authentication.

.PARAMETER Force
Forces a new Microsoft Graph connection, disregarding any existing connections.

.PARAMETER ClientId
Specifies the Client ID for connecting to Microsoft Graph. Optional.

.PARAMETER TenantId
Specifies the Tenant ID for connecting to Microsoft Graph. Optional.

.PARAMETER ClientSecret
Specifies the Client Secret for connecting to Microsoft Graph. Optional.

.PARAMETER CertificateThumbprint
Specifies the Certificate Thumbprint for connecting to Microsoft Graph. Optional.

.PARAMETER Scopes
Specifies the permission scopes to request when connecting to Microsoft Graph. Defaults to common administrative scopes.

.PARAMETER MaxRetries
Maximum number of connection retry attempts if the initial connection fails. Defaults to 3.

.PARAMETER Interactive
Use interactive authentication instead of client credentials. Default is $false.

.EXAMPLE
Test-MgGraphConnection -Force
Forces a new Microsoft Graph connection using interactive authentication, even if one already exists.

.EXAMPLE
Test-MgGraphConnection -ClientId 'your-client-id' -TenantId 'your-tenant-id' -ClientSecret 'your-client-secret'
Tests for an existing Microsoft Graph connection and establishes a new one using the provided Client ID, Tenant ID, and Client Secret if none exists.

.EXAMPLE
Test-MgGraphConnection -Interactive -Scopes @("User.Read.All", "Group.Read.All")
Establishes an interactive authentication connection with specific permission scopes.

.NOTES
This function requires the Microsoft.Graph PowerShell module to be installed.
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory=$false)]
        [switch]$Force,

        [Parameter(Mandatory=$false)]
        [string]$ClientId,

        [Parameter(Mandatory=$false)]
        [string]$TenantId,

        [Parameter(Mandatory=$false)]
        [securestring]$ClientSecret,

        [Parameter(Mandatory=$false)]
        [string]$CertificateThumbprint,

        [Parameter(Mandatory=$false)]
        [string[]]$Scopes = @(
            "Directory.Read.All",
            "Directory.ReadWrite.All",
            "User.Read.All",
            "Group.Read.All",
            "RoleManagement.Read.All"
        ),

        [Parameter(Mandatory=$false)]
        [int]$MaxRetries = 3,

        [Parameter(Mandatory=$false)]
        [switch]$Interactive
    )

    begin {
        # Check if Microsoft.Graph module is installed
        if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
            $errorMessage = "Microsoft.Graph module is not installed. Please install it using: Install-Module Microsoft.Graph -Scope CurrentUser"
            Write-Error $errorMessage
            throw $errorMessage
        }

        # Initialize logging
        $functionName = $MyInvocation.MyCommand.Name
        Write-Verbose "$functionName - Starting connection validation"
    }

    process {
        try {
            # Check if we need to force a new connection
            if ($Force) {
                Write-Verbose "$functionName - Force parameter used, disconnecting any existing sessions"
                try {
                    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                }
                catch {
                    # Ignore errors on disconnect
                    Write-Verbose "$functionName - No active session to disconnect or error in disconnection"
                }
            }
            else {
                # Check for an existing connection
                $currentContext = Get-MgContext -ErrorAction SilentlyContinue
                if ($currentContext) {
                    Write-Verbose "$functionName - Existing connection found for tenant: $($currentContext.TenantId)"
                    
                    # Check if we have all required scopes
                    $missingScopes = $Scopes | Where-Object { $_ -notin $currentContext.Scopes }
                    if ($missingScopes.Count -eq 0) {
                        Write-Verbose "$functionName - All required scopes are present in existing connection"
                        Write-Output $true
                        return $true
                    }
                    else {
                        Write-Verbose "$functionName - Missing required scopes: $($missingScopes -join ', '). Reconnecting..."
                        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                    }
                }
            }

            # Determine authentication method
            if ($Interactive) {
                Write-Verbose "$functionName - Using interactive authentication"
                $connectParams = @{
                    Scopes = $Scopes
                }
                # Add TenantId if provided
                if (-not [string]::IsNullOrEmpty($TenantId)) {
                    $connectParams['TenantId'] = $TenantId
                }
            }
            else {
                Write-Verbose "$functionName - Using client credential authentication"
                $connectParams = @{
                    Scopes = $Scopes
                }

                # Validate required parameters for client credential auth
                if ([string]::IsNullOrEmpty($ClientId)) {
                    if (-not $Interactive) {
                        throw "ClientId is required for non-interactive authentication. Please provide a ClientId or use -Interactive switch."
                    }
                }
                else {
                    $connectParams['ClientId'] = $ClientId
                }

                if ([string]::IsNullOrEmpty($TenantId)) {
                    throw "TenantId is required for authentication."
                }
                else {
                    $connectParams['TenantId'] = $TenantId
                }

                # Handle certificate authentication
                if (-not [string]::IsNullOrEmpty($CertificateThumbprint)) {
                    Write-Verbose "$functionName - Using certificate authentication"
                    $connectParams['CertificateThumbprint'] = $CertificateThumbprint
                }
                # Handle client secret authentication
                elseif ($null -ne $ClientSecret) {
                    Write-Verbose "$functionName - Using client secret authentication"
                    $clientSecretCredential = New-Object System.Management.Automation.PSCredential($ClientId, $ClientSecret)
                    $connectParams['ClientSecretCredential'] = $clientSecretCredential
                }
                elseif (-not $Interactive) {
                    throw "Either ClientSecret or CertificateThumbprint must be provided for non-interactive authentication."
                }
            }

            # Attempt to connect with retry logic
            $attempt = 0
            $connected = $false
            
            while (-not $connected -and $attempt -lt $MaxRetries) {
                $attempt++
                try {
                    Write-Verbose "$functionName - Connection attempt $attempt of $MaxRetries"
                    Connect-MgGraph @connectParams -ErrorAction Stop | Out-Null
                    $connected = $true
                    
                    # Verify connection was successful
                    $verifyContext = Get-MgContext -ErrorAction Stop
                    if ($null -eq $verifyContext) {
                        throw "Connection verification failed - unable to get Microsoft Graph context"
                    }
                    
                    Write-Verbose "$functionName - Successfully connected to Microsoft Graph for tenant: $($verifyContext.TenantId)"
                    Write-Output $true
                    return $true
                }
                catch {
                    Write-Warning "$functionName - Connection attempt $attempt failed: $($_.Exception.Message)"
                    if ($attempt -ge $MaxRetries) {
                        throw "Failed to connect to Microsoft Graph after $MaxRetries attempts: $($_.Exception.Message)"
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
            Write-Output $false
            return $false
        }
    }
    
    end {
        Write-Verbose "$functionName - Connection operation completed"
    }
}