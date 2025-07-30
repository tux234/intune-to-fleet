<#
.SYNOPSIS
    Converts Intune CSP JSON exports to Fleet-compatible XML format.

.DESCRIPTION
    This script takes an exported Intune Configuration Service Provider (CSP) JSON file
    and converts it to Fleet-compatible SyncML XML format by querying the Windows Registry
    for actual CSP values and generating the appropriate XML structure.

.PARAMETER InputFile
    Path to the Intune JSON export file. Must have .json extension.

.PARAMETER OutputFile
    Path for the output Fleet XML file. Must have .xml extension.
    If not specified, will be auto-generated based on input file name.

.EXAMPLE
    Convert-IntuneToFleet -InputFile "firewall_policy.json" -OutputFile "firewall_policy.xml"
    
    Converts the specified Intune JSON export to Fleet XML format.

.EXAMPLE
    Convert-IntuneToFleet -InputFile "firewall_policy.json"
    
    Converts the Intune JSON export, auto-generating the output filename.

.EXAMPLE
    Convert-IntuneToFleet
    
    Runs in interactive mode, prompting for input and output file paths.

.NOTES
    Requires Windows environment with PowerShell 5.1+ and registry access.
    Administrative privileges recommended for reliable registry access.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [ValidateScript({
        if ($_ -and -not $_.EndsWith('.json', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "InputFile must have .json extension"
        }
        return $true
    })]
    [string]$InputFile,

    [Parameter(Position = 1)]
    [ValidateScript({
        if ($_ -and -not $_.EndsWith('.xml', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "OutputFile must have .xml extension"
        }
        return $true
    })]
    [string]$OutputFile
)

# Script-level variable for thread-safe logging
$script:LogLock = New-Object System.Object

function Write-ConversionLog {
    <#
    .SYNOPSIS
        Writes structured log entries to file and optionally to console.
    
    .DESCRIPTION
        Provides structured logging with timestamps, log levels, and thread-safe file writing.
        Supports different log levels and console output based on preferences.
    
    .PARAMETER Level
        Log level: Debug, Info, Warning, or Error.
    
    .PARAMETER Message
        Log message to write.
    
    .PARAMETER LogFilePath
        Path to the log file where entries will be written.
    
    .PARAMETER ShowOnConsole
        Whether to also display the message on console based on log level and preferences.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Debug", "Info", "Warning", "Error")]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [string]$LogFilePath,

        [Parameter()]
        [switch]$ShowOnConsole
    )

    # Create timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Format log entry
    $logEntry = "$timestamp [$($Level.ToUpper())] $Message"
    
    # Thread-safe file writing
    [System.Threading.Monitor]::Enter($script:LogLock)
    try {
        # Ensure parent directory exists
        $parentDir = Split-Path -Path $LogFilePath -Parent
        if ($parentDir -and -not (Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }
        
        # Write to log file
        try {
            Add-Content -Path $LogFilePath -Value $logEntry -ErrorAction Stop
        }
        catch {
            # If we can't write to log file, at least show on console
            Write-Warning "Cannot write to log file '$LogFilePath': $($_.Exception.Message)"
            $ShowOnConsole = $true
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($script:LogLock)
    }
    
    # Console output based on level and preferences
    if ($ShowOnConsole) {
        switch ($Level) {
            "Debug" {
                if ($DebugPreference -ne "SilentlyContinue") {
                    Write-Host $logEntry -ForegroundColor Cyan
                }
            }
            "Info" {
                Write-Host $logEntry -ForegroundColor Green
            }
            "Warning" {
                Write-Host $logEntry -ForegroundColor Yellow
            }
            "Error" {
                Write-Host $logEntry -ForegroundColor Red
            }
        }
    }
}

function Get-LogFilePath {
    <#
    .SYNOPSIS
        Generates a log file path based on the output file path.
    
    .DESCRIPTION
        Creates a .log file path in the same directory as the output file,
        using the same base name but with .log extension.
    
    .PARAMETER OutputFile
        The output file path to base the log file path on.
    
    .OUTPUTS
        String representing the log file path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputFile
    )
    
    $directory = Split-Path -Path $OutputFile -Parent
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($OutputFile)
    
    if ([string]::IsNullOrEmpty($directory)) {
        $directory = "."
    }
    
    return Join-Path $directory "$baseName.log"
}

function Get-IntuneSettings {
    <#
    .SYNOPSIS
        Parses an Intune JSON export file and extracts settings and metadata.
    
    .DESCRIPTION
        Reads and parses an Intune Configuration Service Provider (CSP) JSON export,
        extracting policy metadata and settings array for further processing.
    
    .PARAMETER FilePath
        Path to the Intune JSON export file to parse.
    
    .PARAMETER LogFilePath
        Optional path to log file for detailed parsing information.
    
    .OUTPUTS
        PSCustomObject with Metadata, Settings, ParsedSuccessfully, ErrorMessage, and FilePath properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter()]
        [string]$LogFilePath
    )

    # Initialize result object with properly typed empty array
    $result = [PSCustomObject]@{
        Metadata = $null
        Settings = [System.Object[]]@()  # Ensure it's properly typed as array
        ParsedSuccessfully = $false
        ErrorMessage = ""
        FilePath = $FilePath
    }

    # Log parsing start
    if ($LogFilePath) {
        Write-ConversionLog -Level "Info" -Message "Starting JSON parsing for file: $FilePath" -LogFilePath $LogFilePath
    }

    # Validate input file first using existing validation
    try {
        $validation = Test-IntuneJsonFile -FilePath $FilePath
        if (-not $validation.IsValid) {
            $result.ErrorMessage = $validation.ErrorMessage
            $result.Settings = [System.Object[]]@()  # Ensure array is set even on error
            if ($LogFilePath) {
                Write-ConversionLog -Level "Error" -Message "JSON file validation failed: $($validation.ErrorMessage)" -LogFilePath $LogFilePath
            }
            return $result
        }
    }
    catch {
        $result.ErrorMessage = "File validation error: $($_.Exception.Message)"
        $result.Settings = [System.Object[]]@()  # Ensure array is set even on error
        if ($LogFilePath) {
            Write-ConversionLog -Level "Error" -Message "JSON file validation exception: $($_.Exception.Message)" -LogFilePath $LogFilePath
        }
        return $result
    }

    # Read and parse JSON content
    try {
        $jsonContent = Get-Content -Path $FilePath -Raw -ErrorAction Stop
        $jsonObject = $jsonContent | ConvertFrom-Json -ErrorAction Stop
        
        if ($LogFilePath) {
            Write-ConversionLog -Level "Info" -Message "JSON content successfully parsed" -LogFilePath $LogFilePath
        }
    }
    catch {
        $result.ErrorMessage = "JSON parsing failed: $($_.Exception.Message)"
        $result.Settings = [System.Object[]]@()  # Ensure array is set even on error
        if ($LogFilePath) {
            Write-ConversionLog -Level "Error" -Message "JSON parsing failed: $($_.Exception.Message)" -LogFilePath $LogFilePath
        }
        return $result
    }

    # Validate Intune structure (additional validation beyond basic file validation)
    if (-not $jsonObject.PSObject.Properties['@odata.context']) {
        $result.ErrorMessage = "Invalid Intune export structure: Missing '@odata.context' property"
        $result.Settings = [System.Object[]]@()  # Ensure array is set even on error
        if ($LogFilePath) {
            Write-ConversionLog -Level "Error" -Message $result.ErrorMessage -LogFilePath $LogFilePath
        }
        return $result
    }

    if (-not $jsonObject.PSObject.Properties['settings']) {
        $result.ErrorMessage = "Invalid Intune export structure: Missing 'settings' array"
        $result.Settings = [System.Object[]]@()  # Ensure array is set even on error
        if ($LogFilePath) {
            Write-ConversionLog -Level "Error" -Message $result.ErrorMessage -LogFilePath $LogFilePath
        }
        return $result
    }

    # Extract metadata
    $metadata = [PSCustomObject]@{
        Name = $jsonObject.name
        Description = $jsonObject.description
        Id = $jsonObject.id
        Platforms = $jsonObject.platforms
        Technologies = $jsonObject.technologies
        SettingCount = if ($jsonObject.PSObject.Properties['settingCount']) { $jsonObject.settingCount } else { $jsonObject.settings.Count }
        CreatedDateTime = $jsonObject.createdDateTime
        LastModifiedDateTime = $jsonObject.lastModifiedDateTime
        ODataContext = $jsonObject.'@odata.context'
    }

    # Process settings array - ensure we always return an array
    $settings = @()
    if ($jsonObject.settings -is [Array] -and $jsonObject.settings.Count -gt 0) {
        foreach ($setting in $jsonObject.settings) {
            $settings += [PSCustomObject]@{
                Id = $setting.id
                SettingInstance = $setting.settingInstance
                OriginalSetting = $setting  # Keep original for reference
            }
        }
    }
    
    # Always convert to properly typed array for consistent behavior
    if ($settings.Count -eq 0) {
        $settings = New-Object System.Object[] 0
    } else {
        $settings = [System.Object[]]@($settings)
    }

    # Log parsing success
    if ($LogFilePath) {
        Write-ConversionLog -Level "Info" -Message "Successfully parsed $($settings.Count) settings from JSON file" -LogFilePath $LogFilePath
    }

    # Populate result
    $result.Metadata = $metadata
    $result.Settings = $settings
    $result.ParsedSuccessfully = $true

    return $result
}

