<#
.SYNOPSIS
    Converts Microsoft Intune policy JSON exports to Fleet-compatible Windows CSP XML files.

.DESCRIPTION
    This script processes Microsoft Intune configuration policy JSON exports and converts them 
    into individual Windows Configuration Service Provider (CSP) XML files compatible with 
    Fleet device management. 
    
    Key Features:
    - Automatically detects policy types and generates proper SyncML XML
    - Registry-based CSP path resolution with proper TitleCase
    - Supports multiple SyncML format types (bool, int, chr) with correct data encoding
    - Resolver map for handling policies that Intune sometimes leaves unset (ExpectedValue = -1)

    Design Decisions:
    - Boolean vs Integer format detection based on Microsoft CSP documentation
    - Registry lookups ensure proper NodeURI casing 
    - Resolver map handles policies where registry ExpectedValue = -1
    - Suffix-based fallback logic for policies without resolvers

.PARAMETER JsonPath
    Path to the Intune policy JSON export file.

.PARAMETER ResolverMapPath
    Path to the JSON file containing PowerShell expressions for resolving complex policy values.
    Default: "C:\CSPConverter\resolver-map.json"

.PARAMETER OutputPath
    Directory where individual CSP XML files will be created.
    Default: "C:\CSPConverter\Output"

.PARAMETER LogPath
    Path for the CSV log file containing conversion results.
    Default: "C:\CSPConverter\ConversionLog.csv"

.PARAMETER DebugMode
    Enables verbose debug output showing detailed processing information.

.PARAMETER DryRun
    Performs conversion analysis without creating output files.

.PARAMETER MergeXml
    Creates a single merged XML file containing all policies instead of individual files.

.EXAMPLE
    .\Convert-IntuneToFleetCSP.ps1 -JsonPath "C:\Export\MyPolicy.json"
    
    Converts the specified Intune JSON export using default settings.

.EXAMPLE
    .\Convert-IntuneToFleetCSP.ps1 -JsonPath "C:\Export\MyPolicy.json" -MergeXml -DebugMode
    
    Converts to a single merged XML file with detailed debug output.

.NOTES
    Author: Mitch Francese   
    Version: 1.0
    Requires: PowerShell 5.1+, Windows with CSP NodeCache registry access
    
    This script achieves ~80% coverage for generic Intune policies. For edge cases,
    customize the $booleanFormatPolicies array or resolver map.

.LINK
    https://learn.microsoft.com/en-us/windows/client-management/mdm/
    https://fleetdm.com/guides/creating-windows-csps#basic-article
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Path to Intune policy JSON export file")]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Leaf)) {
            throw "JSON file not found: $_"
        }
        if (-not ($_ -like "*.json")) {
            throw "File must have .json extension: $_"
        }
        return $true
    })]
    [string]$JsonPath,

    [Parameter(HelpMessage = "Path to resolver map JSON file")]
    [string]$ResolverMapPath = "C:\CSPConverter\resolver-map.json",

    [Parameter(HelpMessage = "Output directory for CSP XML files")]
    [string]$OutputPath = "C:\CSPConverter\Output",

    [Parameter(HelpMessage = "Path for conversion log CSV file")]
    [string]$LogPath = "C:\CSPConverter\ConversionLog.csv",

    [Parameter(HelpMessage = "Enable verbose debug output")]
    [switch]$DebugMode,

    [Parameter(HelpMessage = "Analyze only, do not create output files")]
    [switch]$DryRun,

    [Parameter(HelpMessage = "Create single merged XML file instead of individual files")]
    [switch]$MergeXml
)

#Requires -Version 5.1

# Error handling preference
$ErrorActionPreference = 'Stop'

#region Helper Functions

<#
.SYNOPSIS
    Saves XML content to file without UTF-8 BOM for Fleet compatibility.
    
.DESCRIPTION
    Fleet requires XML files without UTF-8 BOM markers. Standard PowerShell Out-File 
    adds BOM by default, causing Fleet to reject the configuration files.
