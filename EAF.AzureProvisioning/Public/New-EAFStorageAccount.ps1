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
    
    .EXAMPLE
        $storageParams = @{
            ResourceGroupName = "rg-storage-prod"
            StorageAccountName = "stbackupprod"
            Sku = "Standard_GRS"
            AccessTier = "Cool"
            Department = "Operations"
            Environment = "prod"
            AllowAllNetworks = $false
            AllowedIpAddressRanges = @("10.0.0.0/24", "10.1.0.0/24")
            BlobSoftDeleteRetentionDays = 30
            FileSoftDeleteRetentionDays = 30
        }
        New-EAFStorageAccount @storageParams
        
        Creates a new geo-redundant cool storage account in the production environment with network restrictions.
    
    .INPUTS
        None. You cannot pipe objects to New-EAFStorageAccount.
    
    .OUTPUTS
        PSCustomObject. Returns an object containing the deployment details.
    
    .NOTES
        Requires Az PowerShell modules.
        Author: EAF Team
        Version: 1.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^st[a-z0-9]+(?:dev|test|prod)$')]
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
        [string]$Sku = 'Standard_LRS',
        
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
        # Check for required Azure PowerShell modules
        try {
            Write-Verbose "Checking for required Az modules..."
            $modules = @('Az.Storage', 'Az.Resources')
            foreach ($module in $modules) {
                if (-not (Get-Module -ListAvailable -Name $module)) {
                    throw "Required module $module is not installed. Please install using: Install-Module $module -Force"
                }
            }
        }
        catch {
            Write-Error ("Module validation failed: " + ${_})
            return
        }
        
        # Initialize variables
        $templatePath = Join-Path -Path $PSScriptRoot -ChildPath "..\Templates\storage.bicep"
        if (-not (Test-Path -Path $templatePath)) {
            Write-Error "Storage account Bicep template not found at: $templatePath"
            return
        }
        
        Write-Verbose "Using Bicep template: $templatePath"
        $dateCreated = Get-Date -Format "yyyy-MM-dd"
    }
    
    process {
        Write-Progress -Activity "Creating Azure Storage Account" -Status "Initializing" -PercentComplete 0
        
        try {
            # Step 1: Verify resource group exists
            Write-Verbose "Checking resource group $ResourceGroupName exists..."
            Write-Progress -Activity "Creating Azure Storage Account" -Status "Verifying resource group" -PercentComplete 10
            
            $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
            if (-not $resourceGroup) {
                throw "Resource group '$ResourceGroupName' not found. Please create it first."
            }
            
            # Use resource group location if not specified
            if (-not $Location) {
                $Location = $resourceGroup.Location
                Write-Verbose "Using resource group location: $Location"
            }
            
            # Step 2: Check if Storage Account name is available (if it doesn't exist)
            Write-Verbose "Checking if Storage Account $StorageAccountName already exists or if name is available..."
            Write-Progress -Activity "Creating Azure Storage Account" -Status "Checking name availability" -PercentComplete 20
            
            $existingStorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
            
            if (-not $existingStorageAccount) {
                # Check if name is available
                $nameAvailability = Get-AzStorageAccountNameAvailability -Name $StorageAccountName
                if (-not $nameAvailability.NameAvailable) {
                    throw "Storage account name '$StorageAccountName' is not available. Reason: $($nameAvailability.Reason) - $($nameAvailability.Message)"
                }
                Write-Verbose "Storage account name '$StorageAccountName' is available."
            } else {
                Write-Verbose "Storage account $StorageAccountName already exists."
                if (-not $Force -and -not $PSCmdlet.ShouldProcess($StorageAccountName, "Update existing Storage Account")) {
                    Write-Output "Storage Account $StorageAccountName already exists. Use -Force to update or modify existing configuration."
                    return $existingStorageAccount
                }
                Write-Verbose "Proceeding with Storage Account update..."
            }
            
            # Step 3: Validate private endpoint parameters if required
            if ($DeployPrivateEndpoint) {
                Write-Verbose "Validating private endpoint parameters..."
                Write-Progress -Activity "Creating Azure Storage Account" -Status "Validating network configuration" -PercentComplete 30
                
                if ([string]::IsNullOrEmpty($PrivateEndpointVirtualNetworkName) -or [string]::IsNullOrEmpty($PrivateEndpointSubnetName)) {
                    throw "When DeployPrivateEndpoint is set to true, PrivateEndpointVirtualNetworkName and PrivateEndpointSubnetName must be specified."
                }
                
                if ([string]::IsNullOrEmpty($PrivateEndpointVnetResourceGroup)) {
                    $PrivateEndpointVnetResourceGroup = $ResourceGroupName
                    Write-Verbose "Using storage account resource group for private endpoint VNet: $PrivateEndpointVnetResourceGroup"
                }
                
                # Verify virtual network and subnet exist
                try {
                    $vnet = Get-AzVirtualNetwork -ResourceGroupName $PrivateEndpointVnetResourceGroup -Name $PrivateEndpointVirtualNetworkName -ErrorAction Stop
                    $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $PrivateEndpointSubnetName }
                    
                    if (-not $subnet) {
                        throw "Subnet '$PrivateEndpointSubnetName' not found in virtual network '$PrivateEndpointVirtualNetworkName'."
                    }
                    
                    # Verify subnet allows private endpoints
                    if ($subnet.PrivateEndpointNetworkPolicies -eq 'Enabled') {
                        Write-Warning "Subnet '$PrivateEndpointSubnetName' has private endpoint network policies enabled, which may block private endpoint creation."
                    }
                    
                    Write-Verbose "Private endpoint network configuration validated successfully."
                }
                catch {
                    throw "Failed to validate private endpoint network configuration: ${_}"
                }
            }
            
            # Step 4: Prepare deployment parameters
            Write-Verbose "Preparing deployment parameters..."
            Write-Progress -Activity "Creating Azure Storage Account" -Status "Preparing deployment" -PercentComplete 40
            
            $deploymentName = "Deploy-Storage-$StorageAccountName-$(Get-Date -Format 'yyyyMMddHHmmss')"
            
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
                privateEndpointVnetResourceGroup = $PrivateEndpointVnetResourceGroup
                createDefaultContainers = $CreateDefaultContainers
                containers = $Containers
                environment = $Environment
                department = $Department
                dateCreated = $dateCreated
            }
            
            # Step 5: Deploy Storage Account using Bicep template
            if ($PSCmdlet.ShouldProcess($StorageAccountName, "Deploy Azure Storage Account")) {
                Write-Verbose "Deploying Storage Account $StorageAccountName..."
                Write-Progress -Activity "Creating Azure Storage Account" -Status "Deploying resources" -PercentComplete 60
                
                $deployment = New-AzResourceGroupDeployment `
                    -ResourceGroupName $ResourceGroupName `
                    -Name $deploymentName `
                    -TemplateFile $templatePath `
                    -TemplateParameterObject $templateParams `
                    -Verbose:$VerbosePreference
                
                Write-Progress -Activity "Creating Azure Storage Account" -Status "Deployment complete" -PercentComplete 100
                
                if ($deployment.ProvisioningState -eq 'Succeeded') {
                    Write-Verbose "Storage Account $StorageAccountName deployed successfully"
                    
                    # Get the Storage Account details
                    $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
                    
                    # Get the connection string (securely)
                    $storageKeys = Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
                    $primaryKey = $storageKeys[0].Value
                    $connectionString = "DefaultEndpointsProtocol=https;AccountName=$StorageAccountName;AccountKey=$primaryKey;EndpointSuffix=$((Get-AzContext).Environment.StorageEndpointSuffix)"
                    
                    # Create a secure string for the connection string
                    $secureConnectionString = ConvertTo-SecureString -String $connectionString -AsPlainText -Force
                    
                    # Return custom object with deployment details
                    $result = [PSCustomObject]@{
                        Name = $storageAccount.StorageAccountName
                        ResourceGroupName = $ResourceGroupName
                        Location = $storageAccount.Location
                        StorageAccountType = $storageAccount.Kind
                        AccessTier = $storageAccount.AccessTier
                        Sku = $storageAccount.Sku.Name
                        BlobEndpoint = $storageAccount.PrimaryEndpoints.Blob
                        FileEndpoint = $storageAccount.PrimaryEndpoints.File
                        QueueEndpoint = $storageAccount.PrimaryEndpoints.Queue
                        TableEndpoint = $storageAccount.PrimaryEndpoints.Table
                        PrivateEndpointDeployed = $DeployPrivateEndpoint
                        NetworkRestricted = -not $AllowAllNetworks
                        SecureConnectionString = $secureConnectionString
                        HierarchicalNamespaceEnabled = $storageAccount.EnableHierarchicalNamespace
                        BlobVersioningEnabled = $EnableBlobVersioning
                        BlobSoftDeleteEnabled = $EnableBlobSoftDelete
                        ProvisioningState = $storageAccount.ProvisioningState
                        DeploymentId = $deployment.DeploymentName
                        DeploymentTimestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        StorageAccountReference = $storageAccount
                    }
                    
                    return $result
                }
                else {
                    throw "Deployment failed with state: $($deployment.ProvisioningState)"
                }
            }
        }
        catch {
            Write-Progress -Activity "Creating Azure Storage Account" -Status "Error" -PercentComplete 100 -Completed
            Write-Error ("Error creating Storage Account " + $StorageAccountName + ": " + ${_})
            throw $_
        }
        finally {
            Write-Progress -Activity "Creating Azure Storage Account" -Completed
            # Clear any sensitive variables from memory
            if ($null -ne $primaryKey) { Remove-Variable -Name primaryKey -ErrorAction SilentlyContinue }
            if ($null -ne $connectionString) { Remove-Variable -Name connectionString -ErrorAction SilentlyContinue }
        }
    }
    
    end {
        Write-Verbose "New-EAFStorageAccount operation completed"
    }
}
