# Validation Helper Functions for EAF.AzureProvisioning
# This module provides common validation functions for Azure resource names, parameters, and dependencies

using namespace System
using namespace System.Management.Automation

# Import custom exception types if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'EAFResourceValidationException').Type) {
    $exceptionModulePath = Join-Path -Path $PSScriptRoot -ChildPath "exceptions.psm1"
    if (Test-Path $exceptionModulePath) {
        Import-Module $exceptionModulePath -Force
    }
}

<#
.SYNOPSIS
    Validates an Azure resource name against EAF naming conventions.
    
.DESCRIPTION
    The Test-EAFResourceName function validates if a given resource name follows the 
    EAF naming standards for the specified resource type. It throws an exception if validation fails.
    
.PARAMETER ResourceName
    The resource name to validate.
    
.PARAMETER ResourceType
    The type of Azure resource being validated.
    
.PARAMETER Environment
    The deployment environment (dev, test, prod). Used in naming convention validation.
    
.PARAMETER ThrowOnInvalid
    If set to $true, this function will throw an exception when validation fails.
    If $false, it returns a boolean result. Default is $true.
    
.EXAMPLE
    Test-EAFResourceName -ResourceName "kv-security-prod" -ResourceType "KeyVault" -Environment "prod"
    
.EXAMPLE
    if (-not (Test-EAFResourceName -ResourceName "incorrect-name" -ResourceType "StorageAccount" -Environment "dev" -ThrowOnInvalid $false)) {
        Write-Warning "Storage account name does not follow naming convention."
    }
    
.OUTPUTS
    [bool] When ThrowOnInvalid is $false, returns $true if the name is valid, otherwise $false.
#>
function Test-EAFResourceName {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('KeyVault', 'StorageAccount', 'AppService', 'VirtualMachine', 'ResourceGroup', 'NetworkSecurityGroup', 'VirtualNetwork', 'Subnet', 'PublicIP', 'LoadBalancer', 'NetworkInterface', 'ManagedDisk', 'AvailabilitySet', 'ContainerRegistry', 'AKSCluster', 'LogAnalyticsWorkspace', 'RecoveryServicesVault', 'ApplicationGateway', 'SqlServer', 'SqlDatabase', 'CosmosDB', 'FunctionApp', 'ApiManagement', 'EventHub', 'ServiceBus', 'ContainerInstance')]
        [string]$ResourceType,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$Environment,
        
        [Parameter(Mandatory = $false)]
        [bool]$ThrowOnInvalid = $true
    )
    
    $validPrefix = $null
    $validPattern = $null
    $lengthLimits = $null
    $allowedChars = $null
    $standardSuffix = "-$Environment"
    
    # Define naming conventions based on resource type
    switch ($ResourceType) {
        'KeyVault' {
            $validPrefix = 'kv-'
            $validPattern = "^kv-[a-z0-9]+-(?:dev|test|prod)$"
            $lengthLimits = @{ Min = 3; Max = 24 }
            $allowedChars = "Lowercase letters, numbers, and hyphens"
        }
        'StorageAccount' {
            $validPrefix = 'st'
            $validPattern = "^st[a-z0-9]+(?:dev|test|prod)$"
            $lengthLimits = @{ Min = 3; Max = 24 }
            $allowedChars = "Lowercase letters and numbers only"
            $standardSuffix = "$Environment" # No hyphen for storage accounts
        }
        'AppService' {
            $validPrefix = 'app-'
            $validPattern = "^app-[a-z0-9]+-(?:dev|test|prod)$"
            $lengthLimits = @{ Min = 2; Max = 60 }
            $allowedChars = "Lowercase letters, numbers, and hyphens"
        }
        'VirtualMachine' {
            $validPrefix = 'vm-'
            $validPattern = "^vm-[a-z0-9]+-(?:dev|test|prod)$"
            $lengthLimits = @{ Min = 1; Max = 15 }
            $allowedChars = "Lowercase letters, numbers, and hyphens"
        }
        'ResourceGroup' {
            $validPrefix = 'rg-'
            $validPattern = "^rg-[a-z0-9]+-(?:dev|test|prod)$"
            $lengthLimits = @{ Min = 1; Max = 90 }
            $allowedChars = "Lowercase letters, numbers, hyphens, underscores, periods, and parentheses"
        }
        'NetworkSecurityGroup' {
            $validPrefix = 'nsg-'
            $validPattern = "^nsg-[a-z0-9]+-(?:dev|test|prod)$"
            $lengthLimits = @{ Min = 1; Max = 80 }
            $allowedChars = "Lowercase letters, numbers, hyphens, underscores, and periods"
        }
        'VirtualNetwork' {
            $validPrefix = 'vnet-'
            $validPattern = "^vnet-[a-z0-9]+-(?:dev|test|prod)$"
            $lengthLimits = @{ Min = 2; Max = 64 }
            $allowedChars = "Lowercase letters, numbers, hyphens, underscores, and periods"
        }
        'Subnet' {
            $validPrefix = 'snet-'
            $validPattern = "^snet-[a-z0-9]+-(?:dev|test|prod)$"
            $lengthLimits = @{ Min = 1; Max = 80 }
            $allowedChars = "Lowercase letters, numbers, hyphens, underscores, and periods"
        }
        'PublicIP' {
            $validPrefix = 'pip-'
            $validPattern = "^pip-[a-z0-9]+-(?:dev|test|prod)$"
            $lengthLimits = @{ Min = 1; Max = 80 }
            $allowedChars = "Lowercase letters, numbers, hyphens, underscores, and periods"
        }
        default {
            # Generic pattern for other resource types
            $validPrefix = $ResourceType.ToLower() + '-'
            $validPattern = "^$($ResourceType.ToLower())-[a-z0-9]+-(?:dev|test|prod)$"
            $lengthLimits = @{ Min = 1; Max = 63 }
            $allowedChars = "Lowercase letters, numbers, and hyphens"
        }
    }
    
    # Perform validation checks
    $isValid = $true
    $validationErrors = @()
    
    # Check prefix
    if (-not $ResourceName.StartsWith($validPrefix)) {
        $isValid = $false
        $validationErrors += "Resource name must start with '$validPrefix'"
    }
    
    # Check pattern
    if (-not ($ResourceName -match $validPattern)) {
        $isValid = $false
        $validationErrors += "Resource name must match pattern '$validPattern'"
    }
    
    # Check environment suffix
    if (-not $ResourceName.EndsWith($standardSuffix)) {
        $isValid = $false
        $validationErrors += "Resource name must end with environment suffix '$standardSuffix'"
    }
    
    # Check length constraints
    if ($ResourceName.Length -lt $lengthLimits.Min -or $ResourceName.Length -gt $lengthLimits.Max) {
        $isValid = $false
        $validationErrors += "Resource name length must be between $($lengthLimits.Min) and $($lengthLimits.Max) characters"
    }
    
    # If validation failed and we're supposed to throw
    if (-not $isValid -and $ThrowOnInvalid) {
        $errorMessage = "Resource name '$ResourceName' for $ResourceType does not meet EAF naming standards:`n"
        $errorMessage += ($validationErrors | ForEach-Object { "- $_" }) -join "`n"
        $errorMessage += "`n`nRequired format: $validPrefix<descriptive-name>$standardSuffix"
        $errorMessage += "`nLength: $($lengthLimits.Min)-$($lengthLimits.Max) characters"
        $errorMessage += "`nAllowed characters: $allowedChars"
        
        throw [EAFResourceValidationException]::new(
            $errorMessage,
            $ResourceType,
            $ResourceName,
            "NamingConvention",
            $ResourceName
        )
    }
    
    return $isValid
}

