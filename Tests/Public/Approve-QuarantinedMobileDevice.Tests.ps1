Describe "Approve-QuarantinedMobileDevice" {
    BeforeAll {
        # Mock the required functions
        . $PSScriptRoot\..\..\Private\Mobile-Device-Management\Get-QuarantinedDevices.ps1
        . $PSScriptRoot\..\..\Private\Mobile-Device-Management\Select-QuarantinedDevice.ps1
        . $PSScriptRoot\..\..\Private\Mobile-Device-Management\Find-DeviceById.ps1
        . $PSScriptRoot\..\..\Private\Mobile-Device-Management\Approve-SelectedDevice.ps1
        . $PSScriptRoot\..\..\Private\Helpers\Write-ActivityLog.ps1
        
        Mock Test-ExchangeOnlineConnection { return $true }
        Mock Get-QuarantinedDevices { 
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
        Mock Select-QuarantinedDevice { 
            param($QuarantinedDevices)
            return $QuarantinedDevices[0] 
        }
        Mock Find-DeviceById { 
            param($QuarantinedDevices, $DeviceId)
            return $QuarantinedDevices | Where-Object { $_.DeviceId -eq $DeviceId }
        }
        Mock Approve-SelectedDevice { 
            param($UserId, $SelectedDevice)
            return [PSCustomObject]@{
                UserId = $UserId
                Status = "Approved"
                Message = "DeviceID $($SelectedDevice.DeviceId) has been approved for user $UserId."
                DeviceId = $SelectedDevice.DeviceId
                DeviceName = $SelectedDevice.FriendlyName
                DeviceModel = $SelectedDevice.DeviceModel
                DeviceType = $SelectedDevice.DeviceType
                Success = $true
            }
        }
        Mock Write-ActivityLog { return $true }
        Mock Write-Verbose { return $true }
    }

    Context "Parameter Validation" {
        It "Should require UserId parameter" {
            { Approve-QuarantinedMobileDevice -ErrorAction Stop } | Should -Throw -ErrorId "MissingArgument,Approve-QuarantinedMobileDevice"
        }

        It "Should require DeviceId when NonInteractive is specified" {
            { Approve-QuarantinedMobileDevice -UserId "user@contoso.com" -NonInteractive -ErrorAction Stop } | Should -Throw
        }
    }

    Context "Interactive Mode" {
        It "Should return success when approving a device in interactive mode" {
            $result = Approve-QuarantinedMobileDevice -UserId "user@contoso.com" -Force
            $result.Status | Should -Be "Approved"
            $result.Success | Should -Be $true
            Should -Invoke Select-QuarantinedDevice -Times 1 -Exactly
            Should -Invoke Approve-SelectedDevice -Times 1 -Exactly
        }

        It "Should handle when no device is selected" {
            Mock Select-QuarantinedDevice { return $null }
            
            $result = Approve-QuarantinedMobileDevice -UserId "user@contoso.com"
            $result.Status | Should -Be "Cancelled"
            $result.Success | Should -Be $false
            Should -Invoke Approve-SelectedDevice -Times 0 -Exactly
        }
    }

    Context "Non-Interactive Mode" {
        It "Should return success when specifying a device ID" {
            $result = Approve-QuarantinedMobileDevice -UserId "user@contoso.com" -DeviceId "Device123" -Force
            $result.Status | Should -Be "Approved"
            $result.Success | Should -Be $true
            $result.DeviceId | Should -Be "Device123"
            Should -Invoke Find-DeviceById -Times 1 -Exactly
            Should -Invoke Approve-SelectedDevice -Times 1 -Exactly
        }

        It "Should handle device ID not found" {
            Mock Find-DeviceById { return $null }
            
            $result = Approve-QuarantinedMobileDevice -UserId "user@contoso.com" -DeviceId "NonExistentDevice" -ErrorAction SilentlyContinue
            $result.Status | Should -Be "Error"
            $result.Success | Should -Be $false
            Should -Invoke Approve-SelectedDevice -Times 0 -Exactly
        }

        It "Should handle when no quarantined devices are found" {
            Mock Get-QuarantinedDevices { return $null }
            
            $result = Approve-QuarantinedMobileDevice -UserId "user@contoso.com"
            $result.Status | Should -Be "NoDevicesFound"
            $result.Success | Should -Be $false
            Should -Invoke Select-QuarantinedDevice -Times 0 -Exactly
            Should -Invoke Approve-SelectedDevice -Times 0 -Exactly
        }
    }

    Context "Error Handling" {
        It "Should handle connection failures" {
            Mock Test-ExchangeOnlineConnection { return $false }
            
            { Approve-QuarantinedMobileDevice -UserId "user@contoso.com" } | Should -Throw
            Should -Invoke Get-QuarantinedDevices -Times 0 -Exactly
        }

        It "Should handle approval failures" {
            Mock Approve-SelectedDevice { 
                return [PSCustomObject]@{
                    UserId = "user@contoso.com"
                    Status = "Error"
                    Message = "Failed to approve device"
                    DeviceId = "Device123"
                    Success = $false
                }
            }
            
            $result = Approve-QuarantinedMobileDevice -UserId "user@contoso.com" -DeviceId "Device123"
            $result.Status | Should -Be "Error"
            $result.Success | Should -Be $false
        }

        It "Should handle critical errors" {
            Mock Get-QuarantinedDevices { throw "Critical error" }
            
            $result = Approve-QuarantinedMobileDevice -UserId "user@contoso.com" -ErrorAction SilentlyContinue
            $result.Status | Should -Be "CriticalError"
            $result.Success | Should -Be $false
        }
    }
}