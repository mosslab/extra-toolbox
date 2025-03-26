function Test-EntraPrivilegedRoleRequirements {
<#
.SYNOPSIS
Tests if all requirements for using the Get-EntraPrivilegedRoleMembers function are met.

.DESCRIPTION
This function verifies that all necessary modules are installed and that the user has the required
permissions to retrieve privileged role information from Microsoft Entra ID.

.PARAMETER LogActivities
Enables logging of validation activities to Azure Log Analytics.

.EXAMPLE
Test-EntraPrivilegedRoleRequirements -LogActivities

.NOTES
This function is intended for internal use by Get-EntraPrivilegedRoleMembers.
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$LogActivities
    )
    
    $functionName = $MyInvocation.MyCommand.Name
    Write-Verbose "$functionName - Verifying environment requirements"
    
    try {
        # Verify required modules
        $requiredModules = @('Microsoft.Graph')
        foreach ($module in $requiredModules) {
            if (-not (Get-Module -ListAvailable $module)) {
                $errorMessage = "Required module '$module' is not installed. Please install it using: Install-Module $module -Scope CurrentUser"
                Write-Error $errorMessage
                
                if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                    $logObject = @{
                        Task = "Module verification"
                        Result = "Failed"
                        MissingModule = $module
                        ErrorMessage = $errorMessage
                    }
                    $logObject | Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue
                }
                
                return $false
            }
        }

        # Validate Microsoft Graph connection
        try {
            $connectionResult = Test-MgGraphConnection
            
            if (-not $connectionResult) {
                throw "Failed to establish connection to Microsoft Graph"
            }
        } catch {
            $errorMessage = "An error occurred while establishing a connection to Microsoft Graph: $_"
            Write-Error $errorMessage
            
            if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                $logObject = @{
                    Task = "Graph connection check"
                    Result = "Failed"
                    ErrorMessage = $errorMessage
                }
                $logObject | Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue
            }
            
            return $false
        }
        
        # Verify required scopes
        $requiredScopes = @(
            "Directory.Read.All",
            "RoleManagement.Read.All",
            "User.Read.All",
            "Group.Read.All",
            "PrivilegedAccess.Read.AzureAD"
        )
        
        $currentScopes = (Get-MgContext).Scopes
        $missingScopes = $requiredScopes | Where-Object { $_ -notin $currentScopes }
        
        if ($missingScopes) {
            $errorMessage = "Missing required scopes: $($missingScopes -join ', '). Please authenticate with all required scopes."
            Write-Error $errorMessage
            
            if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                $logObject = @{
                    Task = "Scope verification"
                    Result = "Failed"
                    MissingScopes = $missingScopes -join ", "
                    ErrorMessage = $errorMessage
                }
                $logObject | Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue
            }
            
            return $false
        }
        
        # All checks passed
        Write-Verbose "$functionName - All requirements verified successfully"
        return $true
    }
    catch {
        $errorMessage = "Error verifying environment requirements: $_"
        Write-Error $errorMessage
        
        if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
            $logObject = @{
                Task = "Requirements verification"
                Result = "Error"
                ErrorMessage = $errorMessage
            }
            $logObject | Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue
        }
        
        return $false
    }
}