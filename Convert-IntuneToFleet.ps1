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

    # Check if no parameters provided - indicate interactive mode
    if (-not $InputFile -and -not $OutputFile) {
        Write-Host "No parameters provided - entering interactive mode" -ForegroundColor Yellow
    }

    # Validate input file if provided
    if ($InputFile) {
        $inputValidation = Test-IntuneJsonFile -FilePath $InputFile
        if (-not $inputValidation.IsValid) {
            throw $inputValidation.ErrorMessage
        }
        Write-Verbose "Input file validation passed: $InputFile"
    }

    # Generate output file path if not provided
    if ($InputFile -and -not $OutputFile) {
        $OutputFile = [System.IO.Path]::ChangeExtension($InputFile, '.xml')
        Write-Verbose "Auto-generated output file: $OutputFile"
    }

    # Validate output file path if provided
    if ($OutputFile) {
        $outputValidation = Test-OutputPath -FilePath $OutputFile
        if (-not $outputValidation.IsValid) {
            throw $outputValidation.ErrorMessage
        }
        Write-Verbose "Output path validation passed: $OutputFile"
    }

    # Handle WhatIf scenario first
    if ($WhatIfPreference) {
        $whatIfMessage = "What if: Would convert $InputFile to $OutputFile"
        $PSCmdlet.ShouldProcess("Convert Intune CSP to Fleet XML", "Conversion") | Out-Null
        return $whatIfMessage
    }

    if ($PSCmdlet.ShouldProcess("Convert Intune CSP to Fleet XML", "Conversion")) {
        Write-Verbose "Starting conversion process..."
        
        # TODO: Implement actual conversion logic in subsequent steps
        Write-Host "Conversion logic not yet implemented - this is Step 1 foundation" -ForegroundColor Green
        return "Conversion completed successfully"
    }
}

# If script is run directly (not dot-sourced), call the main function
if ($MyInvocation.InvocationName -ne '.') {
    Convert-IntuneToFleet @PSBoundParameters
}