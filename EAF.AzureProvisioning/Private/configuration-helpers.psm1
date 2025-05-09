# Configuration Helper Functions for EAF.AzureProvisioning
# This module provides centralized configuration management for EAF module, including environment-specific settings

using namespace System
using namespace System.Management.Automation
using namespace System.Security.Cryptography
using namespace System.Collections.Specialized

# Import custom exception types if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'EAFResourceValidationException').Type) {
    $exceptionModulePath = Join-Path -Path $PSScriptRoot -ChildPath "exceptions.psm1"
    if (Test-Path $exceptionModulePath) {
        Import-Module $exceptionModulePath -Force
    }
}

# Import logging helper if available
$loggingModulePath = Join-Path -Path $PSScriptRoot -ChildPath "logging-helpers.psm1"
if (Test-Path $loggingModulePath) {
    Import-Module $loggingModulePath -Force
}

# Initialize configuration cache for improved performance
$script:EAFConfigurationCache = @{}

# Global module configuration settings
$script:EAFConfiguration = @{
    # Default Azure regions by environment
    Regions = @{
        All = @('eastus', 'eastus2', 'westus2', 'centralus', 'northcentralus', 'southcentralus', 'westeurope', 'northeurope')
        Preferred = @{
            dev = @('eastus', 'eastus2', 'centralus')
            test = @('eastus', 'eastus2', 'centralus')
            prod = @('eastus', 'eastus2', 'centralus', 'westus2')
        }
        Default = @{
            dev = 'eastus'
            test = 'eastus'
            prod = 'eastus'
        }
    }
    
    # Naming conventions
    NamingConventions = @{
        ResourceGroup = 'rg-{name}-{env}'
        StorageAccount = 'st{name}{env}'
        KeyVault = 'kv-{name}-{env}'
        AppService = 'app-{name}-{env}'
        VirtualMachine = 'vm-{name}-{env}'
        VirtualNetwork = 'vnet-{name}-{env}'
        Subnet = 'snet-{name}-{env}'
        NetworkSecurityGroup = 'nsg-{name}-{env}'
        PublicIP = 'pip-{name}-{env}'
        LoadBalancer = 'lb-{name}-{env}'
        AppServicePlan = 'plan-{name}-{env}'
        SqlServer = 'sql-{name}-{env}'
        SqlDatabase = 'sqldb-{name}-{env}'
        CosmosDB = 'cosmos-{name}-{env}'
        ContainerRegistry = 'cr{name}{env}'
        FunctionApp = 'func-{name}-{env}'
        LogAnalyticsWorkspace = 'law-{name}-{env}'
        RecoveryServicesVault = 'rsv-{name}-{env}'
    }
    
    # Default SKUs by resource type and environment
    DefaultSKUs = @{
        StorageAccount = @{
            dev = 'Standard_LRS'
            test = 'Standard_LRS'
            prod = 'Standard_GRS'
        }
        AppServicePlan = @{
            dev = 'B1'
            test = 'S1'
            prod = 'P1v2'
        }
        KeyVault = @{
            dev = 'standard'
            test = 'standard'
            prod = 'standard'
        }
        SqlDatabase = @{
            dev = 'Basic'
            test = 'Standard'
            prod = 'Premium'
        }
        VirtualMachine = @{
            dev = 'Standard_B2s'
            test = 'Standard_D2s_v3'
            prod = 'Standard_D4s_v3'
        }
    }
    
    # Default tags for resources
    DefaultTags = @{
        Common = @{
            CreatedBy = 'EAFModule'
            DeploymentType = 'Automated'
            Framework = 'EAF'
        }
        Environment = @{
            dev = @{
                Environment = 'Development'
                CostCenter = 'IT-Dev'
                Criticality = 'Low'
            }
            test = @{
                Environment = 'Test'
                CostCenter = 'IT-Test'
                Criticality = 'Medium'
            }
            prod = @{
                Environment = 'Production'
                CostCenter = 'IT-Prod'
                Criticality = 'High'
            }
        }
    }
    
    # Security configurations
    Security = @{
        EnableRBAC = $true
        DefaultRBACRoles = @{
            Owner = 'Owner'
            Contributor = 'Contributor'
            Reader = 'Reader'
            KeyVaultAdmin = 'Key Vault Administrator'
            StorageBlobDataContributor = 'Storage Blob Data Contributor'
        }
        EnablePrivateEndpoints = @{
            dev = $false
            test = $true
            prod = $true
        }
        EnableDiagnostics = @{
            dev = $true
            test = $true
            prod = $true
        }
        TLS = @{
            MinimumVersion = 'TLS1_2'
        }
        KeyVault = @{
            SoftDeleteRetention = @{
                dev = 7
                test = 30
                prod = 90
            }
            EnablePurgeProtection = @{
                dev = $false
                test = $true
                prod = $true
            }
        }
    }
    
    # Feature flags
    FeatureFlags = @{
        EnableAdvancedMonitoring = @{
            dev = $false
            test = $true
            prod = $true
        }
        EnableAutomatedBackups = @{
            dev = $false
            test = $true
            prod = $true
        }
        EnableAutoScaling = @{
            dev = $false
            test = $true
            prod = $true
        }
    }
    
    # Default configurations for monitoring
    Monitoring = @{
        DiagnosticSettings = @{
            RetentionDays = @{
                dev = 7
                test = 30
                prod = 90
            }
            LogAnalyticsWorkspace = @{
                SuffixFormat = '{env}-{department}-law'
                SKU = 'PerGB2018'
            }
        }
        Alerts = @{
            ActionGroupSuffix = 'actiongroup'
            EmailRecipients = @{
                dev = @('devteam@contoso.com')
                test = @('testteam@contoso.com')
                prod = @('prodteam@contoso.com', 'oncall@contoso.com')
            }
        }
    }
}