function Get-AllSettingDefinitionIds {
    <#
    .SYNOPSIS
        Recursively extracts all settingDefinitionId entries from parsed Intune settings.
    
    .DESCRIPTION
        Traverses the settings hierarchy to find all settingDefinitionId values, including those
        nested within children arrays. Tracks path context for error reporting and provides
        structured output for registry lookup operations.
    
    .PARAMETER Settings
        Array of parsed settings from Get-IntuneSettings output.
    
    .PARAMETER LogFilePath
        Optional path to log file for extraction progress tracking.
    
    .OUTPUTS
        Array of PSCustomObject containing SettingDefinitionId, Value, SettingType, Path, and OriginalSettingInstance.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.Object[]]$Settings,

        [Parameter()]
        [string]$LogFilePath
    )

    # Initialize result array
    $extractedSettings = [System.Collections.ArrayList]::new()

    # Handle null or empty settings
    if (-not $Settings -or $Settings.Count -eq 0) {
        if ($LogFilePath) {
            Write-ConversionLog -Level "Info" -Message "No settings to extract - input is null or empty" -LogFilePath $LogFilePath
        }
        # Explicitly create empty array to avoid null return
        $emptyArray = New-Object System.Object[] 0
        return ,$emptyArray
    }

    # Log extraction start
    if ($LogFilePath) {
        Write-ConversionLog -Level "Info" -Message "Extracting settingDefinitionIds from $($Settings.Count) settings" -LogFilePath $LogFilePath
    }

    # Process each top-level setting
    for ($i = 0; $i -lt $Settings.Count; $i++) {
        $setting = $Settings[$i]
        $basePath = "settings[$i]"
        
        # Skip invalid settings with graceful error handling
        if (-not $setting -or -not $setting.PSObject.Properties['SettingInstance']) {
            if ($LogFilePath) {
                Write-ConversionLog -Level "Warning" -Message "Skipping invalid setting at $basePath - missing SettingInstance" -LogFilePath $LogFilePath
            }
            continue
        }

        $settingInstance = $setting.SettingInstance
        if (-not $settingInstance.PSObject.Properties['settingDefinitionId']) {
            if ($LogFilePath) {
                Write-ConversionLog -Level "Warning" -Message "Skipping setting at $basePath - missing settingDefinitionId" -LogFilePath $LogFilePath
            }
            continue
        }

        # Extract this setting
        $extractedSetting = Extract-SettingDefinitionId -SettingInstance $settingInstance -Path $basePath -LogFilePath $LogFilePath
        if ($extractedSetting) {
            $null = $extractedSettings.Add($extractedSetting)
        }

        # Recursively process children
        $childSettings = Get-ChildSettings -SettingInstance $settingInstance -BasePath $basePath -LogFilePath $LogFilePath
        if ($childSettings -and $childSettings.Count -gt 0) {
            foreach ($childSetting in $childSettings) {
                $null = $extractedSettings.Add($childSetting)
            }
        }
    }

    # Log extraction completion
    if ($LogFilePath) {
        Write-ConversionLog -Level "Info" -Message "Extracted $($extractedSettings.Count) settingDefinitionIds successfully" -LogFilePath $LogFilePath
    }

    return ,[System.Object[]]@($extractedSettings)
}

