# Entra-Toolbox

A PowerShell module providing a comprehensive set of tools for Microsoft Entra ID (formerly Azure AD) administration, designed for Service Desk and IT Support teams.

## Features

- **Test connectivity** to Microsoft Graph and Exchange Online services
- **Approve quarantined mobile devices** for users in Exchange Online
- **Generate Temporary Access Passes (TAPs)** for individual users or in bulk
- **Retrieve privileged role members** from Entra ID, including PIM assignments
- **Secure logging** to Azure Log Analytics

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

### Connection Management

- **Test-MgGraphConnection**: Tests and establishes a connection to Microsoft Graph API
- **Test-ExchangeOnlineConnection**: Tests and establishes a connection to Exchange Online

### Device Management

- **Approve-QuarantinedMobileDevice**: Approves quarantined mobile devices for users

### User Management

- **New-TemporaryAccessPassForUser**: Creates Temporary Access Passes for users (single or bulk)
- **Get-EntraPrivilegedRoleMembers**: Retrieves members of privileged roles in Entra ID

### Logging

- **Write-ActivityToLogAnalytics**: Logs activities to Azure Log Analytics for auditing
- **Test-WriteToLogAnalytics**: Tests Log Analytics connectivity

## Usage Examples

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

## Security Considerations

This module includes several security enhancements:

- **Secure credential handling**: Using SecureString and credential stores
- **Comprehensive logging**: Detailed activity logging for auditing
- **Error handling**: Robust error handling and reporting
- **Confirmation prompts**: Prevents accidental operations

## For Developers

### Running Tests

The module includes Pester tests that can be run to verify functionality:

```powershell
# Run tests without code coverage
.\build-tests.ps1

# Run tests with code coverage
.\build-tests.ps1 -Coverage
```

### Building the Module

Use the included build script to create a distributable version:

```powershell
.\build-module.ps1 -ModuleVersion "1.1.0"
```

### CI/CD Integration

The module includes GitLab CI/CD configuration for automated testing and deployment.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