<#
.SYNOPSIS
    Gets EAF configuration settings.
    
.DESCRIPTION
    The Get-EAFConfiguration function retrieves configuration settings from the EAF module.
    It can be used to access environment-specific settings, defaults, and naming conventions.
    
.PARAMETER ConfigPath
    The dot-notation path to the specific configuration value to retrieve.
    Example: "Regions.Default.dev" returns the default region for the dev environment.
    
.PARAMETER Environment
    The deployment environment (dev, test, prod). Used for environment-specific settings.
    
.PARAMETER Department
    The department or business unit to use in naming templates.
    
.EXAMPLE
    Get-EAFConfiguration -ConfigPath "DefaultSKUs.StorageAccount.prod"
    
.EXAMPLE
    $defaultRegion = Get-EAFConfiguration -ConfigPath "Regions.Default" -Environment "dev"
    
.OUTPUTS
    [object] The requested configuration value or the entire configuration object if no path is specified.
#>
function Get-EAFConfiguration {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$Environment,
        
        [Parameter(Mandatory = $false)]
        [string]$Department
    )
    
    if ([string]::IsNullOrEmpty($ConfigPath)) {
        # Return the entire configuration
        return $script:EAFConfiguration
    }
    
    # Parse the config path into segments
    $pathSegments = $ConfigPath -split '\.'
    $currentConfig = $script:EAFConfiguration
    
    # Navigate through the configuration object based on path segments
    foreach ($segment in $pathSegments) {
        if ($currentConfig -eq $null -or -not $currentConfig.ContainsKey($segment)) {
            return $null # Path not found
        }
        $currentConfig = $currentConfig[$segment]
    }
    
    # Handle environment-specific values
    if ($Environment -and $currentConfig -is [hashtable] -and $currentConfig.ContainsKey($Environment)) {
        return $currentConfig[$Environment]
    }
    
    # Apply replacements for department or other variables
    if ($currentConfig -is [string] -and $Department) {
        return $currentConfig.Replace('{department}', $Department)
    }
    
    return $currentConfig
}

<#
.SYNOPSIS
    Sets EAF configuration settings.
    
.DESCRIPTION
    The Set-EAFConfiguration function allows updating configuration settings in the EAF module.
    This can be used to override default values for specific organizational requirements.
    
.PARAMETER ConfigPath
    The dot-notation path to the specific configuration value to set.
    Example: "Regions.Default.dev" sets the default region for the dev environment.
    
.PARAMETER Value
    The new value to set for the specified configuration path.
    
.PARAMETER Temporary
    If set to $true, the configuration change is only applied for the current session.
    Default is $false, which persists the configuration change across sessions.
    
.EXAMPLE
    Set-EAFConfiguration -ConfigPath "DefaultSKUs.StorageAccount.dev" -Value "Standard_GRS"
    
.EXAMPLE
    Set-EAFConfiguration -ConfigPath "Security.EnablePrivateEndpoints.dev" -Value $true -Temporary $true
    
