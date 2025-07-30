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
            
            $result.Settings | Should -Not -BeNullOrEmpty
            $result.Settings.GetType().BaseType.Name | Should -Be "Array"
            $result.Settings.Count | Should -Be 2
            $result.Settings[0].Id | Should -Be "0"
            $result.Settings[1].Id | Should -Be "1"
        }
        
        It "Should handle empty settings array" {
            $result = Get-IntuneSettings -FilePath $script:MinimalJsonPath
            
            $result.Settings.Count | Should -Be 0
            # The Settings property should be a properly typed array even when empty
            if ($result.Settings) {
                $result.Settings.GetType().BaseType.Name | Should -Be "Array"
            }
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

Describe "Setting Extraction Engine" {
    BeforeAll {
        # Create test directory for setting extraction tests
        $script:ExtractionTestDir = Join-Path $TestDrive "SettingExtractionTests"
        New-Item -Path $script:ExtractionTestDir -ItemType Directory -Force | Out-Null
        
        # Create test JSON with nested settings for extraction testing
        $script:NestedSettingsJson = @{
            "@odata.context" = "https://graph.microsoft.com/beta/`$metadata#deviceManagement/configurationPolicies/`$entity"
            "name" = "Complex Nested Settings Test"
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
                                        "children" = @(
                                            @{
                                                "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"
                                                "settingDefinitionId" = "vendor_msft_firewall_mdmstore_privateprofile_nested_level3"
                                                "choiceSettingValue" = @{
                                                    "value" = "vendor_msft_firewall_mdmstore_privateprofile_nested_level3_enabled"
                                                    "children" = @()
                                                }
                                            }
                                        )
                                    }
                                }
                            )
                        }
                    }
                },
                @{
                    "id" = "1"
                    "settingInstance" = @{
                        "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance"
                        "settingDefinitionId" = "vendor_msft_policy_config_update_activehoursstart"
                        "simpleSettingValue" = @{
                            "@odata.type" = "#microsoft.graph.deviceManagementConfigurationIntegerSettingValue"
                            "value" = 8
                        }
                    }
                },
                @{
                    "id" = "2"
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
        } | ConvertTo-Json -Depth 15
        
        $script:NestedSettingsJsonPath = Join-Path $script:ExtractionTestDir "nested_settings.json"
        Set-Content -Path $script:NestedSettingsJsonPath -Value $script:NestedSettingsJson
        
        # Create simple settings test JSON
        $script:SimpleExtractionJson = @{
            "@odata.context" = "https://graph.microsoft.com/beta/`$metadata#test"
            "name" = "Simple Extraction Test"
            "settings" = @(
                @{
                    "id" = "0"
                    "settingInstance" = @{
                        "settingDefinitionId" = "simple_setting_only"
                        "choiceSettingValue" = @{
                            "value" = "simple_value"
                            "children" = @()
                        }
                    }
                }
            )
        } | ConvertTo-Json -Depth 10
        
        $script:SimpleExtractionJsonPath = Join-Path $script:ExtractionTestDir "simple_extraction.json"
        Set-Content -Path $script:SimpleExtractionJsonPath -Value $script:SimpleExtractionJson
    }
    
    Context "Get-AllSettingDefinitionIds Function" {
        It "Should exist and be callable" {
            { Get-AllSettingDefinitionIds -Settings @() } | Should -Not -Throw
        }
        
        It "Should return empty array for empty settings" {
            $result = Get-AllSettingDefinitionIds -Settings @()
            $result.Count | Should -Be 0
            # The result should be a properly typed array even when empty
            if ($result) {
                $result.GetType().BaseType.Name | Should -Be "Array"
            }
        }
        
        It "Should extract top-level settingDefinitionIds" {
            $parsedSettings = Get-IntuneSettings -FilePath $script:SimpleExtractionJsonPath
            $result = Get-AllSettingDefinitionIds -Settings $parsedSettings.Settings
            
            $result.Count | Should -Be 1
            $result[0].SettingDefinitionId | Should -Be "simple_setting_only"
            $result[0].Value | Should -Be "simple_value"
            $result[0].Path | Should -Be "settings[0]"
        }
        
        It "Should recursively extract nested children settingDefinitionIds" {
            $parsedSettings = Get-IntuneSettings -FilePath $script:NestedSettingsJsonPath
            $result = Get-AllSettingDefinitionIds -Settings $parsedSettings.Settings
            
            # Should find: privateprofile_enablefirewall, allowlocalipsecpolicymerge, nested_level3, activehoursstart, publicprofile_enablefirewall
            $result.Count | Should -Be 5
            
            $settingIds = $result | ForEach-Object { $_.SettingDefinitionId }
            $settingIds | Should -Contain "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall"
            $settingIds | Should -Contain "vendor_msft_firewall_mdmstore_privateprofile_allowlocalipsecpolicymerge"
            $settingIds | Should -Contain "vendor_msft_firewall_mdmstore_privateprofile_nested_level3"
            $settingIds | Should -Contain "vendor_msft_policy_config_update_activehoursstart"
            $settingIds | Should -Contain "vendor_msft_firewall_mdmstore_publicprofile_enablefirewall"
        }
        
        It "Should track path context for each extracted setting" {
            $parsedSettings = Get-IntuneSettings -FilePath $script:NestedSettingsJsonPath
            $result = Get-AllSettingDefinitionIds -Settings $parsedSettings.Settings
            
            # Check that paths are properly tracked
            $topLevelSetting = $result | Where-Object { $_.SettingDefinitionId -eq "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall" }
            $topLevelSetting.Path | Should -Be "settings[0]"
            
            $nestedSetting = $result | Where-Object { $_.SettingDefinitionId -eq "vendor_msft_firewall_mdmstore_privateprofile_allowlocalipsecpolicymerge" }
            $nestedSetting.Path | Should -Be "settings[0].children[0]"
            
            $deepNestedSetting = $result | Where-Object { $_.SettingDefinitionId -eq "vendor_msft_firewall_mdmstore_privateprofile_nested_level3" }
            $deepNestedSetting.Path | Should -Be "settings[0].children[0].children[0]"
        }
        
        It "Should handle both choiceSettingValue and simpleSettingValue types" {
            $parsedSettings = Get-IntuneSettings -FilePath $script:NestedSettingsJsonPath
            $result = Get-AllSettingDefinitionIds -Settings $parsedSettings.Settings
            
            $choiceSetting = $result | Where-Object { $_.SettingDefinitionId -eq "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall" }
            $choiceSetting.SettingType | Should -Be "choice"
            $choiceSetting.Value | Should -Be "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall_true"
            
            $simpleSetting = $result | Where-Object { $_.SettingDefinitionId -eq "vendor_msft_policy_config_update_activehoursstart" }
            $simpleSetting.SettingType | Should -Be "simple"
            $simpleSetting.Value | Should -Be 8
        }
        
        It "Should return structured objects with all required properties" {
            $parsedSettings = Get-IntuneSettings -FilePath $script:SimpleExtractionJsonPath
            $result = Get-AllSettingDefinitionIds -Settings $parsedSettings.Settings
            
            $setting = $result[0]
            $setting.PSObject.Properties.Name | Should -Contain "SettingDefinitionId"
            $setting.PSObject.Properties.Name | Should -Contain "Value"
            $setting.PSObject.Properties.Name | Should -Contain "SettingType"
            $setting.PSObject.Properties.Name | Should -Contain "Path"
            $setting.PSObject.Properties.Name | Should -Contain "OriginalSettingInstance"
        }
        
        It "Should preserve original setting instance for context" {
            $parsedSettings = Get-IntuneSettings -FilePath $script:SimpleExtractionJsonPath
            $result = Get-AllSettingDefinitionIds -Settings $parsedSettings.Settings
            
            $setting = $result[0]
            $setting.OriginalSettingInstance | Should -Not -BeNullOrEmpty
            $setting.OriginalSettingInstance.settingDefinitionId | Should -Be "simple_setting_only"
        }
        
        It "Should handle settings with no children gracefully" {
            $settingsWithNoChildren = @(
                [PSCustomObject]@{
                    Id = "0"
                    SettingInstance = [PSCustomObject]@{
                        settingDefinitionId = "test_no_children"
                        choiceSettingValue = [PSCustomObject]@{
                            value = "test_value"
                            children = @()
                        }
                    }
                }
            )
            
            $result = Get-AllSettingDefinitionIds -Settings $settingsWithNoChildren
            $result.Count | Should -Be 1
            $result[0].SettingDefinitionId | Should -Be "test_no_children"
        }
        
        It "Should handle missing children property gracefully" {
            $settingsWithoutChildrenProperty = @(
                [PSCustomObject]@{
                    Id = "0"
                    SettingInstance = [PSCustomObject]@{
                        settingDefinitionId = "test_no_children_prop"
                        choiceSettingValue = [PSCustomObject]@{
                            value = "test_value"
                        }
                    }
                }
            )
            
            $result = Get-AllSettingDefinitionIds -Settings $settingsWithoutChildrenProperty
            $result.Count | Should -Be 1
            $result[0].SettingDefinitionId | Should -Be "test_no_children_prop"
        }
        
        It "Should provide logging integration" {
            Mock Write-ConversionLog { }
            
            $parsedSettings = Get-IntuneSettings -FilePath $script:NestedSettingsJsonPath
            $result = Get-AllSettingDefinitionIds -Settings $parsedSettings.Settings -LogFilePath "test.log"
            
            Assert-MockCalled Write-ConversionLog -ParameterFilter { $Level -eq "Info" -and $Message -like "*Extracting*" }
        }
    }
    
    Context "Integration with JSON Parser" {
        It "Should work seamlessly with Get-IntuneSettings output" {
            $parsedSettings = Get-IntuneSettings -FilePath $script:NestedSettingsJsonPath
            
            { Get-AllSettingDefinitionIds -Settings $parsedSettings.Settings } | Should -Not -Throw
            
            $result = Get-AllSettingDefinitionIds -Settings $parsedSettings.Settings
            $result.Count | Should -BeGreaterThan 0
        }
        
        It "Should handle parsed settings from different JSON structures" {
            $simpleSettings = Get-IntuneSettings -FilePath $script:SimpleExtractionJsonPath
            $complexSettings = Get-IntuneSettings -FilePath $script:NestedSettingsJsonPath
            
            $simpleResult = Get-AllSettingDefinitionIds -Settings $simpleSettings.Settings
            $complexResult = Get-AllSettingDefinitionIds -Settings $complexSettings.Settings
            
            $simpleResult.Count | Should -Be 1
            $complexResult.Count | Should -Be 5
        }
    }
    
    Context "Error Handling and Edge Cases" {
        It "Should handle null or invalid settings input" {
            { Get-AllSettingDefinitionIds -Settings $null } | Should -Not -Throw
            $result = Get-AllSettingDefinitionIds -Settings $null
            $result.Count | Should -Be 0
        }
        
        It "Should handle settings with missing settingDefinitionId" {
            $invalidSettings = @(
                [PSCustomObject]@{
                    Id = "0"
                    SettingInstance = [PSCustomObject]@{
                        choiceSettingValue = [PSCustomObject]@{
                            value = "test_value"
                            children = @()
                        }
                    }
                }
            )
            
            { Get-AllSettingDefinitionIds -Settings $invalidSettings } | Should -Not -Throw
            $result = Get-AllSettingDefinitionIds -Settings $invalidSettings
            $result.Count | Should -Be 0  # Should skip invalid settings
        }
        
        It "Should handle corrupted setting structure gracefully" {
            $corruptedSettings = @(
                [PSCustomObject]@{
                    Id = "0"
                    # Missing SettingInstance property
                }
            )
            
            { Get-AllSettingDefinitionIds -Settings $corruptedSettings } | Should -Not -Throw
            $result = Get-AllSettingDefinitionIds -Settings $corruptedSettings
            $result.Count | Should -Be 0  # Should skip corrupted settings
        }
        
        It "Should log errors for invalid settings when logging enabled" {
            Mock Write-ConversionLog { }
            
            $invalidSettings = @(
                [PSCustomObject]@{
                    Id = "0"
                    SettingInstance = [PSCustomObject]@{
                        # Missing settingDefinitionId
                        choiceSettingValue = [PSCustomObject]@{
                            value = "test_value"
                        }
                    }
                }
            )
            
            Get-AllSettingDefinitionIds -Settings $invalidSettings -LogFilePath "test.log"
            
            Assert-MockCalled Write-ConversionLog -ParameterFilter { $Level -eq "Warning" -and $Message -like "*skipping*" }
        }
    }
    
    Context "Performance Testing" {
        It "Should handle large numbers of nested settings efficiently" {
            # Create a large number of nested settings
            $largeSettings = @()
            for ($i = 0; $i -lt 20; $i++) {
                $children = @()
                for ($j = 0; $j -lt 5; $j++) {
                    $children += [PSCustomObject]@{
                        "settingDefinitionId" = "child_setting_$i_$j"
                        "choiceSettingValue" = [PSCustomObject]@{
                            "value" = "child_value_$i_$j"
                            "children" = @()
                        }
                    }
                }
                
                $largeSettings += [PSCustomObject]@{
                    Id = "$i"
                    SettingInstance = [PSCustomObject]@{
                        settingDefinitionId = "parent_setting_$i"
                        choiceSettingValue = [PSCustomObject]@{
                            value = "parent_value_$i"
                            children = $children
                        }
                    }
                }
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Get-AllSettingDefinitionIds -Settings $largeSettings
            $stopwatch.Stop()
            
            $result.Count | Should -Be 120  # 20 parent + 100 children
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 3000  # Should complete within 3 seconds
        }
    }
}

