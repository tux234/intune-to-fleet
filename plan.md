# Intune to Fleet CSP Conversion Tool - TDD Development Plan

## High-Level Architecture Overview

The PowerShell script will be structured as a modular system with clear separation of concerns:

1. **Parameter Handling & User Input** - CLI parameters with interactive fallback
2. **JSON Processing** - Parse and validate Intune export files  
3. **Registry Lookup Engine** - Query Windows Registry for CSP values
4. **XML Generation** - Create Fleet-compatible SyncML XML
5. **Logging & Reporting** - Progress tracking and error reporting
6. **Main Orchestration** - Coordinate all components

## Iterative Development Phases

### Phase 1: Foundation & Core Infrastructure
- Parameter handling system
- Basic logging framework
- File I/O utilities
- Test infrastructure setup

### Phase 2: JSON Processing Engine
- JSON validation and parsing
- Setting extraction (recursive traversal)
- Data structure modeling

### Phase 3: Registry Lookup System
- Registry query function
- Error handling for registry access
- Data type determination logic

### Phase 4: XML Generation Engine
- SyncML XML structure creation
- Data formatting and escaping
- Output file generation

### Phase 5: Integration & User Experience
- Main workflow orchestration
- Progress reporting
- Error summary generation
- End-to-end testing

## Detailed Step-by-Step Implementation

### Step 1: Project Setup and Parameter Handling
**Goal**: Create the basic script structure with parameter handling and help system
**Test Focus**: Parameter validation, help output, error handling for missing inputs

### Step 2: File I/O and Validation Framework
**Goal**: Build robust file handling with proper validation
**Test Focus**: File existence checks, permission validation, JSON structure validation

### Step 3: Logging Infrastructure
**Goal**: Implement comprehensive logging system
**Test Focus**: Log file creation, different log levels, progress tracking

### Step 4: JSON Parser Foundation
**Goal**: Create basic JSON parsing with validation
**Test Focus**: Parse valid/invalid JSON, identify Intune export structure

### Step 5: Setting Extraction Engine
**Goal**: Recursively extract all settingDefinitionId entries
**Test Focus**: Handle nested children, extract all CSP identifiers, track line numbers

### Step 6: Registry Mock Framework (for Testing)
**Goal**: Create testable registry interface with mock capability
**Test Focus**: Registry abstraction layer, mock registry for unit tests

### Step 7: Registry Lookup Implementation
**Goal**: Implement actual Windows Registry queries
**Test Focus**: Registry search functionality, error handling for missing entries

### Step 8: Data Type Detection
**Goal**: Determine int vs chr format based on registry values
**Test Focus**: Type detection logic, edge cases, default handling

### Step 9: XML Structure Generator
**Goal**: Create SyncML XML building blocks
**Test Focus**: Valid XML generation, namespace handling, escaping

### Step 10: XML Assembly Engine
**Goal**: Combine individual settings into complete XML document
**Test Focus**: Multi-setting XML documents, proper formatting

### Step 11: Error Tracking System
**Goal**: Track and report skipped entries with context
**Test Focus**: Error collection, line number tracking, summary generation

### Step 12: Progress Reporting
**Goal**: User-friendly progress indicators during processing
**Test Focus**: Progress calculation, console output formatting

### Step 13: Main Workflow Integration
**Goal**: Connect all components into complete workflow
**Test Focus**: End-to-end processing, error propagation, cleanup

### Step 14: Interactive Mode Implementation
**Goal**: Add fallback prompts when CLI parameters missing
**Test Focus**: User input handling, file selection, validation

### Step 15: Final Polish and Error Handling
**Goal**: Comprehensive error handling and user experience improvements
**Test Focus**: Edge cases, error messages, graceful degradation

## TDD Implementation Prompts

### ✅ Prompt 1: Project Setup and Parameter Handling - COMPLETED

