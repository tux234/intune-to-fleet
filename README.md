# Intune to Fleet CSP Converter

A PowerShell tool that converts Microsoft Intune configuration policy JSON exports into Fleet-compatible Windows Configuration Service Provider (CSP) XML files.

## Overview

This tool assists in migrating Microsoft Intune enrolled devices to Fleet by converting Intune policies into the SyncML XML format required by Fleet's Windows configuration profiles.

### Key Features

- **Universal Conversion**: Handles any Intune policy type with ~80% coverage out of the box
- **Intelligent Format Detection**: Automatically determines the correct SyncML format (bool, int, chr) based on Microsoft CSP documentation
- **Registry-Based Path Resolution**: Uses Windows CSP NodeCache registry to make sure proper TitleCase NodeURI paths
- **Runtime Policy Resolution**: Resolver map system for policies requiring dynamic value determination
- **Comprehensive Logging**: Detailed CSV logs showing conversion status for each policy

## Files

- **`Convert-IntuneToFleetCSP.ps1`** - Main production-ready conversion script
- **`resolver-map.json`** - Configuration file containing PowerShell expressions for complex policy resolution

## Quick Start

1. **Export your Intune policy**:
   - Go to Microsoft Intune Admin Center
   - Navigate to Devices > [Configuration](https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/DevicesMenu/~/configuration)
   - Select your policy and export as JSON

2. **Run the converter**:
   ```powershell
   .\Convert-IntuneToFleetCSP.ps1 -JsonPath "C:\Path\To\Your\Policy.json"
   ```

3. **Review the output**:
   - Individual XML files created in `C:\CSPConverter\Output\`
   - Conversion log saved to `C:\CSPConverter\ConversionLog.csv`

## Usage Examples

### Basic Conversion
```powershell
.\Convert-IntuneToFleetCSP.ps1 -JsonPath "MyFirewallPolicy.json"
```

### Create Single Merged File
```powershell
.\Convert-IntuneToFleetCSP.ps1 -JsonPath "MyPolicy.json" -MergeXml -OutputPath "C:\Fleet\CSPs"
```

### Debug Mode with Dry Run
```powershell
.\Convert-IntuneToFleetCSP.ps1 -JsonPath "MyPolicy.json" -DebugMode -DryRun
```

### Custom Resolver Map
```powershell
.\Convert-IntuneToFleetCSP.ps1 -JsonPath "MyPolicy.json" -ResolverMapPath "C:\Custom\resolver-map.json"
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `JsonPath` | Path to Intune policy JSON export file | *Required* |
| `ResolverMapPath` | Path to resolver map JSON file | `C:\CSPConverter\resolver-map.json` |
| `OutputPath` | Directory for output XML files | `C:\CSPConverter\Output` |
| `LogPath` | Path for conversion log CSV file | `C:\CSPConverter\ConversionLog.csv` |
| `DebugMode` | Enable verbose debug output | `$false` |
| `DryRun` | Analyze only, don't create files | `$false` |
| `MergeXml` | Create single merged XML file | `$false` |

## How It Works

### 1. Policy Extraction
The script recursively parses the nested Intune JSON structure, extracting all individual policy settings, including parent choice values and child configurations.

### 2. Registry Lookup
For each policy, the script queries the Windows CSP NodeCache registry to:
- Find the exact NodeURI path with proper TitleCase formatting
- Retrieve the ExpectedValue (1=enabled, 0=disabled, -1=requires resolver)

### 3. Format Detection
Based on Microsoft CSP documentation and testing, the script determines whether each policy should use:
- **`bool` format**: For policies that explicitly require true/false values
- **`int` format**: For most policies using 0/1 values  
- **`chr` format**: For string values with CDATA wrapping

### 4. Value Resolution
For policies with ExpectedValue = -1, the script uses the resolver map to execute PowerShell expressions that determine the current system value.

### 5. XML Generation
Each policy is converted to proper SyncML XML format:
```xml
<Replace>
    <Item>
        <Meta>
            <Format xmlns="syncml:metinf">bool</Format>
        </Meta>
        <Target>
            <LocURI>./Vendor/MSFT/Firewall/MdmStore/PrivateProfile/EnableFirewall</LocURI>
        </Target>
        <Data>true</Data>
    </Item>
</Replace>
```

## Resolver Map

The `resolver-map.json` file contains PowerShell expressions for policies that Intune sometimes leaves unset (ExpectedValue = -1). The script uses this file to query the Registry to verify the value. Each entry maps a CSP path segment to a PowerShell command:

```json
{
  "EnableFirewall": "if (@(Get-NetFirewallProfile | Where-Object { $_.Enabled -eq 'True' }).Count -gt 0) { 1 } else { 0 }",
  "RealTimeProtection": "try { if ((Get-MpPreference -ErrorAction Stop).DisableRealtimeMonitoring -eq $false) { 1 } else { 0 } } catch { 1 }"
}
```

## Customization

### Adding Boolean Format Policies
To specify additional policies that should use boolean format, edit the `$booleanFormatPolicies` array in the `Get-SyncMLFormatAndData` function:

```powershell
$booleanFormatPolicies = @(
    "*firewall*enablefirewall*",
    "*your*custom*policy*pattern*"
)
```

### Adding Custom Resolvers
Add entries to `resolver-map.json` for policies requiring dynamic value resolution:

```json
{
  "YourPolicyName": "PowerShell expression that returns 1 or 0"
}
```

## Troubleshooting

### Common Issues

**"No match found for NodeURI"**
- The policy may not be supported on your Windows version
- Try running on a system where the policy has been applied via Intune

**"Resolver execution failed"**
- Check that the required PowerShell modules are available
- Verify the resolver expression syntax in `resolver-map.json`

### Debug Mode
Enable debug mode to see detailed processing information:
```powershell
.\Convert-IntuneToFleetCSP.ps1 -JsonPath "MyPolicy.json" -DebugMode
```

## Requirements

- **PowerShell 5.1 or later**
- **Windows system** enrolled in Intune to retrieve settings from NodeCache 
- **Administrative rights** for registry access (recommended)

## Contributing

The script is designed for ~80% coverage of standard Intune policies. For edge cases:

1. Add patterns to the `$booleanFormatPolicies` array
2. Create resolver map entries for complex policies  
3. Test with your specific policy types

## Support

For issues or questions:
- Check the conversion log CSV for detailed status information
- Use debug mode to troubleshoot specific policies
- Review Microsoft CSP documentation for policy-specific requirements

## References

- [Microsoft CSP Documentation](https://learn.microsoft.com/en-us/windows/client-management/mdm/)
- [Configuring Fleet OS settings for Windows](https://fleetdm.com/guides/creating-windows-csps#basic-article)