<#
.SYNOPSIS
    Validates if a resource group exists in Azure.
    
.DESCRIPTION
    The Test-EAFResourceGroupExists function checks if a specified resource group
    exists in Azure and optionally throws an exception if it doesn't exist.
    
.PARAMETER ResourceGroupName
    The name of the resource group to check.
    
.PARAMETER CreateIfNotExist
    If set to $true and the resource group doesn't exist, this function will attempt to create it.
    Default is $false.
    
.PARAMETER Location
    The Azure region where the resource group should be created if CreateIfNotExist is $true.
    
.PARAMETER ThrowOnNotExist
    If set to $true, this function will throw an exception when the resource group doesn't exist.
    If $false, it returns a boolean result. Default is $true.
    
.EXAMPLE
    Test-EAFResourceGroupExists -ResourceGroupName "rg-security-prod"
    
.EXAMPLE
    $rgExists = Test-EAFResourceGroupExists -ResourceGroupName "rg-data-dev" -ThrowOnNotExist $false
    if (-not $rgExists) {
        Write-Warning "Resource group doesn't exist, creating..."
        New-AzResourceGroup -Name "rg-data-dev" -Location "eastus"
    }
    
.OUTPUTS
    [bool] When ThrowOnNotExist is $false, returns $true if the resource group exists, otherwise $false.
#>
function Test-EAFResourceGroupExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $false)]
        [bool]$CreateIfNotExist = $false,
        
        [Parameter(Mandatory = $false)]
        [string]$Location = "eastus",
        
        [Parameter(Mandatory = $false)]
        [bool]$ThrowOnNotExist = $true
    )
    
    try {
        $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
        
        if (-not $resourceGroup) {
            if ($CreateIfNotExist) {
                Write-Verbose "Resource group '$ResourceGroupName' doesn't exist. Creating in location '$Location'..."
                $resourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
                
                if ($resourceGroup) {
                    Write-Verbose "Resource group '$ResourceGroupName' created successfully."
                    return $true
                }
                else {
                    if ($ThrowOnNotExist) {
                        throw [EAFDependencyException]::new(
                            "Failed to create resource group '$ResourceGroupName' in location '$Location'.",
                            "ResourceGroup",
                            $ResourceGroupName,
                            "ResourceGroup",
                            $ResourceGroupName,
                            "NotCreated"
                        )
                    }
                    return $false
                }
            }
            
            if ($ThrowOnNotExist) {
                throw [EAFDependencyException]::new(
                    "Resource group '$ResourceGroupName' not found. Please create it first or use -CreateIfNotExist parameter.",
                    "ResourceGroup",
                    $ResourceGroupName,
                    "ResourceGroup",
                    $ResourceGroupName,
                    "NotFound"
                )
            }
            
            return $false
        }
        
        return $true
    }
    catch {
        if ($_.Exception -is [EAFDependencyException]) {
            throw
        }
        
        if ($ThrowOnNotExist) {
            throw [EAFDependencyException]::new(
                "Error checking resource group '$ResourceGroupName': $($_.Exception.Message)",
                "ResourceGroup",
                $ResourceGroupName,
                "ResourceGroup",
                $ResourceGroupName,
                "ErrorChecking"
            )
        }
        
        return $false
    }
}