.OUTPUTS
    [bool] Returns $true if the configuration was updated successfully, $false otherwise.
#>
function Set-EAFConfiguration {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory = $true)]
        [object]$Value,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Memory', 'File', 'Registry')]
        [string]$StorageType = 'Memory',
        
        [Parameter(Mandatory = $false)]
        [string]$ConfigFileName = 'EAFConfiguration.json',
        
        [Parameter(Mandatory = $false)]
        [string]$Environment,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [switch]$ClearCache
    )
    
    try {
        # Parse the config path into segments
        $pathSegments = $ConfigPath -split '\.'
        
        # If the path is too short, we can't set anything
        if ($pathSegments.Count -lt 1) {
            throw [EAFResourceValidationException]::new(
                "Configuration path must contain at least one segment.",
                "Configuration",
                $ConfigPath,
                "InvalidPath",
                $ConfigPath
            )
        }
        
        # Log the configuration change
        if (Get-Command -Name 'Write-EAFLog' -ErrorAction SilentlyContinue) {
            $valueString = if ($Value -is [securestring]) { "********" } else { "$Value" }
            Write-EAFLog -Message "Updating configuration: $ConfigPath = $valueString" -Level Info -Component "Configuration"
        }
        else {
            Write-Verbose "Updating configuration: $ConfigPath"
        }
        
        # Navigate through the configuration object and update the value
        $currentConfig = $script:EAFConfiguration
        $lastSegment = $pathSegments[$pathSegments.Count - 1]
        
        for ($i = 0; $i -lt $pathSegments.Count - 1; $i++) {
            $segment = $pathSegments[$i]
            
            if (-not $currentConfig.ContainsKey($segment)) {
                $currentConfig[$segment] = @{}
            }
            
            $currentConfig = $currentConfig[$segment]
        }
        
        # If environment is specified and this is an environment-specific setting
        if ($Environment -and $currentConfig -is [hashtable] -and ($currentConfig.ContainsKey('dev') -or $currentConfig.ContainsKey('test') -or $currentConfig.ContainsKey('prod'))) {
            # Create environment key if it doesn't exist
            if (-not $currentConfig.ContainsKey($Environment)) {
                $currentConfig[$Environment] = @{}
            }
            
            # If we're setting a sub-property within an environment
            if ($lastSegment -ne $Environment) {
                # Check if we're overriding the entire environment section
                if ($lastSegment -eq '*') {
                    $currentConfig[$Environment] = $Value
                }
                else {
                    # Set just the specific property within the environment
                    $currentConfig[$Environment][$lastSegment] = $Value
                }
            }
            else

<#
.SYNOPSIS
    Generates a valid resource name following EAF naming conventions.
    
.DESCRIPTION
    The Get-EAFResourceName function generates a name for an Azure resource that adheres to 
    EAF naming conventions, using the specified base name, resource type, and environment.
    
.PARAMETER BaseName
    The descriptive base name for the resource.
    
.PARAMETER ResourceType
    The type of Azure resource to generate a name for.
    
.PARAMETER Environment
    The deployment environment (dev, test, prod).
    
.PARAMETER AddRandomSuffix
    If set to $true, adds a random suffix to ensure uniqueness. Default is $false.
    
.PARAMETER RandomSuffixLength
    The length of the random suffix, if enabled. Default is 4.
    
.EXAMPLE
    Get-EAFResourceName -BaseName "payroll" -ResourceType "KeyVault" -Environment "prod"
    # Returns: kv-payroll-prod
    
.EXAMPLE
    Get-EAFResourceName -BaseName "web" -ResourceType "StorageAccount" -Environment "dev" -AddRandomSuffix $true
    # Returns: stwebdev1a2b (with random suffix)
    
.OUTPUTS
    [string] A properly formatted resource name according to EAF naming conventions.
#>
function Get-EAFResourceName {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$BaseName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('ResourceGroup', 'StorageAccount', 'KeyVault', 'AppService', 'VirtualMachine', 'VirtualNetwork', 'Subnet', 'NetworkSecurityGroup', 'PublicIP', 'LoadBalancer', 'AppServicePlan', 'SqlServer', 'SqlDatabase', 'CosmosDB', 'ContainerRegistry', 'FunctionApp', 'LogAnalyticsWorkspace', 'RecoveryServicesVault')]
        [string]$ResourceType,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$Environment,
        
        [Parameter(Mandatory = $false)]
        [bool]$AddRandomSuffix = $false,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(2, 8)]
        [int]$RandomSuffixLength = 4
    )
    
    # Get the naming convention template for the specified resource type
    $namingTemplate = Get-EAFConfiguration -ConfigPath "NamingConventions.$ResourceType"
    
    if (-not $namingTemplate) {
        throw [EAFResourceValidationException]::new(
            "No naming convention defined for resource type '$ResourceType'.",
            $ResourceType,
            "Naming",
            "UndefinedConvention",
            $ResourceType
        )
    }
    
    # Clean the base name to ensure it follows Azure naming restrictions
    $cleanBaseName = $BaseName -replace '[^a-zA-Z0-9]', '' # Remove special characters
    $cleanBaseName = $cleanBaseName.ToLower() # Ensure lowercase
    
    # Apply the naming convention template
    $resourceName = $namingTemplate -replace '{name}', $cleanBaseName -replace '{env}', $Environment
    
    # Add random suffix if requested
    if ($AddRandomSuffix) {
        $chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
        $random = ''
        $random = 1..$RandomSuffixLength | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] }
        $random = -join $random
        $resourceName = $resourceName + $random
    }
    
    # Validate final name length against Azure limits
    $maxLengths = @{
        'StorageAccount' = 24
        'KeyVault' = 24
        'ResourceGroup' = 90
        'VirtualMachine' = 15
        'AppService' = 60
        'NetworkSecurityGroup' = 80
        'VirtualNetwork' = 64
        'PublicIP' = 80
        'LoadBalancer' = 80
        'SqlServer' = 63
        'SqlDatabase' = 128
        'CosmosDB' = 44
        'ContainerRegistry' = 50
        'Default' = 63  # Default max length
    }
    
    $maxLength = 63  # Default max length
    if ($maxLengths.ContainsKey($ResourceType)) {
        $maxLength = $maxLengths[$ResourceType]
    }
    
    if ($resourceName.Length -gt $maxLength) {
        Write-Warning "Generated name '$resourceName' exceeds maximum length of $maxLength characters for $ResourceType. Truncating."
        $resourceName = $resourceName.Substring(0, $maxLength)
    }
    
    return $resourceName
}

