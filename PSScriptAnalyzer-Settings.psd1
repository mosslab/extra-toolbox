@{
    Severity = @('Error', 'Warning')
    IncludeRules = @('*')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSingularNouns'
    )
    Rules = @{
        PSUseCompatibleCommands = @{
            Enable = $true
            TargetProfiles = @(
                'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core'
                'win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
                'ubuntu_x64_18.04_7.0.0_x64_3.1.2_core'
            )
        }
        PSUseCompatibleSyntax = @{
            Enable = $true
            TargetVersions = @(
                '5.1',
                '7.0'
            )
        }
    }
}