<#
.SYNOPSIS
    Validates virtual network and subnet configuration for Azure resources.
    
.DESCRIPTION
    The Test-EAFNetworkConfiguration function checks if a specified virtual network and subnet
    exist and have the necessary configuration for the target resource deployment.
    
.PARAMETER ResourceGroupName
    The name of the resource group containing the virtual network.
    
.PARAMETER VirtualNetworkName
    The name of the virtual network to check.
    
.PARAMETER SubnetName
    The name of the subnet to check.
    
.PARAMETER RequirePrivateEndpointNetwork
    If set to $true, validates that the subnet allows private endpoints.
    Default is $false.
    
.PARAMETER RequireServiceEndpoints
    An array of required service endpoints that the subnet should have.
    Example: @('Microsoft.Storage', 'Microsoft.KeyVault')
    
.PARAMETER ThrowOnInvalid
    If set to $true, this function will throw an exception when validation fails.
    If $false, it returns a boolean result. Default is $true.
    
.EXAMPLE
    Test-EAFNetworkConfiguration -ResourceGroupName "rg-network-prod" -VirtualNetworkName "vnet-prod" -SubnetName "snet-app-prod"
    
.EXAMPLE
    Test-EAFNetworkConfiguration -ResourceGroupName "rg-network-prod" -VirtualNetworkName "vnet-prod" -SubnetName "snet-data-prod" -RequirePrivateEndpointNetwork $true -RequireServiceEndpoints @('Microsoft.Storage')
    
.OUTPUTS
    [bool] When ThrowOnInvalid is $false, returns $true if the network configuration is valid, otherwise $false.
#>
function Test-EAFNetworkConfiguration {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$VirtualNetworkName,
        
        [Parameter(Mandatory = $true)]
        [string]$SubnetName,
        
        [Parameter(Mandatory = $false)]
        [bool]$RequirePrivateEndpointNetwork = $false,
        
        [Parameter(Mandatory = $false)]
        [string[]]$RequireServiceEndpoints = @(),
        
        [Parameter(Mandatory = $false)]
        [bool]$ThrowOnInvalid = $true
    )
    
    try {
        # First check if resource group exists
        $rgExists = Test-EAFResourceGroupExists -ResourceGroupName $ResourceGroupName -ThrowOnNotExist $false
        if (-not $rgExists) {
            if ($ThrowOnInvalid) {
                throw [EAFDependencyException]::new(
                    "Resource group '$ResourceGroupName' not found. Required for network validation.",
                    "VirtualNetwork",
                    $VirtualNetworkName,
                    "ResourceGroup",
                    $ResourceGroupName,
                    "NotFound"
                )
            }
            return $false
        }
        
        # Check if virtual network exists
        $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VirtualNetworkName -ErrorAction SilentlyContinue
        if (-not $vnet) {
            if ($ThrowOnInvalid) {
                throw [EAFDependencyException]::new(
                    "Virtual network '$VirtualNetworkName' not found in resource group '$ResourceGroupName'.",
                    "VirtualNetwork",
                    $VirtualNetworkName,
                    "VirtualNetwork",
                    $VirtualNetworkName,
                    "NotFound"
                )
            }
            return $false
        }
        
        # Check if subnet exists
        $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $SubnetName }
        if (-not $subnet) {
            if ($ThrowOnInvalid) {
                throw [EAFDependencyException]::new(
                    "Subnet '$SubnetName' not found in virtual network '$VirtualNetworkName'.",
                    "Subnet",
                    $SubnetName,
                    "Subnet",
                    $SubnetName,
                    "NotFound"
                )
            }
            return $false
        }
        
        # Validate subnet configuration for private endpoints if required
        if ($RequirePrivateEndpointNetwork) {
            # Check if private endpoint network policies are disabled (which is required for private endpoints)
            if ($subnet.PrivateEndpointNetworkPolicies -eq 'Enabled') {
                if ($ThrowOnInvalid) {
                    throw [EAFNetworkConfigurationException]::new(
                        "Subnet '$SubnetName' has private endpoint network policies enabled, which blocks private endpoint creation. Use: Set-AzVirtualNetworkSubnetConfig to disable it.",
                        "Subnet",
                        $SubnetName,
                        "PrivateEndpointNetworkPolicies",
                        "Enabled (should be Disabled)"
                    )
                }
                return $false
            }
        }
        
        # Validate service endpoints if specified
        if ($RequireServiceEndpoints.Count -gt 0) {
            $missingEndpoints = @()
            
            foreach ($requiredEndpoint in $RequireServiceEndpoints) {
                $endpointExists = $false
                
                if ($subnet.ServiceEndpoints) {
                    $endpointExists = $subnet.ServiceEndpoints | Where-Object { $_.Service -eq $requiredEndpoint }
                }
                
                if (-not $endpointExists) {
                    $missingEndpoints += $requiredEndpoint
                }
            }
            
            if ($missingEndpoints.Count -gt 0) {
                if ($ThrowOnInvalid) {
                    throw [EAFNetworkConfigurationException]::new(
                        "Subnet '$SubnetName' is missing required service endpoints: $($missingEndpoints -join ', ')",
                        "Subnet",
                        $SubnetName,
                        "ServiceEndpoints",
                        "Missing: $($missingEndpoints -join ', ')"
                    )
                }
                return $false
            }
        }
        
        # All validation passed
        return $true
    }
    catch {
        if ($_.Exception -is [EAFDependencyException] -or $_.Exception -is [EAFNetworkConfigurationException]) {
            throw
        }
        
        if ($ThrowOnInvalid) {
            throw [EAFNetworkConfigurationException]::new(
                "Error validating network configuration: $($_.Exception.Message)",
                "Network",
                "$VirtualNetworkName/$SubnetName",
                "Validation",
                $_.Exception.Message
            )
        }
        
        return $false
    }
}

