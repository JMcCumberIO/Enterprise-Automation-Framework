# EAF.AzureProvisioning Documentation

This documentation provides an overview of the EAF.AzureProvisioning module, its templates, scripts, and testing approach.

## Overview

EAF.AzureProvisioning is a PowerShell module and Bicep template collection for provisioning secure, scalable, and well-monitored Azure resources. It supports:

- Virtual Machines
- App Services
- Storage Accounts
- Key Vaults

## Structure

- **Public/**: User-facing PowerShell scripts for resource deployment.
- **Private/**: Internal helper modules for configuration, validation, and monitoring.
- **Templates/**: Bicep templates for Azure resource deployment.
- **Tests/**: Unit, integration, and load tests for validation.

## Usage

Import the module and use the provided cmdlets (e.g., `New-EAFVM`, `New-EAFAppService`) to deploy resources. Refer to each cmdlet's help for parameter details.

## Testing

Run `Tests/Run-Tests.ps1` to execute all tests. Results are output to `TestResults/TestReport.html`.

## Contribution

Contributions are welcome! Please submit issues or pull requests via the repository.