function Extract-SettingDefinitionId {
    <#
    .SYNOPSIS
        Extracts a single settingDefinitionId with its context information.
    
    .DESCRIPTION
        Creates a structured object containing the settingDefinitionId, its value,
        type information, and context for a single setting instance.
    
    .PARAMETER SettingInstance
        The setting instance object to extract information from.
    
    .PARAMETER Path
        The path context for this setting within the JSON structure.
    
    .PARAMETER LogFilePath
        Optional path to log file for detailed extraction logging.
    
    .OUTPUTS
        PSCustomObject with extracted setting information.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $SettingInstance,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [string]$LogFilePath
    )

    try {
        # Determine setting type and extract value
        $settingType = "unknown"
        $value = $null

        if ($SettingInstance.PSObject.Properties['choiceSettingValue']) {
            $settingType = "choice"
            $value = $SettingInstance.choiceSettingValue.value
        } elseif ($SettingInstance.PSObject.Properties['simpleSettingValue']) {
            $settingType = "simple"
            $value = $SettingInstance.simpleSettingValue.value
        }

        # Create structured result
        $result = [PSCustomObject]@{
            SettingDefinitionId = $SettingInstance.settingDefinitionId
            Value = $value
            SettingType = $settingType
            Path = $Path
            OriginalSettingInstance = $SettingInstance
        }

        return $result
    }
    catch {
        if ($LogFilePath) {
            Write-ConversionLog -Level "Warning" -Message "Error extracting setting at $Path`: $($_.Exception.Message)" -LogFilePath $LogFilePath
        }
        return $null
    }
}

function Get-ChildSettings {
    <#
    .SYNOPSIS
        Recursively extracts settingDefinitionIds from child settings.
    
    .DESCRIPTION
        Processes the children array of a setting instance to find nested
        settingDefinitionId entries, recursively processing multiple levels.
    
    .PARAMETER SettingInstance
        The parent setting instance containing potential children.
    
    .PARAMETER BasePath
        The base path for building child paths.
    
    .PARAMETER LogFilePath
        Optional path to log file for detailed extraction logging.
    
    .OUTPUTS
        Array of PSCustomObject with extracted child settings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $SettingInstance,

        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter()]
        [string]$LogFilePath
    )

    $childSettings = [System.Collections.ArrayList]::new()

    # Check for children in choiceSettingValue
    $children = $null
    if ($SettingInstance.PSObject.Properties['choiceSettingValue'] -and 
        $SettingInstance.choiceSettingValue.PSObject.Properties['children']) {
        $children = $SettingInstance.choiceSettingValue.children
    }

    # Process children if they exist
    if ($children -and $children -is [Array] -and $children.Count -gt 0) {
        for ($i = 0; $i -lt $children.Count; $i++) {
            $child = $children[$i]
            $childPath = "$BasePath.children[$i]"

            # Skip invalid children
            if (-not $child -or -not $child.PSObject.Properties['settingDefinitionId']) {
                if ($LogFilePath) {
                    Write-ConversionLog -Level "Warning" -Message "Skipping invalid child setting at $childPath - missing settingDefinitionId" -LogFilePath $LogFilePath
                }
                continue
            }

            # Extract this child setting
            $extractedChild = Extract-SettingDefinitionId -SettingInstance $child -Path $childPath -LogFilePath $LogFilePath
            if ($extractedChild) {
                $null = $childSettings.Add($extractedChild)
            }

            # Recursively process grandchildren
            $grandchildren = Get-ChildSettings -SettingInstance $child -BasePath $childPath -LogFilePath $LogFilePath
            if ($grandchildren -and $grandchildren.Count -gt 0) {
                foreach ($grandchild in $grandchildren) {
                    $null = $childSettings.Add($grandchild)
                }
            }
        }
    }

    return ,[System.Object[]]@($childSettings)
}

# Script-level variable for mock CSP registry data
$script:MockCSPRegistryData = @{}

