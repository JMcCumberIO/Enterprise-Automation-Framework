# Mocks for Testing

This folder contains mock modules and data used for unit and integration testing of the EAF.AzureProvisioning module.

## Purpose

Mocks are used to simulate Azure resources, API responses, and module behaviors to enable isolated and reliable testing without requiring live Azure resources.

## Usage

- Place mock scripts and data files here (e.g., mock modules, JSON responses).
- Reference these mocks in your test scripts using Pester's mocking features.

## Example

To mock a cmdlet in your test:

```powershell
Mock Get-AzResourceGroup { return @{ Name = 'MockRG'; Location = 'eastus' } }
```