<#
.SYNOPSIS
    Validates if an Azure resource exists and meets specific criteria.
    
.DESCRIPTION
    The Test-EAFResourceExists function checks if a specified Azure resource exists
    and optionally validates its configuration against specified requirements.
    
.PARAMETER ResourceGroupName
    The name of the resource group containing the resource.
    
.PARAMETER ResourceType
    The type of Azure resource to check (e.g., 'Microsoft.KeyVault/vaults', 'Microsoft.Storage/storageAccounts').
    
.PARAMETER ResourceName
    The name of the resource to check.
    
.PARAMETER RequiredProperties
    A hashtable of property paths and expected values to validate.
    Example: @{ 'properties.enabledForDeployment' = $true, 'sku.name' = 'Standard' }
    
.PARAMETER ThrowOnNotExist
    If set to $true, this function will throw an exception when the resource doesn't exist.
    If $false, it returns a boolean result. Default is $true.
    
.EXAMPLE
    Test-EAFResourceExists -ResourceGroupName "rg-security-prod" -ResourceType "Microsoft.KeyVault/vaults" -ResourceName "kv-security-prod"
    
.EXAMPLE
    $keyVaultValid = Test-EAFResourceExists -ResourceGroupName "rg-security-prod" `
                      -ResourceType "Microsoft.KeyVault/vaults" `
                      -ResourceName "kv-security-prod" `
                      -RequiredProperties @{ 'properties.enableRbacAuthorization' = $true } `
                      -ThrowOnNotExist $false
    
.OUTPUTS
    [bool] When ThrowOnNotExist is $false, returns $true if the resource exists and meets criteria, otherwise $false.
#>
function Test-EAFResourceExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceType,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceName,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$RequiredProperties = @{},
        
        [Parameter(Mandatory = $false)]
        [bool]$ThrowOnNotExist = $true
    )
    
    try {
        # Check if resource group exists
        $rgExists = Test-EAFResourceGroupExists -ResourceGroupName $ResourceGroupName -ThrowOnNotExist $false
        if (-not $rgExists) {
            if ($ThrowOnNotExist) {
                throw [EAFDependencyException]::new(
                    "Resource group '$ResourceGroupName' not found. Required for resource validation.",
                    $ResourceType,
                    $ResourceName,
                    "ResourceGroup",
                    $ResourceGroupName,
                    "NotFound"
                )
            }
            return $false
        }
        
        # Check if resource exists
        $resource = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType $ResourceType -Name $ResourceName -ErrorAction SilentlyContinue
        
        if (-not $resource) {
            if ($ThrowOnNotExist) {
                throw [EAFDependencyException]::new(
                    "Resource '$ResourceName' of type '$ResourceType' not found in resource group '$ResourceGroupName'.",
                    $ResourceType,
                    $ResourceName,
                    $ResourceType,
                    $ResourceName,
                    "NotFound"
                )
            }
            return $false
        }
        
        # If required properties are specified, validate them
        if ($RequiredProperties.Count -gt 0) {
            $invalidProperties = @()
            
            foreach ($property in $RequiredProperties.Keys) {
                $expectedValue = $RequiredProperties[$property]
                $actualValue = $null
                
                # Handle nested properties (e.g., 'properties.enabledForDeployment')
                $propertyPath = $property -split '\.'
                $currentObj = $resource
                
                foreach ($segment in $propertyPath) {
                    if ($currentObj -eq $null) {
                        break
                    }
                    
                    $currentObj = $currentObj.$segment
                }
                
                $actualValue = $currentObj
                
                # Compare values
                if ($actualValue -ne $expectedValue) {
                    $invalidProperties += @{
                        Property = $property
                        ExpectedValue = $expectedValue
                        ActualValue = $actualValue
                    }
                }
            }
            
            if ($invalidProperties.Count -gt 0) {
                if ($ThrowOnNotExist) {
                    $errorMessage = "Resource '$ResourceName' exists but does not meet required configuration:`n"
                    foreach ($invalid in $invalidProperties) {
                        $errorMessage += "- Property '$($invalid.Property)' expected value: '$($invalid.ExpectedValue)', actual value: '$($invalid.ActualValue)'`n"
                    }
                    
                    throw [EAFResourceValidationException]::new(
                        $errorMessage,
                        $ResourceType,
                        $ResourceName,
                        "PropertyValidation",
                        ($invalidProperties | ConvertTo-Json -Compress)
                    )
                }
                return $false
            }
        }
        
        # All validation passed
        return $true
    }
    catch {
        if ($_.Exception -is [EAFDependencyException] -or $_.Exception -is [EAFResourceValidationException]) {
            throw
        }
        
        if ($ThrowOnNotExist) {
            throw [EAFDependencyException]::new(
                "Error validating resource '$ResourceName': $($_.Exception.Message)",
                $ResourceType,
                $ResourceName,
                "Validation",
                "Error"
            )
        }
        
        return $false
    }
}

<#
.SYNOPSIS
    Validates if a storage account name is valid and available.
    
.DESCRIPTION
    The Test-EAFStorageAccountName function verifies that a storage account name meets
    Azure requirements (length, characters) and is available to use for creation.
    
