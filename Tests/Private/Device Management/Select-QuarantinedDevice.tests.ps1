Describe "Select-QuarantinedDevice" {
    BeforeAll {
        # Mock the required functions
        . $PSScriptRoot\..\..\Private\Helpers\Write-ActivityLog.ps1
        
        $testDevices = @(
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
        
        Mock Out-GridView { 
            return $testDevices[0]
        }
        Mock Write-ActivityLog { return $true }
        Mock Write-Host { return $true }
        Mock Write-Verbose { return $true }
        Mock Write-Warning { return $true }
        Mock Read-Host { return "0" }
    }

    Context "GridView Selection" {
        It "Should return the selected device from GridView" {
            $selectedDevice = Select-QuarantinedDevice -QuarantinedDevices $testDevices
            $selectedDevice | Should -Not -BeNullOrEmpty
            $selectedDevice.DeviceId | Should -Be "Device123"
            Should -Invoke Out-GridView -Times 1 -Exactly
        }

        It "Should handle when no device is selected in GridView" {
            Mock Out-GridView { return $null }
            
            $selectedDevice = Select-QuarantinedDevice -QuarantinedDevices $testDevices
            $selectedDevice | Should -BeNullOrEmpty
            Should -Invoke Write-Error -Times 1 -Exactly
        }
    }

    Context "Error Handling" {
        It "Should handle unexpected errors" {
            Mock Out-GridView { throw "Unexpected error" }
            Mock Select-DeviceFromConsole { throw "Console selection error" }
            
            { Select-QuarantinedDevice -QuarantinedDevices $testDevices } | Should -Throw
        }
    }

    Context "Logging" {
        It "Should log activities when LogActivities is specified" {
            Mock Out-GridView { return $null }
            
            $selectedDevice = Select-QuarantinedDevice -QuarantinedDevices $testDevices -LogActivities
            Should -Invoke Write-ActivityLog -Times 1 -Exactly
        }
    }
}Invoke Out-GridView -Times 1 -Exactly
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $ForegroundColor -eq "Yellow" }
        }
    }

    Context "Console Selection Fallback" {
        It "Should use console selection when GridView is not available" {
            Mock Out-GridView { throw "Out-GridView is not available" }
            
            $selectedDevice = Select-QuarantinedDevice -QuarantinedDevices $testDevices
            $selectedDevice | Should -Not -BeNullOrEmpty
            $selectedDevice.DeviceId | Should -Be "Device123"
            Should -Invoke Write-Warning -Times 1 -Exactly
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $ForegroundColor -eq "Cyan" }
            Should -Invoke Read-Host -Times 1 -Exactly
        }

        It "Should handle when user cancels console selection" {
            Mock Out-GridView { throw "Out-GridView is not available" }
            Mock Read-Host { return "q" }
            
            $selectedDevice = Select-QuarantinedDevice -QuarantinedDevices $testDevices
            $selectedDevice | Should -BeNullOrEmpty
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $ForegroundColor -eq "Yellow" }
        }

        It "Should handle invalid console selection" {
            Mock Out-GridView { throw "Out-GridView is not available" }
            Mock Read-Host { return "99" }
            
            $selectedDevice = Select-QuarantinedDevice -QuarantinedDevices $testDevices
            $selectedDevice | Should -BeNullOrEmpty
            Should -Invoke Write-Error -Times 1 -Exactly
        }

        It "Should handle non-numeric console selection" {
            Mock Out-GridView { throw "Out-GridView is not available" }
            Mock Read-Host { return "abc" }
            
            $selectedDevice = Select-QuarantinedDevice -QuarantinedDevices $testDevices
            $selectedDevice | Should -BeNullOrEmpty
            Should -