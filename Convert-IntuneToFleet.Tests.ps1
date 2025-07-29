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

Describe "Logging Infrastructure" {
    BeforeAll {
        # Create test directory for logging tests
        $script:LogTestDir = Join-Path $TestDrive "LoggingTests"
        New-Item -Path $script:LogTestDir -ItemType Directory -Force | Out-Null
        
        # Define test log file paths
        $script:TestLogFile = Join-Path $script:LogTestDir "test_conversion.log"
        $script:TestOutputFile = Join-Path $script:LogTestDir "test_output.xml"
    }
    
    Context "Write-ConversionLog Function" {
        It "Should exist and be callable" {
            { Write-ConversionLog -Level "Info" -Message "Test message" -LogFilePath $script:TestLogFile } | Should -Not -Throw
        }
        
        It "Should create log file if it doesn't exist" {
            $newLogFile = Join-Path $script:LogTestDir "new_log.log"
            Write-ConversionLog -Level "Info" -Message "Test message" -LogFilePath $newLogFile
            Test-Path $newLogFile | Should -Be $true
        }
        
        It "Should write structured log entries with timestamps" {
            Write-ConversionLog -Level "Info" -Message "Test structured logging" -LogFilePath $script:TestLogFile
            
            $logContent = Get-Content $script:TestLogFile -Raw
            $logContent | Should -Match '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'  # Timestamp format
            $logContent | Should -Match '\[INFO\]'  # Log level
            $logContent | Should -Match 'Test structured logging'  # Message
        }
        
        It "Should support different log levels" {
            $levels = @("Debug", "Info", "Warning", "Error")
            
            foreach ($level in $levels) {
                Write-ConversionLog -Level $level -Message "Test $level message" -LogFilePath $script:TestLogFile
            }
            
            $logContent = Get-Content $script:TestLogFile -Raw
            foreach ($level in $levels) {
                $logContent | Should -Match "\[$($level.ToUpper())\]"
            }
        }
        
        It "Should append to existing log file" {
            $freshLogFile = Join-Path $script:LogTestDir "append_test.log"
            Write-ConversionLog -Level "Info" -Message "First message" -LogFilePath $freshLogFile
            Write-ConversionLog -Level "Info" -Message "Second message" -LogFilePath $freshLogFile
            
            $logLines = Get-Content $freshLogFile
            $logLines | Should -HaveCount 2
            $logLines[0] | Should -Match "First message"
            $logLines[1] | Should -Match "Second message"
        }
        
        It "Should handle console output parameter" {
            Mock Write-Host { }
            
            Write-ConversionLog -Level "Info" -Message "Console test" -LogFilePath $script:TestLogFile -ShowOnConsole
            
            Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Console test*" }
        }
        
        It "Should not show debug messages on console by default" {
            Mock Write-Host { }
            
            Write-ConversionLog -Level "Debug" -Message "Debug test" -LogFilePath $script:TestLogFile -ShowOnConsole
            
            Assert-MockCalled Write-Host -Times 0
        }
        
        It "Should show debug messages on console when DebugPreference is set" {
            Mock Write-Host { }
            
            $originalDebugPreference = $DebugPreference
            $DebugPreference = "Continue"
            
            try {
                Write-ConversionLog -Level "Debug" -Message "Debug test" -LogFilePath $script:TestLogFile -ShowOnConsole
                Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Debug test*" }
            }
            finally {
                $DebugPreference = $originalDebugPreference
            }
        }
    }
    
    Context "Get-LogFilePath Helper Function" {
        It "Should exist and be callable" {
            { Get-LogFilePath -OutputFile $script:TestOutputFile } | Should -Not -Throw
        }
        
        It "Should generate log file path based on output file" {
            $logPath = Get-LogFilePath -OutputFile $script:TestOutputFile
            $logPath | Should -Match "test_output\.log$"
        }
        
        It "Should handle output files without extensions" {
            $outputWithoutExt = Join-Path $script:LogTestDir "no_extension"
            $logPath = Get-LogFilePath -OutputFile $outputWithoutExt
            $logPath | Should -Match "no_extension\.log$"
        }
        
        It "Should place log file in same directory as output file" {
            $logPath = Get-LogFilePath -OutputFile $script:TestOutputFile
            Split-Path $logPath -Parent | Should -Be $script:LogTestDir
        }
    }
    
    Context "Integration with Main Function" {
        It "Should initialize logging when Convert-IntuneToFleet is called" {
            Mock Write-ConversionLog { }
            Mock Test-IntuneJsonFile { return [PSCustomObject]@{ IsValid = $true; ErrorMessage = ""; FilePath = $FilePath } }
            Mock Test-OutputPath { return [PSCustomObject]@{ IsValid = $true; ErrorMessage = ""; FilePath = $FilePath } }
            
            Convert-IntuneToFleet -InputFile $script:TestJsonFile -OutputFile $script:TestOutputFile -WhatIf
            
            Assert-MockCalled Write-ConversionLog -ParameterFilter { $Level -eq "Info" -and $Message -like "*Starting conversion*" }
        }
        
        It "Should log validation steps" {
            Mock Write-ConversionLog { }
            Mock Test-IntuneJsonFile { return [PSCustomObject]@{ IsValid = $true; ErrorMessage = ""; FilePath = $FilePath } }
            Mock Test-OutputPath { return [PSCustomObject]@{ IsValid = $true; ErrorMessage = ""; FilePath = $FilePath } }
            
            Convert-IntuneToFleet -InputFile $script:TestJsonFile -OutputFile $script:TestOutputFile -WhatIf
            
            Assert-MockCalled Write-ConversionLog -ParameterFilter { $Level -eq "Info" -and $Message -like "*validation passed*" }
        }
        
        It "Should log errors when validation fails" {
            Mock Write-ConversionLog { }
            Mock Test-IntuneJsonFile { return [PSCustomObject]@{ IsValid = $false; ErrorMessage = "Test validation error"; FilePath = $FilePath } }
            
            { Convert-IntuneToFleet -InputFile $script:TestJsonFile -WhatIf } | Should -Throw
            
            Assert-MockCalled Write-ConversionLog -ParameterFilter { $Level -eq "Error" -and $Message -like "*Test validation error*" }
        }
        
        It "Should replace Write-Host calls with logging system" {
            Mock Write-ConversionLog { }
            Mock Test-IntuneJsonFile { return [PSCustomObject]@{ IsValid = $true; ErrorMessage = ""; FilePath = $FilePath } }
            Mock Test-OutputPath { return [PSCustomObject]@{ IsValid = $true; ErrorMessage = ""; FilePath = $FilePath } }
            Mock Write-Host { }
            
            Convert-IntuneToFleet -WhatIf
            
            # Should use logging instead of Write-Host for interactive mode message
            Assert-MockCalled Write-ConversionLog -ParameterFilter { $Message -like "*interactive mode*" }
            Assert-MockCalled Write-Host -Times 0
        }
    }
    
    Context "Log File Management" {
        It "Should handle concurrent logging safely" {
            $concurrentLogFile = Join-Path $script:LogTestDir "concurrent_test.log"
            $jobs = @()
            
            for ($i = 1; $i -le 5; $i++) {
                $jobs += Start-Job -ScriptBlock {
                    param($LogFile, $ScriptPath, $Message)
                    . $ScriptPath
                    Write-ConversionLog -Level "Info" -Message $Message -LogFilePath $LogFile
                } -ArgumentList $concurrentLogFile, "$PSScriptRoot\Convert-IntuneToFleet.ps1", "Concurrent message $i"
            }
            
            $jobs | Wait-Job | Remove-Job
            
            # Wait a moment for file system to settle
            Start-Sleep -Milliseconds 100
            
            $logContent = Get-Content $concurrentLogFile
            $logContent | Should -HaveCount 5
            $logContent | ForEach-Object { $_ | Should -Match "Concurrent message \d+" }
        }
        
        It "Should handle log file permission errors gracefully" {
            if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
                $readOnlyLog = Join-Path $script:LogTestDir "readonly.log"
                New-Item -Path $readOnlyLog -ItemType File -Force | Out-Null
                Set-ItemProperty -Path $readOnlyLog -Name IsReadOnly -Value $true
                
                { Write-ConversionLog -Level "Info" -Message "Test" -LogFilePath $readOnlyLog } | Should -Not -Throw
                
                # Clean up
                Set-ItemProperty -Path $readOnlyLog -Name IsReadOnly -Value $false
                Remove-Item -Path $readOnlyLog -Force
            } else {
                Set-ItResult -Skipped -Because "Read-only file test not supported on this platform"
            }
        }
    }
}

