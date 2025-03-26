function Get-DirectRoleAssignments {
<#
.SYNOPSIS
Gets direct role assignments for a specified Entra ID role.

.DESCRIPTION
This internal function retrieves direct role assignments for a specified Entra ID role,
processes group memberships if requested, and adds results to the shared results collection.

.PARAMETER Role
The Entra ID role object to process.

.PARAMETER ExpandGroups
When specified, expands group memberships to include all nested members.

.PARAMETER IncludeGroups
When specified, includes groups as individual objects in the output.

.PARAMETER Metrics
Reference to a hashtable for tracking metrics during processing.

.EXAMPLE
Get-DirectRoleAssignments -Role $roleObject -ExpandGroups -IncludeGroups -Metrics $metricsHashtable

.NOTES
This function is intended for internal use by Get-EntraPrivilegedRoleMembers.
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]$Role,
        
        [Parameter(Mandatory = $false)]
        [switch]$ExpandGroups,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeGroups,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Metrics
    )
    
    $functionName = $MyInvocation.MyCommand.Name
    Write-Verbose "$functionName - Getting direct members for role: $($Role.DisplayName)"
    
    try {
        # Get direct role members
        $members = Get-MgDirectoryRoleMember -DirectoryRoleId $Role.Id
        
        # Update role counts
        $script:roleCounts[$Role.DisplayName].Direct = $members.Count
        
        foreach ($member in $members) {
            if ($member.AdditionalProperties.'@odata.type' -eq "#microsoft.graph.group" -and $ExpandGroups) {
                Write-Verbose "$functionName - Expanding direct assignment group: $($member.Id) for role: $($Role.DisplayName)"
                
                Get-NestedGroupMembers -GroupId $member.Id -OriginalRoleName $Role.DisplayName `
                    -AssignmentSource "Direct Assignment"
            }
            else {
                # Process direct member
                $memberDetails = $null
                
                switch ($member.AdditionalProperties.'@odata.type') {
                    "#microsoft.graph.user" {
                        $memberDetails = Get-MgUser -UserId $member.Id -Property Id, UserPrincipalName, 
                            DisplayName, Mail, JobTitle, Department, AccountEnabled, 
                            SignInActivity, CreatedDateTime, LastPasswordChangeDateTime -ErrorAction SilentlyContinue
                    }
                    "#microsoft.graph.group" {
                        if ($IncludeGroups) {
                            $memberDetails = Get-MgGroup -GroupId $member.Id -ErrorAction SilentlyContinue
                        }
                    }
                }

                if ($memberDetails) {
                    $lastSignIn = if ($memberDetails.SignInActivity.LastSignInDateTime) {
                        $memberDetails.SignInActivity.LastSignInDateTime
                    } else { "Never" }
                    
                    $daysSinceSignIn = if ($lastSignIn -ne "Never") {
                        ((Get-Date) - $lastSignIn).Days
                    } else { [int]::MaxValue }

                    # Add to results collection
                    $script:results.Add([PSCustomObject]@{
                        RoleName = $Role.DisplayName
                        ObjectType = $member.AdditionalProperties.'@odata.type'.Split('.')[-1]
                        ObjectId = $memberDetails.Id
                        DisplayName = $memberDetails.DisplayName
                        UPN = $memberDetails.UserPrincipalName
                        Email = $memberDetails.Mail
                        Department = $memberDetails.Department
                        JobTitle = $memberDetails.JobTitle
                        Enabled = $memberDetails.AccountEnabled
                        LastSignIn = $lastSignIn
                        DaysSinceSignIn = $daysSinceSignIn
                        Created = $memberDetails.CreatedDateTime
                        LastPasswordChange = $memberDetails.LastPasswordChangeDateTime
                        AssignmentType = "Direct"
                        AssignmentPath = "Direct"
                    })
                    
                    $Metrics.TotalMembers++
                }
            }
        }
        
        $Metrics.DirectRolesProcessed++
    }
    catch {
        Write-Warning "Error getting direct role assignments for $($Role.DisplayName): $_"
        $Metrics.ProcessingErrors++
    }
}