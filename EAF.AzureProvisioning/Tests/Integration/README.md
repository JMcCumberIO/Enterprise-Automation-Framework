# Integration Tests

This folder contains integration tests for the EAF.AzureProvisioning module. These tests validate the end-to-end deployment and configuration of Azure resources using the module's cmdlets and templates.

## Structure

- Each `*Tests.ps1` file targets a specific resource or scenario (e.g., VM, App Service, Storage).
- Test configuration files (e.g., `test-config.json`) provide environment-specific parameters.

## Running Integration Tests

To run only integration tests:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File ..\Run-Tests.ps1 -TestType Integration
```

## Adding New Tests

- Place new integration test scripts in this folder.
- Use descriptive names and include assertions for resource existence, configuration, and security.