Describe "Registry Mock Framework" {
    BeforeAll {
        # Create test directory for registry mock tests
        $script:RegistryTestDir = Join-Path $TestDrive "RegistryMockTests"
        New-Item -Path $script:RegistryTestDir -ItemType Directory -Force | Out-Null
        
        # Sample CSP registry data based on firewall example
        $script:MockCSPData = @{
            "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall" = @{
                NodeUri = "./Vendor/MSFT/Firewall/MdmStore/PrivateProfile/EnableFirewall"
                ExpectedValue = "true"
                DataType = "bool"
                AccessLevel = "Get,Replace"
            }
            "vendor_msft_firewall_mdmstore_privateprofile_allowlocalipsecpolicymerge" = @{
                NodeUri = "./Vendor/MSFT/Firewall/MdmStore/PrivateProfile/AllowLocalIpsecPolicyMerge"
                ExpectedValue = "true"
                DataType = "bool"
                AccessLevel = "Get,Replace"
            }
            "vendor_msft_firewall_mdmstore_publicprofile_enablefirewall" = @{
                NodeUri = "./Vendor/MSFT/Firewall/MdmStore/PublicProfile/EnableFirewall"
                ExpectedValue = "true"
                DataType = "bool"
                AccessLevel = "Get,Replace"
            }
            "vendor_msft_policy_config_update_activehoursstart" = @{
                NodeUri = "./Vendor/MSFT/Policy/Config/Update/ActiveHoursStart"
                ExpectedValue = "8"
                DataType = "int"
                AccessLevel = "Get,Replace"
            }
            "nonexistent_setting" = $null  # For testing missing entries
        }
    }
    
    Context "Get-CSPRegistryValue Interface" {
        It "Should exist and be callable" {
            { Get-CSPRegistryValue -SettingDefinitionId "test_setting" } | Should -Not -Throw
        }
        
        It "Should return structured registry lookup result" {
            $result = Get-CSPRegistryValue -SettingDefinitionId "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall"
            $result | Should -BeOfType [PSCustomObject]
            $result.PSObject.Properties.Name | Should -Contain "SettingDefinitionId"
            $result.PSObject.Properties.Name | Should -Contain "Found"
            $result.PSObject.Properties.Name | Should -Contain "NodeUri"
            $result.PSObject.Properties.Name | Should -Contain "ExpectedValue"
            $result.PSObject.Properties.Name | Should -Contain "DataType"
            $result.PSObject.Properties.Name | Should -Contain "ErrorMessage"
        }
        
        It "Should find known CSP registry entries" {
            Initialize-MockCSPRegistry -MockData $script:MockCSPData
            $result = Get-CSPRegistryValue -SettingDefinitionId "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall"
            
            $result.Found | Should -Be $true
            $result.SettingDefinitionId | Should -Be "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall"
            $result.NodeUri | Should -Be "./Vendor/MSFT/Firewall/MdmStore/PrivateProfile/EnableFirewall"
            $result.ExpectedValue | Should -Be "true"
            $result.DataType | Should -Be "bool"
            $result.ErrorMessage | Should -BeNullOrEmpty
        }
        
        It "Should handle missing registry entries gracefully" {
            $result = Get-CSPRegistryValue -SettingDefinitionId "nonexistent_setting_id"
            
            $result.Found | Should -Be $false
            $result.SettingDefinitionId | Should -Be "nonexistent_setting_id"
            $result.NodeUri | Should -BeNullOrEmpty
            $result.ExpectedValue | Should -BeNullOrEmpty
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
        }
        
        It "Should support different data types (bool, int, string)" {
            $boolResult = Get-CSPRegistryValue -SettingDefinitionId "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall"
            $intResult = Get-CSPRegistryValue -SettingDefinitionId "vendor_msft_policy_config_update_activehoursstart"
            
            $boolResult.DataType | Should -Be "bool"
            $boolResult.ExpectedValue | Should -Be "true"
            
            $intResult.DataType | Should -Be "int"
            $intResult.ExpectedValue | Should -Be "8"
        }
        
        It "Should provide logging integration" {
            Mock Write-ConversionLog { }
            
            $result = Get-CSPRegistryValue -SettingDefinitionId "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall" -LogFilePath "test.log"
            
            Assert-MockCalled Write-ConversionLog -ParameterFilter { $Level -eq "Info" -and $Message -like "*registry lookup*" }
        }
        
        It "Should handle registry access denied scenarios" {
            # Test with a setting that simulates access denied
            $result = Get-CSPRegistryValue -SettingDefinitionId "access_denied_setting"
            
            $result.Found | Should -Be $false
            $result.ErrorMessage | Should -Match "access.*denied|permission"
        }
        
        It "Should validate input parameters" {
            { Get-CSPRegistryValue -SettingDefinitionId "" } | Should -Throw
            { Get-CSPRegistryValue -SettingDefinitionId $null } | Should -Throw
        }
    }
    
    Context "Mock-CSPRegistry Implementation" {
        It "Should exist and be callable" {
            { Initialize-MockCSPRegistry -MockData $script:MockCSPData } | Should -Not -Throw
        }
        
        It "Should set up mock registry data correctly" {
            Initialize-MockCSPRegistry -MockData $script:MockCSPData
            
            $result = Get-CSPRegistryValue -SettingDefinitionId "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall"
            $result.Found | Should -Be $true
            $result.NodeUri | Should -Be "./Vendor/MSFT/Firewall/MdmStore/PrivateProfile/EnableFirewall"
        }
        
        It "Should support clearing mock data" {
            Initialize-MockCSPRegistry -MockData $script:MockCSPData
            Clear-MockCSPRegistry
            
            $result = Get-CSPRegistryValue -SettingDefinitionId "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall"
            $result.Found | Should -Be $false
        }
        
        It "Should allow adding individual mock entries" {
            Clear-MockCSPRegistry
            Add-MockCSPEntry -SettingDefinitionId "test_setting" -NodeUri "./Test/Path" -ExpectedValue "test_value" -DataType "string"
            
            $result = Get-CSPRegistryValue -SettingDefinitionId "test_setting"
            $result.Found | Should -Be $true
            $result.ExpectedValue | Should -Be "test_value"
            $result.DataType | Should -Be "string"
        }
        
        It "Should simulate registry error conditions" {
            Clear-MockCSPRegistry
            Add-MockCSPEntry -SettingDefinitionId "error_setting" -ErrorCondition "AccessDenied"
            
            $result = Get-CSPRegistryValue -SettingDefinitionId "error_setting"
            $result.Found | Should -Be $false
            $result.ErrorMessage | Should -Match "access.*denied"
        }
    }
    
    Context "Integration with Setting Extraction" {
        It "Should work with extracted settings from Step 5" {
            # Set up mock data
            Initialize-MockCSPRegistry -MockData $script:MockCSPData
            
            # Create test settings like those from Get-AllSettingDefinitionIds
            $extractedSettings = @(
                [PSCustomObject]@{
                    SettingDefinitionId = "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall"
                    Value = "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall_true"
                    SettingType = "choice"
                    Path = "settings[0]"
                    OriginalSettingInstance = @{}
                }
            )
            
            $result = Get-CSPRegistryValue -SettingDefinitionId $extractedSettings[0].SettingDefinitionId
            $result.Found | Should -Be $true
            $result.NodeUri | Should -Not -BeNullOrEmpty
        }
        
        It "Should process multiple settings efficiently" {
            Initialize-MockCSPRegistry -MockData $script:MockCSPData
            
            $settingIds = @(
                "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall",
                "vendor_msft_firewall_mdmstore_publicprofile_enablefirewall",
                "vendor_msft_policy_config_update_activehoursstart"
            )
            
            $results = @()
            foreach ($settingId in $settingIds) {
                $results += Get-CSPRegistryValue -SettingDefinitionId $settingId
            }
            
            $results.Count | Should -Be 3
            ($results | Where-Object { $_.Found }).Count | Should -Be 3
        }
    }
    
    Context "Error Handling and Edge Cases" {
        It "Should handle malformed mock data gracefully" {
            $malformedData = @{
                "bad_entry" = "not_an_object"
            }
            
            { Initialize-MockCSPRegistry -MockData $malformedData } | Should -Not -Throw
            
            $result = Get-CSPRegistryValue -SettingDefinitionId "bad_entry"
            $result.Found | Should -Be $false
        }
        
        It "Should provide detailed error context" {
            $result = Get-CSPRegistryValue -SettingDefinitionId "nonexistent_setting"
            
            $result.PSObject.Properties.Name | Should -Contain "SettingDefinitionId"
            $result.SettingDefinitionId | Should -Be "nonexistent_setting"
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
        }
        
        It "Should be thread-safe for concurrent lookups" {
            Initialize-MockCSPRegistry -MockData $script:MockCSPData
            
            $jobs = @()
            for ($i = 1; $i -le 5; $i++) {
                $jobs += Start-Job -ScriptBlock {
                    param($ScriptPath, $SettingId)
                    . $ScriptPath
                    Initialize-MockCSPRegistry -MockData @{
                        "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall" = @{
                            NodeUri = "./Vendor/MSFT/Firewall/MdmStore/PrivateProfile/EnableFirewall"
                            ExpectedValue = "true"
                            DataType = "bool"
                        }
                    }
                    Get-CSPRegistryValue -SettingDefinitionId $SettingId
                } -ArgumentList "$PSScriptRoot/Convert-IntuneToFleet.ps1", "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall"
            }
            
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job
            
            $results.Count | Should -Be 5
            ($results | Where-Object { $_.Found }).Count | Should -Be 5
        }
    }
    
    Context "Performance and Scalability" {
        It "Should handle large mock registry datasets efficiently" {
            # Create large mock dataset
            $largeMockData = @{}
            for ($i = 1; $i -le 100; $i++) {
                $largeMockData["test_setting_$i"] = @{
                    NodeUri = "./Test/Setting$i"
                    ExpectedValue = "value_$i"
                    DataType = "string"
                }
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Initialize-MockCSPRegistry -MockData $largeMockData
            $stopwatch.Stop()
            
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 1000  # Should complete within 1 second
            
            # Test lookup performance
            $stopwatch.Restart()
            $result = Get-CSPRegistryValue -SettingDefinitionId "test_setting_50"
            $stopwatch.Stop()
            
            $result.Found | Should -Be $true
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 100  # Should find entry within 100ms
        }
        
        It "Should maintain performance with multiple lookups" {
            Initialize-MockCSPRegistry -MockData $script:MockCSPData
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            for ($i = 1; $i -le 50; $i++) {
                Get-CSPRegistryValue -SettingDefinitionId "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall"
            }
            $stopwatch.Stop()
            
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 2000  # 50 lookups within 2 seconds
        }
    }
}

Describe "Registry Integration" {
    Context "Registry Functionality" {
        BeforeEach {
            Clear-MockCSPRegistry
        }
        
        It "Should exist and be callable" {
            { Get-CSPRegistryValue -SettingDefinitionId "test_setting" } | Should -Not -Throw
        }
        
        It "Should return structured registry lookup result" {
            $result = Get-CSPRegistryValue -SettingDefinitionId "test_setting"
            
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain "Found"
            $result.PSObject.Properties.Name | Should -Contain "NodeUri"
            $result.PSObject.Properties.Name | Should -Contain "ExpectedValue"
            $result.PSObject.Properties.Name | Should -Contain "DataType"
            $result.PSObject.Properties.Name | Should -Contain "ErrorMessage"
        }
        
        It "Should support mock mode by default for testing" {
            # Set up mock data
            Initialize-MockCSPRegistry -MockData $script:MockCSPData
            
            # Default behavior should use mock data
            $result = Get-CSPRegistryValue -SettingDefinitionId "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall"
            
            $result.Found | Should -Be $true
            $result.NodeUri | Should -Be "./Vendor/MSFT/Firewall/MdmStore/PrivateProfile/EnableFirewall"
            $result.ExpectedValue | Should -Be "true"
        }
        
        It "Should support registry lookup when enabled" {
            # Test that the EnableRegistryLookup parameter is accepted
            { Get-CSPRegistryValue -SettingDefinitionId "test_setting" -EnableRegistryLookup } | Should -Not -Throw
        }
        
        It "Should handle registry lookup errors gracefully" {
            Mock Test-Path { return $false }
            
            $result = Get-CSPRegistryValue -SettingDefinitionId "test_setting" -EnableRegistryLookup
            
            $result.Found | Should -Be $false
            $result.ErrorMessage | Should -Match "Registry path not found"
        }
        
        It "Should validate input parameters" {
            { Get-CSPRegistryValue -SettingDefinitionId "" } | Should -Throw "*argument is null or empty*"
            { Get-CSPRegistryValue -SettingDefinitionId $null } | Should -Throw "*argument is null or empty*"
        }
    }
}

Describe "Data Type Detection" {
    Context "Get-CSPDataType Function" {
        It "Should exist and be callable" {
            Get-Command Get-CSPDataType | Should -Not -BeNullOrEmpty
            Get-Command Get-CSPDataType | Should -HaveCount 1
        }
        
        It "Should return chr format for string values" {
            $result = Get-CSPDataType -Value "TestString"
            $result.Format | Should -Be "chr"
            $result.Type | Should -Be "string"
        }
        
        It "Should return int format for integer values" {
            $result = Get-CSPDataType -Value 42
            $result.Format | Should -Be "int"
            $result.Type | Should -Be "integer"
        }
        
        It "Should return int format for boolean true values" {
            $result = Get-CSPDataType -Value $true
            $result.Format | Should -Be "int"
            $result.Type | Should -Be "boolean"
            $result.ConvertedValue | Should -Be 1
        }
        
        It "Should return int format for boolean false values" {
            $result = Get-CSPDataType -Value $false
            $result.Format | Should -Be "int"
            $result.Type | Should -Be "boolean"
            $result.ConvertedValue | Should -Be 0
        }
        
        It "Should return int format for numeric strings" {
            $result = Get-CSPDataType -Value "123"
            $result.Format | Should -Be "int"
            $result.Type | Should -Be "numeric_string"
            $result.ConvertedValue | Should -Be 123
        }
        
        It "Should return chr format for non-numeric strings" {
            $result = Get-CSPDataType -Value "NotANumber"
            $result.Format | Should -Be "chr"
            $result.Type | Should -Be "string"
        }
        
        It "Should handle registry choice values (vendor_msft format)" {
            $result = Get-CSPDataType -Value "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall_true"
            $result.Format | Should -Be "chr"
            $result.Type | Should -Be "choice_setting"
        }
        
        It "Should handle mixed case boolean string values" {
            $result = Get-CSPDataType -Value "True"
            $result.Format | Should -Be "int"
            $result.Type | Should -Be "boolean_string"
            $result.ConvertedValue | Should -Be 1
            
            $result = Get-CSPDataType -Value "FALSE"
            $result.Format | Should -Be "int"
            $result.Type | Should -Be "boolean_string"
            $result.ConvertedValue | Should -Be 0
        }
        
        It "Should return structured data type information" {
            $result = Get-CSPDataType -Value "test"
            
            $result.PSObject.Properties.Name | Should -Contain "Format"
            $result.PSObject.Properties.Name | Should -Contain "Type"
            $result.PSObject.Properties.Name | Should -Contain "OriginalValue"
            $result.PSObject.Properties.Name | Should -Contain "ConvertedValue"
        }
        
        It "Should preserve original value in all cases" {
            $testValue = "original_value"
            $result = Get-CSPDataType -Value $testValue
            $result.OriginalValue | Should -Be $testValue
        }
        
        It "Should handle null and empty values gracefully" {
            $result = Get-CSPDataType -Value ""
            $result.Format | Should -Be "chr"
            $result.Type | Should -Be "empty_string"
            
            $result = Get-CSPDataType -Value $null
            $result.Format | Should -Be "chr"
            $result.Type | Should -Be "null_value"
        }
        
        It "Should validate input parameters" {
            # Should accept any input type but validate parameter presence
            { Get-CSPDataType } | Should -Throw "*missing mandatory parameters*"
        }
        
        It "Should handle decimal numbers correctly" {
            $result = Get-CSPDataType -Value 3.14
            $result.Format | Should -Be "chr"  # Decimals should be treated as strings in CSP context
            $result.Type | Should -Be "decimal"
        }
        
        It "Should handle negative numbers correctly" {
            $result = Get-CSPDataType -Value (-42)
            $result.Format | Should -Be "int"
            $result.Type | Should -Be "integer"
            $result.ConvertedValue | Should -Be (-42)
        }
    }
}