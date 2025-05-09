function New-EAFKeyVault {
    <#
    .SYNOPSIS
        Creates a new Azure Key Vault using EAF standards.
        
    .DESCRIPTION
        Creates a new Azure Key Vault using Enterprise Azure Framework (EAF) standards. 
        It provisions a Key Vault with proper naming, tagging, security settings, and access controls.
        
        This cmdlet uses the keyVault.bicep template to ensure consistent Key Vault deployments across the organization.
    
    .PARAMETER ResourceGroupName
        Specifies the name of the resource group where the Key Vault will be deployed.
    
    .PARAMETER KeyVaultName
        Specifies the name of the Key Vault. Must follow naming convention kv-{name}-{env}.
        Note: Key Vault names must be globally unique, between 3-24 characters, and contain only alphanumeric characters and hyphens.
    
    .PARAMETER Location
        Specifies the Azure region where the Key Vault will be deployed. Defaults to the resource group's location.
    
    .PARAMETER SkuName
        Specifies the SKU name for the Key Vault. Valid values: standard, premium.
        Defaults to standard.
    
    .PARAMETER EnableRbacAuthorization
        Indicates whether RBAC authorization should be enabled. Defaults to true.
        When true, access policies must be managed via RBAC roles. When false, access policies must be explicitly configured.
    
    .PARAMETER EnableSoftDelete
        Indicates whether soft delete should be enabled. Defaults to true.
    
    .PARAMETER SoftDeleteRetentionInDays
        Specifies the soft delete retention period in days. Range: 7-90 days. Defaults to 90.
    
    .PARAMETER EnablePurgeProtection
        Indicates whether purge protection should be enabled. Defaults to true.
        Note: Once enabled, purge protection cannot be disabled.
    
    .PARAMETER EnabledForTemplateDeployment
        Indicates whether Key Vault is enabled for template deployment. Defaults to false.
    
    .PARAMETER EnabledForDiskEncryption
        Indicates whether Key Vault is enabled for disk encryption. Defaults to false.
    
    .PARAMETER EnabledForDeployment
        Indicates whether Key Vault is enabled for deployment (VMs). Defaults to false.
    
    .PARAMETER PublicNetworkAccess
        Indicates whether public network access is allowed. Defaults to false.
    
    .PARAMETER NetworkAclDefaultAction
        Specifies the default network ACL action. Valid values: Allow, Deny.
        Defaults to Deny.
    
    .PARAMETER AllowedVirtualNetworkSubnetIds
        Specifies an array of virtual network subnet resource IDs that are allowed to access the Key Vault.
    
    .PARAMETER AllowedIpAddressRanges
        Specifies an array of IP address ranges in CIDR notation that are allowed to access the Key Vault.
    
    .PARAMETER DeployPrivateEndpoint
        Indicates whether a private endpoint should be deployed for the Key Vault. Defaults to false.
    
    .PARAMETER PrivateEndpointVirtualNetworkName
        Specifies the name of the virtual network for the private endpoint.
    
    .PARAMETER PrivateEndpointSubnetName
        Specifies the name of the subnet for the private endpoint.
    
    .PARAMETER PrivateEndpointVnetResourceGroup
        Specifies the resource group of the virtual network for the private endpoint.
        Defaults to the Key Vault's resource group.
    
    .PARAMETER AdminObjectId
        Specifies the Object ID of the AAD user, group, or service principal to grant admin permissions.
        Required if RBAC or default access policy is enabled.
    
    .PARAMETER DeployDefaultAccessPolicy
        Indicates whether to deploy a default access policy. Defaults to false.
        Only applicable when RBAC authorization is disabled.
    
    .PARAMETER AccessPolicies
        Specifies an array of access policies to assign to the Key Vault.
        Only applicable when RBAC authorization is disabled.
        
        Each access policy should contain:
        - TenantId: Tenant ID
        - ObjectId: AAD object ID (user, group, or service principal)
        - Permissions: Object with keys, secrets, and certificates arrays specifying permissions
    
    .PARAMETER Secrets
        Specifies an array of secrets to add to the Key Vault.
        
        Each secret should contain:
        - Name: Secret name
        - Value: Secret value
        - ContentType (optional): Content type of the secret
        - Enabled (optional): Whether the secret is enabled
    
    .PARAMETER Environment
        Specifies the deployment environment (dev, test, prod). Defaults to dev.
    
    .PARAMETER Department
        Specifies the department or team responsible for the Key Vault.
    
    .PARAMETER Force
        Forces the command to run without asking for user confirmation.
    
    .EXAMPLE
        New-EAFKeyVault -ResourceGroupName "rg-security-dev" -KeyVaultName "kv-app1-dev" -Department "IT" -AdminObjectId "00000000-0000-0000-0000-000000000000"
        
        Creates a new Key Vault named "kv-app1-dev" in the resource group "rg-security-dev" with default settings and RBAC authorization.
    
    .EXAMPLE
        New-EAFKeyVault -ResourceGroupName "rg-security-test" -KeyVaultName "kv-app1-test" -SkuName "premium" -EnableRbacAuthorization $false -DeployDefaultAccessPolicy $true -AdminObjectId "00000000-0000-0000-0000-000000000000" -Department "Finance" -Environment "test"
        
        Creates a new premium Key Vault in the test environment with a default access policy.
    
    .EXAMPLE
        $secretsToAdd = @(
            @{
                name = "AppSecret"
                value = "MySecretValue123!"
                contentType = "text/plain"
            },
            @{
                name = "DatabaseConnection"
                value = "Server=myserver;Database=mydb;User Id=admin;Password=password;"
            }
        )
        
        $kvParams = @{
            ResourceGroupName = "rg-security-prod"
            KeyVaultName = "kv-app1-prod"
            SkuName = "premium"
            Department = "Operations"
            Environment = "prod"
            PublicNetworkAccess = $false
            DeployPrivateEndpoint = $true
            PrivateEndpointVirtualNetworkName = "vnet-prod"
            PrivateEndpointSubnetName = "subnet-services"
            AdminObjectId = "00000000-0000-0000-0000-000000000000"
            Secrets = $secretsToAdd
        }
        New-EAFKeyVault @kvParams
        
        Creates a new premium Key Vault in the production environment with private endpoint and initial secrets.
    
    .INPUTS
        None. You cannot pipe objects to New-EAFKeyVault.
    
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
        [ValidatePattern('^kv-[a-zA-Z0-9]+-(?:dev|test|prod)$')]
        [ValidateLength(3, 24)]
        [string]$KeyVaultName,
        
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Location,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('standard', 'premium')]
        [string]$SkuName = 'standard',
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableRbacAuthorization = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableSoftDelete = $true,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(7, 90)]
        [int]$SoftDeleteRetentionInDays = 90,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnablePurgeProtection = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnabledForTemplateDeployment = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnabledForDiskEncryption = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnabledForDeployment = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$PublicNetworkAccess = $false,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Allow', 'Deny')]
        [string]$NetworkAclDefaultAction = 'Deny',
        
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
        [string]$AdminObjectId = '',
        
        [Parameter(Mandatory = $false)]
        [bool]$DeployDefaultAccessPolicy = $false,
        
        [Parameter(Mandatory = $false)]
        [array]$AccessPolicies = @(),
        
        [Parameter(Mandatory = $false)]
        [array]$Secrets = @(),
        
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
        # Import helper modules
        $modulePath = Split-Path -Path $PSScriptRoot -Parent
        $privateModulePath = Join-Path -Path $modulePath -ChildPath "Private"
        
        $helperModules = @(
            "exceptions.psm1",
            "retry-logic.psm1",
            "validation-helpers.psm1",
            "configuration-helpers.psm1",
            "monitoring-helpers.psm1"
        )
        
        foreach ($helperModule in $helperModules) {
            $modulePath = Join-Path -Path $privateModulePath -ChildPath $helperModule
            if (Test-Path -Path $modulePath) {
                Import-Module -Name $modulePath -Force -ErrorAction Stop
            }
            else {
                Write-Warning "Helper module not found: $modulePath"
            }
        }
        
        # Check for required Azure PowerShell modules
        try {
            Write-Verbose "Checking for required Az modules..."
            $modules = @('Az.KeyVault', 'Az.Resources', 'Az.Network')
            foreach ($module in $modules) {
                if (-not (Get-Module -ListAvailable -Name $module)) {
                    throw [EAFDependencyException]::new(
                        "Required module $module is not installed. Please install using: Install-Module $module -Force",
                        "KeyVault",
                        "Module",
                        "AzureModule",
                        $module,
                        "NotInstalled"
                    )
                }
            }
        }
        catch {
            if ($_.Exception -is [EAFDependencyException]) {
                Write-EAFException -Exception $_.Exception -ErrorCategory NotInstalled -Throw
            }
            else {
                Write-Error ("Module validation failed: " + ${_})
                return
            }
        }
        
        # Initialize variables
        $templatePath = Join-Path -Path $PSScriptRoot -ChildPath "..\Templates\keyVault.bicep"
        if (-not (Test-Path -Path $templatePath)) {
            throw [EAFDependencyException]::new(
                "Key Vault Bicep template not found at: $templatePath",
                "KeyVault",
                "BicepTemplate",
                "Template",
                $templatePath,
                "NotFound"
            )
        }
        
        Write-Verbose "Using Bicep template: $templatePath"
        $dateCreated = Get-Date -Format "yyyy-MM-dd"
    }
    
    process {
        Write-Progress -Activity "Creating Azure Key Vault" -Status "Initializing" -PercentComplete 0
        
        try {
            # Step 1: Validate parameters
            Write-Verbose "Validating parameters..."
            Write-Progress -Activity "Creating Azure Key Vault" -Status "Validating parameters" -PercentComplete 5
            
            # Validate key vault name using our validation helper
            $keyVaultNameValid = Test-EAFResourceName -ResourceName $KeyVaultName -ResourceType "KeyVault" -Environment $Environment -ThrowOnInvalid $false
            if (-not $keyVaultNameValid) {
                throw [EAFResourceValidationException]::new(
                    "Key Vault name '$KeyVaultName' does not follow EAF naming standards. Should be in format: kv-{name}-{env}",
                    "KeyVault",
                    $KeyVaultName,
                    "NamingConvention",
                    $KeyVaultName
                )
            }
            
            # Step 2: Verify resource group exists using our validation helper
            Write-Verbose "Checking resource group $ResourceGroupName exists..."
            Write-Progress -Activity "Creating Azure Key Vault" -Status "Verifying resource group" -PercentComplete 10
            
            $rgExists = Test-EAFResourceGroupExists -ResourceGroupName $ResourceGroupName -ThrowOnNotExist $true
            
            # Use resource group location if not specified
            if (-not $Location) {
                # Try to get from config first
                $configLocation = Get-EAFConfiguration -ConfigPath "Regions.Default.$Environment"
                
                if (-not [string]::IsNullOrEmpty($configLocation)) {
                    $Location = $configLocation
                    Write-Verbose "Using location from configuration: $Location"
                }
                else {
                    # Fall back to resource group location
                    $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
                    $Location = $resourceGroup.Location
                    Write-Verbose "Using resource group location: $Location"
                }
            }
            
            # Step 3: Verify Admin Object ID is provided when required
            Write-Verbose "Validating admin identity configuration..."
            Write-Progress -Activity "Creating Azure Key Vault" -Status "Validating configurations" -PercentComplete 15
            
            if ($EnableRbacAuthorization -and [string]::IsNullOrEmpty($AdminObjectId)) {
                Write-Warning "RBAC authorization is enabled but no AdminObjectId provided. No default admin will be assigned."
            }
            
            if (-not $EnableRbacAuthorization -and $DeployDefaultAccessPolicy -and [string]::IsNullOrEmpty($AdminObjectId)) {
                throw [EAFResourceValidationException]::new(
                    "When RBAC authorization is disabled and DeployDefaultAccessPolicy is true, AdminObjectId must be specified.",
                    "KeyVault",
                    $KeyVaultName,
                    "AdminObjectId",
                    "NotSpecified"
                )
            }
            
            # Step 4: Check if Key Vault already exists (idempotency)
            Write-Verbose "Checking if Key Vault $KeyVaultName already exists..."
            Write-Progress -Activity "Creating Azure Key Vault" -Status "Checking existing resources" -PercentComplete 20
            
            # Use retry logic for potential transient failures
            $existingKeyVault = Invoke-WithRetry -ScriptBlock {
                Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName -ErrorAction SilentlyContinue
            } -MaxRetryCount 3 -ActivityName "Checking Key Vault existence"
            
            if ($existingKeyVault) {
                Write-Verbose "Key Vault $KeyVaultName already exists"
                
                # Validate if purge protection can be modified
                if ($existingKeyVault.EnablePurgeProtection -ne $EnablePurgeProtection -and $existingKeyVault.EnablePurgeProtection) {
                    Write-Warning "Key Vault $KeyVaultName has purge protection enabled which cannot be disabled once set."
                }
                
                if (-not $Force -and -not $PSCmdlet.ShouldProcess($KeyVaultName, "Update existing Key Vault")) {
                    Write-Output "Key Vault $KeyVaultName already exists. Use -Force to update or modify existing configuration."
                    return $existingKeyVault
                }
                Write-Verbose "Proceeding with Key Vault update..."
            }
            
            # Step 5: Validate private endpoint parameters if required
            if ($DeployPrivateEndpoint) {
                Write-Verbose "Validating private endpoint parameters..."
                Write-Progress -Activity "Creating Azure Key Vault" -Status "Validating network configuration" -PercentComplete 30
                
                if ([string]::IsNullOrEmpty($PrivateEndpointVirtualNetworkName) -or [string]::IsNullOrEmpty($PrivateEndpointSubnetName)) {
                    throw "When DeployPrivateEndpoint is set to true, PrivateEndpointVirtualNetworkName and PrivateEndpointSubnetName must be specified."
                }
                
                if ([string]::IsNullOrEmpty($PrivateEndpointVnetResourceGroup)) {
                    $PrivateEndpointVnetResourceGroup = $ResourceGroupName
                    Write-Verbose "Using key vault resource group for private endpoint VNet: $PrivateEndpointVnetResourceGroup"
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
            
            # Step 5: Validate network configuration
            Write-Verbose "Validating network access configuration..."
            
            if (-not $PublicNetworkAccess -and $NetworkAclDefaultAction -eq 'Deny' -and 
                $AllowedVirtualNetworkSubnetIds.Count -eq 0 -and 
                $AllowedIpAddressRanges.Count -eq 0 -and 
                -not $DeployPrivateEndpoint) {
                Write-Warning "Key Vault will not be accessible - public network access disabled, default action set to Deny, and no allowed networks or private endpoint configured."
            }
            
            # Step 6: Validate secrets if provided
            if ($Secrets.Count -gt 0) {
                Write-Verbose "Validating secrets configuration..."
                foreach ($secret in $Secrets) {
                    if (-not $secret.ContainsKey('name') -or -not $secret.ContainsKey('value')) {
                        throw "All secrets must contain 'name' and 'value' properties."
                    }
                    
                    # Check if secrets contain sensitive information in plaintext (basic check)
                    if ($secret.ContainsKey('value') -and $secret.value -match '(?i)password|pwd|secret|key|token|credential') {
                        Write-Warning "Secret '${secret.name}' appears to contain sensitive information. Ensure this is intentional and secure."
                    }
                }
                Write-Verbose "Secrets validation complete."
            }
            
            # Step 7: Prepare deployment parameters
            Write-Verbose "Preparing deployment parameters..."
            Write-Progress -Activity "Creating Azure Key Vault" -Status "Preparing deployment" -PercentComplete 50
            
            $deploymentName = "Deploy-KeyVault-$KeyVaultName-$(Get-Date -Format 'yyyyMMddHHmmss')"
            
            $templateParams = @{
                keyVaultName = $KeyVaultName
                location = $Location
                skuName = $SkuName
                enableRbacAuthorization = $EnableRbacAuthorization
                enableSoftDelete = $EnableSoftDelete
                softDeleteRetentionInDays = $SoftDeleteRetentionInDays
                enablePurgeProtection = $EnablePurgeProtection
                enabledForTemplateDeployment = $EnabledForTemplateDeployment
                enabledForDiskEncryption = $EnabledForDiskEncryption
                enabledForDeployment = $EnabledForDeployment
                publicNetworkAccess = $PublicNetworkAccess
                networkAclDefaultAction = $NetworkAclDefaultAction
                allowedVirtualNetworkSubnetIds = $AllowedVirtualNetworkSubnetIds
                allowedIpAddressRanges = $AllowedIpAddressRanges
                deployPrivateEndpoint = $DeployPrivateEndpoint
                privateEndpointVirtualNetworkName = $PrivateEndpointVirtualNetworkName
                privateEndpointSubnetName = $PrivateEndpointSubnetName
                privateEndpointVnetResourceGroup = $PrivateEndpointVnetResourceGroup
                adminObjectId = $AdminObjectId
                deployDefaultAccessPolicy = $DeployDefaultAccessPolicy
                accessPolicies = $AccessPolicies
                secrets = $Secrets
                environment = $Environment
                department = $Department
                dateCreated = $dateCreated
            }
            
            # Step 8: Prepare deployment parameters
            Write-Verbose "Preparing deployment parameters..."
            Write-Progress -Activity "Creating Azure Key Vault" -Status "Preparing deployment" -PercentComplete 50
            
            # Use configuration helper to get default tags
            $defaultTags = Get-EAFDefaultTags -Environment $Environment -Department $Department -ResourceType "KeyVault"
            
            $deploymentName = "Deploy-KeyVault-$KeyVaultName-$(Get-Date -Format 'yyyyMMddHHmmss')"
            
            # Set retention days from configuration if not explicitly specified
            if ($SoftDeleteRetentionInDays -eq 90) { # If using the default value
                $configRetention = Get-EAFConfiguration -ConfigPath "Security.KeyVault.SoftDeleteRetention.$Environment"
                if ($configRetention -gt 0) {
                    $SoftDeleteRetentionInDays = $configRetention
                    Write-Verbose "Using soft delete retention from configuration: $SoftDeleteRetentionInDays days"
                }
            }
            
            $templateParams = @{
                keyVaultName = $KeyVaultName
                location = $Location
                skuName = $SkuName
                enableRbacAuthorization = $EnableRbacAuthorization
                enableSoftDelete = $EnableSoftDelete
                softDeleteRetentionInDays = $SoftDeleteRetentionInDays
                enablePurgeProtection = $EnablePurgeProtection
                enabledForTemplateDeployment = $EnabledForTemplateDeployment
                enabledForDiskEncryption = $EnabledForDiskEncryption
                enabledForDeployment = $EnabledForDeployment
                publicNetworkAccess = $PublicNetworkAccess
                networkAclDefaultAction = $NetworkAclDefaultAction
                allowedVirtualNetworkSubnetIds = $AllowedVirtualNetworkSubnetIds
                allowedIpAddressRanges = $AllowedIpAddressRanges
                deployPrivateEndpoint = $DeployPrivateEndpoint
                privateEndpointVirtualNetworkName = $PrivateEndpointVirtualNetworkName
                privateEndpointSubnetName = $PrivateEndpointSubnetName
                privateEndpointVnetResourceGroup = $PrivateEndpointVnetResourceGroup
                adminObjectId = $AdminObjectId
                deployDefaultAccessPolicy = $DeployDefaultAccessPolicy
                accessPolicies = $AccessPolicies
                secrets = $Secrets
                environment = $Environment
                department = $Department
                tags = $defaultTags
                dateCreated = $dateCreated
            }
            
            # Step 9: Deploy Key Vault using Bicep template with retry logic
            if ($PSCmdlet.ShouldProcess($KeyVaultName, "Deploy Azure Key Vault")) {
                Write-Verbose "Deploying Key Vault $KeyVaultName..."
                Write-Progress -Activity "Creating Azure Key Vault" -Status "Deploying resources" -PercentComplete 70
                
                try {
                    # Use retry logic for the deployment to handle transient failures
                    $deployment = Invoke-WithRetry -ScriptBlock {
                        New-AzResourceGroupDeployment `
                            -ResourceGroupName $ResourceGroupName `
                            -Name $deploymentName `
                            -TemplateFile $templatePath `
                            -TemplateParameterObject $templateParams `
                            -ErrorAction Stop `
                            -Verbose:$VerbosePreference
                    } -MaxRetryCount 3 -ActivityName "Deploying Key Vault"
                    
                    Write-Progress -Activity "Creating Azure Key Vault" -Status "Deployment complete" -PercentComplete 90
                    
                    if ($deployment.ProvisioningState -ne 'Succeeded') {
                        throw [EAFProvisioningFailedException]::new(
                            "Key Vault deployment failed. Deployment state: $($deployment.ProvisioningState)",
                            "KeyVault",
                            $KeyVaultName,
                            $deployment.ProvisioningState,
                            $deployment.DeploymentName,
                            ($deployment.Error | ConvertTo-Json -Compress)
                        )
                    }
                    
                    Write-Verbose "Key Vault $KeyVaultName deployed successfully"
                    # Step 10: Set up diagnostic settings if enabled in configuration
                    $enableDiagnostics = Get-EAFConfiguration -ConfigPath "Security.EnableDiagnostics.$Environment"
                    if ($enableDiagnostics -ne $false) { # If null or true
                        Write-Verbose "Setting up diagnostic settings for Key Vault $KeyVaultName..."
                        Write-Progress -Activity "Creating Azure Key Vault" -Status "Configuring diagnostics" -PercentComplete 95
                        
                        try {
                            # Get the Key Vault resource ID
                            $keyVault = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName
                            $keyVaultResourceId = $keyVault.ResourceId
                            
                            # Use our monitoring helper to enable diagnostic settings
                            Enable-EAFDiagnosticSettings `
                                -ResourceId $keyVaultResourceId `
                                -ResourceGroupName "rg-monitoring-$Environment" `
                                -Categories @('AuditEvent', 'AllLogs') `
                                -MetricCategories @('AllMetrics') `
                                -Environment $Environment `
                                -Department $Department
                                
                            Write-Verbose "Diagnostic settings configured successfully for Key Vault $KeyVaultName"
                        }
                        catch {
                            # Log the error but don't fail the deployment
                            Write-Warning "Failed to configure diagnostic settings for Key Vault $KeyVaultName: $($_.Exception.Message)"
                        }
                    }
                    
                    # Step 11: Get Key Vault details for return
                    # Use retry logic for getting details to handle transient failures
                    $keyVault = Invoke-WithRetry -ScriptBlock {
                        Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName -ErrorAction Stop
                    } -MaxRetryCount 3 -ActivityName "Getting Key Vault details"
                    
                    # Get any deployed secrets (just names, not values for security)
                    $deployedSecrets = @()
                    if ($Secrets.Count -gt 0) {
                        try {
                            $secretsList = Invoke-WithRetry -ScriptBlock {
                                Get-AzKeyVaultSecret -VaultName $KeyVaultName -ErrorAction SilentlyContinue
                            } -MaxRetryCount 3 -ActivityName "Getting Key Vault secrets"
                            
                            $deployedSecrets = $secretsList | Select-Object -ExpandProperty Name
                        }
                        catch {
                            Write-Warning "Unable to retrieve secrets list: $($_.Exception.Message)"
                        }
                    }
                    
                    # Determine how the vault can be accessed
                    $accessMethods = @()
                    if ($PublicNetworkAccess) { $accessMethods += "Public Network" }
                    if ($NetworkAclDefaultAction -eq 'Allow') { $accessMethods += "All Networks" }
                    if ($AllowedIpAddressRanges.Count -gt 0) { $accessMethods += "Selected IP Ranges" }
                    if ($AllowedVirtualNetworkSubnetIds.Count -gt 0) { $accessMethods += "Virtual Network Service Endpoints" }
                    if ($DeployPrivateEndpoint) { $accessMethods += "Private Endpoint" }
                    
                    # Return custom object with deployment details
                    $result = [PSCustomObject]@{
                        Name = $keyVault.VaultName
                        ResourceGroupName = $ResourceGroupName
                        Location = $keyVault.Location
                        VaultUri = $keyVault.VaultUri
                        SkuName = $keyVault.Sku.Name
                        TenantId = $keyVault.TenantId
                        ResourceId = $keyVault.ResourceId
                        EnableRbacAuthorization = $keyVault.EnableRbacAuthorization
                        EnableSoftDelete = $keyVault.EnableSoftDelete
                        SoftDeleteRetentionInDays = $keyVault.SoftDeleteRetentionInDays
                        EnablePurgeProtection = $keyVault.EnablePurgeProtection
                        AccessMethods = $accessMethods
                        PrivateEndpoint = $DeployPrivateEndpoint
                        DeployedSecrets = $deployedSecrets
                        Environment = $Environment
                        Department = $Department
                        DeploymentTimestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                    }
                    
                    Write-Verbose "Key Vault deployment completed successfully."
                    Write-Progress -Activity "Creating Azure Key Vault" -Completed
                    
                    return $result
                }
                catch {
                    # Handle different types of exceptions with appropriate error messages
                    if ($_.Exception -is [EAFProvisioningFailedException]) {
                        Write-EAFException -Exception $_.Exception -ErrorCategory ResourceUnavailable -Throw
                    }
                    elseif ($_.Exception -is [EAFResourceValidationException] -or 
                            $_.Exception -is [EAFNetworkConfigurationException] -or 
                            $_.Exception -is [EAFDependencyException]) {
                        Write-EAFException -Exception $_.Exception -Throw
                    }
                    else {
                        throw [EAFProvisioningFailedException]::new(
                            "Failed to deploy Key Vault $KeyVaultName. Error: $($_.Exception.Message)",
                            "KeyVault",
                            $KeyVaultName,
                            "Failed",
                            "Deployment",
                            $_.Exception.Message
                        )
                    }
                }
            }
            else {
                Write-Verbose "Deployment skipped due to -WhatIf parameter."
                Write-Progress -Activity "Creating Azure Key Vault" -Completed
            }
        }
        catch {
            # Main error handling - ensure we write proper errors
            if ($_.Exception -is [EAFException]) {
                Write-EAFException -Exception $_.Exception -Throw
            }
            else {
                Write-Error $_
            }
            Write-Progress -Activity "Creating Azure Key Vault" -Completed
        }
    }
    
    end {
        # Clean up any resources
        Write-Verbose "Cleaning up..."
        
        # Unload helper modules to avoid namespace conflicts
        $helperModules = @(
            "exceptions",
            "retry-logic",
            "validation-helpers",
            "configuration-helpers",
            "monitoring-helpers"
        )
        
        foreach ($helperModule in $helperModules) {
            if (Get-Module -Name $helperModule) {
                Remove-Module -Name $helperModule -ErrorAction SilentlyContinue
            }
        }
        
        Write-Verbose "New-EAFKeyVault completed."
    }
}
