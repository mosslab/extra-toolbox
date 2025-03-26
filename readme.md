# Entra-Toolbox

A PowerShell module providing a comprehensive set of tools for Microsoft Entra ID (formerly Azure AD) administration, designed for Service Desk and IT Support teams.

## Installation

### From PowerShell Gallery (Recommended)

```powershell
Install-Module -Name Entra-Toolbox -Scope CurrentUser
```

### Manual Installation

1. Clone this repository
2. Run the build script to create the module:

```powershell
.\build-module.ps1
```

3. Copy the output to your PowerShell modules directory:

```powershell
.\publish-module.ps1 -Local
```

## Prerequisites

The module requires the following PowerShell modules:

- Microsoft.Graph
- ExchangeOnlineManagement

These will be automatically installed as dependencies when installing from the PowerShell Gallery.

## Functions

### Authentication

- **Test-MgGraphConnection**: Tests and establishes a connection to Microsoft Graph API
- **Test-ExchangeOnlineConnection**: Tests and establishes a connection to Exchange Online

### Mobile Device Management

- **Approve-QuarantinedMobileDevice**: Approves Exchange quarantined mobile devices for user(s)

### User Management

- **New-TemporaryAccessPassForUser**: Creates Temporary Access Passes for users (single or bulk)
- **Get-EntraPrivilegedRoleMembers**: Retrieves entitlement lists of privileged roles in Entra ID

### Logging for the Risk and Cybersecuriity folks

- **Write-ActivityToLogAnalytics**: Logs activities to Azure Log Analytics for auditing
- **Test-WriteToLogAnalytics**: Tests Log Analytics connectivity

## Examples

### Approve Quarantined Mobile Device

```powershell
# Interactive mode - will show a grid view of devices to select
Approve-QuarantinedMobileDevice -UserId "john.doe@contoso.com"

# Non-interactive mode with specific device ID
Approve-QuarantinedMobileDevice -UserId "john.doe@contoso.com" -DeviceId "AppleABCD1234" -Force -NonInteractive
```

### Create Temporary Access Pass

```powershell
# For a single user
New-TemporaryAccessPassForUser -UserID "jane.smith@contoso.com" -ExpiresIn "4 hours"

# For multiple users from a CSV file
New-TemporaryAccessPassForUser -BulkUserCSV "C:\Temp\users.csv" -ExpiresIn "8 hours" -LogActivities
```

### Get Privileged Role Members

```powershell
# Basic usage
$roleMembers = Get-EntraPrivilegedRoleMembers

# With additional options
$roleMembers = Get-EntraPrivilegedRoleMembers -AssignmentType All -ExpandPIMGroups -IncludeGroups -ShowGridView
```

### CI/CD Integration

The module includes some CI/CD toolchain additions, specifically Pester for automated testing.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
