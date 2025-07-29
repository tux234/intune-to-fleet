BeforeAll {
    # Import the script under test
    . $PSScriptRoot\Convert-IntuneToFleet.ps1
}

Describe "Convert-IntuneToFleet Parameter Handling" {
    Context "Parameter Binding" {
        It "Should accept InputFile parameter" {
            { Convert-IntuneToFleet -InputFile "test.json" -WhatIf } | Should -Not -Throw
        }

        It "Should accept OutputFile parameter" {
            { Convert-IntuneToFleet -OutputFile "test.xml" -WhatIf } | Should -Not -Throw
        }

        It "Should accept both InputFile and OutputFile parameters" {
            { Convert-IntuneToFleet -InputFile "test.json" -OutputFile "test.xml" -WhatIf } | Should -Not -Throw
        }

        It "Should support WhatIf parameter" {
            $result = Convert-IntuneToFleet -InputFile "test.json" -OutputFile "test.xml" -WhatIf
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should support Verbose parameter" {
            { Convert-IntuneToFleet -InputFile "test.json" -OutputFile "test.xml" -Verbose -WhatIf } | Should -Not -Throw
        }
    }

    Context "Parameter Validation" {
        It "Should validate InputFile has .json extension" {
            { Convert-IntuneToFleet -InputFile "test.txt" -WhatIf } | Should -Throw
        }

        It "Should validate OutputFile has .xml extension" {
            { Convert-IntuneToFleet -OutputFile "test.txt" -WhatIf } | Should -Throw
        }

        It "Should accept valid file extensions" {
            { Convert-IntuneToFleet -InputFile "test.json" -OutputFile "test.xml" -WhatIf } | Should -Not -Throw
        }
    }

    Context "Help System" {
        It "Should have synopsis in help" {
            $help = Get-Help Convert-IntuneToFleet
            $help.Synopsis | Should -Not -BeNullOrEmpty
        }

        It "Should have description in help" {
            $help = Get-Help Convert-IntuneToFleet
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It "Should have parameter help for InputFile" {
            $help = Get-Help Convert-IntuneToFleet -Parameter InputFile
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It "Should have parameter help for OutputFile" {
            $help = Get-Help Convert-IntuneToFleet -Parameter OutputFile
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It "Should have examples in help" {
            $help = Get-Help Convert-IntuneToFleet
            $help.Examples | Should -Not -BeNullOrEmpty
        }
    }

    Context "No Parameters Provided" {
        It "Should not throw when no parameters provided" {
            { Convert-IntuneToFleet -WhatIf } | Should -Not -Throw
        }

        It "Should indicate interactive mode when no parameters provided" {
            Mock Write-Host { }
            Convert-IntuneToFleet -WhatIf
            Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*interactive*" }
        }
    }
}