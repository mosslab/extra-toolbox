Describe "Approve-SelectedDevice" {
    BeforeAll {
        # Mock the required functions
        . $PSScriptRoot\..\..\Private\Helpers\Write-ActivityLog.ps1
        
        $testDevice = [PSCustomObject]@{
            DeviceId = "Device123"
            FriendlyName = "iPhone"
            DeviceModel = "iPhone 13"
            DeviceType = "iPhone"
            DeviceOS = "iOS 15"
        }
        
        Mock Set-CASMailbox { return $true }
        Mock Write-ActivityLog { return $true }
        Mock Write-Host { return $true }
        Mock Write-Verbose { return $true }
        Mock Write-Error { return $true }
        Mock ShouldProcess { return $true } -ModuleName Approve-SelectedDevice
    }

    Context "Successful Approval" {
        It "Should approve the device and return success" {
            $result = Approve-SelectedDevice -UserId "user@contoso.com" -SelectedDevice $testDevice -Force
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Approved"
            $result.Success | Should -Be $true
            $result.DeviceId | Should -Be "Device123"
            Should -Invoke Set-CASMailbox -Times 1 -Exactly -ParameterFilter { $UserId -eq "user@contoso.com" }
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $ForegroundColor -eq "Green" }
        }
    }

    Context "Approval Failure" {
        It "Should handle CAS mailbox update failures" {
            Mock Set-CASMailbox { throw "Failed to update CAS mailbox" }
            
            $result = Approve-SelectedDevice -UserId "user@contoso.com" -SelectedDevice $testDevice -Force
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Error"
            $result.Success | Should -Be $false
            Should -Invoke Set-CASMailbox -Times 1 -Exactly
            Should -Invoke Write-Error -Times 1 -Exactly
        }
    }

    Context "Confirmation Handling" {
        It "Should respect ShouldProcess and skip approval when confirmation is denied" {
            Mock ShouldProcess { return $false } -ModuleName Approve-SelectedDevice
            
            $result = Approve-SelectedDevice -UserId "user@contoso.com" -SelectedDevice $testDevice
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Cancelled"
            $result.Success | Should -Be $false
            Should -Invoke Set-CASMailbox -Times 0 -Exactly
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $ForegroundColor -eq "Yellow" }
        }

        It "Should bypass confirmation when Force is specified" {
            Mock ShouldProcess { return $false } -ModuleName Approve-SelectedDevice
            
            $result = Approve-SelectedDevice -UserId "user@contoso.com" -SelectedDevice $testDevice -Force
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Approved"
            $result.Success | Should -Be $true
            Should -Invoke Set-CASMailbox -Times 1 -Exactly
        }

        It "Should bypass confirmation when NonInteractive is specified" {
            Mock ShouldProcess { return $false } -ModuleName Approve-SelectedDevice
            
            $result = Approve-SelectedDevice -UserId "user@contoso.com" -SelectedDevice $testDevice -NonInteractive
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Approved"
            $result.Success | Should -Be $true
            Should -Invoke Set-CASMailbox -Times 1 -Exactly
        }
    }

    Context "Logging" {
        It "Should log activities when LogActivities is specified" {
            $result = Approve-SelectedDevice -UserId "user@contoso.com" -SelectedDevice $testDevice -Force -LogActivities
            Should -Invoke Write-ActivityLog -Times 1 -Exactly -ParameterFilter { $Task -eq "Device approval" -and $Result -eq "Approved" }
            
            Mock Set-CASMailbox { throw "Failed to update CAS mailbox" }
            $result = Approve-SelectedDevice -UserId "user@contoso.com" -SelectedDevice $testDevice -Force -LogActivities
            Should -Invoke Write-ActivityLog -Times 1 -Exactly -ParameterFilter { $Task -eq "Device approval error" }
        }
    }
}