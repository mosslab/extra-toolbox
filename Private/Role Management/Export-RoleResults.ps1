function Export-RoleResults {
<#
.SYNOPSIS
Exports role membership results to a CSV file.

.DESCRIPTION
This function exports the collection of role membership results to a CSV file at the specified path.

.PARAMETER Results
The collection of role membership results to export.

.PARAMETER OutputPath
The file path where the CSV file should be created.

.PARAMETER LogActivities
Enables logging of export activities to Azure Log Analytics.

.EXAMPLE
Export-RoleResults -Results $roleResults -OutputPath "C:\Reports\EntraPrivilegedRoles.csv"

.NOTES
This function is intended for internal use by Get-EntraPrivilegedRoleMembers.
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$Results,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$LogActivities
    )
    
    $functionName = $MyInvocation.MyCommand.Name
    Write-Verbose "$functionName - Exporting results to CSV file: $OutputPath"
    
    try {
        # Create directory if it doesn't exist
        $directory = Split-Path -Path $OutputPath -Parent
        if (-not [string]::IsNullOrEmpty($directory) -and -not (Test-Path -Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        # Export to CSV
        $Results | Export-Csv -Path $OutputPath -NoTypeInformation -ErrorAction Stop
        Write-Host "Results exported to: $OutputPath" -ForegroundColor Green
        
        if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
            $logObject = @{
                Task = "Export results"
                Result = "Success"
                OutputPath = $OutputPath
                RecordsExported = $Results.Count
            }
            $logObject | Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue
        }
    }
    catch {
        $errorMessage = "Error exporting results to CSV: $_"
        Write-Error $errorMessage
        
        if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
            $logObject = @{
                Task = "Export results"
                Result = "Error"
                OutputPath = $OutputPath
                ErrorMessage = $errorMessage
            }
            $logObject | Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue
        }
    }
}