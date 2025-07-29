# Intune to Fleet CSP Conversion Tool Specification

## Overview

A PowerShell script that automatically converts exported Intune Configuration Service Provider (CSP) JSON files into Fleet-compatible CSP XML files. The script performs comprehensive conversion of all CSP settings including nested children settings by querying the Windows Registry for actual expected values.

## Core Problem

Intune exports configuration policies as complex nested JSON structures, while Fleet requires SyncML XML format with specific CSP paths and data values. Manual conversion is time-consuming and error-prone, especially for policies with many nested settings like firewall configurations.

## MVP Scope

### Input Processing
- **Single file processing**: One JSON file input → One XML file output
- **CLI parameters with fallback**: Accept command-line arguments but prompt interactively if none provided
- **Input validation**: Verify file is valid Intune export JSON before processing

### Conversion Logic
- **Comprehensive CSP coverage**: Process ALL `settingDefinitionId` entries including nested children settings
- **Registry-based value lookup**: Use Windows Registry queries to get actual `ExpectedValue` data rather than assumptions
- **Path transformation**: Convert Intune setting IDs to proper Fleet LocURI paths
- **Data type handling**: Automatically determine and set correct format (int/chr) based on registry data

### Error Handling
- **Skip and continue**: Skip individual settings that fail registry lookup
- **Track failures**: Maintain list of skipped entries with JSON line references
- **End-of-run summary**: Present console summary of results with log file reference

### User Experience
- **Progress indicators**: Show "Processing setting X of Y..." during execution
- **Minimal console noise**: Only show progress and final success/failure status
- **Detailed logging**: Create comprehensive log file alongside XML output
- **Summary reporting**: Console summary with reference to detailed log file

## Technical Requirements

### PowerShell Script Features
- **Parameter support**: `-InputFile` and `-OutputFile` parameters
- **Interactive prompts**: Fallback file selection when parameters not provided
- **Registry access**: Function to query `HKLM:\SOFTWARE\Microsoft\Provisioning\NodeCache\CSP\Device\MS DM Server\Nodes`
- **XML generation**: Create properly formatted SyncML XML structure

### Registry Lookup Function
Based on the manual process PowerShell one-liner:
```powershell
$inputString = "settingDefinitionId"; 
Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Provisioning\NodeCache\CSP\Device\MS DM Server\Nodes' -Recurse | 
Get-ItemProperty | 
Where-Object { $_.NodeUri -like "*$inputString*" } | 
Select-Object NodeUri, ExpectedValue
```

### Data Type Logic
- If `ExpectedValue` is integer → `<Format xmlns="syncml:metinf">int</Format>`
- If `ExpectedValue` is string → `<Format xmlns="syncml:metinf">chr</Format>`
- Use `NodeUri` as `LocURI` path
- Use `ExpectedValue` as `<Data>` content

## Input/Output Examples

### Input JSON Structure
```json
{
  "settings": [
    {
      "settingInstance": {
        "settingDefinitionId": "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall",
        "choiceSettingValue": {
          "value": "vendor_msft_firewall_mdmstore_privateprofile_enablefirewall_true",
          "children": [...]
        }
      }
    }
  ]
}
```

### Expected XML Output
```xml
<Replace>
    <Item>
        <Meta>
            <Format xmlns="syncml:metinf">int</Format>
        </Meta>
        <Target>
            <LocURI>./Device/Vendor/MSFT/Firewall/MDMStore/PrivateProfile/EnableFirewall</LocURI>
        </Target>
        <Data>-1</Data>
    </Item>
</Replace>
```

## Detailed Workflow

### 1. Input Processing
- Parse command-line parameters or prompt for file paths
- Validate JSON structure contains expected Intune export format
- Count total settings for progress tracking

### 2. Setting Extraction
- Recursively traverse JSON to find all `settingDefinitionId` entries
- Handle both parent settings and nested children settings
- Extract associated values and data types

### 3. Registry Lookup
- For each `settingDefinitionId`, query Windows Registry
- Search for matching `NodeUri` containing the setting identifier
- Extract `NodeUri` (becomes LocURI) and `ExpectedValue` (becomes Data)
- Determine data format based on value type

### 4. XML Generation
- Create SyncML XML structure with proper namespaces
- Generate `<Replace><Item>` blocks for each successful lookup
- Set appropriate `<Format>` based on data type
- Skip entries where registry lookup fails

### 5. Output and Reporting
- Write XML file to specified output path
- Create detailed log file with same base name
- Display console summary with success/failure counts
- List any skipped entries with JSON line references

## Error Scenarios

### Registry Access Issues
- **Missing CSP**: Setting not found in registry → Skip with warning
- **Access denied**: Insufficient permissions → Skip with error message
- **Malformed data**: Unexpected registry structure → Skip with details

### File Handling Issues
- **Invalid JSON**: Malformed input file → Exit with clear error
- **Write permissions**: Cannot create output files → Exit with error
- **File not found**: Input file missing → Prompt for correct path

## Success Criteria

### Functional Requirements
- ✅ Successfully converts firewall policy example (2 main settings + ~30 nested children)
- ✅ Handles all CSP setting types (choice, simple string, simple integer)
- ✅ Produces valid SyncML XML that Fleet can import
- ✅ Provides clear feedback on conversion results

### Performance Requirements
- ✅ Processes typical policy (50 settings) within reasonable time (~2-3 minutes)
- ✅ Shows progress to prevent user confusion during registry lookups
- ✅ Handles large policies (200+ settings) without memory issues

### Usability Requirements
- ✅ Works with both command-line automation and interactive use
- ✅ Provides clear error messages and guidance
- ✅ Creates comprehensive logs for troubleshooting
- ✅ Follows PowerShell best practices and conventions

## Future Enhancements (Out of Scope for MVP)

- Batch processing of multiple JSON files
- GUI interface for non-technical users
- Validation of generated XML against Fleet schema
- Direct integration with Fleet API for upload
- Support for additional data types beyond int/chr
- Configuration file for custom CSP mappings

## Development Notes

### Prerequisites
- Windows environment with PowerShell 5.1+
- Administrative privileges recommended for registry access
- Valid Intune-managed device for registry CSP data

### Testing Strategy
- Use provided firewall policy example as primary test case
- Verify XML output matches expected Fleet format
- Test error handling with incomplete/invalid JSON
- Validate registry lookup function with known CSP values

### Documentation Requirements
- Inline code comments for complex logic
- README with usage examples and troubleshooting
- Sample input/output files for reference