.PARAMETER StorageAccountName
    The name of the storage account to validate.
    
.PARAMETER Environment
    The deployment environment (dev, test, prod). Used in convention validation.
    
.PARAMETER CheckAvailability
    If set to $true, this function will check if the name is available in Azure.
    Default is $true.
    
.PARAMETER ThrowOnInvalid
    If set to $true, this function will throw an exception when validation fails.
    If $false, it returns a boolean result. Default is $true.
    
.EXAMPLE
    Test-EAFStorageAccountName -StorageAccountName "stwebdev" -Environment "dev"
    
.EXAMPLE
    $isValid = Test-EAFStorageAccountName -StorageAccountName "stwebdev" -Environment "dev" -ThrowOnInvalid $false
    
.OUTPUTS
    [bool] When ThrowOnInvalid is $false, returns $true if the name is valid, otherwise $false.
#>
function Test-EAFStorageAccountName {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$Environment,
        
        [Parameter(Mandatory = $false)]
        [bool]$CheckAvailability = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$ThrowOnInvalid = $true
    )
    
    # First check naming convention
    $isValid = Test-EAFResourceName -ResourceName $StorageAccountName -ResourceType 'StorageAccount' -Environment $Environment -ThrowOnInvalid $false
    
    if (-not $isValid) {
        if ($ThrowOnInvalid) {
            throw [EAFResourceValidationException]::new(
                "Storage account name '$StorageAccountName' does not meet EAF naming convention. Must follow pattern: st<name>$Environment",
                "StorageAccount",
                $StorageAccountName,
                "NamingConvention",
                $StorageAccountName
            )
        }
        return $false
    }
    
    # Additional storage account specific validations
    if (-not ($StorageAccountName -cmatch '^[a-z0-9]+$')) {
        if ($ThrowOnInvalid) {
            throw [EAFResourceValidationException]::new(
                "Storage account name '$StorageAccountName' can only contain lowercase letters and numbers.",
                "StorageAccount",
                $StorageAccountName,
                "CharacterValidation",
                $StorageAccountName
            )
        }
        return $false
    }
    
    if ($StorageAccountName.Length -lt 3 -or $StorageAccountName.Length -gt 24) {
        if ($ThrowOnInvalid) {
            throw [EAFResourceValidationException]::new(
                "Storage account name '$StorageAccountName' must be between 3 and 24 characters long.",
                "StorageAccount",
                $StorageAccountName,
                "LengthValidation",
                $StorageAccountName
            )
        }
        return $false
    }
    
    # Check global name availability if requested
    if ($CheckAvailability) {
        try {
            $nameAvailable = $null
            $nameAvailable = Get-AzStorageAccountNameAvailability -Name $StorageAccountName
            
            if (-not $nameAvailable.NameAvailable) {
            if (-not $nameAvailable.NameAvailable) {
                if ($ThrowOnInvalid) {
                    throw [EAFResourceValidationException]::new(
                        "Storage account name '$StorageAccountName' is not available. Reason: $($nameAvailable.Reason) - $($nameAvailable.Message)",
                        "StorageAccount",
                        $StorageAccountName,
                        "NameAvailability",
                        $nameAvailable.Reason
                    )
                }
                return $false
            }
        }
        catch {
            if ($ThrowOnInvalid) {
                throw [EAFResourceValidationException]::new(
                    "Error checking storage account name availability: $($_.Exception.Message)",
                    "StorageAccount",
                    $StorageAccountName,
                    "NameAvailability",
                    "Error"
                )
            }
            return $false
        }
    }
    
    # All validation passed
    return $true
}

<#
.SYNOPSIS
    Validates password complexity for Azure resources.
    
.DESCRIPTION
    The Test-EAFSecurePassword function checks if a password meets the security requirements
    for Azure resources, including length, complexity, and character types.
    
.PARAMETER Password
    The password to validate as a SecureString object.
    
.PARAMETER PlainTextPassword
    The password to validate as a plain text string. Use this only for development/testing!
    
.PARAMETER MinLength
    The minimum required password length. Default is 12 characters.
    
.PARAMETER RequireUppercase
    If set to $true, the password must contain at least one uppercase letter. Default is $true.
    
.PARAMETER RequireLowercase
    If set to $true, the password must contain at least one lowercase letter. Default is $true.
    
.PARAMETER RequireDigit
    If set to $true, the password must contain at least one digit. Default is $true.
    
.PARAMETER RequireSpecialChar
    If set to $true, the password must contain at least one special character. Default is $true.
    
.PARAMETER DisallowCommonPatterns
    If set to $true, the password cannot contain common patterns or dictionary words. Default is $true.
    
.PARAMETER ThrowOnInvalid
    If set to $true, this function will throw an exception when validation fails.
    If $false, it returns a boolean result. Default is $true.
    
.EXAMPLE
    Test-EAFSecurePassword -Password $securePassword
    
.EXAMPLE
    $isValid = Test-EAFSecurePassword -PlainTextPassword "MyPassword123!" -ThrowOnInvalid $false
    
.OUTPUTS
    [bool] When ThrowOnInvalid is $false, returns $true if the password is valid, otherwise $false.
