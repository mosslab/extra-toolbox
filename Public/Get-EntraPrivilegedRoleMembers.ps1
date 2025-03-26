function Get-EntraPrivilegedRoleMembers {
<#
.SYNOPSIS
Gets the members of privileged Entra groups and roles with detailed information.

.DESCRIPTION
This function retrieves detailed information about members of privileged roles in Microsoft Entra ID (formerly Azure AD).
It supports retrieving direct role assignments, PIM (Privileged Identity Management) eligible and active assignments,
and can expand nested group memberships to provide a comprehensive view of privileges.

The function includes enhanced security features, logging, and performance optimizations for large environments.

.PARAMETER IncludeGroups
When specified, includes groups as individual objects in the output (in addition to expanding their membership).
This provides visibility into both group and user assignments.

.PARAMETER ShowGridView
Displays the results in a GridView UI element for interactive filtering and selection.

.PARAMETER OutputPath
Specifies a file path to export results as a CSV file.

.PARAMETER SpecificRoles
Limits the query to specific role names instead of checking all privileged roles.
Useful for targeted analysis or performance improvement.

.PARAMETER AssignmentType
Specifies which assignment types to include:
- All: Both direct assignments and PIM assignments (default)
- Direct: Only direct role assignments
- PIMOnly: Only PIM eligible and active assignments

.PARAMETER ExpandPIMGroups
When specified, expands PIM assignments granted to groups to include all nested members.
This provides full visibility into effective PIM privileges granted through groups.

.PARAMETER DaysInactive
Filters output to include only users who have been active within the specified number of days.
Default is 90 days. Set to 0 to disable this filter.

.PARAMETER IncludeRoleSummary
Includes a summary of role assignments in the output, showing total counts by role type.

.PARAMETER UseProgressBar
Displays a progress bar during processing, helpful for large environments.

.PARAMETER MaxConcurrentGroups
Specifies the maximum number of concurrent group membership queries to execute.
Useful for large environments. Default is 5.

.PARAMETER LogActivities
Enables logging of activities to Azure Log Analytics if the Write-ActivityToLogAnalytics function is available.

.EXAMPLE
# Basic usage
$roleMembers = Get-EntraPrivilegedRoleMembers

.EXAMPLE
# Basic usage with PIM expansion
$roleMembers = Get-EntraPrivilegedRoleMembers -ExpandPIMGroups

.NOTES
This function requires the Microsoft Graph PowerShell module with Directory.Read.All, RoleManagement.Read.All,
User.Read.All, Group.Read.All, and PrivilegedAccess.Read.AzureAD permissions.
#>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$IncludeGroups,

        [Parameter(Mandatory=$false)]
        [switch]$ShowGridView,

        [Parameter(Mandatory=$false)]
        [string]$OutputPath,

        [Parameter(Mandatory=$false)]
        [string[]]$SpecificRoles,

        [Parameter(Mandatory=$false)]
        [ValidateSet('All', 'Direct', 'PIMOnly')]
        [string]$AssignmentType = 'All',

        [Parameter(Mandatory=$false)]
        [switch]$ExpandPIMGroups,

        [Parameter(Mandatory=$false)]
        [int]$DaysInactive = 90,
        
        [Parameter(Mandatory=$false)]
        [switch]$IncludeRoleSummary,
        
        [Parameter(Mandatory=$false)]
        [switch]$UseProgressBar,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxConcurrentGroups = 5,
        
        [Parameter(Mandatory=$false)]
        [switch]$LogActivities
    )

    begin {
        # Initialize logging
        $functionName = $MyInvocation.MyCommand.Name
        Write-Verbose "$functionName - Starting privileged role member analysis"
        
        # Initialize metrics for logging
        $metrics = @{
            StartTime = Get-Date
            DirectRolesProcessed = 0
            PIMRolesProcessed = 0
            GroupsExpanded = 0
            TotalMembers = 0
            ProcessingErrors = 0
        }
        
        if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
            $logObject = @{
                Task = "Starting privileged role member analysis"
                AssignmentType = $AssignmentType
                ExpandGroups = $ExpandPIMGroups
                IncludeGroups = $IncludeGroups
                SpecificRolesCount = if ($SpecificRoles) { $SpecificRoles.Count } else { 0 }
            }
            $logObject | Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue
        }
        
        # Verify connection and required scopes
        $validationResult = Test-EntraPrivilegedRoleRequirements -LogActivities:$LogActivities
        if (-not $validationResult) {
            throw "Failed to validate environment requirements for analyzing privileged roles"
        }

        # Initialize results collection and tracking dictionaries
        $script:results = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
        $script:roleCounts = @{}
        $script:processedObjects = [System.Collections.Concurrent.ConcurrentDictionary[string, bool]]::new()

        # Define highly privileged roles if no specific roles are specified
        $defaultRoles = Get-DefaultPrivilegedRoles
    }

    process {
        try {
            # Get directory roles
            if ($UseProgressBar) {
                Write-Progress -Activity "Getting Directory Roles" -Status "Retrieving roles..." -PercentComplete -1
            }
            
            $roles = if ($SpecificRoles) {
                Get-MgDirectoryRole -All | Where-Object { $_.DisplayName -in $SpecificRoles }
            }
            else {
                Get-MgDirectoryRole -All | Where-Object { $_.DisplayName -in $defaultRoles }
            }
            
            $totalRoles = $roles.Count
            $currentRole = 0
            
            Write-Verbose "$functionName - Found $totalRoles roles to process"
            
            if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                $logObject = @{
                    Task = "Role discovery"
                    RolesFound = $totalRoles
                    UsingSpecificRoles = $null -ne $SpecificRoles
                }
                $logObject | Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue
            }

            # Process each role
            foreach ($role in $roles) {
                $currentRole++
                Write-Verbose "$functionName - Processing role: $($role.DisplayName) ($currentRole of $totalRoles)"
                
                if ($UseProgressBar) {
                    $percentComplete = [math]::Round(($currentRole / $totalRoles) * 100)
                    Write-Progress -Activity "Processing Directory Roles" -Status "Role: $($role.DisplayName)" -PercentComplete $percentComplete
                }
                
                # Create role entry in counts dictionary
                if (-not $script:roleCounts.ContainsKey($role.DisplayName)) {
                    $script:roleCounts[$role.DisplayName] = @{
                        PIMEligible = 0
                        PIMActive = 0
                        Direct = 0
                        Total = 0
                    }
                }
                
                # Process direct assignments if requested
                if ($AssignmentType -in @('All', 'Direct')) {
                    Get-DirectRoleAssignments -Role $role -ExpandGroups:$ExpandPIMGroups -IncludeGroups:$IncludeGroups -Metrics $metrics
                }

                # Process PIM assignments if requested
                if ($AssignmentType -in @('All', 'PIMOnly')) {
                    Get-PIMRoleAssignments -RoleDefinitionId $role.RoleTemplateId -RoleName $role.DisplayName `
                        -ExpandGroups:$ExpandPIMGroups -IncludeGroups:$IncludeGroups -UseProgressBar:$UseProgressBar `
                        -LogActivities:$LogActivities -Metrics $metrics -MaxConcurrentGroups $MaxConcurrentGroups
                }
            }
            
            # Wait for any remaining thread jobs to complete
            Get-Job | Wait-Job | Receive-Job -ErrorAction SilentlyContinue
            Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue
            
            if ($UseProgressBar) {
                Write-Progress -Activity "Processing Directory Roles" -Completed
            }
            
            # Update total counts
            foreach ($roleName in $script:roleCounts.Keys) {
                $roleCount = $script:roleCounts[$roleName]
                $roleCount.Total = $roleCount.Direct + $roleCount.PIMActive + $roleCount.PIMEligible
            }
        }
        catch {
            $errorMessage = "Error processing roles: $_"
            Write-Error $errorMessage
            
            if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                $logObject = @{
                    Task = "Role processing critical error"
                    ErrorMessage = $errorMessage
                    StackTrace = $_.ScriptStackTrace
                }
                $logObject | Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue
            }
            
            throw $errorMessage
        }
    }

    end {
        # Calculate execution time
        $metrics.EndTime = Get-Date
        $executionTime = $metrics.EndTime - $metrics.StartTime
        $executionTimeFormatted = "{0:hh\:mm\:ss}" -f $executionTime
        
        Write-Verbose "$functionName - Processing completed in $executionTimeFormatted"
        Write-Verbose "$functionName - Processed $($metrics.DirectRolesProcessed) direct roles, $($metrics.PIMRolesProcessed) PIM roles"
        Write-Verbose "$functionName - Expanded $($metrics.GroupsExpanded) groups, found $($metrics.TotalMembers) total members"
        Write-Verbose "$functionName - Encountered $($metrics.ProcessingErrors) errors during processing"
        
        # Create final results array from the concurrent bag
        [array]$finalResults = $script:results
        
        # Filter inactive users if specified
        if ($DaysInactive -gt 0) {
            $finalResults = $finalResults | Where-Object { 
                $_.ObjectType -ne "User" -or $_.DaysSinceSignIn -eq "N/A" -or $_.DaysSinceSignIn -le $DaysInactive 
            }
            
            Write-Verbose "$functionName - Filtered results to $($finalResults.Count) active members (within $DaysInactive days)"
        }
        
        # Include role summary if requested
        if ($IncludeRoleSummary) {
            $finalResults = Add-RoleSummary -Results $finalResults -RoleCounts $script:roleCounts
        }
        
        # Export results if path specified
        if ($OutputPath) {
            Export-RoleResults -Results $finalResults -OutputPath $OutputPath -LogActivities:$LogActivities
        }

        # Show in GridView if specified
        if ($ShowGridView) {
            Show-RoleResultsInGridView -Results $finalResults
        }
        
        # Log completion
        if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
            $logObject = @{
                Task = "Role analysis completed"
                ExecutionTimeSeconds = $executionTime.TotalSeconds
                RolesProcessed = ($script:roleCounts.Keys).Count
                MembersFound = $metrics.TotalMembers
                GroupsExpanded = $metrics.GroupsExpanded
                Errors = $metrics.ProcessingErrors
            }
            $logObject | Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue
        }

        # Return results for pipeline
        return $finalResults
    }
}