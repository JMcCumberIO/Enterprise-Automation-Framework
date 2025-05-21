# EAF.AzureProvisioning Module

Welcome to the Enterprise Azure Framework (EAF) Azure Provisioning module repository! This PowerShell module is designed to provide a standardized, robust, and maintainable way to provision Azure resources according to defined enterprise standards. It leverages PowerShell for orchestration and Bicep templates for Azure resource deployment (Infrastructure as Code).

## Key Features

*   **Standardized Provisioning:** Enforces EAF naming conventions, tagging, security configurations, and monitoring setups.
*   **PowerShell Cmdlets:** Provides easy-to-use public cmdlets for provisioning common Azure resources:
    *   `New-EAFAppService`: Deploys Azure App Services and related components.
    *   `New-EAFKeyVault`: Deploys Azure Key Vaults with standardized security.
    *   `New-EAFStorageAccount`: Deploys Azure Storage Accounts with EAF best practices.
    *   `New-EAFVM`: Deploys Azure Virtual Machines (Windows/Linux).
*   **Bicep for IaC:** Utilizes Azure Bicep templates for declarative resource definitions, ensuring consistency and repeatability.
*   **Modular Design:** Features a collection of private helper PowerShell modules for:
    *   Configuration Management (`configuration-helpers.psm1`)
    *   Custom Error Handling (`exceptions.psm1`)
    *   Retry Logic for Azure calls (`retry-logic.psm1`)
    *   Standardized Validation (`validation-helpers.psm1`)
    *   Secure Configuration Handling (`secure-configuration-helpers.psm1`)
    *   Monitoring Setup (`monitoring-helpers.psm1`)
*   **Test Framework:** Includes Pester-based unit tests and a strategy for true integration testing.

## Repository Structure

```
EAF.AzureProvisioning/
├── EAF.AzureProvisioning.psd1     # Module Manifest
├── EAF.AzureProvisioning.psm1     # Main Module Script (loader)
├── Private/                       # Private helper modules (PowerShell)
│   ├── configuration-helpers.psm1
│   ├── configuration-monitoring-helpers.psm1
│   ├── exceptions.psm1
│   ├── monitoring-helpers.psm1
│   ├── retry-logic.psm1
│   ├── secure-configuration-helpers.psm1
│   └── validation-helpers.psm1
├── Public/                        # Public PowerShell cmdlets
│   ├── New-EAFAppService.ps1
│   ├── New-EAFKeyVault.ps1
│   ├── New-EAFStorageAccount.ps1
│   └── New-EAFVM.ps1
├── Templates/                     # Bicep templates
│   ├── appService.bicep
│   ├── keyVault.bicep
│   ├── storage.bicep
│   └── vm.bicep
├── Tests/                         # Pester tests
│   ├── Unit/                      # Unit tests for PowerShell scripts
│   │   ├── New-EAFAppService.Unit.Tests.ps1
│   │   ├── New-EAFKeyVault.Unit.Tests.ps1
│   │   ├── New-EAFStorageAccount.Unit.Tests.ps1
│   │   └── New-EAFVM.Unit.Tests.ps1
│   │   └── Configuration-Monitoring.Tests.ps1
│   │   └── Secure-Configuration.Tests.ps1
│   ├── Integration.Real/          # True integration tests (target live Azure)
│   │   └── New-EAFAppService.Integration.Tests.ps1 # (Template, more to be added)
│   ├── Integration/               # Old mock-based "integration" tests (to be refactored/removed)
│   ├── Mocks/                     # Mocking modules for unit tests
│   └── Run-Tests.ps1              # Script to execute Pester tests
└── README.md                      # This file
```

## Prerequisites

*   PowerShell 7.0 or higher.
*   Azure PowerShell (Az) modules. Key modules used include (but are not limited to):
    *   `Az.Accounts`
    *   `Az.Resources`
    *   `Az.Storage`
    *   `Az.Websites`
    *   `Az.KeyVault`
    *   `Az.Compute`
    *   `Az.Network`
    *   `Az.Monitor`
    *   `Az.OperationalInsights`
    *   `Az.RecoveryServices` (for VM backup features)
    *   *It's recommended to have the latest versions of these modules installed.*
*   (Optional) Azure CLI and Bicep CLI if you intend to work directly with Bicep files outside of this module.

## Getting Started

1.  **Clone the Repository:**
    ```bash
    git clone <repository-url>
    cd EAF.AzureProvisioning
    ```
2.  **Import the Module:**
    ```powershell
    Import-Module ./EAF.AzureProvisioning.psd1
    ```
3.  **Use the Cmdlets:**
    ```powershell
    # Example: Deploying a new Key Vault
    $kvParams = @{
        ResourceGroupName = 'rg-my-keyvaults-dev'
        KeyVaultName      = 'kv-myapp-dev'
        Location          = 'eastus'
        Department        = 'IT'
        Environment       = 'dev'
        AdminObjectId     = (Get-AzADUser -UserPrincipalName 'user@example.com').Id # Or other principal ID
    }
    New-EAFKeyVault @kvParams

    # Get help for any cmdlet
    Get-Help New-EAFAppService -Full
    ```

## Testing

The module includes a suite of Pester tests.

*   **Unit Tests:** These test the PowerShell cmdlets and helper functions in isolation, using mocks for external dependencies (Azure APIs, other helpers).
*   **Integration Tests (`Tests/Integration.Real/`):** These are designed to deploy actual resources to Azure and validate their configuration. They require an active Azure subscription and proper configuration (e.g., service principal for CI/CD). *Currently, a template for `New-EAFAppService` integration tests is provided; more will be developed.*

**Running Tests:**

The `Tests/Run-Tests.ps1` script is used to execute tests:

```powershell
# Navigate to the Tests directory
cd ./EAF.AzureProvisioning/Tests/

# Run all tests (Unit and Integration if configured)
./Run-Tests.ps1

# Run only Unit tests
./Run-Tests.ps1 -TestType Unit

# Run specific tests (Pester will use its own filtering for -TestName on Describe/It blocks)
# For example, to run tests with "KeyVault" in their name from all files:
# ./Run-Tests.ps1 -TestName *KeyVault* 
# (Note: Run-Tests.ps1's TestName parameter currently filters files, not Pester test names directly)

# Test reports are generated in Tests/TestResults/
```

## Known Limitations & Future Work

*   **Bicep Template Completeness:**
    *   `storage.bicep`: The resource definition section of this template was corrupted and currently only contains parameters after a cleanup attempt. It needs to be fully restored to deploy storage accounts.
    *   `keyVault.bicep`: The content for this template was partially cut off during the review. While functional for many aspects, it needs verification for complete metric alert definitions, initial secret deployment via Bicep, and private endpoint resource definitions.
*   **Integration Tests:** The true integration test suite (`Tests/Integration.Real/`) is currently outlined with one template and needs full implementation for all public cmdlets and various scenarios. The older mock-based tests in `Tests/Integration/` should be refactored into unit tests or removed.
*   **External Configuration for EAF Standards:** The core EAF standards (naming, default SKUs, tags, etc.) are currently managed within `configuration-helpers.psm1`. Future work could involve allowing these to be customized further via external configuration files (e.g., JSON).
*   **Code Review Items:** This README is being updated post a code review. Several items identified (like full Bicep repairs and integration test implementation) are part of ongoing enhancements.

## Contributing

Contributions are welcome! Please follow standard Git practices: fork, branch, commit, and submit a pull request with a clear description of your changes. Ensure new functionality includes relevant Pester tests.

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