#>
function Test-EAFSecurePassword {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'Secure')]
        [SecureString]$Password,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'PlainText')]
        [string]$PlainTextPassword,
        
        [Parameter(Mandatory = $false)]
        [int]$MinLength = 12,
        
        [Parameter(Mandatory = $false)]
        [bool]$RequireUppercase = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$RequireLowercase = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$RequireDigit = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$RequireSpecialChar = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$DisallowCommonPatterns = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$ThrowOnInvalid = $true
    )
    
    # Convert secure string to plain text if necessary (only in memory)
    $passwordToCheck = $PlainTextPassword
    if ($Password) {
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        $passwordToCheck = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }
    
    # Validation checks
    $validationErrors = @()
    
    # Check length
    if ($passwordToCheck.Length -lt $MinLength) {
        $validationErrors += "Password must be at least $MinLength characters long."
    }
    
    # Check for uppercase letters
    if ($RequireUppercase -and -not ($passwordToCheck -cmatch '[A-Z]')) {
        $validationErrors += "Password must contain at least one uppercase letter."
    }
    
    # Check for lowercase letters
    if ($RequireLowercase -and -not ($passwordToCheck -cmatch '[a-z]')) {
        $validationErrors += "Password must contain at least one lowercase letter."
    }
    
    # Check for digits
    if ($RequireDigit -and -not ($passwordToCheck -cmatch '[0-9]')) {
        $validationErrors += "Password must contain at least one digit."
    }
    
    # Check for special characters
    if ($RequireSpecialChar -and -not ($passwordToCheck -cmatch '[^a-zA-Z0-9]')) {
        $validationErrors += "Password must contain at least one special character."
    }
    
    # Check for common patterns
    if ($DisallowCommonPatterns) {
        $commonPatterns = @(
            'password',
            '12345',
            'qwerty',
            'admin',
            'welcome',
            'letmein',
            '123abc'
        )
        
        foreach ($pattern in $commonPatterns) {
            if ($passwordToCheck -match $pattern) {
                $validationErrors += "Password contains a common pattern '$pattern' which is not allowed."
                break
            }
        }
        
        # Check for keyboard sequences
        $keyboardSequences = @(
            'qwerty',
            'asdfgh',
            'zxcvbn',
            '12345'
        )
        
        foreach ($sequence in $keyboardSequences) {
            if ($passwordToCheck -match $sequence) {
                $validationErrors += "Password contains a keyboard sequence which is not allowed."
                break
            }
        }
    }
    
    # Clear the plain text password from memory
    [System.GC]::Collect()
    
    # If validation failed and we're supposed to throw
    if ($validationErrors.Count -gt 0 -and $ThrowOnInvalid) {
        $errorMessage = "Password does not meet complexity requirements:`n"
        $errorMessage += ($validationErrors | ForEach-Object { "- $_" }) -join "`n"
        
        throw [EAFResourceValidationException]::new(
            $errorMessage,
            "Security",
            "Password",
            "PasswordComplexity",
            "Failed validation checks: $($validationErrors.Count)"
        )
    }
    
    return $validationErrors.Count -eq 0
}

<#
.SYNOPSIS
    Validates parameter values against common requirements.
    
.DESCRIPTION
    The Test-EAFParameter function provides a generic validation mechanism for 
    parameter values against common requirements like non-empty strings, numeric ranges,
    valid email addresses, etc.
    
.PARAMETER ParameterName
    The name of the parameter being validated.
    
.PARAMETER ParameterValue
    The value of the parameter to validate.
    
.PARAMETER ResourceType
    The type of resource this parameter is associated with.
    
.PARAMETER ValidationType
    The type of validation to perform.
    Valid values: NotNullOrEmpty, MinLength, MaxLength, Range, Email, Uri, Pattern
    
.PARAMETER MinLength
    The minimum length for string validation.
    
.PARAMETER MaxLength
    The maximum length for string validation.
    
.PARAMETER MinValue
    The minimum value for numeric range validation.
    
.PARAMETER MaxValue
    The maximum value for numeric range validation.
    
.PARAMETER Pattern
    A regular expression pattern to match against.
    
.PARAMETER ThrowOnInvalid
    If set to $true, this function will throw an exception when validation fails.
    If $false, it returns a boolean result. Default is $true.
    
.EXAMPLE
    Test-EAFParameter -ParameterName "Email" -ParameterValue "user@example.com" -ResourceType "Contact" -ValidationType "Email"
    
.EXAMPLE
    $isValid = Test-EAFParameter -ParameterName "Port" -ParameterValue 8080 -ResourceType "AppService" -ValidationType "Range" -MinValue 1 -MaxValue 65535 -ThrowOnInvalid $false
    
.OUTPUTS
    [bool] When ThrowOnInvalid is $false, returns $true if the parameter is valid, otherwise $false.