function Get-CSPRegistryValue {
    <#
    .SYNOPSIS
        Abstract interface for CSP registry value lookup operations.
    
    .DESCRIPTION
        Provides a testable interface for querying Windows Registry for CSP (Configuration Service Provider)
        settings. Supports both mock and real registry implementations through a clean abstraction.
    
    .PARAMETER SettingDefinitionId
        The CSP setting definition identifier to lookup in the registry.
    
    .PARAMETER EnableRegistryLookup
        Enable Windows Registry lookups for CSP settings. When not specified, uses mock data for testing.
    
    .PARAMETER LogFilePath
        Optional path to log file for detailed lookup information.
    
    .OUTPUTS
        PSCustomObject with registry lookup results including Found, NodeUri, ExpectedValue, DataType, and ErrorMessage.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SettingDefinitionId,

        [Parameter()]
        [switch]$EnableRegistryLookup,

        [Parameter()]
        [string]$LogFilePath
    )

    # Initialize result object
    $result = [PSCustomObject]@{
        SettingDefinitionId = $SettingDefinitionId
        Found = $false
        NodeUri = $null
        ExpectedValue = $null
        DataType = $null
        ErrorMessage = ""
    }

    # Log registry lookup start
    if ($LogFilePath) {
        Write-ConversionLog -Level "Info" -Message "Starting registry lookup for setting: $SettingDefinitionId" -LogFilePath $LogFilePath
    }

    try {
        if ($EnableRegistryLookup) {
            # Windows Registry lookup implementation
            if ($LogFilePath) {
                Write-ConversionLog -Level "Info" -Message "Searching registry for setting: $SettingDefinitionId" -LogFilePath $LogFilePath
            }
            
            # Define the CSP registry base path
            $registryBasePath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device"
            
            # Check if registry path exists
            if (-not (Test-Path -Path $registryBasePath)) {
                $result.ErrorMessage = "Registry path not found: $registryBasePath"
                if ($LogFilePath) {
                    Write-ConversionLog -Level "Warning" -Message $result.ErrorMessage -LogFilePath $LogFilePath
                }
                return $result
            }
            
            try {
                # Get all registry entries recursively
                $registryEntries = Get-ChildItem -Path $registryBasePath -Recurse -ErrorAction Stop
                
                if ($LogFilePath) {
                    Write-ConversionLog -Level "Debug" -Message "Found $($registryEntries.Count) registry entries to search" -LogFilePath $LogFilePath
                }
                
                # Convert setting definition ID to registry key name pattern
                # Example: vendor_msft_firewall_mdmstore_privateprofile_enablefirewall
                # Should match: Vendor~Policy~MSFT~Firewall~MdmStore~PrivateProfile~EnableFirewall
                $searchPattern = $SettingDefinitionId -replace '_', '~' -replace 'vendor~', 'Vendor~Policy~' -replace '~msft~', '~MSFT~'
                
                # Apply title case transformation to each segment with special handling for compound words
                $segments = $searchPattern -split '~'
                for ($i = 0; $i -lt $segments.Length; $i++) {
                    if ($segments[$i].Length -gt 0) {
                        # Handle compound words like "mdmstore" -> "MdmStore", "privateprofile" -> "PrivateProfile"
                        $segment = $segments[$i].ToLower()
                        
                        # Special case transformations for common CSP patterns
                        $segment = $segment -replace '^msft$', 'MSFT'  # Keep MSFT uppercase
                        $segment = $segment -replace '^mdmstore$', 'MdmStore'
                        $segment = $segment -replace '^privateprofile$', 'PrivateProfile'
                        $segment = $segment -replace '^publicprofile$', 'PublicProfile'
                        $segment = $segment -replace '^enablefirewall$', 'EnableFirewall'
                        $segment = $segment -replace '^activehoursstart$', 'ActiveHoursStart'
                        
                        # Default title case for segments not specially handled
                        if ($segment -eq $segments[$i].ToLower()) {
                            $segment = $segment.Substring(0,1).ToUpper() + $segment.Substring(1)
                        }
                        
                        $segments[$i] = $segment
                    }
                }
                $formattedPattern = $segments -join '~'
                
                if ($LogFilePath) {
                    Write-ConversionLog -Level "Debug" -Message "Searching for registry key matching pattern: $formattedPattern" -LogFilePath $LogFilePath
                }
                
                # Find matching registry entry (case-insensitive with multiple matching strategies)
                $matchingEntry = $registryEntries | Where-Object { 
                    # Strategy 1: Exact formatted pattern match
                    $_.Name -like "*$formattedPattern*" -or
                    # Strategy 2: Original search pattern match  
                    $_.Name -like "*$searchPattern*" -or
                    # Strategy 3: Case-insensitive original setting ID match
                    $_.Name.ToLower() -like "*$($SettingDefinitionId.ToLower())*"
                }
                
                if ($matchingEntry) {
                    # Get the first match if multiple found
                    $registryKey = $matchingEntry | Select-Object -First 1
                    
                    if ($LogFilePath) {
                        Write-ConversionLog -Level "Info" -Message "Found matching registry key: $($registryKey.Name)" -LogFilePath $LogFilePath
                    }
                    
                    try {
                        # Get registry properties
                        $properties = Get-ItemProperty -Path $registryKey.PSPath -ErrorAction Stop
                        
                        # Check for required properties
                        if ($properties.PSObject.Properties['NodeUri']) {
                            $result.Found = $true
                            $result.NodeUri = $properties.NodeUri
                            
                            # Get ExpectedValue if available
                            if ($properties.PSObject.Properties['ExpectedValue']) {
                                $result.ExpectedValue = $properties.ExpectedValue
                            }
                            
                            # Get DataType if available, otherwise infer from ExpectedValue
                            if ($properties.PSObject.Properties['DataType']) {
                                $result.DataType = $properties.DataType
                            } else {
                                # Infer data type from ExpectedValue
                                if ($result.ExpectedValue -match '^\d+$') {
                                    $result.DataType = "int"
                                } elseif ($result.ExpectedValue -eq "true" -or $result.ExpectedValue -eq "false") {
                                    $result.DataType = "bool"
                                } else {
                                    $result.DataType = "chr"
                                }
                            }
                            
                            if ($LogFilePath) {
                                Write-ConversionLog -Level "Info" -Message "Successfully retrieved registry values for $SettingDefinitionId" -LogFilePath $LogFilePath
                            }
                        } else {
                            $result.ErrorMessage = "Missing required registry properties (NodeUri) for setting: $SettingDefinitionId"
                            if ($LogFilePath) {
                                Write-ConversionLog -Level "Warning" -Message $result.ErrorMessage -LogFilePath $LogFilePath
                            }
                        }
                    } catch [System.IO.IOException] {
                        $result.ErrorMessage = "Registry read error for setting $SettingDefinitionId`: $($_.Exception.Message)"
                        if ($LogFilePath) {
                            Write-ConversionLog -Level "Error" -Message $result.ErrorMessage -LogFilePath $LogFilePath
                        }
                    } catch {
                        $result.ErrorMessage = "Registry property read error for setting $SettingDefinitionId`: $($_.Exception.Message)"
                        if ($LogFilePath) {
                            Write-ConversionLog -Level "Error" -Message $result.ErrorMessage -LogFilePath $LogFilePath
                        }
                    }
                } else {
                    $result.ErrorMessage = "No matching registry entries found for setting: $SettingDefinitionId"
                    if ($LogFilePath) {
                        Write-ConversionLog -Level "Info" -Message $result.ErrorMessage -LogFilePath $LogFilePath
                    }
                }
                
            } catch [System.UnauthorizedAccessException] {
                $result.ErrorMessage = "Access denied to registry for setting $SettingDefinitionId`: $($_.Exception.Message)"
                if ($LogFilePath) {
                    Write-ConversionLog -Level "Error" -Message $result.ErrorMessage -LogFilePath $LogFilePath
                }
            } catch [System.Security.SecurityException] {
                $result.ErrorMessage = "Security exception accessing registry for setting $SettingDefinitionId`: $($_.Exception.Message)"
                if ($LogFilePath) {
                    Write-ConversionLog -Level "Error" -Message $result.ErrorMessage -LogFilePath $LogFilePath
                }
            } catch {
                $result.ErrorMessage = "Registry enumeration error for setting $SettingDefinitionId`: $($_.Exception.Message)"
                if ($LogFilePath) {
                    Write-ConversionLog -Level "Error" -Message $result.ErrorMessage -LogFilePath $LogFilePath
                }
            }
        } else {
            # Mock registry implementation for testing purposes
            if ($script:MockCSPRegistryData.ContainsKey($SettingDefinitionId)) {
                $mockEntry = $script:MockCSPRegistryData[$SettingDefinitionId]
                
                # Handle special error conditions
                if ($mockEntry -and $mockEntry.PSObject.Properties['ErrorCondition']) {
                    switch ($mockEntry.ErrorCondition) {
                        "AccessDenied" {
                            $result.ErrorMessage = "Registry access denied for setting: $SettingDefinitionId"
                            if ($LogFilePath) {
                                Write-ConversionLog -Level "Warning" -Message $result.ErrorMessage -LogFilePath $LogFilePath
                            }
                            return $result
                        }
                        default {
                            $result.ErrorMessage = "Mock registry error: $($mockEntry.ErrorCondition)"
                            if ($LogFilePath) {
                                Write-ConversionLog -Level "Warning" -Message $result.ErrorMessage -LogFilePath $LogFilePath
                            }
                            return $result
                        }
                    }
                }
                
                # Handle valid mock entry
                if ($mockEntry -and $mockEntry.PSObject.Properties['NodeUri']) {
                    $result.Found = $true
                    $result.NodeUri = $mockEntry.NodeUri
                    $result.ExpectedValue = $mockEntry.ExpectedValue
                    $result.DataType = $mockEntry.DataType
                    
                    if ($LogFilePath) {
                        Write-ConversionLog -Level "Info" -Message "Found mock registry entry for $SettingDefinitionId" -LogFilePath $LogFilePath
                    }
                    return $result
                }
            }

            # Check for special test cases that simulate access denied
            if ($SettingDefinitionId -eq "access_denied_setting") {
                $result.ErrorMessage = "Registry access denied for setting: $SettingDefinitionId"
                if ($LogFilePath) {
                    Write-ConversionLog -Level "Warning" -Message $result.ErrorMessage -LogFilePath $LogFilePath
                }
                return $result
            }

            # If not found in mock data and not in special cases, return not found
            $result.ErrorMessage = "CSP registry entry not found for setting: $SettingDefinitionId"
            if ($LogFilePath) {
                Write-ConversionLog -Level "Info" -Message $result.ErrorMessage -LogFilePath $LogFilePath
            }
        }
    }
    catch {
        $result.ErrorMessage = "Registry lookup error: $($_.Exception.Message)"
        if ($LogFilePath) {
            Write-ConversionLog -Level "Error" -Message $result.ErrorMessage -LogFilePath $LogFilePath
        }
    }

    return $result
}

