BeforeAll {
    # Import the script under test
    . $PSScriptRoot\Convert-IntuneToFleet.ps1
    
    # Create a valid test JSON file for parameter binding tests
    $script:TestJsonFile = Join-Path $TestDrive "parameter_test.json"
    $testJson = @{
        "@odata.context" = "https://graph.microsoft.com/beta/\$metadata#deviceManagement/configurationPolicies/\$entity"
        "name" = "Parameter Test Policy"
        "settings" = @()
    } | ConvertTo-Json -Depth 5
    Set-Content -Path $script:TestJsonFile -Value $testJson
}

Describe "Convert-IntuneToFleet Parameter Handling" {
    Context "Parameter Binding" {
        It "Should accept InputFile parameter" {
            { Convert-IntuneToFleet -InputFile $script:TestJsonFile -WhatIf } | Should -Not -Throw
        }

        It "Should accept OutputFile parameter" {
            { Convert-IntuneToFleet -OutputFile "test.xml" -WhatIf } | Should -Not -Throw
        }

        It "Should accept both InputFile and OutputFile parameters" {
            { Convert-IntuneToFleet -InputFile $script:TestJsonFile -OutputFile "test.xml" -WhatIf } | Should -Not -Throw
        }

        It "Should support WhatIf parameter" {
            $result = Convert-IntuneToFleet -InputFile $script:TestJsonFile -OutputFile "test.xml" -WhatIf
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should support Verbose parameter" {
            { Convert-IntuneToFleet -InputFile $script:TestJsonFile -OutputFile "test.xml" -Verbose -WhatIf } | Should -Not -Throw
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
            { Convert-IntuneToFleet -InputFile $script:TestJsonFile -OutputFile "test.xml" -WhatIf } | Should -Not -Throw
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

Describe "File I/O and Validation Framework" {
    BeforeAll {
        # Create test directory for file operations
        $script:TestDir = Join-Path $TestDrive "FileValidationTests"
        New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null
        
        # Create valid Intune JSON test file
        $script:ValidIntuneJson = @{
            "@odata.context" = "https://graph.microsoft.com/beta/\$metadata#deviceManagement/configurationPolicies/\$entity"
            "name" = "Test Policy"
            "settings" = @(
                @{
                    "settingInstance" = @{
                        "settingDefinitionId" = "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall"
                        "choiceSettingValue" = @{
                            "value" = "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall_true"
                        }
                    }
                }
            )
        } | ConvertTo-Json -Depth 10
        
        $script:ValidJsonPath = Join-Path $script:TestDir "valid_intune.json"
        Set-Content -Path $script:ValidJsonPath -Value $script:ValidIntuneJson
        
        # Create invalid JSON test file
        $script:InvalidJsonPath = Join-Path $script:TestDir "invalid.json"
        Set-Content -Path $script:InvalidJsonPath -Value '{"invalid": json syntax'
        
        # Create valid JSON but wrong format test file
        $script:WrongFormatJsonPath = Join-Path $script:TestDir "wrong_format.json"
        Set-Content -Path $script:WrongFormatJsonPath -Value '{"someProperty": "value"}'
        
        # Create read-only test file path
        $script:ReadOnlyPath = Join-Path $script:TestDir "readonly.json"
        Set-Content -Path $script:ReadOnlyPath -Value $script:ValidIntuneJson
        if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
            Set-ItemProperty -Path $script:ReadOnlyPath -Name IsReadOnly -Value $true
        } else {
            chmod 444 $script:ReadOnlyPath
        }
    }
    
    Context "Test-IntuneJsonFile Function" {
        It "Should exist and be callable" {
            { Test-IntuneJsonFile -FilePath "dummy.json" } | Should -Not -Throw
        }
        
        It "Should return structured validation result" {
            $result = Test-IntuneJsonFile -FilePath $script:ValidJsonPath
            $result | Should -BeOfType [PSCustomObject]
            $result.PSObject.Properties.Name | Should -Contain "IsValid"
            $result.PSObject.Properties.Name | Should -Contain "ErrorMessage"
            $result.PSObject.Properties.Name | Should -Contain "FilePath"
        }
        
        It "Should validate existing valid Intune JSON file" {
            $result = Test-IntuneJsonFile -FilePath $script:ValidJsonPath
            $result.IsValid | Should -Be $true
            $result.ErrorMessage | Should -BeNullOrEmpty
            $result.FilePath | Should -Be $script:ValidJsonPath
        }
        
        It "Should fail validation for non-existent file" {
            $nonExistentPath = Join-Path $script:TestDir "nonexistent.json"
            $result = Test-IntuneJsonFile -FilePath $nonExistentPath
            $result.IsValid | Should -Be $false
            $result.ErrorMessage | Should -Match "not found|does not exist"
        }
        
        It "Should fail validation for invalid JSON syntax" {
            $result = Test-IntuneJsonFile -FilePath $script:InvalidJsonPath
            $result.IsValid | Should -Be $false
            $result.ErrorMessage | Should -Match "JSON|syntax|parse"
        }
        
        It "Should fail validation for wrong JSON format (missing settings array)" {
            $result = Test-IntuneJsonFile -FilePath $script:WrongFormatJsonPath
            $result.IsValid | Should -Be $false
            $result.ErrorMessage | Should -Match "Intune|settings|format"
        }
        
        It "Should fail validation for wrong JSON format (missing @odata.context)" {
            $noODataJson = @{
                "name" = "Test Policy"
                "settings" = @()
            } | ConvertTo-Json -Depth 5
            $noODataPath = Join-Path $script:TestDir "no_odata.json"
            Set-Content -Path $noODataPath -Value $noODataJson
            
            $result = Test-IntuneJsonFile -FilePath $noODataPath
            $result.IsValid | Should -Be $false
            $result.ErrorMessage | Should -Match "Intune|@odata.context|format"
        }
    }
    
    Context "Test-OutputPath Function" {
        It "Should exist and be callable" {
            { Test-OutputPath -FilePath "dummy.xml" } | Should -Not -Throw
        }
        
        It "Should return structured validation result" {
            $result = Test-OutputPath -FilePath "test.xml"
            $result | Should -BeOfType [PSCustomObject]
            $result.PSObject.Properties.Name | Should -Contain "IsValid"
            $result.PSObject.Properties.Name | Should -Contain "ErrorMessage"
            $result.PSObject.Properties.Name | Should -Contain "FilePath"
        }
        
        It "Should validate valid output path" {
            $validOutputPath = Join-Path $script:TestDir "output.xml"
            $result = Test-OutputPath -FilePath $validOutputPath
            $result.IsValid | Should -Be $true
            $result.ErrorMessage | Should -BeNullOrEmpty
        }
        
        It "Should fail validation for invalid directory" {
            if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
                $invalidPath = "Z:\NonExistentDrive\output.xml"
            } else {
                $invalidPath = "/nonexistent/deeply/nested/path/output.xml"
            }
            $result = Test-OutputPath -FilePath $invalidPath
            $result.IsValid | Should -Be $false
            $result.ErrorMessage | Should -Match "directory|path|access"
        }
        
        It "Should fail validation for read-only directory" {
            # Skip this test on non-Windows or if we can't create read-only directory
            if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
                $readOnlyDir = Join-Path $script:TestDir "readonly_dir"
                New-Item -Path $readOnlyDir -ItemType Directory -Force | Out-Null
                Set-ItemProperty -Path $readOnlyDir -Name IsReadOnly -Value $true
                
                $readOnlyOutputPath = Join-Path $readOnlyDir "output.xml"
                $result = Test-OutputPath -FilePath $readOnlyOutputPath
                $result.IsValid | Should -Be $false
                $result.ErrorMessage | Should -Match "permission|access|write"
                
                # Clean up
                Set-ItemProperty -Path $readOnlyDir -Name IsReadOnly -Value $false
                Remove-Item -Path $readOnlyDir -Recurse -Force
            } else {
                Set-ItResult -Skipped -Because "Read-only directory test not supported on this platform"
            }
        }
    }
    
    Context "Integration with Main Function" {
        It "Should use validation functions in main Convert-IntuneToFleet function" {
            Mock Test-IntuneJsonFile { return [PSCustomObject]@{ IsValid = $false; ErrorMessage = "Test validation failure"; FilePath = $FilePath } }
            
            { Convert-IntuneToFleet -InputFile $script:ValidJsonPath -WhatIf } | Should -Throw "Test validation failure"
            Assert-MockCalled Test-IntuneJsonFile -Exactly 1
        }
        
        It "Should validate output path in main function" {
            Mock Test-OutputPath { return [PSCustomObject]@{ IsValid = $false; ErrorMessage = "Output path validation failure"; FilePath = $FilePath } }
            Mock Test-IntuneJsonFile { return [PSCustomObject]@{ IsValid = $true; ErrorMessage = ""; FilePath = $FilePath } }
            
            { Convert-IntuneToFleet -InputFile $script:ValidJsonPath -OutputFile "test.xml" -WhatIf } | Should -Throw "Output path validation failure"
            Assert-MockCalled Test-OutputPath -Exactly 1
        }
        
        It "Should proceed when both validations pass" {
            Mock Test-IntuneJsonFile { return [PSCustomObject]@{ IsValid = $true; ErrorMessage = ""; FilePath = $FilePath } }
            Mock Test-OutputPath { return [PSCustomObject]@{ IsValid = $true; ErrorMessage = ""; FilePath = $FilePath } }
            
            $result = Convert-IntuneToFleet -InputFile $script:ValidJsonPath -OutputFile "test.xml" -WhatIf
            $result | Should -Not -BeNullOrEmpty
            Assert-MockCalled Test-IntuneJsonFile -Exactly 1
            Assert-MockCalled Test-OutputPath -Exactly 1
        }
    }
}