```
Create a PowerShell script called Convert-IntuneToFleet.ps1 that implements robust parameter handling with the following requirements:

REQUIREMENTS:
- Accept -InputFile and -OutputFile parameters (both optional)
- Provide comprehensive help with Get-Help support
- Include parameter validation (file extensions, paths)
- Support -WhatIf and -Verbose common parameters
- Follow PowerShell best practices for cmdlet development

TESTING REQUIREMENTS:
- Create Pester tests that validate parameter binding
- Test help system functionality  
- Test parameter validation with invalid inputs
- Test behavior when no parameters provided
- Mock file system interactions for testing

START WITH FAILING TESTS:
Write tests first that define the expected behavior, then implement the minimal code to make them pass.

DELIVERABLES:
1. Convert-IntuneToFleet.ps1 with parameter structure
2. Convert-IntuneToFleet.Tests.ps1 with comprehensive parameter tests
3. Ensure all tests pass
4. Document parameter usage in comment-based help
```

### ✅ Prompt 2: File I/O and Validation Framework - COMPLETED

```
Building on the previous parameter handling foundation, implement file I/O and validation capabilities:

REQUIREMENTS:
- Function Test-IntuneJsonFile to validate input files
- Function Test-OutputPath to validate output file paths
- Check file existence, permissions, and JSON structure
- Detect Intune export format (presence of settings array, @odata.context)
- Return structured validation results with specific error messages

TESTING REQUIREMENTS:
- Create test JSON files (valid Intune export, invalid JSON, wrong format)
- Test file permission scenarios (read-only, non-existent paths)
- Test validation logic with various JSON structures
- Mock file system operations where appropriate

INTEGRATION:
- Wire validation functions into main parameter handling from Step 1
- Update parameter validation to use new validation functions
- Ensure existing tests still pass

START WITH FAILING TESTS:
Write tests that define expected validation behavior before implementing functions.

DELIVERABLES:
1. Updated Convert-IntuneToFleet.ps1 with validation functions
2. Test files for validation scenarios
3. Updated tests covering new validation logic
4. Integration with existing parameter system
```

### ✅ Prompt 3: Logging Infrastructure - COMPLETED

```
Implement a comprehensive logging system integrated with the existing script:

REQUIREMENTS:
- Function Write-ConversionLog for structured logging
- Support log levels: Info, Warning, Error, Debug
- Log to file with timestamps and structured format
- Console output with progress indicators
- Log file naming based on output file name
- Thread-safe logging implementation

TESTING REQUIREMENTS:
- Test log file creation and writing
- Test different log levels and filtering
- Test console vs file output differences
- Test log file naming conventions
- Mock file operations for testing

INTEGRATION:
- Integrate logging into parameter validation from previous steps
- Update error handling to use logging system
- Ensure all console output goes through logging framework
- Maintain existing functionality while adding logging

START WITH FAILING TESTS:
Define logging behavior through tests before implementation.

DELIVERABLES:
1. Updated Convert-IntuneToFleet.ps1 with logging functions
2. Comprehensive logging tests
3. Integration with existing validation and parameter systems
4. Documentation of logging levels and usage
```

### ✅ Prompt 4: JSON Parser Foundation - COMPLETED

```
Create JSON processing capabilities building on existing validation:

REQUIREMENTS:
- Function Get-IntuneSettings to parse validated JSON
- Extract basic metadata (name, description, settingCount)
- Parse settings array structure
- Handle malformed JSON gracefully with detailed error messages
- Return structured PowerShell objects for further processing

TESTING REQUIREMENTS:
- Use the provided firewall JSON example as primary test case
- Test with various JSON structures and edge cases
- Test error handling for malformed JSON
- Validate returned object structure and properties
- Performance testing with large JSON files

INTEGRATION:
- Build on validation framework from Step 2
- Integrate with logging system from Step 3
- Use existing parameter handling for file input
- Ensure all error conditions are properly logged

START WITH FAILING TESTS:
Write tests defining expected JSON parsing behavior and object structure.

DELIVERABLES:
1. Updated Convert-IntuneToFleet.ps1 with JSON parsing functions
2. Comprehensive JSON parsing tests using real data
3. Error handling integration with logging system
4. Performance baseline for typical JSON sizes
```

### Prompt 5: Setting Extraction Engine