<#
.SYNOPSIS
    Gets the default tags for Azure resources based on environment and department.
    
.DESCRIPTION
    The Get-EAFDefaultTags function returns a hashtable of recommended tags for Azure resources
    based on the specified environment and department, following EAF tagging standards.
    
.PARAMETER Environment
    The deployment environment (dev, test, prod).
    
.PARAMETER Department
    The department or business unit responsible for the resource.
    
.PARAMETER ResourceType
    The type of Azure resource being tagged.
    
.PARAMETER AdditionalTags
    A hashtable of additional custom tags to include in the result.
    
.EXAMPLE
    Get-EAFDefaultTags -Environment "prod" -Department "Finance"
    
.EXAMPLE
    $tags = Get-EAFDefaultTags -Environment "dev" -Department "IT" -ResourceType "StorageAccount" -AdditionalTags @{ Project = "DataMigration"; Owner = "John.Doe" }
    
.OUTPUTS
    [hashtable] A hashtable containing all the generated tags.
#>
function Get-EAFDefaultTags {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$Environment,
        
        [Parameter(Mandatory = $true)]
        [string]$Department,
        
        [Parameter(Mandatory = $false)]
        [string]$ResourceType = '',
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalTags = @{}
    )
    
    # Get common tags
    $commonTags = Get-EAFConfiguration -ConfigPath "DefaultTags.Common"
    
    # Get environment-specific tags
    $environmentTags = Get-EAFConfiguration -ConfigPath "DefaultTags.Environment.$Environment"
    
    # Create base tags collection
    $tags = @{
        Department = $Department
        DateCreated = (Get-Date).ToString('yyyy-MM-dd')
    }
    
    # Add common tags
    foreach ($key in $commonTags.Keys) {
        $tags[$key] = $commonTags[$key]
    }
    
    # Add environment-specific tags
    foreach ($key in $environmentTags.Keys) {
        $tags[$key] = $environmentTags[$key]
    }
    
    # Add resource type if provided
    if (-not [string]::IsNullOrEmpty($ResourceType)) {
        $tags['ResourceType'] = $ResourceType
    }
    
    # Add additional custom tags
    foreach ($key in $AdditionalTags.Keys) {
        $tags[$key] = $AdditionalTags[$key]
    }
    
    return $tags
}