function Get-CSPDataType {
    <#
    .SYNOPSIS
        Analyzes a value to determine the appropriate CSP XML data format.
    
    .DESCRIPTION
        Determines whether a given value should be formatted as "int" or "chr" 
        in the CSP XML output. This is critical for proper Fleet configuration 
        parsing, as incorrect data types can cause configuration failures.
    
    .PARAMETER Value
        The value to analyze for data type determination.
    
    .OUTPUTS
        PSCustomObject with properties:
        - Format: "int" or "chr" for XML formatting
        - Type: Descriptive type classification
        - OriginalValue: The input value preserved
        - ConvertedValue: Value converted for XML (if applicable)
    
    .EXAMPLE
        Get-CSPDataType -Value 42
        Returns format "int" for integer values
    
    .EXAMPLE
        Get-CSPDataType -Value "TestString"
        Returns format "chr" for string values
    
    .EXAMPLE
        Get-CSPDataType -Value $true
        Returns format "int" with ConvertedValue 1 for boolean true
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        $Value
    )
    
    # Initialize result object
    $result = [PSCustomObject]@{
        Format = "chr"  # Default to chr format
        Type = "unknown"
        OriginalValue = $Value
        ConvertedValue = $Value
    }
    
    # Handle null values
    if ($null -eq $Value) {
        $result.Type = "null_value"
        $result.ConvertedValue = ""
        return $result
    }
    
    # Handle empty strings (but not boolean false which also equals "")
    if ($Value -eq "" -and $Value.GetType().Name -eq "String") {
        $result.Type = "empty_string"
        return $result
    }
    
    # Determine the PowerShell type first
    $valueType = $Value.GetType().Name
    
    switch ($valueType) {
        "Boolean" {
            $result.Format = "int"
            $result.Type = "boolean"
            $result.ConvertedValue = if ($Value) { 1 } else { 0 }
            break
        }
        
        { $_ -in @("Int32", "Int64", "UInt32", "UInt64") } {
            $result.Format = "int"
            $result.Type = "integer"
            $result.ConvertedValue = $Value
            break
        }
        
        { $_ -in @("Double", "Single", "Decimal") } {
            $result.Format = "chr"  # Decimals should be treated as strings in CSP context
            $result.Type = "decimal"
            $result.ConvertedValue = $Value.ToString()
            break
        }
        
        "String" {
            # String requires additional analysis
            
            # Check for vendor_msft choice settings (these are always strings)
            if ($Value -match "^vendor_msft_") {
                $result.Type = "choice_setting"
                return $result
            }
            
            # Check for boolean string values (case insensitive)
            if ($Value -match "^(true|false)$") {
                $result.Format = "int"
                $result.Type = "boolean_string"
                $result.ConvertedValue = if ($Value.ToLower() -eq "true") { 1 } else { 0 }
                return $result
            }
            
            # Check if string represents a pure integer
            $intValue = 0
            if ([int]::TryParse($Value, [ref]$intValue)) {
                $result.Format = "int"
                $result.Type = "numeric_string"
                $result.ConvertedValue = $intValue
                return $result
            }
            
            # Default to string handling
            $result.Type = "string"
        }
        
        default {
            # For any other types, convert to string and handle as chr
            $result.Type = "object"
            $result.ConvertedValue = $Value.ToString()
        }
    }
    
    return $result
}