#>
function Test-EAFParameter {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ParameterName,
        
        [Parameter(Mandatory = $true)]
        [object]$ParameterValue,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceType,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('NotNullOrEmpty', 'MinLength', 'MaxLength', 'Range', 'Email', 'Uri', 'Pattern')]
        [string]$ValidationType,
        
        [Parameter(Mandatory = $false)]
        [int]$MinLength = 0,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxLength = 0,
        
        [Parameter(Mandatory = $false)]
        [int]$MinValue = 0,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxValue = 0,
        
        [Parameter(Mandatory = $false)]
        [string]$Pattern = '',
        
        [Parameter(Mandatory = $false)]
        [bool]$ThrowOnInvalid = $true
    )
    
    $isValid = $true
    $errorMessage = ""
    
    switch ($ValidationType) {
        'NotNullOrEmpty' {
            if ([string]::IsNullOrEmpty($ParameterValue)) {
                $isValid = $false
                $errorMessage = "Parameter '$ParameterName' cannot be null or empty."
            }
        }
        'MinLength' {
            if ($ParameterValue.Length -lt $MinLength) {
                $isValid = $false
                $errorMessage = "Parameter '$ParameterName' must be at least $MinLength characters long."
            }
        }
        'MaxLength' {
            if ($ParameterValue.Length -gt $MaxLength) {
                $isValid = $false
                $errorMessage = "Parameter '$ParameterName' cannot exceed $MaxLength characters."
            }
        }
        'Range' {
            if ($ParameterValue -lt $MinValue -or $ParameterValue -gt $MaxValue) {
                $isValid = $false
                $errorMessage = "Parameter '$ParameterName' must be between $MinValue and $MaxValue."
            }
        }
        'Email' {
            if (-not ($ParameterValue -match "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")) {
                $isValid = $false
                $errorMessage = "Parameter '$ParameterName' must be a valid email address."
            }
        }
        'Uri' {
            try {
                $uri = [System.Uri]::new($ParameterValue)
                if (-not ($uri.Scheme -eq 'http' -or $uri.Scheme -eq 'https')) {
                    $isValid = $false
                    $errorMessage = "Parameter '$ParameterName' must be a valid HTTP or HTTPS URI."
                }
            }
            catch {
                $isValid = $false
                $errorMessage = "Parameter '$ParameterName' must be a valid URI."
            }
        }
        'Pattern' {
            if (-not ($ParameterValue -match $Pattern)) {
                $isValid = $false
                $errorMessage = "Parameter '$ParameterName' must match pattern '$Pattern'."
            }
        }
    }
    
    if (-not $isValid -and $ThrowOnInvalid) {
        throw [EAFResourceValidationException]::new(
            $errorMessage,
            $ResourceType,
            $ParameterName,
            "ParameterValidation",
            $ParameterValue
        )
    }
    
    return $isValid
}

<#
.SYNOPSIS
    Validates if an Azure SKU supports the requested features.
    
.DESCRIPTION
    The Test-EAFSKUSupport function checks if a specified Azure SKU supports 
    the features or capabilities requested for a resource deployment.
    
.PARAMETER ResourceType
    The type of Azure resource being validated.
    
.PARAMETER SKU
    The SKU name or tier to validate.
    
.PARAMETER Features
    An array of feature names to validate against the SKU.
    
.PARAMETER ThrowOnInvalid
    If set to $true, this function will throw an exception when validation fails.
    If $false, it returns a boolean result. Default is $true.
    
.EXAMPLE
    Test-EAFSKUSupport -ResourceType "StorageAccount" -SKU "Standard_LRS" -Features @("Encryption", "StaticWebsite")
    
.EXAMPLE
    $isValid = Test-EAFSKUSupport -ResourceType "AppServicePlan" -SKU "F1" -Features @("AutoScale", "Slots") -ThrowOnInvalid $false
    
.OUTPUTS
    [bool] When ThrowOnInvalid is $false, returns $true if the SKU supports all features, otherwise $false.