```
Implement recursive setting extraction from parsed JSON:

REQUIREMENTS:
- Function Get-AllSettingDefinitionIds to recursively traverse JSON
- Extract all settingDefinitionId values including nested children
- Track line numbers/paths for error reporting
- Handle both choiceSettingValue and simpleSettingValue types
- Return collection with setting ID, value, and location context

TESTING REQUIREMENTS:
- Test with firewall example (should find ~32 settingDefinitionIds)
- Test recursive traversal of nested children settings
- Test line number/path tracking accuracy
- Test different setting value types
- Validate complete extraction (no missed settings)

INTEGRATION:
- Use JSON parser from Step 4 as input
- Integrate with logging for extraction progress
- Build structured data for registry lookup phase
- Ensure extraction results are properly logged

START WITH FAILING TESTS:
Define expected extraction results for known JSON structures.

DELIVERABLES:
1. Updated Convert-IntuneToFleet.ps1 with recursive extraction logic
2. Tests validating complete setting extraction
3. Line number tracking and error context
4. Integration with existing JSON parsing pipeline
```

### Prompt 6: Registry Mock Framework

```
Create testable registry interface with mock capabilities:

REQUIREMENTS:
- Abstract interface for registry operations (Get-CSPRegistryValue)
- Mock implementation for unit testing (Mock-CSPRegistry)
- Test data setup simulating real registry structure
- Support for missing entries, access denied, malformed data scenarios
- Clean separation between registry logic and business logic

TESTING REQUIREMENTS:
- Create comprehensive mock registry data based on firewall example
- Test registry abstraction with known CSP entries
- Test error scenarios (missing, access denied, corrupt data)
- Validate mock behavior matches expected real registry responses
- Performance testing of registry operations

INTEGRATION:
- Design interface for integration with setting extraction from Step 5
- Prepare for real registry implementation in next step
- Ensure mockable design for all downstream components

START WITH FAILING TESTS:
Define registry interface behavior through tests before implementation.

DELIVERABLES:
1. Updated Convert-IntuneToFleet.ps1 with registry abstraction
2. Mock registry implementation with test data
3. Comprehensive registry interface tests
4. Foundation for real registry implementation
```

### Prompt 7: Registry Lookup Implementation

```
Implement actual Windows Registry queries using the abstraction from Step 6:

REQUIREMENTS:
- Function Get-CSPRegistryValue implementing real registry queries
- Based on provided PowerShell one-liner approach
- Handle Windows Registry path traversal and search
- Robust error handling for missing entries, access issues
- Performance optimization for batch registry queries

TESTING REQUIREMENTS:
- Integration tests requiring actual registry (skip if not available)
- Test registry search patterns and result extraction
- Test error handling for various registry issues
- Validate results match expected NodeUri/ExpectedValue format
- Performance testing with multiple concurrent lookups

INTEGRATION:
- Replace mock registry with real implementation
- Maintain compatibility with abstraction interface from Step 6
- Integrate with setting extraction pipeline from Step 5
- Ensure comprehensive error logging for registry issues

START WITH FAILING TESTS:
Define real registry behavior expectations through tests.

DELIVERABLES:
1. Updated Convert-IntuneToFleet.ps1 with real registry implementation
2. Integration tests for registry functionality
3. Error handling for all registry scenarios
4. Performance optimization for batch operations
```

### Prompt 8: Data Type Detection

```
Implement data type detection logic for registry values:

REQUIREMENTS:
- Function Get-CSPDataType to determine int vs chr format
- Analyze ExpectedValue from registry to determine type
- Handle edge cases (null, empty, non-standard values)
- Provide sensible defaults when type cannot be determined
- Return structured type information for XML generation

TESTING REQUIREMENTS:
- Test type detection with various registry value types
- Test edge cases and malformed data
- Validate type detection accuracy against known CSP examples
- Test default handling for ambiguous cases
- Performance testing of type detection logic

INTEGRATION:
- Integrate with registry lookup from Step 7
- Prepare data structure for XML generation
- Ensure type information is properly logged
- Build on existing error handling patterns

START WITH FAILING TESTS:
Define type detection behavior through comprehensive tests.

DELIVERABLES:
1. Updated Convert-IntuneToFleet.ps1 with type detection logic
2. Comprehensive type detection tests
3. Integration with registry lookup pipeline
4. Structured data preparation for XML generation
```

### Prompt 9: XML Structure Generator