<#
.SYNOPSIS
    Gets the recommended SKU for an Azure resource based on environment.
    
.DESCRIPTION
    The Get-EAFDefaultSKU function returns the recommended SKU for an Azure resource
    based on the specified resource type and environment, following EAF standards.
    
.PARAMETER ResourceType
    The type of Azure resource to get the SKU for.
    
.PARAMETER Environment
    The deployment environment (dev, test, prod).
    
.PARAMETER UseProduction
    If set to $true, always returns the production-grade SKU regardless of environment.
    Useful for critical resources that need production performance in any environment.
    Default is $false.
    
.EXAMPLE
    Get-EAFDefaultSKU -ResourceType "AppServicePlan" -Environment "test"
    
.EXAMPLE
    Get-EAFDefaultSKU -ResourceType "StorageAccount" -Environment "dev" -UseProduction $true
    
.OUTPUTS
    [string] The recommended SKU name for the specified resource and environment.
#>
function Get-EAFDefaultSKU {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('StorageAccount', 'AppServicePlan', 'KeyVault', 'SqlDatabase', 'VirtualMachine')]
        [string]$ResourceType,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$Environment,
        
        [Parameter(Mandatory = $false)]
        [bool]$UseProduction = $false
    )
    
    # If UseProduction is true, always use the production SKU
    $envToUse = $Environment
    if ($UseProduction) {
        $envToUse = 'prod'
    }
    
    # Get SKU from configuration
    $sku = Get-EAFConfiguration -ConfigPath "DefaultSKUs.$ResourceType.$envToUse"
    
    if (-not $sku) {
        throw [EAFResourceValidationException]::new(
            "No default SKU defined for resource type '$ResourceType' in environment '$envToUse'.",
            $ResourceType,
            "SKU",
            "UndefinedSKU",
            $ResourceType
        )
    }
    
    return $sku
}

<#
.SYNOPSIS
    Validates that configuration settings are valid and compatible.
    
.DESCRIPTION
    The Test-EAFConfiguration function validates that the EAF configuration settings
    are valid, compatible, and meet basic quality requirements.
    
.PARAMETER ConfigPaths
    An array of specific configuration paths to validate. If not provided, validates 
    the entire configuration.
    
.PARAMETER ThrowOnInvalid
    If set to $true, throws an exception if validation fails. Default is $true.
    
.EXAMPLE
    Test-EAFConfiguration
    
.EXAMPLE
    Test-EAFConfiguration -ConfigPaths @("DefaultSKUs.StorageAccount", "Security.EnablePrivateEndpoints") -ThrowOnInvalid $false
    
.OUTPUTS
    [bool] Returns $true if validation passes, $false if validation fails and ThrowOnInvalid is $false.