Describe "JSON Parser Foundation" {
    BeforeAll {
        # Create test directory for JSON parsing tests
        $script:JsonTestDir = Join-Path $TestDrive "JsonParsingTests"
        New-Item -Path $script:JsonTestDir -ItemType Directory -Force | Out-Null
        
        # Create comprehensive test JSON based on firewall example structure
        $script:CompleteIntuneJson = @{
            "@odata.context" = "https://graph.microsoft.com/beta/`$metadata#deviceManagement/configurationPolicies/`$entity"
            "createdDateTime" = "2024-10-27T17:24:38.080948Z"
            "description" = "Enable firewall for public and private profiles"
            "lastModifiedDateTime" = "2025-03-31T21:03:29.7043237Z"
            "name" = "Enable public and private firewall"
            "platforms" = "windows10"
            "settingCount" = 2
            "technologies" = "mdm"
            "id" = "b35539e6-4421-4844-82e3-79c7d566c406"
            "settings" = @(
                @{
                    "id" = "0"
                    "settingInstance" = @{
                        "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"
                        "settingDefinitionId" = "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall"
                        "choiceSettingValue" = @{
                            "value" = "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall_true"
                            "children" = @(
                                @{
                                    "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"
                                    "settingDefinitionId" = "vendor_msft_firewall_mdmstore_privateprofile_allowlocalipsecpolicymerge"
                                    "choiceSettingValue" = @{
                                        "value" = "vendor_msft_firewall_mdmstore_privateprofile_allowlocalipsecpolicymerge_true"
                                        "children" = @()
                                    }
                                }
                            )
                        }
                    }
                },
                @{
                    "id" = "1"
                    "settingInstance" = @{
                        "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"
                        "settingDefinitionId" = "vendor_msft_firewall_mdmstore_publicprofile_enablefirewall"
                        "choiceSettingValue" = @{
                            "value" = "vendor_msft_firewall_mdmstore_publicprofile_enablefirewall_true"
                            "children" = @()
                        }
                    }
                }
            )
        } | ConvertTo-Json -Depth 10
        
        $script:CompleteJsonPath = Join-Path $script:JsonTestDir "complete_firewall.json"
        Set-Content -Path $script:CompleteJsonPath -Value $script:CompleteIntuneJson
        
        # Create minimal valid JSON
        $script:MinimalIntuneJson = @{
            "@odata.context" = "https://graph.microsoft.com/beta/`$metadata#test"
            "name" = "Minimal Test Policy"
            "settings" = @()
        } | ConvertTo-Json -Depth 5
        
        $script:MinimalJsonPath = Join-Path $script:JsonTestDir "minimal.json"
        Set-Content -Path $script:MinimalJsonPath -Value $script:MinimalIntuneJson
        
        # Create JSON with simple setting type
        $script:SimpleSettingJson = @{
            "@odata.context" = "https://graph.microsoft.com/beta/`$metadata#test"
            "name" = "Simple Setting Test"
            "settings" = @(
                @{
                    "id" = "0"
                    "settingInstance" = @{
                        "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance"
                        "settingDefinitionId" = "test_simple_setting"
                        "simpleSettingValue" = @{
                            "@odata.type" = "#microsoft.graph.deviceManagementConfigurationStringSettingValue"
                            "value" = "test string value"
                        }
                    }
                }
            )
        } | ConvertTo-Json -Depth 10
        
        $script:SimpleSettingJsonPath = Join-Path $script:JsonTestDir "simple_setting.json"
        Set-Content -Path $script:SimpleSettingJsonPath -Value $script:SimpleSettingJson
    }
    
    Context "Get-IntuneSettings Function" {
        It "Should exist and be callable" {
            { Get-IntuneSettings -FilePath $script:CompleteJsonPath } | Should -Not -Throw
        }
        
        It "Should return structured PowerShell object" {
            $result = Get-IntuneSettings -FilePath $script:CompleteJsonPath
            $result | Should -BeOfType [PSCustomObject]
            $result.PSObject.Properties.Name | Should -Contain "Metadata"
            $result.PSObject.Properties.Name | Should -Contain "Settings"
            $result.PSObject.Properties.Name | Should -Contain "ParsedSuccessfully"
        }
        
        It "Should extract basic metadata correctly" {
            $result = Get-IntuneSettings -FilePath $script:CompleteJsonPath
            
            $result.Metadata | Should -BeOfType [PSCustomObject]
            $result.Metadata.Name | Should -Be "Enable public and private firewall"
            $result.Metadata.Description | Should -Be "Enable firewall for public and private profiles"
            $result.Metadata.SettingCount | Should -Be 2
            $result.Metadata.Id | Should -Be "b35539e6-4421-4844-82e3-79c7d566c406"
            $result.Metadata.Platforms | Should -Be "windows10"
            $result.Metadata.Technologies | Should -Be "mdm"
        }
        
        It "Should handle missing optional metadata gracefully" {
            $result = Get-IntuneSettings -FilePath $script:MinimalJsonPath
            
            $result.Metadata.Name | Should -Be "Minimal Test Policy"
            $result.Metadata.Description | Should -BeNullOrEmpty
            $result.Metadata.SettingCount | Should -Be 0
        }
        
        It "Should parse settings array structure" {
            $result = Get-IntuneSettings -FilePath $script:CompleteJsonPath
            
            $result.Settings | Should -BeOfType [Array]
            $result.Settings.Count | Should -Be 2
            $result.Settings[0].Id | Should -Be "0"
            $result.Settings[1].Id | Should -Be "1"
        }
        
        It "Should handle empty settings array" {
            $result = Get-IntuneSettings -FilePath $script:MinimalJsonPath
            
            $result.Settings | Should -BeOfType [Array]
            $result.Settings.Count | Should -Be 0
        }
        
        It "Should preserve original setting structure" {
            $result = Get-IntuneSettings -FilePath $script:CompleteJsonPath
            
            $firstSetting = $result.Settings[0]
            $firstSetting.SettingInstance | Should -Not -BeNullOrEmpty
            $firstSetting.SettingInstance.settingDefinitionId | Should -Be "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall"
            $firstSetting.SettingInstance.choiceSettingValue | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle different setting types (choice vs simple)" {
            $result = Get-IntuneSettings -FilePath $script:SimpleSettingJsonPath
            
            $setting = $result.Settings[0]
            $setting.SettingInstance.'@odata.type' | Should -Be "#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance"
            $setting.SettingInstance.simpleSettingValue | Should -Not -BeNullOrEmpty
        }
        
        It "Should track parsing success status" {
            $result = Get-IntuneSettings -FilePath $script:CompleteJsonPath
            $result.ParsedSuccessfully | Should -Be $true
        }
        
        It "Should handle malformed JSON gracefully" {
            $malformedJsonPath = Join-Path $script:JsonTestDir "malformed.json"
            Set-Content -Path $malformedJsonPath -Value '{"invalid": json syntax'
            
            $result = Get-IntuneSettings -FilePath $malformedJsonPath
            $result.ParsedSuccessfully | Should -Be $false
            $result.ErrorMessage | Should -Match "JSON|parse|syntax"
        }
        
        It "Should validate required Intune structure" {
            $invalidStructurePath = Join-Path $script:JsonTestDir "invalid_structure.json"
            $invalidJson = @{ "someProperty" = "value" } | ConvertTo-Json
            Set-Content -Path $invalidStructurePath -Value $invalidJson
            
            $result = Get-IntuneSettings -FilePath $invalidStructurePath
            $result.ParsedSuccessfully | Should -Be $false
            $result.ErrorMessage | Should -Match "Intune|structure|format"
        }
        
        It "Should handle large JSON files efficiently" {
            # Create a larger JSON file with many settings
            $largeSettings = @()
            for ($i = 0; $i -lt 50; $i++) {
                $largeSettings += @{
                    "id" = "$i"
                    "settingInstance" = @{
                        "settingDefinitionId" = "test_setting_$i"
                        "choiceSettingValue" = @{
                            "value" = "test_value_$i"
                            "children" = @()
                        }
                    }
                }
            }
            
            $largeJson = @{
                "@odata.context" = "https://graph.microsoft.com/beta/`$metadata#test"
                "name" = "Large Test Policy"
                "settingCount" = 50
                "settings" = $largeSettings
            } | ConvertTo-Json -Depth 10
            
            $largeJsonPath = Join-Path $script:JsonTestDir "large.json"
            Set-Content -Path $largeJsonPath -Value $largeJson
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Get-IntuneSettings -FilePath $largeJsonPath
            $stopwatch.Stop()
            
            $result.ParsedSuccessfully | Should -Be $true
            $result.Settings.Count | Should -Be 50
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000  # Should complete within 5 seconds
        }
    }
    
    Context "Integration with Existing Systems" {
        It "Should integrate with file validation from Step 2" {
            Mock Test-IntuneJsonFile { return [PSCustomObject]@{ IsValid = $true; ErrorMessage = ""; FilePath = $FilePath } }
            
            $result = Get-IntuneSettings -FilePath $script:CompleteJsonPath
            
            Assert-MockCalled Test-IntuneJsonFile -Exactly 1
            $result.ParsedSuccessfully | Should -Be $true
        }
        
        It "Should handle validation failures gracefully" {
            Mock Test-IntuneJsonFile { return [PSCustomObject]@{ IsValid = $false; ErrorMessage = "Test validation error"; FilePath = $FilePath } }
            
            $result = Get-IntuneSettings -FilePath $script:CompleteJsonPath
            
            $result.ParsedSuccessfully | Should -Be $false
            $result.ErrorMessage | Should -Match "Test validation error"
        }
        
        It "Should integrate with logging system from Step 3" {
            Mock Write-ConversionLog { }
            
            $result = Get-IntuneSettings -FilePath $script:CompleteJsonPath -LogFilePath "test.log"
            
            Assert-MockCalled Write-ConversionLog -ParameterFilter { $Level -eq "Info" -and $Message -like "*JSON parsing*" }
        }
        
        It "Should log parsing errors appropriately" {
            Mock Write-ConversionLog { }
            $malformedJsonPath = Join-Path $script:JsonTestDir "malformed2.json"
            Set-Content -Path $malformedJsonPath -Value '{"broken": json'
            
            $result = Get-IntuneSettings -FilePath $malformedJsonPath -LogFilePath "test.log"
            
            Assert-MockCalled Write-ConversionLog -ParameterFilter { $Level -eq "Error" -and ($Message -like "*parsing failed*" -or $Message -like "*validation failed*") }
        }
    }
    
    Context "Error Handling and Edge Cases" {
        It "Should handle file not found errors" {
            $nonExistentPath = Join-Path $script:JsonTestDir "nonexistent.json"
            
            $result = Get-IntuneSettings -FilePath $nonExistentPath
            
            $result.ParsedSuccessfully | Should -Be $false
            $result.ErrorMessage | Should -Match "not found|does not exist"
        }
        
        It "Should handle permission denied errors" {
            if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
                $restrictedPath = Join-Path $script:JsonTestDir "restricted.json"
                Set-Content -Path $restrictedPath -Value $script:MinimalIntuneJson
                Set-ItemProperty -Path $restrictedPath -Name IsReadOnly -Value $true
                
                # This should still work on most systems, but test the error handling pattern
                $result = Get-IntuneSettings -FilePath $restrictedPath
                $result | Should -Not -BeNullOrEmpty
                
                # Clean up
                Set-ItemProperty -Path $restrictedPath -Name IsReadOnly -Value $false
                Remove-Item -Path $restrictedPath -Force
            } else {
                Set-ItResult -Skipped -Because "Permission test not supported on this platform"
            }
        }
        
        It "Should provide detailed error context" {
            $result = Get-IntuneSettings -FilePath $script:CompleteJsonPath
            
            # Should include parsing context information
            $result.PSObject.Properties.Name | Should -Contain "FilePath"
            $result.FilePath | Should -Be $script:CompleteJsonPath
        }
    }
}