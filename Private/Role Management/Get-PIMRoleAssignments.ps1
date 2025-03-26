function Get-PIMRoleAssignments {
<#
.SYNOPSIS
Gets PIM (Privileged Identity Management) role assignments for a specified role.

.DESCRIPTION
This internal function retrieves both eligible and active PIM role assignments for a specified role,
processes group memberships if requested, and adds results to the shared results collection.

.PARAMETER RoleDefinitionId
The role definition ID (template ID) of the role to process.

.PARAMETER RoleName
The display name of the role to process.

.PARAMETER ExpandGroups
When specified, expands group memberships to include all nested members.

.PARAMETER IncludeGroups
When specified, includes groups as individual objects in the output.

.PARAMETER UseProgressBar
Displays a progress bar during processing.

.PARAMETER LogActivities
Enables logging of activities to Azure Log Analytics.

.PARAMETER Metrics
Reference to a hashtable for tracking metrics during processing.

.PARAMETER MaxConcurrentGroups
Maximum number of concurrent group membership queries to execute.

.EXAMPLE
Get-PIMRoleAssignments -RoleDefinitionId "62e90394-69f5-4237-9190-012177145e10" -RoleName "Global Administrator" -ExpandGroups -Metrics $metricsHashtable

.NOTES
This function is intended for internal use by Get-EntraPrivilegedRoleMembers.
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$RoleDefinitionId,
        
        [Parameter(Mandatory = $true)]
        [string]$RoleName,
        
        [Parameter(Mandatory = $false)]
        [switch]$ExpandGroups,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeGroups,
        
        [Parameter(Mandatory = $false)]
        [switch]$UseProgressBar,
        
        [Parameter(Mandatory = $false)]
        [switch]$LogActivities,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Metrics,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxConcurrentGroups = 5
    )

    $functionName = $MyInvocation.MyCommand.Name
    
    try {
        Write-Verbose "$functionName - Processing PIM assignments for role: $RoleName"
        
        if ($UseProgressBar) {
            Write-Progress -Activity "Processing PIM Assignments" -Status "Role: $RoleName" -PercentComplete -1
        }
        
        # Get eligible assignments
        $eligibleAssignments = Get-MgRoleManagementDirectoryRoleEligibilitySchedule -All | 
            Where-Object { $_.RoleDefinitionId -eq $RoleDefinitionId }
        
        # Update role counts
        if (-not $script:roleCounts.ContainsKey($RoleName)) {
            $script:roleCounts[$RoleName] = @{
                PIMEligible = 0
                PIMActive = 0
                Direct = 0
                Total = 0
            }
        }
        
        $script:roleCounts[$RoleName].PIMEligible = $eligibleAssignments.Count
        
        # Process eligible assignments
        foreach ($assignment in $eligibleAssignments) {
            if ($assignment.PrincipalType -eq "Group" -and $ExpandGroups) {
                Write-Verbose "$functionName - Expanding PIM eligible group: $($assignment.PrincipalId) for role: $RoleName"
                
                Get-NestedGroupMembers -GroupId $assignment.PrincipalId -OriginalRoleName $RoleName `
                    -AssignmentSource "PIM Eligible" -EligibilityStart $assignment.StartDateTime `
                    -EligibilityEnd $assignment.EndDateTime -MaxConcurrentGroups $MaxConcurrentGroups `
                    -LogActivities:$LogActivities
            }
            else {
                $principalInfo = $null
                
                switch ($assignment.PrincipalType) {
                    "User" { 
                        $principalInfo = Get-MgUser -UserId $assignment.PrincipalId -Property Id, UserPrincipalName, 
                            DisplayName, Mail, JobTitle, Department, AccountEnabled, SignInActivity, 
                            CreatedDateTime, LastPasswordChangeDateTime -ErrorAction SilentlyContinue
                    }
                    "Group" { 
                        if ($IncludeGroups) { 
                            $principalInfo = Get-MgGroup -GroupId $assignment.PrincipalId -ErrorAction SilentlyContinue
                        }
                    }
                }

                if ($principalInfo) {
                    $lastSignIn = if ($principalInfo.SignInActivity.LastSignInDateTime) {
                        $principalInfo.SignInActivity.LastSignInDateTime
                    } else { "Never" }
                    
                    $daysSinceSignIn = if ($lastSignIn -ne "Never") {
                        ((Get-Date) - $lastSignIn).Days
                    } else { [int]::MaxValue }

                    # Add to results collection
                    $script:results.Add([PSCustomObject]@{
                        RoleName = $RoleName
                        ObjectType = $assignment.PrincipalType
                        ObjectId = $principalInfo.Id
                        DisplayName = $principalInfo.DisplayName
                        UPN = $principalInfo.UserPrincipalName
                        Email = $principalInfo.Mail
                        Department = $principalInfo.Department
                        JobTitle = $principalInfo.JobTitle
                        Enabled = $principalInfo.AccountEnabled
                        LastSignIn = $lastSignIn
                        DaysSinceSignIn = $daysSinceSignIn
                        Created = $principalInfo.CreatedDateTime
                        LastPasswordChange = $principalInfo.LastPasswordChangeDateTime
                        EligibilityStart = $assignment.StartDateTime
                        EligibilityEnd = $assignment.EndDateTime
                        AssignmentType = "PIM Eligible"
                        AssignmentPath = "Direct"
                    })
                    
                    $Metrics.TotalMembers++
                }
            }
        }

        # Get active assignments
        $activeAssignments = Get-MgRoleManagementDirectoryRoleAssignmentSchedule -All |
            Where-Object { $_.RoleDefinitionId -eq $RoleDefinitionId }
        
        # Update role counts
        $script:roleCounts[$RoleName].PIMActive = $activeAssignments.Count
        
        # Process active assignments
        foreach ($assignment in $activeAssignments) {
            if ($assignment.PrincipalType -eq "Group" -and $ExpandGroups) {
                Write-Verbose "$functionName - Expanding PIM active group: $($assignment.PrincipalId) for role: $RoleName"
                
                Get-NestedGroupMembers -GroupId $assignment.PrincipalId -OriginalRoleName $RoleName `
                    -AssignmentSource "PIM Active" -EligibilityStart $assignment.StartDateTime `
                    -EligibilityEnd $assignment.EndDateTime -MaxConcurrentGroups $MaxConcurrentGroups `
                    -LogActivities:$LogActivities
            }
            else {
                $principalInfo = $null
                
                switch ($assignment.PrincipalType) {
                    "User" { 
                        $principalInfo = Get-MgUser -UserId $assignment.PrincipalId -Property Id, UserPrincipalName, 
                            DisplayName, Mail, JobTitle, Department, AccountEnabled, SignInActivity, 
                            CreatedDateTime, LastPasswordChangeDateTime -ErrorAction SilentlyContinue
                    }
                    "Group" { 
                        if ($IncludeGroups) { 
                            $principalInfo = Get-MgGroup -GroupId $assignment.PrincipalId -ErrorAction SilentlyContinue
                        }
                    }
                }

                if ($principalInfo) {
                    $lastSignIn = if ($principalInfo.SignInActivity.LastSignInDateTime) {
                        $principalInfo.SignInActivity.LastSignInDateTime
                    } else { "Never" }
                    
                    $daysSinceSignIn = if ($lastSignIn -ne "Never") {
                        ((Get-Date) - $lastSignIn).Days
                    } else { [int]::MaxValue }

                    # Add to results collection
                    $script:results.Add([PSCustomObject]@{
                        RoleName = $RoleName
                        ObjectType = $assignment.PrincipalType
                        ObjectId = $principalInfo.Id
                        DisplayName = $principalInfo.DisplayName
                        UPN = $principalInfo.UserPrincipalName
                        Email = $principalInfo.Mail
                        Department = $principalInfo.Department
                        JobTitle = $principalInfo.JobTitle
                        Enabled = $principalInfo.AccountEnabled
                        LastSignIn = $lastSignIn
                        DaysSinceSignIn = $daysSinceSignIn
                        Created = $principalInfo.CreatedDateTime
                        LastPasswordChange = $principalInfo.LastPasswordChangeDateTime
                        AssignmentStart = $assignment.StartDateTime
                        AssignmentEnd = $assignment.EndDateTime
                        AssignmentType = "PIM Active"
                        AssignmentPath = "Direct"
                    })
                    
                    $Metrics.TotalMembers++
                }
            }
        }
        
        $Metrics.PIMRolesProcessed++
    }
    catch {
        $errorMessage = "Error processing PIM assignments for role $RoleName`: $_"
        Write-Warning $errorMessage
        $Metrics.ProcessingErrors++
        
        if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
            $logObject = @{
                Task = "PIM role processing"
                RoleName = $RoleName
                Result = "Error"
                ErrorMessage = $errorMessage
            }
            $logObject | Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue
        }
    }
}