#>
function Test-EAFConfiguration {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$ConfigPaths = @(),
        
        [Parameter(Mandatory = $false)]
        [bool]$ThrowOnInvalid = $true
    )
    
    $isValid = $true
    $validationErrors = @()
    
    try {
        # If no specific paths are provided, validate the entire configuration
        if ($ConfigPaths.Count -eq 0) {
            # Check required configuration sections
            $requiredSections = @('Regions', 'NamingConventions', 'DefaultSKUs', 'DefaultTags', 'Security')
            
            foreach ($section in $requiredSections) {
                if (-not $script:EAFConfiguration.ContainsKey($section)) {
                    $isValid = $false
                    $validationErrors += "Required configuration section '$section' is missing."
                }
            }
            
            # Validate regions configuration
            if ($script:EAFConfiguration.ContainsKey('Regions')) {
                $regions = $script:EAFConfiguration.Regions
                
                # Check Default regions for each environment
                foreach ($env in @('dev', 'test', 'prod')) {
                    if (-not ($regions.Default.ContainsKey($env))) {
                        $isValid = $false
                        $validationErrors += "Default region for environment '$env' is not defined."
                    }
                }
            }
            
            # Validate naming conventions
            if ($script:EAFConfiguration.ContainsKey('NamingConventions')) {
                $namingConventions = $script:EAFConfiguration.NamingConventions
                
                $requiredResourceTypes = @('ResourceGroup', 'StorageAccount', 'KeyVault', 'VirtualMachine')
                foreach ($resourceType in $requiredResourceTypes) {
                    if (-not $namingConventions.ContainsKey($resourceType)) {
                        $isValid = $false
                        $validationErrors += "Naming convention for resource type '$resourceType' is not defined."
                    }
                    else {
                        $convention = $namingConventions[$resourceType]
                        if (-not ($convention -match '{name}') -or -not ($convention -match '{env}')) {
                            $isValid = $false
                            $validationErrors += "Naming convention for '$resourceType' must include both {name} and {env} placeholders."
                        }
                    }
                }
            }
            
            # Validate default SKUs
            if ($script:EAFConfiguration.ContainsKey('DefaultSKUs')) {
                $defaultSKUs = $script:EAFConfiguration.DefaultSKUs
                
                $requiredResourceTypes = @('StorageAccount', 'AppServicePlan', 'KeyVault')
                foreach ($resourceType in $requiredResourceTypes) {
                    if (-not $defaultSKUs.ContainsKey($resourceType)) {
                        $isValid = $false
                        $validationErrors += "Default SKUs for resource type '$resourceType' are not defined."
                    }
                    else {
                        foreach ($env in @('dev', 'test', 'prod')) {
                            if (-not $defaultSKUs[$resourceType].ContainsKey($env)) {
                                $isValid = $false
                                $validationErrors += "Default SKU for '$resourceType' in environment '$env' is not defined."
                            }
                        }
                    }
                }
            }
        }
        else {
            # Validate only the specified configuration paths
            foreach ($path in $ConfigPaths) {
                $value = Get-EAFConfiguration -ConfigPath $path
                
                if ($null -eq $value) {
                    $isValid = $false
                    $validationErrors += "Configuration path '$path' does not exist."
                }
                else {
                    # Specific validations based on path
                    if ($path -eq "Regions.Default") {
                        foreach ($env in @('dev', 'test', 'prod')) {
                            if (-not $value.ContainsKey($env)) {
                                $isValid = $false
                                $validationErrors += "Default region for environment '$env' is not defined."
                            }
                        }
                    }
                    elseif ($path -like "NamingConventions.*") {
                        if (-not ($value -match '{name}') -or -not ($value -match '{env}')) {
                            $isValid = $false
                            $validationErrors += "Naming convention must include both {name} and {env} placeholders."
                        }
                    }
                    elseif ($path -like "DefaultSKUs.*") {
                        foreach ($env in @('dev', 'test', 'prod')) {
                            if (-not $value.ContainsKey($env)) {
                                $isValid = $false
                                $validationErrors += "Default SKU for environment '$env' is not defined in '$path'."
                            }
                        }
                    }
                }
            }
        }
        
        # If validation failed and we're supposed to throw
        if (-not $isValid -and $ThrowOnInvalid) {
            $errorMessage = "EAF Configuration validation failed with the following errors:`n"
            $errorMessage += ($validationErrors | ForEach-Object { "- $_" }) -join "`n"
            
            throw [EAFResourceValidationException]::new(
                $errorMessage,
                "Configuration",
                "Validation",
                "ConfigurationValidation",
                ($validationErrors | ConvertTo-Json -Compress)
            )
        }
        
        return $isValid
    }
    catch {
        if ($_.Exception -is [EAFResourceValidationException]) {
            throw
        }
        
        if ($ThrowOnInvalid) {
            throw [EAFResourceValidationException]::new(
                "Error validating EAF configuration: $($_.Exception.Message)",
                "Configuration",
                "Validation",
                "ValidationError",
                $_.Exception.Message
            )
        }
        
        return $false
    }
}

<#
.SYNOPSIS
    Gets the default configuration for a resource type.
    
.DESCRIPTION
    The Get-EAFResourceDefaultConfig function returns the recommended default configuration
    for a specific resource type based on EAF standards and the specified environment.
    
.PARAMETER ResourceType
    The type of Azure resource to get the default configuration for.
    
.PARAMETER Environment
    The deployment environment (dev, test, prod).
    
.PARAMETER Department
    The department or business unit responsible for the resource.
    
.EXAMPLE
    Get-EAFResourceDefaultConfig -ResourceType "KeyVault" -Environment "prod" -Department "Finance"
    
.OUTPUTS
    [hashtable] A hashtable containing the default configuration parameters for the specified resource type.
