function Add-RoleSummary {
<#
.SYNOPSIS
Adds role summary information to the results collection.

.DESCRIPTION
This function adds role summary objects to the results collection, showing counts of
different assignment types for each role.

.PARAMETER Results
The collection of role membership results to add summary information to.

.PARAMETER RoleCounts
A hashtable containing role count information for each role.

.EXAMPLE
$enhancedResults = Add-RoleSummary -Results $roleResults -RoleCounts $roleCounts

.NOTES
This function is intended for internal use by Get-EntraPrivilegedRoleMembers.
#>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$Results,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$RoleCounts
    )
    
    $functionName = $MyInvocation.MyCommand.Name
    Write-Verbose "$functionName - Adding role summary information to results"
    
    try {
        # Create role summary objects
        $roleSummary = foreach ($roleName in $RoleCounts.Keys) {
            $counts = $RoleCounts[$roleName]
            [PSCustomObject]@{
                RoleName = $roleName
                DirectMembers = $counts.Direct
                PIMActiveMembers = $counts.PIMActive
                PIMEligibleMembers = $counts.PIMEligible
                TotalMembers = $counts.Total
            }
        }
        
        # Add role summary to results
        $enhancedResults = $Results + ($roleSummary | ForEach-Object {
            [PSCustomObject]@{
                RoleName = $_.RoleName
                ObjectType = "Summary"
                ObjectId = "N/A"
                DisplayName = "Role Summary"
                UPN = $null
                Email = $null
                Department = $null
                JobTitle = $null
                Enabled = $null
                LastSignIn = $null
                DaysSinceSignIn = $null
                Created = $null
                LastPasswordChange = $null
                DirectMembers = $_.DirectMembers
                PIMActiveMembers = $_.PIMActiveMembers
                PIMEligibleMembers = $_.PIMEligibleMembers
                TotalMembers = $_.TotalMembers
                AssignmentType = "Summary"
                AssignmentPath = "N/A"
            }
        })
        
        return $enhancedResults
    }
    catch {
        Write-Warning "$functionName - Error adding role summary: $_"
        return $Results
    }
}