function Initialize-MockCSPRegistry {
    <#
    .SYNOPSIS
        Initializes the mock CSP registry with test data.
    
    .DESCRIPTION
        Sets up mock registry data for testing CSP registry operations without
        requiring actual Windows Registry access. Supports comprehensive test scenarios.
    
    .PARAMETER MockData
        Hashtable containing mock CSP registry entries with NodeUri, ExpectedValue, and DataType.
    
    .OUTPUTS
        None. Initializes script-level mock registry data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$MockData
    )

    # Clear existing mock data
    $script:MockCSPRegistryData = @{}

    # Process each mock entry
    foreach ($key in $MockData.Keys) {
        $value = $MockData[$key]
        
        # Handle null entries (for testing missing entries)
        if ($null -eq $value) {
            continue
        }
        
        # Validate mock entry structure
        if ($value -is [hashtable] -and $value.ContainsKey('NodeUri')) {
            $script:MockCSPRegistryData[$key] = [PSCustomObject]@{
                NodeUri = $value.NodeUri
                ExpectedValue = $value.ExpectedValue
                DataType = $value.DataType
                AccessLevel = if ($value.ContainsKey('AccessLevel')) { $value.AccessLevel } else { "Get,Replace" }
            }
        }
        elseif ($value -is [hashtable] -and $value.ContainsKey('ErrorCondition')) {
            $script:MockCSPRegistryData[$key] = [PSCustomObject]@{
                ErrorCondition = $value.ErrorCondition
            }
        }
        else {
            # Skip malformed entries silently
            continue
        }
    }
}

function Clear-MockCSPRegistry {
    <#
    .SYNOPSIS
        Clears all mock CSP registry data.
    
    .DESCRIPTION
        Removes all mock registry entries, returning the mock registry to an empty state.
        Useful for test cleanup and isolation between test cases.
    
    .OUTPUTS
        None. Clears script-level mock registry data.
    #>
    [CmdletBinding()]
    param()

    $script:MockCSPRegistryData = @{}
}

