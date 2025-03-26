function New-TemporaryAccessPassForUser {
<#
.SYNOPSIS
Creates a Temporary Access Pass (TAP) for a user or a list of users (provided in .csv format) using Microsoft Graph.

.DESCRIPTION
The function New-TemporaryAccessPassForUser generates Temporary Access Passes (TAPs) for individual or multiple users.
These TAPs can be used for authentication, MFA enrolment, and are generated using the Microsoft Graph PowerShell SDK.
The function allows you to set the expiration duration, and optionally the single-use status for the TAP.
Enhanced error handling, logging, and secure output options are provided.

.PARAMETER UserID
Specifies the UserID the TAP will be generated for. This parameter is required if the function is run for an individual user.

.PARAMETER ExpiresIn
Specifies the duration for which the TAP is valid. The allowed values are '1 hour', '2 hours', '4 hours', '8 hours', and '1 day'.
You will need to ensure the TAP authentication policy in Microsoft Entra matches the maximum duration value specified.

.PARAMETER IsUsableOnce
Specifies whether the TAP can be used only once. Default is $false. This parameter is not mandatory.

.PARAMETER BulkUserCSV
Specifies the path to a CSV file containing a list of user IDs (work_email_address) for bulk TAP creation.
If this parameter is used the module will loop through a list of users.

.PARAMETER OutputPath
Specifies the path where the output CSV file will be saved for bulk operations.
If not specified, it will default to the same directory as the input CSV with '-taps' appended to the filename.

.PARAMETER HidePasswords
When specified, masks the TAP codes in console output while still storing them in the result objects.
Useful for running the function in environments where screen visibility might be a concern.

.PARAMETER Force
Bypasses confirmation prompts when generating TAPs for multiple users.

.PARAMETER LogActivities
Enables logging of TAP creation activities to Log Analytics if the Write-ActivityToLogAnalytics function is available.

.PARAMETER SecureOutput
Outputs TAP values as SecureString objects rather than plain text strings.

.EXAMPLE
New-TemporaryAccessPassForUser -UserID 'testuser@domain.com' -ExpiresIn '4 hours'
Generates a TAP for the user with ID 'testuser@domain.com' that expires in 4 hours.

.EXAMPLE
New-TemporaryAccessPassForUser -BulkUserCSV 'C:\Users\testuser\bulkusers.csv' -ExpiresIn '2 hours' -OutputPath 'C:\TAPs\users-taps.csv'
Generates TAPs for multiple users specified in the 'bulkusers.csv' file, with each TAP expiring in 2 hours, 
and saves the results to the specified output path.

.EXAMPLE
New-TemporaryAccessPassForUser -UserID 'testuser@domain.com' -ExpiresIn '8 hours' -IsUsableOnce $true -SecureOutput
Generates a single-use TAP for the user that expires in 8 hours and returns the TAP as a SecureString.

.NOTES
This function requires the Microsoft.Graph PowerShell module to be installed with appropriate permissions.
Required permissions: User.ReadWrite.All, UserAuthenticationMethod.ReadWrite.All
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'SingleUser')]
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'SingleUser', Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$UserID,

        [Parameter(Mandatory = $true)]
        [ValidateSet("1 hour", "2 hours", "4 hours", "8 hours", "1 day")]
        [string]$ExpiresIn,

        [Parameter(Mandatory = $false)]
        [bool]$IsUsableOnce = $false,

        [Parameter(Mandatory = $true, ParameterSetName = 'BulkUser')]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$BulkUserCSV,

        [Parameter(Mandatory = $false, ParameterSetName = 'BulkUser')]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [switch]$HidePasswords,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$LogActivities,

        [Parameter(Mandatory = $false)]
        [switch]$SecureOutput
    )

    begin {
        # Initialize logging
        $functionName = $MyInvocation.MyCommand.Name
        Write-Verbose "$functionName - Starting temporary access pass generation"
        
        # Required permissions check
        $requiredScopes = @(
            "User.ReadWrite.All",
            "UserAuthenticationMethod.ReadWrite.All"
        )
        
        # Map expiration times to minutes
        $expirationMap = @{
            "1 hour"  = 60
            "2 hours" = 120
            "4 hours" = 240
            "8 hours" = 480
            "1 day"   = 1440
        }
        
        $lifetimeMinutes = $expirationMap[$ExpiresIn]
        
        # Create a timestamp for TAP start time
        $startDateTimeForTAP = Get-Date

        # Log activity if required
        if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
            $logObject = @{
                Task = "Initializing temporary access pass generation"
                ExpiresIn = $ExpiresIn
                IsUsableOnce = $IsUsableOnce
                Mode = if ($PSCmdlet.ParameterSetName -eq 'BulkUser') { "Bulk" } else { "Single" }
            }
            $logObject | Write-ActivityToLogAnalytics
        }
        
        # Determine output path for bulk operations
        if ($PSCmdlet.ParameterSetName -eq 'BulkUser' -and [string]::IsNullOrEmpty($OutputPath)) {
            $inputCsvInfo = Get-Item $BulkUserCSV
            $OutputPath = Join-Path $inputCsvInfo.Directory.FullName "$($inputCsvInfo.BaseName)-taps.csv"
            Write-Verbose "$functionName - Auto-generated output path: $OutputPath"
        }
        
        # Container for results
        $results = @()
    }

    process {
        try {
            # Ensure Graph connection
            Write-Verbose "$functionName - Validating Microsoft Graph connection"
            
            try {
                $connectionResult = Test-MgGraphConnection
                
                if (-not $connectionResult) {
                    throw "Failed to establish connection to Microsoft Graph"
                }
                
                # Verify required scopes
                $context = Get-MgContext
                $missingScopes = $requiredScopes | Where-Object { $_ -notin $context.Scopes }
                
                if ($missingScopes.Count -gt 0) {
                    throw "Missing required scopes: $($missingScopes -join ', '). Please reconnect with sufficient permissions."
                }
            }
            catch {
                Write-Error "Graph connection error: $($_.Exception.Message)"
                throw
            }
            
            # Define TAP properties
            $properties = @{
                UsableOnce = $IsUsableOnce
                LifetimeInMinutes = $lifetimeMinutes
                StartDateTime = $startDateTimeForTAP.ToString('o')  # ISO 8601 format
            }
            
            $propertiesJSON = $properties | ConvertTo-Json
            
            # Process single user
            if ($PSCmdlet.ParameterSetName -eq 'SingleUser') {
                Write-Verbose "$functionName - Processing single user: $UserID"
                
                if ($PSCmdlet.ShouldProcess("User $UserID", "Create temporary access pass")) {
                    try {
                        # Create the TAP
                        $response = New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $UserID -BodyParameter $propertiesJSON -ErrorAction Stop
                        $tap = $response.TemporaryAccessPass
                        
                        # Create secure string version if requested
                        $secureTap = if ($SecureOutput) {
                            ConvertTo-SecureString $tap -AsPlainText -Force
                        } else {
                            $null
                        }
                        
                        # Create result object
                        $result = [PSCustomObject]@{
                            Username = $UserID
                            TemporaryAccessPass = if ($SecureOutput) { $null } else { $tap }
                            SecureTemporaryAccessPass = $secureTap
                            Expiration = $ExpiresIn
                            IsUsableOnce = $IsUsableOnce
                            StartTime = $startDateTimeForTAP
                            EndTime = $startDateTimeForTAP.AddMinutes($lifetimeMinutes)
                            Status = "Success"
                        }
                        
                        # Add to results collection
                        $results += $result
                        
                        # Display output
                        if ($HidePasswords) {
                            Write-Host "User: $UserID, Temporary Access Pass: ***********, Expiration: $ExpiresIn" -ForegroundColor Green
                        } else {
                            Write-Host "User: $UserID, Temporary Access Pass: $tap, Expiration: $ExpiresIn" -ForegroundColor Green
                        }
                        
                        if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                            $logObject = @{
                                Task = "TAP creation"
                                UserId = $UserID
                                ExpiresIn = $ExpiresIn
                                IsUsableOnce = $IsUsableOnce
                                Result = "Success"
                            }
                            $logObject | Write-ActivityToLogAnalytics
                        }
                    }
                    catch {
                        $errorMessage = "Failed to create TAP for user $UserID: $($_.Exception.Message)"
                        Write-Error $errorMessage
                        
                        if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                            $logObject = @{
                                Task = "TAP creation error"
                                UserId = $UserID
                                ExpiresIn = $ExpiresIn
                                IsUsableOnce = $IsUsableOnce
                                Result = "Error"
                                ErrorMessage = $_.Exception.Message
                            }
                            $logObject | Write-ActivityToLogAnalytics
                        }
                        
                        # Add error result
                        $results += [PSCustomObject]@{
                            Username = $UserID
                            TemporaryAccessPass = $null
                            SecureTemporaryAccessPass = $null
                            Expiration = $ExpiresIn
                            IsUsableOnce = $IsUsableOnce
                            StartTime = $null
                            EndTime = $null
                            Status = "Error"
                            ErrorMessage = $_.Exception.Message
                        }
                    }
                }
            }
            # Process bulk users
            else {
                Write-Verbose "$functionName - Processing bulk users from CSV: $BulkUserCSV"
                
                # Validate CSV file
                if (-not (Test-Path $BulkUserCSV -PathType Leaf)) {
                    throw "CSV file not found: $BulkUserCSV"
                }
                
                try {
                    # Import CSV and validate structure
                    $inputRecords = Import-Csv -Path $BulkUserCSV -ErrorAction Stop
                    
                    if ($inputRecords.Count -eq 0) {
                        throw "CSV file contains no records"
                    }
                    
                    if (-not ($inputRecords[0].PSObject.Properties.Name -contains 'work_email_address')) {
                        throw "CSV file must contain a 'work_email_address' column"
                    }
                    
                    # Count of users to process
                    $totalUsers = $inputRecords.Count
                    Write-Verbose "$functionName - Found $totalUsers users to process"
                    
                    # Confirm bulk operation
                    if (-not $Force -and $totalUsers -gt 5) {
                        $confirmMessage = "This will generate temporary access passes for $totalUsers users. Do you want to continue?"
                        if (-not $PSCmdlet.ShouldProcess($confirmMessage, "Generate TAPs for $totalUsers users", "Bulk TAP Generation Confirmation")) {
                            Write-Host "Operation cancelled." -ForegroundColor Yellow
                            return
                        }
                    }
                    
                    # Process each user
                    $progressCount = 0
                    foreach ($record in $inputRecords) {
                        $progressCount++
                        $userId = $record.work_email_address
                        
                        if ([string]::IsNullOrEmpty($userId)) {
                            Write-Warning "Skipping empty user ID at row $progressCount"
                            continue
                        }
                        
                        # Display progress
                        $progressParams = @{
                            Activity = "Generating Temporary Access Passes"
                            Status = "Processing $progressCount of $totalUsers"
                            PercentComplete = [math]::Round(($progressCount / $totalUsers) * 100)
                        }
                        Write-Progress @progressParams
                        
                        try {
                            # Create the TAP for this user
                            Write-Verbose "$functionName - Processing user #$progressCount : $userId"
                            
                            if ($PSCmdlet.ShouldProcess("User $userId", "Create temporary access pass")) {
                                $response = New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $userId -BodyParameter $propertiesJSON -ErrorAction Stop
                                $tap = $response.TemporaryAccessPass
                                
                                # Create secure string version if requested
                                $secureTap = if ($SecureOutput) {
                                    ConvertTo-SecureString $tap -AsPlainText -Force
                                } else {
                                    $null
                                }
                                
                                # Create result object
                                $result = [PSCustomObject]@{
                                    Username = $userId
                                    TemporaryAccessPass = if ($SecureOutput) { $null } else { $tap }
                                    SecureTemporaryAccessPass = $secureTap
                                    Expiration = $ExpiresIn
                                    IsUsableOnce = $IsUsableOnce
                                    StartTime = $startDateTimeForTAP
                                    EndTime = $startDateTimeForTAP.AddMinutes($lifetimeMinutes)
                                    Status = "Success"
                                }
                                
                                # Add to results collection
                                $results += $result
                                
                                # Display output
                                if ($HidePasswords) {
                                    Write-Host "User: $userId, Temporary Access Pass: ***********, Expiration: $ExpiresIn" -ForegroundColor Green
                                } else {
                                    Write-Host "User: $userId, Temporary Access Pass: $tap, Expiration: $ExpiresIn" -ForegroundColor Green
                                }
                                
                                if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                                    $logObject = @{
                                        Task = "TAP creation"
                                        UserId = $userId
                                        ExpiresIn = $ExpiresIn
                                        IsUsableOnce = $IsUsableOnce
                                        Result = "Success"
                                    }
                                    $logObject | Write-ActivityToLogAnalytics
                                }
                            }
                        }
                        catch {
                            $errorMessage = "Failed to create TAP for user $userId: $($_.Exception.Message)"
                            Write-Error $errorMessage
                            
                            if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                                $logObject = @{
                                    Task = "TAP creation error"
                                    UserId = $userId
                                    ExpiresIn = $ExpiresIn
                                    IsUsableOnce = $IsUsableOnce
                                    Result = "Error"
                                    ErrorMessage = $_.Exception.Message
                                }
                                $logObject | Write-ActivityToLogAnalytics
                            }
                            
                            # Add error result
                            $results += [PSCustomObject]@{
                                Username = $userId
                                TemporaryAccessPass = $null
                                SecureTemporaryAccessPass = $null
                                Expiration = $ExpiresIn
                                IsUsableOnce = $IsUsableOnce
                                StartTime = $null
                                EndTime = $null
                                Status = "Error"
                                ErrorMessage = $_.Exception.Message
                            }
                        }
                    }
                    
                    Write-Progress -Activity "Generating Temporary Access Passes" -Completed
                    
                    # Export results to CSV if there are any successful records
                    $successfulResults = $results | Where-Object { $_.Status -eq "Success" }
                    if ($successfulResults.Count -gt 0) {
                        try {
                            # Create a clean export version (no secure strings)
                            $exportResults = $results | Select-Object Username, 
                                                        @{Name = 'TemporaryAccessPass'; Expression = { if ($_.Status -eq 'Success') { if ($SecureOutput) { '******' } else { $_.TemporaryAccessPass } } else { $null } }}, 
                                                        Expiration, IsUsableOnce, StartTime, EndTime, Status, ErrorMessage
                            
                            $exportResults | Export-Csv -Path $OutputPath -NoTypeInformation -ErrorAction Stop
                            Write-Host "Results exported to: $OutputPath" -ForegroundColor Green
                            
                            if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                                $logObject = @{
                                    Task = "TAP export completed"
                                    TotalUsers = $totalUsers
                                    SuccessCount = $successfulResults.Count
                                    FailureCount = ($results | Where-Object { $_.Status -ne "Success" }).Count
                                    OutputPath = $OutputPath
                                }
                                $logObject | Write-ActivityToLogAnalytics
                            }
                        }
                        catch {
                            $errorMessage = "Failed to export results to CSV: $($_.Exception.Message)"
                            Write-Error $errorMessage
                            
                            if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                                $logObject = @{
                                    Task = "TAP export error"
                                    OutputPath = $OutputPath
                                    ErrorMessage = $_.Exception.Message
                                }
                                $logObject | Write-ActivityToLogAnalytics
                            }
                        }
                    }
                    else {
                        Write-Warning "No successful TAP creations to export"
                    }
                }
                catch {
                    $errorMessage = "Error processing bulk CSV file: $($_.Exception.Message)"
                    Write-Error $errorMessage
                    
                    if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                        $logObject = @{
                            Task = "Bulk TAP processing error"
                            CSVFile = $BulkUserCSV
                            ErrorMessage = $_.Exception.Message
                        }
                        $logObject | Write-ActivityToLogAnalytics
                    }
                    
                    throw
                }
            }
        }
        catch {
            $errorMessage = "Critical error in TAP creation: $($_.Exception.Message)"
            Write-Error $errorMessage
            Write-Error $_.ScriptStackTrace
            
            if ($LogActivities -and (Get-Command Write-ActivityToLogAnalytics -ErrorAction SilentlyContinue)) {
                $logObject = @{
                    Task = "TAP creation critical error"
                    ErrorMessage = $_.Exception.Message
                    StackTrace = $_.ScriptStackTrace
                }
                $logObject | Write-ActivityToLogAnalytics
            }
            
            throw
        }
    }
    
    end {
        Write-Verbose "$functionName - Temporary access pass generation completed"
        return $results
    }
}