#>
function Save-XmlFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content,
        
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    try {
        # Create UTF-8 encoding without BOM - critical for Fleet compatibility
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
        Write-Verbose "Saved XML file without BOM: $Path"
    }
    catch {
        Write-Error "Failed to save XML file '$Path': $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Determines appropriate SyncML format and data value based on policy type and suffix.
    
.DESCRIPTION
    This function encapsulates the core logic for determining whether a Windows CSP policy
    should use 'bool', 'int', or 'chr' SyncML format, and what the actual data value should be.
    
    Key Design Decisions:
    - Microsoft CSP documentation is inconsistent about bool vs int formats
    - We maintain a curated list of policies that definitively use boolean format
    - Most policies use integer format (0/1) even for enable/disable scenarios
    - String values always use 'chr' format with CDATA wrapping
    
.PARAMETER DefinitionId
    The base policy definition ID without suffix (e.g., "vendor_msft_firewall_enablefirewall").
    
.PARAMETER Suffix
    The policy value suffix (e.g., "_true", "_false", "_1", "_0").
    
.PARAMETER SimpleSettingValue
    Simple setting value object for string/integer policies (non-choice settings).
    
.OUTPUTS
    Hashtable with Format, DataValue, and IsValid properties.
#>
function Get-SyncMLFormatAndData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DefinitionId,
        
        [Parameter()]
        [string]$Suffix,
        
        [Parameter()]
        [object]$SimpleSettingValue = $null
    )
    
    $result = @{
        Format = "int"
        DataValue = $null
        IsValid = $false
    }
    
    # Handle simple setting values (strings, integers) first
    # These are non-choice settings like file paths, numeric values, etc.
    if ($SimpleSettingValue) {
        switch ($SimpleSettingValue.'@odata.type') {
            "#microsoft.graph.deviceManagementConfigurationStringSettingValue" {
                $result.Format = "chr"
                $result.DataValue = "<![CDATA[$($SimpleSettingValue.value)]]>"
                $result.IsValid = $true
                Write-Verbose "Detected string setting: $DefinitionId"
                return $result
            }
            "#microsoft.graph.deviceManagementConfigurationIntegerSettingValue" {
                $result.Format = "int"
                $result.DataValue = $SimpleSettingValue.value
                $result.IsValid = $true
                Write-Verbose "Detected integer setting: $DefinitionId"
                return $result
            }
        }
    }
    
    # Handle choice setting values with suffixes
    if (-not $Suffix) {
        Write-Verbose "No suffix found for choice setting: $DefinitionId"
        return $result
    }
    
    # Define policies that use boolean format (true/false data values)
    # Based on Microsoft CSP documentation and testing results
    # Note: This is the critical customization point for specific CSP requirements
    $booleanFormatPolicies = @(
        # Windows Firewall policies confirmed to use boolean format
        "*firewall*allowlocalipsecpolicymerge*",
        "*firewall*allowlocalpolicymerge*",
        "*firewall*authappsallowuserprefmerge*",
        "*firewall*globalportsallowuserprefmerge*",
        "*firewall*disableinboundnotifications*",
        "*firewall*disablestealthmode*",
        "*firewall*disablestealthmodeipsecsecuredpacketexemption*",
        "*firewall*disableunicastresponsestomulticastbroadcast*",
        "*firewall*shielded*",
        "*firewall*enablefirewall*",
        
        # Windows Defender policies
        "*defender*realtimeprotection*",
        "*defender*cloudprotection*",
        "*defender*automaticsamplesubmission*",
        "*defender*puaprotection*",
        "*defender*tamperprotection*",
        
        # BitLocker policies  
        "*bitlocker*requiredeviceencryption*",
        "*bitlocker*requiretpm*",
        "*bitlocker*allowstandardusers*",
        
        # SmartScreen policies
        "*smartscreen*enablesmartscreen*",
        "*smartscreen*enableappinstallcontrol*",
        
        # DeviceLock policies
        "*devicelock*requirepassword*",
        
        # Generic patterns for policies that commonly use boolean format
        "*enable*",
        "*disable*",
        "*allow*",
        "*block*",
        "*require*"
    )
    
    # Check if this policy should use boolean format
    $useBooleanFormat = $false
    foreach ($pattern in $booleanFormatPolicies) {
        if ($DefinitionId -like $pattern) {
            $useBooleanFormat = $true
            Write-Verbose "Policy '$DefinitionId' matched boolean format pattern: $pattern"
            break
        }
    }
    
    # Parse suffix and determine format/data based on pattern matching
    # This handles all common Intune policy suffix patterns
    switch -Regex ($Suffix) {
        "^_true$" {
            if ($useBooleanFormat) {
                $result.Format = "bool"
                $result.DataValue = "true"
            } else {
                $result.Format = "int" 
                $result.DataValue = 1
            }
            $result.IsValid = $true
        }
        "^_false$" {
            if ($useBooleanFormat) {
                $result.Format = "bool"
                $result.DataValue = "false"
            } else {
                $result.Format = "int"
                $result.DataValue = 0
            }
            $result.IsValid = $true
        }
        "^_1$" {
            $result.Format = "int"
            $result.DataValue = 1
            $result.IsValid = $true
        }
        "^_0$" {
            $result.Format = "int"
            $result.DataValue = 0
            $result.IsValid = $true
        }
        "^_enabled$" {
            if ($useBooleanFormat) {
                $result.Format = "bool"
                $result.DataValue = "true"
            } else {
                $result.Format = "int"
                $result.DataValue = 1
            }
            $result.IsValid = $true
        }
        "^_disabled$" {
            if ($useBooleanFormat) {
                $result.Format = "bool"
                $result.DataValue = "false"
            } else {
                $result.Format = "int"
                $result.DataValue = 0
            }
            $result.IsValid = $true
        }
        "^_allow$" {
            if ($useBooleanFormat) {
                $result.Format = "bool"
                $result.DataValue = "true"
            } else {
                $result.Format = "int"
                $result.DataValue = 1
            }
            $result.IsValid = $true
        }
        "^_block$" {
            if ($useBooleanFormat) {
                $result.Format = "bool"
                $result.DataValue = "false"
            } else {
                $result.Format = "int"
                $result.DataValue = 0
            }
            $result.IsValid = $true
        }
        "^_(\d+)$" {
            # Any numeric suffix - always use int format
            $result.Format = "int"
            $result.DataValue = [int]$Matches[1]
            $result.IsValid = $true
        }
        default {
            Write-Warning "Unknown suffix pattern '$Suffix' for policy '$DefinitionId'"
        }
    }
    
    Write-Verbose "Format detection for '$DefinitionId$Suffix': Format=$($result.Format), Value=$($result.DataValue), Valid=$($result.IsValid)"
    return $result
}