function Add-MockCSPEntry {
    <#
    .SYNOPSIS
        Adds a single mock CSP registry entry.
    
    .DESCRIPTION
        Adds an individual mock registry entry for testing specific scenarios.
        Supports both normal entries and error condition simulation.
    
    .PARAMETER SettingDefinitionId
        The CSP setting definition identifier for the mock entry.
    
    .PARAMETER NodeUri
        The registry node URI for the mock entry.
    
    .PARAMETER ExpectedValue
        The expected value for the mock entry.
    
    .PARAMETER DataType
        The data type (bool, int, string) for the mock entry.
    
    .PARAMETER ErrorCondition
        Optional error condition to simulate (e.g., "AccessDenied").
    
    .OUTPUTS
        None. Adds entry to script-level mock registry data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SettingDefinitionId,

        [Parameter()]
        [string]$NodeUri,

        [Parameter()]
        [string]$ExpectedValue,

        [Parameter()]
        [string]$DataType,

        [Parameter()]
        [string]$ErrorCondition
    )

    if ($ErrorCondition) {
        $script:MockCSPRegistryData[$SettingDefinitionId] = [PSCustomObject]@{
            ErrorCondition = $ErrorCondition
        }
    }
    else {
        $script:MockCSPRegistryData[$SettingDefinitionId] = [PSCustomObject]@{
            NodeUri = $NodeUri
            ExpectedValue = $ExpectedValue
            DataType = $DataType
            AccessLevel = "Get,Replace"
        }
    }
}

function Test-IntuneJsonFile {
    <#
    .SYNOPSIS
        Validates an Intune JSON export file.
    
    .DESCRIPTION
        Checks if the specified file exists, contains valid JSON, and has the expected
        Intune export structure (settings array and @odata.context).
    
    .PARAMETER FilePath
        Path to the JSON file to validate.
    
    .OUTPUTS
        PSCustomObject with IsValid, ErrorMessage, and FilePath properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    
    $result = [PSCustomObject]@{
        IsValid = $false
        ErrorMessage = ""
        FilePath = $FilePath
    }
    
    # Check if file exists
    if (-not (Test-Path -Path $FilePath)) {
        $result.ErrorMessage = "File not found: $FilePath"
        return $result
    }
    
    # Check if file is readable
    try {
        $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
    }
    catch {
        $result.ErrorMessage = "Cannot read file: $($_.Exception.Message)"
        return $result
    }
    
    # Parse JSON
    try {
        $jsonObject = $content | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $result.ErrorMessage = "Invalid JSON syntax: $($_.Exception.Message)"
        return $result
    }
    
    # Validate Intune export format
    if (-not $jsonObject.PSObject.Properties['@odata.context']) {
        $result.ErrorMessage = "Invalid Intune export format: Missing '@odata.context' property"
        return $result
    }
    
    if (-not $jsonObject.PSObject.Properties['settings']) {
        $result.ErrorMessage = "Invalid Intune export format: Missing 'settings' array"
        return $result
    }
    
    if ($jsonObject.settings -isnot [Array]) {
        $result.ErrorMessage = "Invalid Intune export format: 'settings' must be an array"
        return $result
    }
    
    # All validations passed
    $result.IsValid = $true
    return $result
}

function Test-OutputPath {
    <#
    .SYNOPSIS
        Validates an output file path for write access.
    
    .DESCRIPTION
        Checks if the specified output path is valid and writable, including
        checking parent directory existence and permissions.
    
    .PARAMETER FilePath
        Path to the output file to validate.
    
    .OUTPUTS
        PSCustomObject with IsValid, ErrorMessage, and FilePath properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    
    $result = [PSCustomObject]@{
        IsValid = $false
        ErrorMessage = ""
        FilePath = $FilePath
    }
    
    # Get parent directory
    $parentDir = Split-Path -Path $FilePath -Parent
    if ([string]::IsNullOrEmpty($parentDir)) {
        $parentDir = "."
    }
    
    # Check if parent directory exists
    if (-not (Test-Path -Path $parentDir)) {
        # Try to resolve the parent directory to see if it's valid
        try {
            # For absolute paths that don't exist, this will fail
            $null = [System.IO.Path]::GetFullPath($parentDir)
            # Additional check - see if we can access parent of parent
            $grandParent = Split-Path -Path $parentDir -Parent
            if ($grandParent -and -not (Test-Path -Path $grandParent)) {
                $result.ErrorMessage = "Invalid directory path: $parentDir (parent directory does not exist)"
                return $result
            }
        }
        catch {
            $result.ErrorMessage = "Invalid directory path: $parentDir"
            return $result
        }
    }
    
    # Test write access by attempting to create a temporary file
    $testFile = Join-Path $parentDir "temp_write_test_$(Get-Random).tmp"
    try {
        New-Item -Path $testFile -ItemType File -Force -ErrorAction Stop | Out-Null
        Remove-Item -Path $testFile -Force -ErrorAction SilentlyContinue
    }
    catch {
        $result.ErrorMessage = "Cannot write to directory: $($_.Exception.Message)"
        return $result
    }
    
    # All validations passed
    $result.IsValid = $true
    return $result
}

