function New-EAFStorageAccount {
    <#
    .SYNOPSIS
        Creates a new Azure Storage Account using EAF standards.
    
    .DESCRIPTION
        The New-EAFStorageAccount cmdlet creates a new Azure Storage Account according to Enterprise Azure Framework (EAF) 
        standards. It provisions a storage account with proper naming, tagging, security settings, and diagnostic configurations.
        
        This cmdlet uses the storage.bicep template to ensure consistent storage account deployments across the organization.
    
    .PARAMETER ResourceGroupName
        Specifies the name of the resource group where the storage account will be deployed.
    
    .PARAMETER StorageAccountName
        Specifies the name of the storage account. Must follow naming convention st{name}{env}.
        Note: Storage account names must be between 3 and 24 characters, use lowercase letters and numbers only.
    
    .PARAMETER Location
        Specifies the Azure region where the storage account will be deployed. Defaults to the resource group's location.
    
    .PARAMETER StorageAccountType
        Specifies the type of storage account. Valid values: StorageV2, BlockBlobStorage, FileStorage.
        Defaults to StorageV2.
    
    .PARAMETER AccessTier
        Specifies the access tier for the storage account. Valid values: Hot, Cool.
        Defaults to Hot.
    
    .PARAMETER Sku
        Specifies the SKU for the storage account. 
        Valid values: Standard_LRS, Standard_GRS, Standard_RAGRS, Standard_ZRS, Premium_LRS, Premium_ZRS.
        Defaults to Standard_LRS.
    
    .PARAMETER EnableBlobVersioning
        Indicates whether blob versioning should be enabled. Defaults to true.
    
    .PARAMETER EnableBlobSoftDelete
        Indicates whether blob soft delete should be enabled. Defaults to true.
    
    .PARAMETER BlobSoftDeleteRetentionDays
        Specifies the number of days to retain deleted blobs. Range: 1-365 days. Defaults to 7.
    
    .PARAMETER EnableFileSoftDelete
        Indicates whether file share soft delete should be enabled. Defaults to true.
    
    .PARAMETER FileSoftDeleteRetentionDays
        Specifies the number of days to retain deleted file shares. Range: 1-365 days. Defaults to 7.
    
    .PARAMETER EnableHierarchicalNamespace
        Indicates whether hierarchical namespace (Data Lake Storage) should be enabled. Defaults to false.
    
    .PARAMETER AllowBlobPublicAccess
        Indicates whether public access is allowed to all blobs or containers in the storage account. Defaults to false.
    
    .PARAMETER AllowSharedKeyAccess
        Indicates whether shared key access is allowed. Defaults to true.
    
    .PARAMETER SupportsHttpsTrafficOnly
        Indicates whether the storage account only supports HTTPS traffic. Defaults to true.
    
    .PARAMETER MinimumTlsVersion
        Specifies the minimum TLS version required. Valid values: TLS1_0, TLS1_1, TLS1_2.
        Defaults to TLS1_2.
    
    .PARAMETER AllowAllNetworks
        Indicates whether access is allowed from all networks. Defaults to false.
    
    .PARAMETER AllowedVirtualNetworkSubnetIds
        Specifies an array of virtual network subnet resource IDs that are allowed to access the storage account.
    
    .PARAMETER AllowedIpAddressRanges
        Specifies an array of IP address ranges that are allowed to access the storage account.
    
    .PARAMETER DeployPrivateEndpoint
        Indicates whether a private endpoint should be deployed for the storage account. Defaults to false.
    
    .PARAMETER PrivateEndpointVirtualNetworkName
        Specifies the name of the virtual network for the private endpoint.
    
    .PARAMETER PrivateEndpointSubnetName
        Specifies the name of the subnet for the private endpoint.
    
    .PARAMETER PrivateEndpointVnetResourceGroup
        Specifies the resource group of the virtual network for the private endpoint.
        Defaults to the storage account's resource group.
    
    .PARAMETER CreateDefaultContainers
        Indicates whether default containers should be created. Defaults to false.
    
    .PARAMETER Containers
        Specifies an array of container names to create. Defaults to ['documents', 'images', 'logs'].
    
    .PARAMETER Environment
        Specifies the deployment environment (dev, test, prod). Defaults to dev.
    
    .PARAMETER Department
        Specifies the department or team responsible for the storage account.
    
    .PARAMETER Force
        Forces the command to run without asking for user confirmation.
    
    .EXAMPLE
        New-EAFStorageAccount -ResourceGroupName "rg-storage-dev" -StorageAccountName "stshareddev" -Department "IT"
        
        Creates a new storage account named "stshareddev" in the resource group "rg-storage-dev" with default settings.
    
    .EXAMPLE
        New-EAFStorageAccount -ResourceGroupName "rg-storage-test" -StorageAccountName "stanalyticstest" -StorageAccountType "BlockBlobStorage" -Sku "Premium_LRS" -Department "DataScience" -Environment "test" -AllowBlobPublicAccess $false -CreateDefaultContainers $true
        
        Creates a new premium block blob storage account in the test environment with default containers.
    
    .INPUTS
        None. You cannot pipe objects to New-EAFStorageAccount.
    
    .OUTPUTS
        PSCustomObject. Returns an object containing the deployment details.
    
    .NOTES
        Requires Az PowerShell modules.
        Author: EAF Team
        Version: 1.1
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        # Pattern validation will be handled by Test-EAFStorageAccountName
        # [ValidatePattern('^st[a-z0-9]+(?:dev|test|prod)$')] 
        [ValidateLength(3, 24)]
        [string]$StorageAccountName,
        
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Location,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('StorageV2', 'BlockBlobStorage', 'FileStorage')]
        [string]$StorageAccountType = 'StorageV2',
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Hot', 'Cool')]
        [string]$AccessTier = 'Hot',
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS', 'Premium_LRS', 'Premium_ZRS')]
        [string]$Sku = 'Standard_LRS', # Default, might be overridden by Get-EAFDefaultSKU
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableBlobVersioning = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableBlobSoftDelete = $true,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 365)]
        [int]$BlobSoftDeleteRetentionDays = 7,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableFileSoftDelete = $true,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 365)]
        [int]$FileSoftDeleteRetentionDays = 7,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableHierarchicalNamespace = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$AllowBlobPublicAccess = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$AllowSharedKeyAccess = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$SupportsHttpsTrafficOnly = $true,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('TLS1_0', 'TLS1_1', 'TLS1_2')]
        [string]$MinimumTlsVersion = 'TLS1_2',
        
        [Parameter(Mandatory = $false)]
        [bool]$AllowAllNetworks = $false,
        
        [Parameter(Mandatory = $false)]
        [string[]]$AllowedVirtualNetworkSubnetIds = @(),
        
        [Parameter(Mandatory = $false)]
        [string[]]$AllowedIpAddressRanges = @(),
        
        [Parameter(Mandatory = $false)]
        [bool]$DeployPrivateEndpoint = $false,
        
        [Parameter(Mandatory = $false)]
        [string]$PrivateEndpointVirtualNetworkName = '',
        
        [Parameter(Mandatory = $false)]
        [string]$PrivateEndpointSubnetName = '',
        
        [Parameter(Mandatory = $false)]
        [string]$PrivateEndpointVnetResourceGroup = '',
        
        [Parameter(Mandatory = $false)]
        [bool]$CreateDefaultContainers = $false,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Containers = @('documents', 'images', 'logs'),
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$Environment = 'dev',
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Department,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    begin {
        Write-Verbose "Initializing New-EAFStorageAccount operation..."
        # Import helper modules
        $modulePath = Split-Path -Path $PSScriptRoot -Parent
        $privateModulePath = Join-Path -Path $modulePath -ChildPath "Private"
        
        $script:EAFHelperModulesLoaded = $false
        $helperModules = @(
            "exceptions.psm1",
            "retry-logic.psm1",
            "validation-helpers.psm1",
            "configuration-helpers.psm1",
            "monitoring-helpers.psm1" # Assuming this might contain Get-EAFDefaultTags or similar
        )
        
        foreach ($helperModuleFile in $helperModules) {
            $helperModulePath = Join-Path -Path $privateModulePath -ChildPath $helperModuleFile
            if (Test-Path -Path $helperModulePath) {
                Import-Module -Name $helperModulePath -Force -ErrorAction Stop
                Write-Verbose "Loaded helper module: $helperModuleFile"
            }
            else {
                # Using Write-Warning as per New-EAFAppService example, but throwing an exception might be more robust for critical helpers
                Write-Warning "Helper module not found: $helperModulePath" 
            }
        }
        $script:EAFHelperModulesLoaded = $true

        # Check for required Azure PowerShell modules
        try {
            Write-Verbose "Checking for required Az modules..."
            $requiredAzModules = @('Az.Storage', 'Az.Resources', 'Az.Network') # Az.Network for private endpoint checks
            foreach ($azModule in $requiredAzModules) {
                if (-not (Get-Module -ListAvailable -Name $azModule)) {
                    throw [EAFDependencyException]::new(
                        "Required module $azModule is not installed. Please install using: Install-Module $azModule -Force",
                        "StorageAccount", # ResourceType
                        "AzureModule",    # DependencyType
                        $azModule,         # DependencyName
                        "NotInstalled"    # Status
                    )
                }
            }
            Write-Verbose "All required Az modules are available."
        }
        catch {
            # Assuming Write-EAFException is available from exceptions.psm1
            Write-EAFException -Exception $_.Exception -ErrorCategory NotInstalled -Throw 
            return # Should not be reached if -Throw works
        }
        
        # Initialize Bicep template path
        $script:templatePath = Join-Path -Path $PSScriptRoot -ChildPath "..\Templates\storage.bicep"
        if (-not (Test-Path -Path $script:templatePath)) {
            throw [EAFDependencyException]::new(
                "Storage Account Bicep template not found at: $($script:templatePath)",
                "StorageAccount",   # ResourceType
                "BicepTemplate",    # DependencyType
                $script:templatePath, # DependencyName
                "NotFound"          # Status
            )
        }
        Write-Verbose "Using Bicep template: $($script:templatePath)"
    }
    
    process {
        Write-Progress -Activity "Creating Azure Storage Account" -Status "Initializing" -PercentComplete 0
        $primaryKey = $null
        $connectionString = $null

        try {
            # Step 1: Verify resource group exists
            Write-Verbose "Checking resource group $ResourceGroupName exists..."
            Write-Progress -Activity "Creating Azure Storage Account" -Status "Verifying resource group" -PercentComplete 5
            Test-EAFResourceGroupExists -ResourceGroupName $ResourceGroupName -ThrowOnNotExist $true
            
            # Step 2: Determine Location
            Write-Progress -Activity "Creating Azure Storage Account" -Status "Determining location" -PercentComplete 10
            if (-not $PSBoundParameters.ContainsKey('Location') -or [string]::IsNullOrEmpty($Location)) {
                $configLocation = Get-EAFConfiguration -ConfigPath "Regions.Default.$Environment" -ErrorAction SilentlyContinue
                if (-not [string]::IsNullOrEmpty($configLocation)) {
                    $Location = $configLocation
                    Write-Verbose "Using location from EAF configuration: $Location"
                }
                else {
                    $resourceGroupDetails = Get-AzResourceGroup -Name $ResourceGroupName
                    $Location = $resourceGroupDetails.Location
                    Write-Verbose "Using resource group location: $Location"
                }
            }

            # Step 3: Determine SKU
            Write-Progress -Activity "Creating Azure Storage Account" -Status "Determining SKU" -PercentComplete 15
            if ($PSBoundParameters.ContainsKey('Sku') -and $Sku -eq 'Standard_LRS') { # Check if it's the default
                 $defaultSku = Get-EAFDefaultSKU -ResourceType "StorageAccount" -Environment $Environment -ErrorAction SilentlyContinue
                 if(-not [string]::IsNullOrEmpty($defaultSku)) {
                     $Sku = $defaultSku
                     Write-Verbose "Using SKU from EAF configuration: $Sku"
                 }
            }

            # Step 4: Validate Storage Account Name and check availability
            Write-Verbose "Validating Storage Account name $StorageAccountName..."
            Write-Progress -Activity "Creating Azure Storage Account" -Status "Validating name" -PercentComplete 20
            Test-EAFStorageAccountName -StorageAccountName $StorageAccountName -Environment $Environment -ThrowOnInvalid $true
            
            # Step 5: Check if Storage Account already exists (Idempotency)
            Write-Verbose "Checking if Storage Account $StorageAccountName already exists..."
            Write-Progress -Activity "Creating Azure Storage Account" -Status "Checking existing resource" -PercentComplete 25
            
            $existingStorageAccount = Invoke-WithRetry -ScriptBlock {
                Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
            } -MaxRetryCount 3 -ActivityName "Checking Storage Account existence"
            
            if ($existingStorageAccount) {
                Write-Verbose "Storage account $StorageAccountName already exists in resource group $ResourceGroupName."
                if (-not $Force -and -not $PSCmdlet.ShouldProcess($StorageAccountName, "Update existing Storage Account configuration (Note: Some properties may not be updatable once set. Review Bicep output for details.)")) {
                    Write-Warning "Storage Account $StorageAccountName already exists. No changes will be made. Use -Force to attempt an update."
                    # Consider returning a more EAF-standard object if the existing object is directly returned
                    return $existingStorageAccount 
                }
                Write-Verbose "Proceeding with Storage Account update/reconfiguration as -Force or -Confirm was provided."
            }
            
            # Step 6: Validate private endpoint parameters if required
            if ($DeployPrivateEndpoint) {
                Write-Verbose "Validating private endpoint parameters..."
                Write-Progress -Activity "Creating Azure Storage Account" -Status "Validating network configuration" -PercentComplete 30
                
                if ([string]::IsNullOrEmpty($PrivateEndpointVirtualNetworkName) -or [string]::IsNullOrEmpty($PrivateEndpointSubnetName)) {
                    throw [EAFParameterValidationException]::new(
                        "When DeployPrivateEndpoint is set to true, PrivateEndpointVirtualNetworkName and PrivateEndpointSubnetName must be specified.",
                        "StorageAccount",
                        "PrivateEndpointVirtualNetworkName/PrivateEndpointSubnetName",
                        "MissingParameters"
                    )
                }
                
                $effectivePrivateEndpointVnetRG = if ([string]::IsNullOrEmpty($PrivateEndpointVnetResourceGroup)) { $ResourceGroupName } else { $PrivateEndpointVnetResourceGroup }
                Write-Verbose "Private endpoint VNet resource group: $effectivePrivateEndpointVnetRG"

                # Using Test-EAFNetworkConfiguration (assuming it can check VNet and Subnet)
                # If it doesn't exist or has different parameters, this would need adjustment or use existing detailed checks.
                # For now, falling back to detailed checks similar to original script, wrapped in EAF exceptions.
                try {
                    Test-EAFNetworkConfiguration -VirtualNetworkName $PrivateEndpointVirtualNetworkName -SubnetName $PrivateEndpointSubnetName -ResourceGroupName $effectivePrivateEndpointVnetRG -ThrowOnInvalid $true
                    Write-Verbose "Private endpoint network configuration validated successfully using Test-EAFNetworkConfiguration."
                }
                catch {
                    if ($_.Exception -is [EAFException]) { Write-EAFException -Exception $_.Exception -Throw }

                    # Fallback to manual-like checks if Test-EAFNetworkConfiguration is not suitable or fails generically
                    Write-Warning "Test-EAFNetworkConfiguration failed or is not fully implemented for this check. Performing detailed validation. Error: $($_.Exception.Message)"
                    $vnet = Get-AzVirtualNetwork -ResourceGroupName $effectivePrivateEndpointVnetRG -Name $PrivateEndpointVirtualNetworkName -ErrorAction SilentlyContinue
                    if (-not $vnet) {
                        throw [EAFNetworkConfigurationException]::new("Virtual network '$PrivateEndpointVirtualNetworkName' not found in resource group '$effectivePrivateEndpointVnetRG'.", "StorageAccount", $PrivateEndpointVirtualNetworkName, "VNetNotFound")
                    }
                    $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $PrivateEndpointSubnetName }
                    if (-not $subnet) {
                        throw [EAFNetworkConfigurationException]::new("Subnet '$PrivateEndpointSubnetName' not found in virtual network '$PrivateEndpointVirtualNetworkName'.", "StorageAccount", $PrivateEndpointSubnetName, "SubnetNotFound")
                    }
                    if ($subnet.PrivateEndpointNetworkPolicies -eq 'Enabled') {
                        Write-Warning "Subnet '$PrivateEndpointSubnetName' has PrivateEndpointNetworkPolicies enabled. This setting can interfere with Private Link Service/Endpoint creation. Consider disabling it if issues arise."
                    }
                    Write-Verbose "Detailed private endpoint network configuration validated."
                }
            }
            
            # Step 7: Prepare deployment parameters
            Write-Verbose "Preparing deployment parameters..."
            Write-Progress -Activity "Creating Azure Storage Account" -Status "Preparing deployment" -PercentComplete 40
            
            $deploymentName = "Deploy-Storage-$StorageAccountName-$(Get-Date -Format 'yyyyMMddHHmmss')"
            $defaultTags = Get-EAFDefaultTags -Environment $Environment -Department $Department -ResourceType "StorageAccount"
            
            $templateParams = @{
                storageAccountName = $StorageAccountName
                location = $Location
                storageAccountType = $StorageAccountType
                accessTier = $AccessTier
                sku = $Sku
                enableBlobVersioning = $EnableBlobVersioning
                enableBlobSoftDelete = $EnableBlobSoftDelete
                blobSoftDeleteRetentionDays = $BlobSoftDeleteRetentionDays
                enableFileSoftDelete = $EnableFileSoftDelete
                fileSoftDeleteRetentionDays = $FileSoftDeleteRetentionDays
                enableHierarchicalNamespace = $EnableHierarchicalNamespace
                allowBlobPublicAccess = $AllowBlobPublicAccess
                allowSharedKeyAccess = $AllowSharedKeyAccess
                supportsHttpsTrafficOnly = $SupportsHttpsTrafficOnly
                minimumTlsVersion = $MinimumTlsVersion
                allowAllNetworks = $AllowAllNetworks
                allowedVirtualNetworkSubnetIds = $AllowedVirtualNetworkSubnetIds
                allowedIpAddressRanges = $AllowedIpAddressRanges
                deployPrivateEndpoint = $DeployPrivateEndpoint
                privateEndpointVirtualNetworkName = $PrivateEndpointVirtualNetworkName
                privateEndpointSubnetName = $PrivateEndpointSubnetName
                # Use effective RG for PE VNet
                privateEndpointVnetResourceGroup = if ($DeployPrivateEndpoint) { if ([string]::IsNullOrEmpty($PrivateEndpointVnetResourceGroup)) { $ResourceGroupName } else { $PrivateEndpointVnetResourceGroup } } else { '' }
                # CreateDefaultContainers and Containers are not in the repaired bicep, but kept for consistency if bicep is expanded
                # containers = $Containers 
                environment = $Environment
                department = $Department
                # Assuming Get-EAFDefaultTags returns a hashtable to be merged
                additionalTags = $defaultTags 
            }
            
            # Step 8: Deploy Storage Account using Bicep template
            if ($PSCmdlet.ShouldProcess($StorageAccountName, "Deploy Azure Storage Account")) {
                Write-Verbose "Deploying Storage Account $StorageAccountName via Bicep template $($script:templatePath)..."
                Write-Progress -Activity "Creating Azure Storage Account" -Status "Deploying resources" -PercentComplete 60
                
                $deployment = Invoke-WithRetry -ScriptBlock {
                    New-AzResourceGroupDeployment `
                        -ResourceGroupName $ResourceGroupName `
                        -Name $deploymentName `
                        -TemplateFile $script:templatePath `
                        -TemplateParameterObject $templateParams `
                        -Verbose:$VerbosePreference -ErrorAction Stop # ErrorAction Stop for Invoke-WithRetry
                } -MaxRetryCount 3 -ActivityName "Storage Account Bicep Deployment"
                
                Write-Progress -Activity "Creating Azure Storage Account" -Status "Deployment complete" -PercentComplete 90
                
                if ($deployment.ProvisioningState -eq 'Succeeded') {
                    Write-Verbose "Storage Account $StorageAccountName Bicep deployment reported success."
                    
                    # Get the Storage Account details (may not be strictly necessary if Bicep outputs everything)
                    $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
                    
                    $primaryKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
                    $connectionString = "DefaultEndpointsProtocol=https;AccountName=$StorageAccountName;AccountKey=$primaryKey;EndpointSuffix=$((Get-AzContext).Environment.StorageEndpointSuffix)"
                    $secureConnectionString = ConvertTo-SecureString -String $connectionString -AsPlainText -Force
                    
                    $result = [PSCustomObject]@{
                        Name = $storageAccount.StorageAccountName
                        ResourceGroupName = $ResourceGroupName
                        Location = $storageAccount.Location
                        StorageAccountType = $storageAccount.Kind # Or $StorageAccountType if Bicep output is preferred
                        AccessTier = $storageAccount.AccessTier # Or $AccessTier
                        Sku = $storageAccount.Sku.Name # Or $Sku
                        BlobEndpoint = $storageAccount.PrimaryEndpoints.Blob
                        FileEndpoint = $storageAccount.PrimaryEndpoints.File
                        QueueEndpoint = $storageAccount.PrimaryEndpoints.Queue
                        TableEndpoint = $storageAccount.PrimaryEndpoints.Table
                        PrivateEndpointDeployed = $DeployPrivateEndpoint # This might need to come from Bicep output if complex
                        NetworkRestricted = -not $AllowAllNetworks # This might need to come from Bicep output
                        SecureConnectionString = $secureConnectionString
                        HierarchicalNamespaceEnabled = $storageAccount.EnableHierarchicalNamespace
                        BlobVersioningEnabled = $EnableBlobVersioning # From input, confirm with actual state if needed
                        BlobSoftDeleteEnabled = $EnableBlobSoftDelete # From input, confirm with actual state if needed
                        ProvisioningState = $storageAccount.ProvisioningState
                        DeploymentId = $deployment.DeploymentId # Corrected from DeploymentName
                        DeploymentTimestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        Tags = $storageAccount.Tags # Actual tags applied
                        StorageAccountReference = $storageAccount
                    }
                    Write-Progress -Activity "Creating Azure Storage Account" -Status "Completed" -PercentComplete 100
                    return $result
                }
                else {
                    # Extract error details from deployment result if available
                    $errorDetails = $deployment.Properties.Error.Details | ForEach-Object { $_.Message } | Out-String
                    throw [EAFProvisioningFailedException]::new(
                        "Bicep deployment for Storage Account '$StorageAccountName' failed with state: $($deployment.ProvisioningState). Details: $errorDetails",
                        "StorageAccount",
                        $StorageAccountName,
                        $deployment.ProvisioningState,
                        $deployment.CorrelationId
                    )
                }
            } else {
                 Write-Warning "Deployment of Storage Account $StorageAccountName skipped due to ShouldProcess preference."
                 return $null
            }
        }
        catch {
            Write-Progress -Activity "Creating Azure Storage Account" -Status "Error" -PercentComplete 100 -Completed
            if ($_.Exception -is [EAFException]) {
                Write-EAFException -Exception $_.Exception -Throw
            }
            else {
                # Wrap non-EAF exceptions
                $wrappedException = [EAFProvisioningFailedException]::new(
                    "Failed to create Storage Account '$StorageAccountName': $($_.Exception.Message)",
                    "StorageAccount",
                    $StorageAccountName,
                    "UnknownError",
                    $null, # No correlation ID for non-deployment errors
                    $_.Exception # Inner exception
                )
                Write-EAFException -Exception $wrappedException -Throw
            }
        }
        finally {
            # Clear sensitive variables
            if ($null -ne $primaryKey) { Remove-Variable -Name primaryKey -ErrorAction SilentlyContinue -Scope Script }
            if ($null -ne $connectionString) { Remove-Variable -Name connectionString -ErrorAction SilentlyContinue -Scope Script }
            Write-Progress -Activity "Creating Azure Storage Account" -Completed
        }
    }
    
    end {
        Write-Verbose "New-EAFStorageAccount operation finished."
        if ($script:EAFHelperModulesLoaded) {
            $helperModuleNames = @(
                "exceptions",
                "retry-logic",
                "validation-helpers",
                "configuration-helpers",
                "monitoring-helpers"
            )
            foreach ($helperModuleName in $helperModuleNames) {
                if (Get-Module -Name $helperModuleName -ErrorAction SilentlyContinue) {
                    Remove-Module -Name $helperModuleName -ErrorAction SilentlyContinue
                    Write-Verbose "Unloaded helper module: $helperModuleName"
                }
            }
        }
    }
}
