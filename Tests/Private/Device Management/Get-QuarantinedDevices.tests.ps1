Describe "Get-QuarantinedDevices" {
    BeforeAll {
        # Mock the required functions
        . $PSScriptRoot\..\..\Private\Helpers\Write-ActivityLog.ps1
        
        Mock Get-MobileDevice { 
            return @(
                [PSCustomObject]@{
                    DeviceId = "Device123"
                    FriendlyName = "iPhone"
                    DeviceModel = "iPhone 13"
                    DeviceType = "iPhone"
                    DeviceOS = "iOS 15"
                },
                [PSCustomObject]@{
                    DeviceId = "Device456"
                    FriendlyName = "Android Phone"
                    DeviceModel = "Pixel 6"
                    DeviceType = "AndroidPhone"
                    DeviceOS = "Android 12"
                }
            )
        }
        Mock Write-ActivityLog { return $true }
        Mock Write-Host { return $true }
        Mock Write-Verbose { return $true }
        Mock Format-Table { return $true }
    }

    Context "Successful Retrieval" {
        It "Should return quarantined devices when found" {
            $devices = Get-QuarantinedDevices -UserId "user@contoso.com"
            $devices | Should -Not -BeNullOrEmpty
            $devices.Count | Should -Be 2
            $devices[0].DeviceId | Should -Be "Device123"
            Should -Invoke Get-MobileDevice -Times 1 -Exactly
            Should -Invoke Write-Host -Times 2 -Exactly
        }
    }

    Context "No Devices Found" {
        It "Should return null when no quarantined devices are found" {
            Mock Get-MobileDevice { return @() }
            
            $devices = Get-QuarantinedDevices -UserId "user@contoso.com"
            $devices | Should -BeNullOrEmpty
            Should -Invoke Get-MobileDevice -Times 1 -Exactly
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $ForegroundColor -eq "Yellow" }
            Should -Invoke Write-ActivityLog -Times 1 -Exactly -ParameterFilter { $Task -eq "Quarantined device check" -and $Result -eq "No devices found" }
        }
    }

    Context "Error Handling" {
        It "Should throw an error when Get-MobileDevice fails" {
            Mock Get-MobileDevice { throw "Connection error" }
            
            { Get-QuarantinedDevices -UserId "user@contoso.com" } | Should -Throw
            Should -Invoke Write-ActivityLog -Times 1 -Exactly -ParameterFilter { $Task -eq "Quarantined device retrieval" -and $Result -eq "Error" }
        }
    }

    Context "Logging" {
        It "Should log activities when LogActivities is specified" {
            $devices = Get-QuarantinedDevices -UserId "user@contoso.com" -LogActivities
            Should -Invoke Write-ActivityLog -Times 0 -Exactly
            
            Mock Get-MobileDevice { return @() }
            $devices = Get-QuarantinedDevices -UserId "user@contoso.com" -LogActivities
            Should -Invoke Write-ActivityLog -Times 1 -Exactly
        }
    }
}