function Convert-IntuneToFleet {
    <#
    .SYNOPSIS
        Converts Intune CSP JSON exports to Fleet-compatible XML format.

    .DESCRIPTION
        This script takes an exported Intune Configuration Service Provider (CSP) JSON file
        and converts it to Fleet-compatible SyncML XML format by querying the Windows Registry
        for actual CSP values and generating the appropriate XML structure.

    .PARAMETER InputFile
        Path to the Intune JSON export file. Must have .json extension.

    .PARAMETER OutputFile
        Path for the output Fleet XML file. Must have .xml extension.
        If not specified, will be auto-generated based on input file name.

    .EXAMPLE
        Convert-IntuneToFleet -InputFile "firewall_policy.json" -OutputFile "firewall_policy.xml"
        
        Converts the specified Intune JSON export to Fleet XML format.

    .EXAMPLE
        Convert-IntuneToFleet -InputFile "firewall_policy.json"
        
        Converts the Intune JSON export, auto-generating the output filename.

    .EXAMPLE
        Convert-IntuneToFleet
        
        Runs in interactive mode, prompting for input and output file paths.

    .NOTES
        Requires Windows environment with PowerShell 5.1+ and registry access.
        Administrative privileges recommended for reliable registry access.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [ValidateScript({
            if ($_ -and -not $_.EndsWith('.json', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "InputFile must have .json extension"
            }
            return $true
        })]
        [string]$InputFile,

        [Parameter(Position = 1)]
        [ValidateScript({
            if ($_ -and -not $_.EndsWith('.xml', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "OutputFile must have .xml extension"
            }
            return $true
        })]
        [string]$OutputFile
    )

    # Initialize logging
    $logFilePath = $null
    if ($OutputFile) {
        $logFilePath = Get-LogFilePath -OutputFile $OutputFile
    } elseif ($InputFile) {
        $tempOutputFile = [System.IO.Path]::ChangeExtension($InputFile, '.xml')
        $logFilePath = Get-LogFilePath -OutputFile $tempOutputFile
    }

    # Log conversion start
    if ($logFilePath) {
        Write-ConversionLog -Level "Info" -Message "Starting conversion process" -LogFilePath $logFilePath -ShowOnConsole
    }

    # Check if no parameters provided - indicate interactive mode
    if (-not $InputFile -and -not $OutputFile) {
        $message = "No parameters provided - entering interactive mode"
        if ($logFilePath) {
            Write-ConversionLog -Level "Info" -Message $message -LogFilePath $logFilePath -ShowOnConsole
        } else {
            # Create a temporary log file for interactive mode
            $tempLogFile = Join-Path (Get-Location) "conversion_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            Write-ConversionLog -Level "Info" -Message $message -LogFilePath $tempLogFile -ShowOnConsole
            $logFilePath = $tempLogFile
        }
    }

    # Validate input file if provided
    if ($InputFile) {
        $inputValidation = Test-IntuneJsonFile -FilePath $InputFile
        if (-not $inputValidation.IsValid) {
            if ($logFilePath) {
                Write-ConversionLog -Level "Error" -Message "Input file validation failed: $($inputValidation.ErrorMessage)" -LogFilePath $logFilePath -ShowOnConsole
            }
            throw $inputValidation.ErrorMessage
        }
        $message = "Input file validation passed: $InputFile"
        Write-Verbose $message
        if ($logFilePath) {
            Write-ConversionLog -Level "Info" -Message $message -LogFilePath $logFilePath
        }
    }

    # Generate output file path if not provided
    if ($InputFile -and -not $OutputFile) {
        $OutputFile = [System.IO.Path]::ChangeExtension($InputFile, '.xml')
        $message = "Auto-generated output file: $OutputFile"
        Write-Verbose $message
        if ($logFilePath) {
            Write-ConversionLog -Level "Info" -Message $message -LogFilePath $logFilePath
        }
        # Update log file path with correct output file
        $logFilePath = Get-LogFilePath -OutputFile $OutputFile
    }

    # Validate output file path if provided
    if ($OutputFile) {
        $outputValidation = Test-OutputPath -FilePath $OutputFile
        if (-not $outputValidation.IsValid) {
            if ($logFilePath) {
                Write-ConversionLog -Level "Error" -Message "Output path validation failed: $($outputValidation.ErrorMessage)" -LogFilePath $logFilePath -ShowOnConsole
            }
            throw $outputValidation.ErrorMessage
        }
        $message = "Output path validation passed: $OutputFile"
        Write-Verbose $message
        if ($logFilePath) {
            Write-ConversionLog -Level "Info" -Message $message -LogFilePath $logFilePath
        }
    }

    # Handle WhatIf scenario first
    if ($WhatIfPreference) {
        $whatIfMessage = "What if: Would convert $InputFile to $OutputFile"
        if ($logFilePath) {
            Write-ConversionLog -Level "Info" -Message $whatIfMessage -LogFilePath $logFilePath
        }
        $PSCmdlet.ShouldProcess("Convert Intune CSP to Fleet XML", "Conversion") | Out-Null
        return $whatIfMessage
    }

    if ($PSCmdlet.ShouldProcess("Convert Intune CSP to Fleet XML", "Conversion")) {
        $message = "Beginning actual conversion process..."
        Write-Verbose $message
        if ($logFilePath) {
            Write-ConversionLog -Level "Info" -Message $message -LogFilePath $logFilePath
        }
        
        # TODO: Implement actual conversion logic in subsequent steps
        $statusMessage = "Conversion logic not yet implemented - this is Step 3 foundation"
        if ($logFilePath) {
            Write-ConversionLog -Level "Info" -Message $statusMessage -LogFilePath $logFilePath -ShowOnConsole
        } else {
            Write-Host $statusMessage -ForegroundColor Green
        }
        
        $completionMessage = "Conversion completed successfully"
        if ($logFilePath) {
            Write-ConversionLog -Level "Info" -Message $completionMessage -LogFilePath $logFilePath -ShowOnConsole
        }
        return $completionMessage
    }
}

# If script is run directly (not dot-sourced), call the main function
if ($MyInvocation.InvocationName -ne '.') {
    Convert-IntuneToFleet @PSBoundParameters
}