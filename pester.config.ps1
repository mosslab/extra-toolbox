# pester.config.ps1
@{
    Run = @{
        Path = "Tests"
        Exit = $true
    }
    CodeCoverage = @{
        Enabled = $true
        Path = "*.ps1"
        OutputFormat = "JaCoCo"
        OutputPath = "coverage.xml"
        CoveragePercentTarget = 80
    }
    TestResult = @{
        Enabled = $true
        OutputFormat = "NUnitXml"
        OutputPath = "TestResults.xml"
    }
    Output = @{
        Verbosity = "Detailed"
    }
}
}