```
Create SyncML XML building blocks for Fleet compatibility:

REQUIREMENTS:
- Function New-CSPXmlItem to create individual <Replace><Item> blocks
- Proper XML namespace handling (syncml:metinf)
- XML escaping and data sanitization  
- Support for both int and chr data formats
- Validate generated XML structure

TESTING REQUIREMENTS:
- Test XML generation with various data types and values
- Test XML escaping for special characters
- Validate generated XML against expected Fleet format
- Test namespace and formatting correctness
- Performance testing for XML generation

INTEGRATION:
- Use data type detection from Step 8
- Integrate with registry lookup results from Step 7
- Prepare for XML assembly in next step
- Ensure generated XML blocks are valid and well-formed

START WITH FAILING TESTS:
Define expected XML output through tests before implementation.

DELIVERABLES:
1. Updated Convert-IntuneToFleet.ps1 with XML generation functions
2. XML validation tests against Fleet requirements
3. Integration with type detection and registry data
4. Foundation for complete XML document assembly
```

### Prompt 10: XML Assembly Engine

```
Build complete XML document assembly from individual XML items:

REQUIREMENTS:
- Function New-FleetConfigurationXml to assemble complete document
- Combine multiple CSP items into single XML document
- Proper XML document structure and formatting
- Handle empty results (no successful registry lookups)
- Write XML to specified output file with proper encoding

TESTING REQUIREMENTS:
- Test assembly of multiple XML items into complete document
- Test XML document formatting and structure
- Test file output with various scenarios (empty, single item, multiple items)
- Validate output XML can be parsed by standard XML parsers
- Test encoding and special character handling

INTEGRATION:
- Use XML item generation from Step 9
- Integrate with file I/O framework from Step 2
- Build on logging infrastructure for output tracking
- Prepare for error tracking integration

START WITH FAILING TESTS:
Define complete XML document requirements through tests.

DELIVERABLES:
1. Updated Convert-IntuneToFleet.ps1 with XML assembly functions
2. Complete XML document tests
3. File output integration and testing
4. XML validation and formatting verification
```

### Prompt 11: Error Tracking System

```
Implement comprehensive error tracking and reporting:

REQUIREMENTS:
- Function Add-SkippedSetting to track failed conversions
- Collect setting context (line numbers, setting IDs, error reasons)
- Generate summary report of all skipped entries
- Provide actionable guidance for manual resolution
- Integration with existing logging framework

TESTING REQUIREMENTS:
- Test error collection and context tracking
- Test summary report generation and formatting
- Test integration with various error scenarios
- Validate error context accuracy and usefulness
- Test error reporting with different failure types

INTEGRATION:
- Integrate with registry lookup error handling from Step 7
- Use logging framework from Step 3 for error output
- Build on setting extraction context from Step 5
- Prepare for main workflow integration

START WITH FAILING TESTS:
Define error tracking and reporting behavior through tests.

DELIVERABLES:
1. Updated Convert-IntuneToFleet.ps1 with error tracking functions
2. Comprehensive error tracking tests
3. Integration with existing error handling
4. User-friendly error reporting and guidance
```

### Prompt 12: Progress Reporting

```
Implement user-friendly progress reporting during processing:

REQUIREMENTS:
- Function Show-ConversionProgress for progress indicators
- Display "Processing setting X of Y..." during registry lookups
- Percentage completion and estimated time remaining
- Minimal noise while providing useful feedback
- Integration with existing logging framework

TESTING REQUIREMENTS:
- Test progress calculation and display accuracy
- Test progress reporting with various dataset sizes
- Test console output formatting and user experience
- Mock long-running operations for progress testing
- Validate progress reporting doesn't interfere with other output

INTEGRATION:
- Integrate with setting extraction count from Step 5
- Use logging framework from Step 3 for console output
- Coordinate with registry lookup operations from Step 7
- Prepare for main workflow integration

START WITH FAILING TESTS:
Define progress reporting behavior and user experience through tests.

DELIVERABLES:
1. Updated Convert-IntuneToFleet.ps1 with progress reporting
2. Progress reporting tests and user experience validation
3. Integration with existing processing pipeline
4. Optimized console output formatting
```

### Prompt 13: Main Workflow Integration