#>
function Get-EAFResourceDefaultConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('StorageAccount', 'KeyVault', 'AppService', 'VirtualMachine', 'SqlDatabase')]
        [string]$ResourceType,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$Environment,
        
        [Parameter(Mandatory = $true)]
        [string]$Department,
        
        [Parameter(Mandatory = $false)]
        [string]$BaseName = '',
        
        [Parameter(Mandatory = $false)]
        [bool]$UseProduction = $false,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalParameters = @{}
    )
    
    # Generate default resource name if base name provided
    $resourceName = ''
    if (-not [string]::IsNullOrEmpty($BaseName)) {
        $resourceName = Get-EAFResourceName -BaseName $BaseName -ResourceType $ResourceType -Environment $Environment
    }
    
    # Get default region
    $location = Get-EAFConfiguration -ConfigPath "Regions.Default.$Environment"
    
    # Get default SKU
    $sku = Get-EAFDefaultSKU -ResourceType $ResourceType -Environment $Environment -UseProduction $UseProduction
    
    # Get default tags
    $tags = Get-EAFDefaultTags -Environment $Environment -Department $Department -ResourceType $ResourceType
    
    # Build base parameters common to all resource types
    $baseParams = @{
        Location = $location
    }
    
    # Add resource name if provided
    if (-not [string]::IsNullOrEmpty($resourceName)) {
        $baseParams['Name'] = $resourceName
    }
    
    # Resource-specific parameter configurations
    $resourceParams = @{}
    
    switch ($ResourceType) {
        'StorageAccount' {
            # Set default storage account parameters based on environment
            $resourceParams = @{
                StorageAccountName = $resourceName
                StorageAccountType = 'StorageV2'
                AccessTier = ($Environment -eq 'prod') ? 'Hot' : 'Cool'
                Sku = $sku
                AllowBlobPublicAccess = $false
                SupportsHttpsTrafficOnly = $true
                MinimumTlsVersion = 'TLS1_2'
                EnableBlobVersioning = $true
                EnableBlobSoftDelete = $true
                BlobSoftDeleteRetentionDays = switch ($Environment) {
                    'dev' { 7 }
                    'test' { 14 }
                    'prod' { 30 }
                }
                EnableFileSoftDelete = $true
                FileSoftDeleteRetentionDays = switch ($Environment) {
                    'dev' { 7 }
                    'test' { 14 }
                    'prod' { 30 }
                }
                AllowAllNetworks = ($Environment -eq 'dev')
                DeployPrivateEndpoint = (Get-EAFConfiguration -ConfigPath "Security.EnablePrivateEndpoints.$Environment")
                CreateDefaultContainers = $true
                Containers = @('documents', 'images', 'logs')
                Environment = $Environment
                Department = $Department
            }
        }
        'KeyVault' {
            # Set default key vault parameters based on environment
            $resourceParams = @{
                KeyVaultName = $resourceName
                Sku = $sku
                EnableRbacAuthorization = (Get-EAFConfiguration -ConfigPath "Security.EnableRBAC")
                EnableSoftDelete = $true
                SoftDeleteRetentionInDays = (Get-EAFConfiguration -ConfigPath "Security.KeyVault.SoftDeleteRetention.$Environment")
                EnablePurgeProtection = (Get-EAFConfiguration -ConfigPath "Security.KeyVault.EnablePurgeProtection.$Environment")
                PublicNetworkAccess = ($Environment -eq 'dev')
                NetworkAclDefaultAction = 'Deny'
                DeployPrivateEndpoint = (Get-EAFConfiguration -ConfigPath "Security.EnablePrivateEndpoints.$Environment")
                Environment = $Environment
                Department = $Department
            }
        }
        'AppService' {
            # Set default app service parameters based on environment
            $aspSku = Get-EAFDefaultSKU -ResourceType 'AppServicePlan' -Environment $Environment -UseProduction $UseProduction
            
            $resourceParams = @{
                AppServiceName = $resourceName
                AppServicePlanName = "$resourceName-plan"
                SkuName = $aspSku
                SkuCapacity = switch ($Environment) {
                    'dev' { 1 }
                    'test' { 1 }
                    'prod' { 2 }
                }
                RuntimeStack = 'dotnet'
                RuntimeVersion = '6.0'
                HttpsOnly = $true
                AlwaysOn = ($Environment -ne 'dev')
                EnableDeploymentSlots = ($Environment -ne 'dev')
                DeploymentSlotsCount = switch ($Environment) {
                    'dev' { 0 }
                    'test' { 1 }
                    'prod' { 2 }
                }
                DeploymentSlotNames = ($Environment -eq 'prod') ? @('staging', 'uat') : @('staging')
                EnableAutoScale = (Get-EAFConfiguration -ConfigPath "FeatureFlags.EnableAutoScaling.$Environment")
                AutoScaleMinInstanceCount = switch ($Environment) {
                    'dev' { 1 }
                    'test' { 1 }
                    'prod' { 2 }
                }
                AutoScaleMaxInstanceCount = switch ($Environment) {
                    'dev' { 1 }
                    'test' { 3 }
                    'prod' { 5 }
                }
                EnableBackup = (Get-EAFConfiguration -ConfigPath "FeatureFlags.EnableAutomatedBackups.$Environment")
                BackupRetentionPeriodDays = switch ($Environment) {
                    'dev' { 7 }
                    'test' { 14 }
                    'prod' { 30 }
                }
                Environment = $Environment
                Department = $Department
            }
        }
        'VirtualMachine' {
            # Set default VM parameters based on environment
            $resourceParams = @{
                VmName = $resourceName
                VmSize = $sku
                OsType = 'Windows'  # Default to Windows, can be overridden
                EnableBootDiagnostics = $true
                EnableManagedIdentity = $true
                ManagedIdentityType = 'SystemAssigned'
                EnableBackup = (Get-EAFConfiguration -ConfigPath "FeatureFlags.EnableAutomatedBackups.$Environment")
                BackupPolicyType = 'Daily'
                BackupRetentionDays = switch ($Environment) {
                    'dev' { 7 }
                    'test' { 14 }
                    'prod' { 30 }
                }
                AddDataDisks = $false
                DataDisksCount = switch ($Environment) {
                    'dev' { 1 }
                    'test' { 1 }
                    'prod' { 2 }
                }
                DataDiskSizeGB = switch ($Environment) {
                    'dev' { 128 }
                    'test' { 256 }
                    'prod' { 512 }
                }
                DataDiskStorageType = ($Environment -eq 'prod') ? 'Premium_LRS' : 'StandardSSD_LRS'
                Environment = $Environment
                Department = $Department
            }
        }
        'SqlDatabase' {
            # Set default SQL database parameters based on environment
            $resourceParams = @{
                ServerName = Get-EAFResourceName -BaseName $BaseName -ResourceType 'SqlServer' -Environment $Environment
                DatabaseName = $resourceName
                Edition = $sku
                RequestedServiceObjectiveName = switch ($Environment) {
                    'dev' { 'Basic' }
                    'test' { 'S1' }
                    'prod' { 'P1' }
                }
                MaxSizeBytes = switch ($Environment) {
                    'dev' { 2GB }
                    'test' { 10GB }
                    'prod' { 50GB }
                }
                ZoneRedundant = ($Environment -eq 'prod')
                ReadScale = ($Environment -eq 'prod') ? 'Enabled' : 'Disabled'
                LicenseType = 'LicenseIncluded'
                MinCapacity = ($Environment -eq 'prod') ? 2 : 0.5
                AutoPauseDelayInMinutes = ($Environment -eq 'dev') ? 60 : -1  # Auto-pause only in dev
                Collation = 'SQL_Latin1_General_CP1_CI_AS'
                EnableAuditing = $true
                EnableThreatDetection = ($Environment -ne 'dev')
                EnableAdvancedDataSecurity = ($Environment -eq 'prod')
                EnableTransparentDataEncryption = $true
                Environment = $Environment
                Department = $Department
            }
        }
        default {
            Write-Warning "No default configuration defined for resource type '$ResourceType'. Returning basic parameters."
        }
    }
    
    # Merge base parameters and resource-specific parameters
    $defaultConfig = $baseParams + $resourceParams
    
    # Add additional custom parameters if provided
    foreach ($key in $AdditionalParameters.Keys) {
        $defaultConfig[$key] = $AdditionalParameters[$key]
    }
    
    return $defaultConfig
}

# Export all functions for use in other modules
Export-ModuleMember -Function @(
    'Get-EAFConfiguration',
    'Set-EAFConfiguration',
    'Get-EAFResourceName',
    'Get-EAFDefaultTags',
    'Get-EAFDefaultSKU',
    'Test-EAFConfiguration',
    'Get-EAFResourceDefaultConfig'
)

