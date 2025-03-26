function Get-DefaultPrivilegedRoles {
<#
.SYNOPSIS
Returns a list of default privileged roles in Microsoft Entra ID.

.DESCRIPTION
This function returns a pre-defined list of highly privileged roles in Microsoft Entra ID
that are commonly of interest for security and compliance purposes.

.EXAMPLE
$privilegedRoles = Get-DefaultPrivilegedRoles

.NOTES
This function is intended for internal use by Get-EntraPrivilegedRoleMembers.
#>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    
    return @(
        "Global Administrator",
        "Privileged Role Administrator",
        "Security Administrator",
        "Exchange Administrator",
        "SharePoint Administrator",
        "Teams Administrator",
        "Power Platform Administrator",
        "Application Administrator",
        "Cloud Application Administrator",
        "Authentication Administrator",
        "Password Administrator",
        "Billing Administrator",
        "User Administrator",
        "Intune Administrator",
        "Compliance Administrator",
        "Azure AD Privileged Role Administrator",
        "Desktop Analytics Administrator",
        "License Administrator",
        "Conditional Access Administrator",
        "Global Reader",
        "Security Reader"
    )
}