```
Integrate all components into complete end-to-end workflow:

REQUIREMENTS:
- Function Convert-IntuneToFleetCSP as main orchestration function
- Connect all components: parameter handling → JSON parsing → setting extraction → registry lookup → XML generation → output
- Comprehensive error handling and cleanup
- Resource management and proper disposal
- Performance optimization for complete workflow

TESTING REQUIREMENTS:
- End-to-end integration tests with real firewall example
- Test complete workflow with various input scenarios
- Test error propagation and handling throughout pipeline
- Performance testing of complete conversion process
- Memory usage and resource cleanup validation

INTEGRATION:
- Integrate all previous components into cohesive workflow
- Ensure all error handling and logging works end-to-end
- Validate complete functionality against original requirements
- Test with provided firewall example as primary test case

START WITH FAILING TESTS:
Define complete workflow behavior through comprehensive integration tests.

DELIVERABLES:
1. Updated Convert-IntuneToFleet.ps1 with complete workflow integration
2. End-to-end integration tests
3. Performance and resource usage optimization
4. Complete functionality validation against requirements
```

### Prompt 14: Interactive Mode Implementation

```
Add interactive prompts for missing CLI parameters:

REQUIREMENTS:
- Function Get-InteractiveInput for file path prompts
- Fallback to interactive mode when parameters not provided
- File browser integration or path validation during prompts
- User-friendly prompts with examples and guidance
- Graceful exit handling for user cancellation

TESTING REQUIREMENTS:
- Test interactive prompt behavior and validation
- Test fallback logic when parameters missing
- Mock user input for automated testing
- Test user cancellation and error scenarios
- Validate seamless integration with existing parameter handling

INTEGRATION:
- Integrate with parameter handling from Step 1
- Use file validation from Step 2 for prompted paths
- Maintain compatibility with existing CLI parameter functionality
- Ensure logging captures interactive mode usage

START WITH FAILING TESTS:
Define interactive mode behavior through tests with mocked input.

DELIVERABLES:  
1. Updated Convert-IntuneToFleet.ps1 with interactive mode
2. Interactive mode tests with mocked user input
3. Integration with existing parameter and validation systems
4. User experience optimization for interactive workflows
```

### Prompt 15: Final Polish and Comprehensive Testing

```
Complete the project with final polish, comprehensive testing, and documentation:

REQUIREMENTS:
- Comprehensive error handling review and enhancement
- Performance optimization and memory usage improvement
- User experience improvements (better error messages, help)
- Code cleanup and PowerShell best practices compliance
- Complete inline documentation and examples

TESTING REQUIREMENTS:
- Complete test suite covering all functionality and edge cases
- Performance benchmarking with various file sizes
- Error scenario testing (invalid files, registry issues, permissions)  
- End-to-end testing with multiple Intune export examples
- User acceptance testing simulation

INTEGRATION:
- Final integration testing of all components
- Regression testing to ensure no functionality broken
- Documentation updates reflecting final implementation
- README creation with usage examples and troubleshooting

START WITH FAILING TESTS:
Create comprehensive test suite covering any remaining gaps in test coverage.

DELIVERABLES:
1. Final Convert-IntuneToFleet.ps1 with all functionality complete
2. Comprehensive test suite with full coverage
3. Performance benchmarks and optimization
4. Complete documentation and usage examples
5. Project ready for production use
```

## Integration Points and Dependencies

### Critical Integration Points:
1. **Parameter → File Validation → JSON Parsing**: Seamless flow from user input to structured data
2. **Setting Extraction → Registry Lookup**: Efficient processing of all discovered settings
3. **Registry Results → XML Generation**: Proper data transformation and formatting
4. **Error Tracking → Logging → User Reporting**: Comprehensive error handling throughout

### Key Dependencies:
- Each step builds on previous functionality
- Testing framework established early and maintained throughout
- Logging integrated into all components for consistency
- Error handling patterns established and reused

### Risk Mitigation:
- Mock frameworks allow testing without Windows Registry dependencies
- Incremental integration reduces complexity at each step
- Comprehensive error handling prevents data loss
- Performance testing prevents scalability issues

## Testing Strategy

### Unit Testing Approach:
- Each function tested in isolation with mocked dependencies
- Comprehensive edge case coverage
- Performance testing for critical paths
- Error scenario validation

### Integration Testing Approach:
- End-to-end workflow testing with real data
- Component interaction validation
- Error propagation testing
- Resource cleanup verification

### Test Data Management:
- Use provided firewall example as primary test case
- Create additional test cases for edge scenarios
- Mock registry data for consistent unit testing
- Performance test data for scalability validation

This plan ensures every component is thoroughly tested, properly integrated, and builds incrementally toward the complete solution while maintaining PowerShell best practices throughout.