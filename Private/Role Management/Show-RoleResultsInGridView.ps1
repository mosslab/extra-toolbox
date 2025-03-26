function Show-RoleResultsInGridView {
<#
.SYNOPSIS
Displays role membership results in a GridView window.

.DESCRIPTION
This function displays the collection of role membership results in an interactive GridView window,
allowing for filtering and selection. It handles environments where GridView is not available.

.PARAMETER Results
The collection of role membership results to display.

.EXAMPLE
Show-RoleResultsInGridView -Results $roleResults

.NOTES
This function is intended for internal use by Get-EntraPrivilegedRoleMembers.
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$Results
    )
    
    $functionName = $MyInvocation.MyCommand.Name
    Write-Verbose "$functionName - Showing results in GridView"
    
    try {
        $Results | Out-GridView -Title "Entra ID Privileged Role Members" -ErrorAction Stop
    }
    catch {
        Write-Warning "Unable to display results in GridView: $_"
        Write-Host "This could be because you're running in a non-interactive session or on a system without GridView support." -ForegroundColor Yellow
        Write-Host "Consider using the -OutputPath parameter to export results to a CSV file instead." -ForegroundColor Yellow
    }
}