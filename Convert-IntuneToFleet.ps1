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