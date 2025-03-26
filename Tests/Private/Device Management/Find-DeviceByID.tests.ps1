Describe "Find-DeviceById" {
    BeforeAll {
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
        
        Mock Write-Verbose { return $true }
    }

    Context "Successful Search" {
        It "Should find a device with the specified ID" {
            $device = Find-DeviceById -QuarantinedDevices $testDevices -DeviceId "Device123"
            $device | Should -Not -BeNullOrEmpty
            $device.DeviceId | Should -Be "Device123"
            $device.FriendlyName | Should -Be "iPhone"
        }
    }

    Context "Device Not Found" {
        It "Should return null when device ID is not found" {
            $device = Find-DeviceById -QuarantinedDevices $testDevices -DeviceId "NonExistentDevice"
            $device | Should -BeNullOrEmpty
        }
    }

    Context "Edge Cases" {
        It "Should handle case sensitivity correctly" {
            $device = Find-DeviceById -QuarantinedDevices $testDevices -DeviceId "device123"
            $device | Should -BeNullOrEmpty  # DeviceId matching is case-sensitive
        }

        It "Should handle empty device ID" {
            $device = Find-DeviceById -QuarantinedDevices $testDevices -DeviceId ""
            $device | Should -BeNullOrEmpty
        }
    }

    Context "Error Handling" {
        It "Should handle errors and rethrow them" {
            Mock Where-Object { throw "Search error" }
            
            { Find-DeviceById -QuarantinedDevices $testDevices -DeviceId "Device123" } | Should -Throw
        }
    }
}