#>
function Test-EAFSKUSupport {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('StorageAccount', 'AppService', 'KeyVault', 'VirtualMachine', 'SqlDatabase', 'CosmosDB')]
        [string]$ResourceType,
        
        [Parameter(Mandatory = $true)]
        [string]$SKU,
        
        [Parameter(Mandatory = $true)]
        [string[]]$Features,
        
        [Parameter(Mandatory = $false)]
        [bool]$ThrowOnInvalid = $true
    )
    
    # Define SKU feature compatibility matrix
    $skuFeatureMatrix = @{
        'StorageAccount' = @{
            'Standard_LRS' = @('Encryption', 'StaticWebsite', 'Snapshots', 'Metrics')
            'Standard_GRS' = @('Encryption', 'StaticWebsite', 'Snapshots', 'Metrics', 'GeoReplication')
            'Standard_RAGRS' = @('Encryption', 'StaticWebsite', 'Snapshots', 'Metrics', 'GeoReplication', 'ReadAccess')
            'Standard_ZRS' = @('Encryption', 'StaticWebsite', 'Snapshots', 'Metrics', 'ZoneRedundancy')
            'Premium_LRS' = @('Encryption', 'Snapshots', 'Metrics', 'HighPerformance')
            'Premium_ZRS' = @('Encryption', 'Snapshots', 'Metrics', 'HighPerformance', 'ZoneRedundancy')
        }
        'AppService' = @{
            'F1' = @('WebDeploy', 'FTP')
            'D1' = @('WebDeploy', 'FTP')
            'B1' = @('WebDeploy', 'FTP', 'CustomDomain', 'SSL', 'AlwaysOn')
            'B2' = @('WebDeploy', 'FTP', 'CustomDomain', 'SSL', 'AlwaysOn')
            'B3' = @('WebDeploy', 'FTP', 'CustomDomain', 'SSL', 'AlwaysOn')
            'S1' = @('WebDeploy', 'FTP', 'CustomDomain', 'SSL', 'AlwaysOn', 'AutoScale', 'Slots', 'TrafficManager')
            'S2' = @('WebDeploy', 'FTP', 'CustomDomain', 'SSL', 'AlwaysOn', 'AutoScale', 'Slots', 'TrafficManager')
            'S3' = @('WebDeploy', 'FTP', 'CustomDomain', 'SSL', 'AlwaysOn', 'AutoScale', 'Slots', 'TrafficManager')
            'P1v2' = @('WebDeploy', 'FTP', 'CustomDomain', 'SSL', 'AlwaysOn', 'AutoScale', 'Slots', 'TrafficManager', 'HighPerformance')
            'P2v2' = @('WebDeploy', 'FTP', 'CustomDomain', 'SSL', 'AlwaysOn', 'AutoScale', 'Slots', 'TrafficManager', 'HighPerformance')
            'P3v2' = @('WebDeploy', 'FTP', 'CustomDomain', 'SSL', 'AlwaysOn', 'AutoScale', 'Slots', 'TrafficManager', 'HighPerformance')
        }
        'KeyVault' = @{
            'standard' = @('Secrets', 'Keys', 'Certificates', 'RBAC', 'SoftDelete', 'PurgeProtection')
            'premium' = @('Secrets', 'Keys', 'Certificates', 'RBAC', 'SoftDelete', 'PurgeProtection', 'HSM')
        }
        'VirtualMachine' = @{
            'Standard_B1s' = @('Encryption', 'ManagedDisks', 'Diagnostics')
            'Standard_B2s' = @('Encryption', 'ManagedDisks', 'Diagnostics')
            'Standard_D2s_v3' = @('Encryption', 'ManagedDisks', 'Diagnostics', 'AcceleratedNetworking', 'PremiumStorage')
            'Standard_D4s_v3' = @('Encryption', 'ManagedDisks', 'Diagnostics', 'AcceleratedNetworking', 'PremiumStorage')
            'Standard_D8s_v3' = @('Encryption', 'ManagedDisks', 'Diagnostics', 'AcceleratedNetworking', 'PremiumStorage')
            'Standard_F2s_v2' = @('Encryption', 'ManagedDisks', 'Diagnostics', 'AcceleratedNetworking', 'PremiumStorage', 'HighPerformance')
            'Standard_F4s_v2' = @('Encryption', 'ManagedDisks', 'Diagnostics', 'AcceleratedNetworking', 'PremiumStorage', 'HighPerformance')
        }
        'SqlDatabase' = @{
            'Basic' = @('Encryption', 'Auditing', 'Metrics')
            'Standard' = @('Encryption', 'Auditing', 'Metrics', 'PointInTimeRestore', 'LongTermBackup')
            'Premium' = @('Encryption', 'Auditing', 'Metrics', 'PointInTimeRestore', 'LongTermBackup', 'HighPerformance', 'ReadReplica')
            'GeneralPurpose' = @('Encryption', 'Auditing', 'Metrics', 'PointInTimeRestore', 'LongTermBackup', 'Serverless')
            'BusinessCritical' = @('Encryption', 'Auditing', 'Metrics', 'PointInTimeRestore', 'LongTermBackup', 'HighPerformance', 'ReadReplica', 'InMemoryOLTP')
            'Hyperscale' = @('Encryption', 'Auditing', 'Metrics', 'PointInTimeRestore', 'LongTermBackup', 'ReadReplica', 'HyperscaleScaling')
        }
        'CosmosDB' = @{
            'Standard' = @('MultiRegion', 'MultipleWriteRegions', 'AutoScale', 'ServerlessCompute', 'PointInTimeRestore')
        }
    }
    
    # Check if the resource type exists in the matrix
    if (-not $skuFeatureMatrix.ContainsKey($ResourceType)) {
        if ($ThrowOnInvalid) {
            throw [EAFResourceValidationException]::new(
                "Resource type '$ResourceType' is not defined in the SKU feature matrix.",
                $ResourceType,
                "SKUValidation",
                "UnsupportedResourceType",
                $ResourceType
            )
        }
        return $false
    }
    
    # Check if the SKU exists for the resource type
    if (-not $skuFeatureMatrix[$ResourceType].ContainsKey($SKU)) {
        if ($ThrowOnInvalid) {
            throw [EAFResourceValidationException]::new(
                "SKU '$SKU' is not defined for resource type '$ResourceType'.",
                $ResourceType,
                "SKUValidation",
                "UnsupportedSKU",
                $SKU
            )
        }
        return $false
    }
    
    # Get the supported features for the specified SKU
    $supportedFeatures = $skuFeatureMatrix[$ResourceType][$SKU]
    
    # Check if all requested features are supported
    $unsupportedFeatures = @()
    foreach ($feature in $Features) {
        if (-not $supportedFeatures.Contains($feature)) {
            $unsupportedFeatures += $feature
        }
    }
    
    # If there are unsupported features, validation fails
    if ($unsupportedFeatures.Count -gt 0) {
        if ($ThrowOnInvalid) {
            $supportedFeaturesStr = $supportedFeatures -join ', '
            $unsupportedFeaturesStr = $unsupportedFeatures -join ', '
            
            $errorMessage = "SKU '$SKU' for resource type '$ResourceType' does not support the following features: $unsupportedFeaturesStr`n"
            $errorMessage += "Supported features for this SKU are: $supportedFeaturesStr"
            
            throw [EAFResourceValidationException]::new(
                $errorMessage,
                $ResourceType,
                "SKUValidation",
                "UnsupportedFeatures",
                $unsupportedFeaturesStr
            )
        }
        return $false
    }
    
    # All features are supported
    return $true
}

# Export all functions for use in other modules
Export-ModuleMember -Function @(
    'Test-EAFResourceName',
    'Test-EAFResourceGroupExists',
    'Test-EAFNetworkConfiguration',
    'Test-EAFResourceExists',
    'Test-EAFStorageAccountName',
    'Test-EAFSecurePassword',
    'Test-EAFParameter',
    'Test-EAFSKUSupport'
)