<#
.SYNOPSIS
    Recursively extracts all settings from Intune JSON policy structure.
    
.DESCRIPTION
    Intune policies have a nested structure where top-level choice settings can have
    child settings. This function flattens that structure while preserving the
    relationship between parent choices and their configured values.
    
.PARAMETER Settings
    Array of settings from the Intune JSON structure.
    
.PARAMETER Depth
    Current recursion depth (used for debug output formatting).
#>
function Get-IntuneSettingsRecursive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [array]$Settings,
        
        [Parameter()]
        [int]$Depth = 0
    )

    $allSettings = @()
    $indent = (' ' * ($Depth * 2))

    foreach ($setting in $Settings) {
        if ($DebugMode) {
            Write-Host "$indent[DEBUG] Processing setting..." -ForegroundColor White
            if ($setting.settingInstance.settingDefinitionId) {
                Write-Host "$indent[DEBUG] → DefinitionId: $($setting.settingInstance.settingDefinitionId)" -ForegroundColor Cyan
            }
        }

        # Process settings with definition IDs
        if ($setting.settingInstance.settingDefinitionId) {
            # For choice settings, use the actual choice value which may have suffix
            if ($setting.settingInstance.choiceSettingValue -and $setting.settingInstance.choiceSettingValue.value) {
                $allSettings += [pscustomobject]@{
                    settingInstance = [pscustomobject]@{
                        settingDefinitionId = $setting.settingInstance.choiceSettingValue.value
                    }
                }
            } else {
                $allSettings += $setting
            }
        }

        # Recursively process child settings
        if ($setting.settingInstance.choiceSettingValue -and $setting.settingInstance.choiceSettingValue.children) {
            $children = $setting.settingInstance.choiceSettingValue.children
            if ($DebugMode) {
                Write-Host "$indent[DEBUG] Found $($children.Count) children for $($setting.settingInstance.settingDefinitionId)" -ForegroundColor Yellow
            }

            foreach ($child in $children) {
                if ($child.settingInstance) {
                    $allSettings += Get-IntuneSettingsRecursive -Settings @($child) -Depth ($Depth + 1)
                }
                elseif ($child.choiceSettingValue) {
                    if ($DebugMode) {
                        Write-Host "$indent  [DEBUG] → Leaf child detected with value: $($child.choiceSettingValue.value)" -ForegroundColor Green
                    }

                    $allSettings += [pscustomobject]@{
                        settingInstance = [pscustomobject]@{
                            settingDefinitionId = $child.choiceSettingValue.value
                        }
                    }
                }
                elseif ($child.simpleSettingValue) {
                    if ($DebugMode) {
                        Write-Host "$indent  [DEBUG] → Simple setting detected: $($child.settingDefinitionId)" -ForegroundColor Green
                    }

                    $allSettings += [pscustomobject]@{
                        settingInstance = [pscustomobject]@{
                            settingDefinitionId = $child.settingDefinitionId
                            simpleSettingValue = $child.simpleSettingValue
                        }
                    }
                }
            }
        }
    }

    Write-Verbose "Extracted $($allSettings.Count) settings at depth $Depth"
    return $allSettings
}

