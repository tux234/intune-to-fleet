# Intune to Fleet CSP Conversion Tool - Development Todo

## Current Status: Planning Complete ✅

## Development Phases

### ✅ Phase 0: Planning and Specification
- [x] Requirements gathering and specification creation
- [x] TDD development plan creation
- [x] Step-by-step implementation prompts defined

### 🔄 Phase 1: Foundation & Core Infrastructure
- [ ] **Step 1**: Project Setup and Parameter Handling
  - [ ] Create Convert-IntuneToFleet.ps1 with parameter structure
  - [ ] Implement -InputFile and -OutputFile parameters
  - [ ] Add comprehensive help with Get-Help support
  - [ ] Create Pester tests for parameter validation
  - [ ] Test help system functionality
  
- [ ] **Step 2**: File I/O and Validation Framework
  - [ ] Implement Test-IntuneJsonFile validation function
  - [ ] Implement Test-OutputPath validation function
  - [ ] Create test JSON files for validation scenarios
  - [ ] Integrate validation with parameter handling
  - [ ] Test file permission scenarios
  
- [ ] **Step 3**: Logging Infrastructure
  - [ ] Implement Write-ConversionLog function
  - [ ] Support multiple log levels (Info, Warning, Error, Debug)
  - [ ] Implement log file creation and naming
  - [ ] Add console output with progress indicators
  - [ ] Create comprehensive logging tests

### 📋 Phase 2: JSON Processing Engine
- [ ] **Step 4**: JSON Parser Foundation
  - [ ] Implement Get-IntuneSettings function
  - [ ] Extract basic metadata (name, description, settingCount)
  - [ ] Parse settings array structure
  - [ ] Handle malformed JSON gracefully
  - [ ] Test with firewall JSON example
  
- [ ] **Step 5**: Setting Extraction Engine
  - [ ] Implement Get-AllSettingDefinitionIds function
  - [ ] Add recursive traversal of nested children
  - [ ] Track line numbers/paths for error reporting
  - [ ] Handle both choice and simple setting value types
  - [ ] Validate complete extraction (should find ~32 settings in firewall example)

### 📋 Phase 3: Registry Lookup System
- [ ] **Step 6**: Registry Mock Framework
  - [ ] Create Get-CSPRegistryValue abstraction interface
  - [ ] Implement Mock-CSPRegistry for testing
  - [ ] Create test data simulating real registry structure
  - [ ] Test error scenarios (missing, access denied, corrupt data)
  - [ ] Design mockable interface for downstream components
  
- [ ] **Step 7**: Registry Lookup Implementation
  - [ ] Implement real Windows Registry queries
  - [ ] Based on PowerShell one-liner approach from spec
  - [ ] Handle registry path traversal and search
  - [ ] Add robust error handling for missing entries
  - [ ] Performance optimization for batch queries
  
- [ ] **Step 8**: Data Type Detection
  - [ ] Implement Get-CSPDataType function
  - [ ] Analyze ExpectedValue to determine int vs chr format
  - [ ] Handle edge cases and provide sensible defaults
  - [ ] Return structured type information for XML generation
  - [ ] Test with various registry value types

### 📋 Phase 4: XML Generation Engine
- [ ] **Step 9**: XML Structure Generator
  - [ ] Implement New-CSPXmlItem function
  - [ ] Create individual <Replace><Item> blocks
  - [ ] Handle XML namespace (syncml:metinf) properly
  - [ ] Add XML escaping and data sanitization
  - [ ] Support both int and chr data formats
  
- [ ] **Step 10**: XML Assembly Engine
  - [ ] Implement New-FleetConfigurationXml function
  - [ ] Combine multiple CSP items into single XML document
  - [ ] Handle empty results gracefully
  - [ ] Write XML to specified output file
  - [ ] Test XML document formatting and structure

### 📋 Phase 5: Integration & User Experience
- [ ] **Step 11**: Error Tracking System
  - [ ] Implement Add-SkippedSetting function
  - [ ] Collect setting context (line numbers, setting IDs, error reasons)
  - [ ] Generate summary report of skipped entries
  - [ ] Provide actionable guidance for manual resolution
  - [ ] Integration with logging framework
  
- [ ] **Step 12**: Progress Reporting
  - [ ] Implement Show-ConversionProgress function
  - [ ] Display "Processing setting X of Y..." during operations
  - [ ] Add percentage completion tracking
  - [ ] Minimal noise while providing useful feedback
  - [ ] Integration with existing logging framework
  
- [ ] **Step 13**: Main Workflow Integration
  - [ ] Implement Convert-IntuneToFleetCSP orchestration function
  - [ ] Connect all components into end-to-end workflow
  - [ ] Add comprehensive error handling and cleanup
  - [ ] Performance optimization for complete workflow
  - [ ] End-to-end integration tests with firewall example
  
- [ ] **Step 14**: Interactive Mode Implementation  
  - [ ] Implement Get-InteractiveInput function
  - [ ] Add fallback prompts when CLI parameters missing
  - [ ] File path validation during prompts
  - [ ] Graceful exit handling for user cancellation
  - [ ] Integration with existing parameter handling
  
- [ ] **Step 15**: Final Polish and Comprehensive Testing
  - [ ] Comprehensive error handling review
  - [ ] Performance optimization and memory usage improvement
  - [ ] User experience improvements
  - [ ] Code cleanup and PowerShell best practices compliance
  - [ ] Complete inline documentation and examples

## Testing Milestones

### Unit Testing Checkpoints:
- [ ] Parameter handling tests pass (Step 1)
- [ ] File validation tests pass (Step 2)  
- [ ] JSON parsing tests pass (Step 4)
- [ ] Setting extraction tests pass (Step 5)
- [ ] Registry interface tests pass (Step 6-7)
- [ ] XML generation tests pass (Step 9-10)

### Integration Testing Checkpoints:
- [ ] Mock registry workflow complete (after Step 6)
- [ ] Real registry integration complete (after Step 7)
- [ ] Complete XML generation pipeline (after Step 10)
- [ ] End-to-end workflow with firewall example (after Step 13)

### Performance Benchmarks:
- [ ] Firewall example (32 settings) processes in <2 minutes
- [ ] Large policy (200+ settings) processes without memory issues
- [ ] Registry lookup performance acceptable for batch operations

### User Acceptance Criteria:
- [ ] Successfully converts firewall policy example
- [ ] Handles all CSP setting types (choice, simple string, simple integer)
- [ ] Produces valid SyncML XML that Fleet can import
- [ ] Provides clear feedback on conversion results
- [ ] Works with both CLI automation and interactive use
- [ ] Creates comprehensive logs for troubleshooting

## Ready for Implementation

✅ **Specification Complete**: Detailed requirements and scope defined
✅ **TDD Plan Complete**: 15 step implementation plan with comprehensive prompts
✅ **Test Strategy Defined**: Unit, integration, and performance testing approach
✅ **Success Criteria Clear**: Functional, performance, and usability requirements

**Next Action**: Begin implementation with Step 1 - Project Setup and Parameter Handling

## Notes
- Each step includes "START WITH FAILING TESTS" requirement for true TDD approach
- Mock frameworks established early to enable testing without Windows dependencies  
- Integration points clearly defined to prevent orphaned code
- Error handling patterns established early and maintained throughout
- Performance considerations built into each phase