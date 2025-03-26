function Get-NestedGroupMembers {
<#
.SYNOPSIS
Recursively retrieves members of a group, including nested groups.

.DESCRIPTION
This internal function recursively retrieves members of a specified group, including nested groups if requested.
It adds results to the shared results collection and tracks processed groups to prevent recursion.

.PARAMETER GroupId
The ID of the group to process.

.PARAMETER OriginalRoleName
The name of the role to associate with the group members.

.PARAMETER AssignmentSource
The source of the role assignment (Direct, PIM Eligible, PIM Active).

.PARAMETER EligibilityStart
The start date/time of the role eligibility period (for PIM assignments).

.PARAMETER EligibilityEnd
The end date/time of the role eligibility period (for PIM assignments).

.PARAMETER MaxConcurrentGroups
Maximum number of concurrent group membership queries to execute.

.PARAMETER LogActivities
Enables logging of activities to Azure Log Analytics.

.EXAMPLE
Get-NestedGroupMembers -GroupId "12345" -OriginalRoleName "Global Admin" -AssignmentSource "PIM Eligible"

.NOTES
This function is intended for internal use by Get-EntraPrivilegedRoleMembers.
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$GroupId,
        
        [Parameter(Mandatory = $true)]
        [string]$OriginalRoleName,
        
        [Parameter(Mandatory = $true)]
        [string]$AssignmentSource,
        
        [Parameter(Mandatory = $false)]
        [datetime]$EligibilityStart,
        
        [Parameter(Mandatory = $false)]
        [datetime]$EligibilityEnd,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxConcurrentGroups = 5,
        
        [Parameter(Mandatory = $false)]
        [switch]$LogActivities
    )

    # Skip if already processed to prevent recursion
    if (-not $script:processedObjects.TryAdd($GroupId, $true)) {
        Write-Verbose "Get-NestedGroupMembers - Skipping already processed group: $GroupId"
        return
    }

    try {
        Write-Verbose "Get-NestedGroupMembers - Expanding group: $GroupId for role: $OriginalRoleName"
        $script:metrics.GroupsExpanded++
        
        # Get group members with paging
        $members = Get-MgGroupMember -GroupId $GroupId -All
        
        # Process members in parallel with throttling
        $throttleParams = @{
            ThrottleLimit = $MaxConcurrentGroups
            ErrorAction = 'Stop'
        }
        
        if ($members) {
            foreach ($member in $members) {
                $memberType = $member.AdditionalProperties.'@odata.type'
                
                if ($memberType -eq "#microsoft.graph.user") {
                    $userDetails = Get-MgUser -UserId $member.Id -Property Id, UserPrincipalName, 
                        DisplayName, Mail, JobTitle, Department, AccountEnabled, SignInActivity, 
                        CreatedDateTime, LastPasswordChangeDateTime -ErrorAction SilentlyContinue
                    
                    if ($userDetails) {
                        $lastSignIn = if ($userDetails.SignInActivity.LastSignInDateTime) {
                            $userDetails.SignInActivity.LastSignInDateTime
                        } else { "Never" }
                        
                        $daysSinceSignIn = if ($lastSignIn -ne "Never") {
                            ((Get-Date) - $lastSignIn).Days
                        } else { [int]::MaxValue }  # Use maximum value for "Never" to ensure filtering works

                        # Add to results collection
                        $script:results.Add([PSCustomObject]@{
                            RoleName = $OriginalRoleName
                            ObjectType = "User"
                            ObjectId = $userDetails.Id
                            DisplayName = $userDetails.DisplayName
                            UPN = $userDetails.UserPrincipalName
                            Email = $userDetails.Mail
                            Department = $userDetails.Department
                            JobTitle = $userDetails.JobTitle
                            Enabled = $userDetails.AccountEnabled
                            LastSignIn = $lastSignIn
                            DaysSinceSignIn = $daysSinceSignIn
                            Created = $userDetails.CreatedDateTime
                            LastPasswordChange = $userDetails.LastPasswordChangeDateTime
                            AssignmentType = $AssignmentSource
                            AssignmentPath = "Via Group"
                            EligibilityStart = $EligibilityStart
                            EligibilityEnd = $EligibilityEnd
                        })
                        
                        $script:metrics.TotalMembers++
                    }
                }
                elseif ($memberType -eq "#microsoft.graph.group" -and $script:IncludeGroups) {
                    Start-ThreadJob @throttleParams -ScriptBlock {
                        param($NestedGroupId, $OriginalRoleName, $AssignmentSource, $EligibilityStart, $EligibilityEnd, $FunctionDef)
                        
                        # Recreate the function in the job context
                        Invoke-Expression $FunctionDef
                        Get-NestedGroupMembers -GroupId $NestedGroupId -OriginalRoleName $OriginalRoleName `
                            -AssignmentSource $AssignmentSource -EligibilityStart $EligibilityStart `
                            -EligibilityEnd $EligibilityEnd
                    } -ArgumentList $member.Id, $OriginalRoleName, $AssignmentSource, $EligibilityStart, $EligibilityEnd, (Get-Item function:Get-NestedGroupMembers).Definition | Out-Null
                }
            }
        }
    }
    catch {
        $errorMessage = "Error processing group $GroupId members: $_"
        Write-Warning $errorMessage
        $script:metrics.ProcessingErrors++
        
        if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
            $logObject = @{
                Task = "Group expansion"
                GroupId = $GroupId
                RoleName = $OriginalRoleName
                Result = "Error"
                ErrorMessage = $errorMessage
            }
            $logObject | Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue
        }
    }
}