#endregion Helper Functions

#region Main Script Logic

try {
    Write-Host "Starting Intune to Fleet CSP conversion..." -ForegroundColor Green
    Write-Verbose "JsonPath: $JsonPath"
    Write-Verbose "OutputPath: $OutputPath"
    Write-Verbose "DryRun: $DryRun"

    # Load and validate resolver map
    if (-not (Test-Path $ResolverMapPath)) { 
        throw "Resolver map file not found at $ResolverMapPath" 
    }
    
    try {
        $ResolverMap = Get-Content $ResolverMapPath | ConvertFrom-Json
        Write-Verbose "Loaded resolver map successfully"
    }
    catch {
        throw "Failed to parse resolver map JSON: $($_.Exception.Message)"
    }

    # Create output directory
    if (-not (Test-Path $OutputPath)) { 
        New-Item -ItemType Directory -Path $OutputPath | Out-Null
        Write-Verbose "Created output directory: $OutputPath"
    }

    # Initialize tracking variables
    $log = @()
    $summary = @{
        TotalPolicies = 0
        Exported      = 0
        Skipped       = 0
        NotFound      = 0
        Resolved      = 0
    }

    # Load and validate Intune JSON
    try {
        $json = Get-Content $JsonPath | ConvertFrom-Json
        
        if (-not $json.settings) {
            throw "Invalid Intune JSON: Missing 'settings' property"
        }
        
        Write-Host "Loaded Intune JSON with $($json.settings.Count) top-level settings" -ForegroundColor Cyan
    }
    catch {
        throw "Failed to load or parse Intune JSON: $($_.Exception.Message)"
    }

    # Extract all settings recursively
    Write-Host "Processing Intune JSON settings..." -ForegroundColor Cyan
    $allSettings = Get-IntuneSettingsRecursive -Settings $json.settings
    Write-Host "Extracted $($allSettings.Count) individual settings for processing" -ForegroundColor Cyan

    # Prepare merged XML collection if needed
    $mergedXmlContent = @()

    # Process each setting
    foreach ($setting in $allSettings) {
        $summary.TotalPolicies++
        $definitionId = $setting.settingInstance.settingDefinitionId
        $originalDefinitionId = $definitionId

        Write-Verbose "Processing setting: $originalDefinitionId"

        try {
            # Handle simple setting values (strings, integers) - with registry lookup for proper casing
            if ($setting.settingInstance.simpleSettingValue) {
                $simpleValue = $setting.settingInstance.simpleSettingValue
                $nodeUriFragment = "./" + ($definitionId -replace '^vendor_', 'Vendor/' -replace '_', '/')
                Write-Host "Processing simple setting: $nodeUriFragment (searching registry for proper casing)" -ForegroundColor Yellow
                
                # Registry lookup for correct TitleCase NodeURI - critical for CSP success
                $matchedNodes = Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Provisioning\NodeCache\CSP\Device\MS DM Server\Nodes' -Recurse -ErrorAction SilentlyContinue |
                    Get-ItemProperty -ErrorAction SilentlyContinue |
                    Where-Object { $_.NodeUri -like "*$nodeUriFragment" } |
                    Select-Object NodeUri, ExpectedValue

                $actualNodeUri = $nodeUriFragment  # Default fallback
                if ($matchedNodes) {
                    $actualNodeUri = $matchedNodes[0].NodeUri  # Use first match with proper casing
                    Write-Host "Found registry match: $actualNodeUri" -ForegroundColor Green
                } else {
                    Write-Host "No registry match found, using constructed path: $actualNodeUri" -ForegroundColor Yellow
                }
                
                $formatData = Get-SyncMLFormatAndData -DefinitionId $definitionId -Suffix $null -SimpleSettingValue $simpleValue
                
                if ($formatData.IsValid) {
                    $summary.Exported++
                    $safeFileName = ($actualNodeUri -replace '[^a-zA-Z0-9]', '_') + ".xml"
                    $xmlPath = Join-Path $OutputPath $safeFileName
                    
                    $xmlEntry = @"
<Replace>
    <Item>
        <Meta>
            <Format xmlns="syncml:metinf">$($formatData.Format)</Format>
        </Meta>
        <Target>
            <LocURI>$actualNodeUri</LocURI>
        </Target>
        <Data>$($formatData.DataValue)</Data>
    </Item>
</Replace>
"@
                    
                    if ($MergeXml) {
                        $mergedXmlContent += $xmlEntry
                    }
                    elseif (-not $DryRun) {
                        Save-XmlFile -Content $xmlEntry -Path $xmlPath
                    }
                    
                    Write-Host "[EXPORTED] $actualNodeUri => $($formatData.DataValue) ($($formatData.Format))" -ForegroundColor Green
                    $log += [pscustomobject]@{
                        Setting = $originalDefinitionId
                        NodeUri = $actualNodeUri
                        Status = "Exported"
                        Value = $formatData.DataValue
                        Notes = "Simple setting value ($($formatData.Format))"
                    }
                }
                continue
            }
            
            # Extract and strip value suffix for choice settings (only match known valid suffixes)
            $suffix = $null
            if ($definitionId -match "(_true|_false|_1|_0|_enabled|_disabled|_allow|_block|_\d+)$") {
                $suffix = $Matches[1]
                $definitionId = $definitionId -replace "(_true|_false|_1|_0|_enabled|_disabled|_allow|_block|_\d+)$", ""
            }

            $nodeUriFragment = "./" + ($definitionId -replace '^vendor_', 'Vendor/' -replace '_', '/')
            Write-Host "Searching for $nodeUriFragment..." -ForegroundColor Yellow

            # Registry lookup to get the actual NodeURI and ExpectedValue
            # This is critical because Windows CSPs are case-sensitive
            $matchedNodes = Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Provisioning\NodeCache\CSP\Device\MS DM Server\Nodes' -Recurse -ErrorAction SilentlyContinue |
                Get-ItemProperty -ErrorAction SilentlyContinue |
                Where-Object { $_.NodeUri -like "*$nodeUriFragment" } |
                Select-Object NodeUri, ExpectedValue

            if (-not $matchedNodes) {
                Write-Warning "No match found for $nodeUriFragment"
                $summary.NotFound++
                $log += [pscustomobject]@{
                    Setting = $originalDefinitionId
                    NodeUri = $nodeUriFragment
                    Status = "Not Found"
                    Value = ""
                    Notes = "No matching NodeUri in registry"
                }
                continue
            }

            foreach ($node in $matchedNodes) {
                $finalValue = $null
                $finalFormat = "int"
                $status = "Exported"
                $notes = ""
                $registryValue = $null

                # Get the registry value first
                # ExpectedValue meanings: 1=enabled, 0=disabled, -1=requires resolver
                switch ($node.ExpectedValue) {
                    1 { 
                        $registryValue = 1
                        $status = "Exported"
                    }
                    0 { 
                        $registryValue = 0
                        $status = "Exported"
                    }
                    -1 {
                        # Use resolver to get the actual value
                        # This handles policies where the actual value must be determined at runtime
                        $lastSegment = ($node.NodeUri -split '/')[-1]

                        if ($DebugMode) {
                            Write-Host "[DEBUG] NodeUri: $($node.NodeUri)" -ForegroundColor Magenta
                            Write-Host "[DEBUG] Last segment: $lastSegment" -ForegroundColor Magenta
                        }

                        $resolverKey = $ResolverMap.PSObject.Properties | Where-Object { 
                            ($_.Name -split '/')[ -1 ] -ieq $lastSegment
                        }

                        if ($resolverKey) {
                            try {
                                $resolvedValue = Invoke-Expression $resolverKey.Value
                                if ($resolvedValue -eq 1 -or $resolvedValue -eq 0) {
                                    $registryValue = $resolvedValue
                                    $status = "Resolved"
                                    $notes = "Resolved from -1 using resolver"
                                    $summary.Resolved++
                                }
                                else {
                                    $notes = "Resolver returned invalid value: $resolvedValue"
                                }
                            }
                            catch {
                                $notes = "Resolver execution failed: $($_.Exception.Message)"
                                Write-Warning "Resolver failed for $($resolverKey.Name): $($_.Exception.Message)"
                            }
                        }
                        else {
                            # No resolver available - use JSON suffix to determine default value
                            # This provides fallback logic when resolvers aren't available
                            if ($suffix) {
                                switch -Regex ($suffix) {
                                    "^(_true|_enabled|_allow)$" {
                                        $registryValue = 1
                                        $status = "Default"
                                        $notes = "Default value from JSON suffix (no resolver available)"
                                    }
                                    "^(_false|_disabled|_block)$" {
                                        $registryValue = 0
                                        $status = "Default"
                                        $notes = "Default value from JSON suffix (no resolver available)"
                                    }
                                    "^(_1|_\d+)$" {
                                        # Extract numeric value from suffix
                                        $numericValue = [int]($suffix -replace '^_', '')
                                        $registryValue = $numericValue
                                        $status = "Default"
                                        $notes = "Default value from JSON suffix (no resolver available)"
                                    }
                                    "^(_0)$" {
                                        $registryValue = 0
                                        $status = "Default"
                                        $notes = "Default value from JSON suffix (no resolver available)"
                                    }
                                    default {
                                        $notes = "No resolver available and unable to determine default from suffix: $suffix"
                                    }
                                }
                            } else {
                                $notes = "No resolver available for this policy and no suffix to infer default"
                            }
                        }
                    }
                }

                # Determine format and final value based on registry value + JSON suffix
                # This is where we apply the boolean vs integer format logic
                if ($null -ne $registryValue) {
                    if ($suffix) {
                        # We have a suffix, so determine format based on suffix type
                        switch -Regex ($suffix) {
                            "^(_true|_false|_enabled|_disabled|_allow|_block)$" {
                                # Boolean-style suffix - use bool format
                                $finalFormat = "bool"
                                if ($registryValue -eq 1) {
                                    $finalValue = "true"
                                } else {
                                    $finalValue = "false"
                                }
                            }
                            "^(_1|_0|_\d+)$" {
                                # Numeric suffix - use int format with registry value
                                $finalFormat = "int"
                                $finalValue = $registryValue
                            }
                            default {
                                # Unknown suffix - default to int format
                                $finalFormat = "int"
                                $finalValue = $registryValue
                            }
                        }
                    } else {
                        # No suffix - default to int format with registry value
                        $finalFormat = "int"
                        $finalValue = $registryValue
                    }
                }

                if ($null -ne $finalValue) {
                    $summary.Exported++
                    $safeFileName = ($node.NodeUri -replace '[^a-zA-Z0-9]', '_') + ".xml"
                    $xmlPath = Join-Path $OutputPath $safeFileName

                    $xmlEntry = @"
<Replace>
    <Item>
        <Meta>
            <Format xmlns="syncml:metinf">$finalFormat</Format>
        </Meta>
        <Target>
            <LocURI>$($node.NodeUri)</LocURI>
        </Target>
        <Data>$finalValue</Data>
    </Item>
</Replace>
"@

                    if ($MergeXml) {
                        $mergedXmlContent += $xmlEntry
                    }
                    elseif (-not $DryRun) {
                        Save-XmlFile -Content $xmlEntry -Path $xmlPath
                    }

                    Write-Host "[EXPORTED] $($node.NodeUri) => $finalValue ($finalFormat)" -ForegroundColor Green
                    $log += [pscustomobject]@{
                        Setting = $originalDefinitionId
                        NodeUri = $node.NodeUri
                        Status = $status
                        Value = $finalValue
                        Notes = "$notes ($finalFormat)"
                    }
                }
                else {
                    $summary.Skipped++
                    $log += [pscustomobject]@{
                        Setting = $originalDefinitionId
                        NodeUri = $node.NodeUri
                        Status = "Skipped"
                        Value = ""
                        Notes = $notes
                    }
                }
            }
        }
        catch {
            Write-Error "Error processing setting '$originalDefinitionId': $($_.Exception.Message)"
            $log += [pscustomobject]@{
                Setting = $originalDefinitionId
                NodeUri = ""
                Status = "Error"
                Value = ""
                Notes = "Processing error: $($_.Exception.Message)"
            }
        }
    }

    # Write merged XML file if requested
    if ($MergeXml -and -not $DryRun) {
        $mergedFilePath = Join-Path $OutputPath "MergedPolicies.xml"
        $mergedContent = $mergedXmlContent -join "`n"
        Save-XmlFile -Content $mergedContent -Path $mergedFilePath
        Write-Host "Merged XML saved to $mergedFilePath" -ForegroundColor Cyan
    }

    # Export log
    if (-not $DryRun) {
        $log | Export-Csv -Path $LogPath -NoTypeInformation
        Write-Host "Conversion log saved to $LogPath" -ForegroundColor Cyan
    }

    # Display summary report
    Write-Host "`n===== CONVERSION SUMMARY =====" -ForegroundColor Green
    Write-Host "Total Policies: $($summary.TotalPolicies)" -ForegroundColor White
    Write-Host "Exported:       $($summary.Exported)" -ForegroundColor Green
    Write-Host "Resolved:       $($summary.Resolved)" -ForegroundColor Yellow
    Write-Host "Skipped:        $($summary.Skipped)" -ForegroundColor Yellow
    Write-Host "Not Found:      $($summary.NotFound)" -ForegroundColor Red
    Write-Host "===============================" -ForegroundColor Green

    if ($DryRun) {
        Write-Host "`nDRY RUN: No files were created" -ForegroundColor Cyan
    } else {
        Write-Host "`nOutput files created in: $OutputPath" -ForegroundColor Cyan
    }

    Write-Host "`nConversion completed successfully!" -ForegroundColor Green
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}

#endregion Main Script Logic
