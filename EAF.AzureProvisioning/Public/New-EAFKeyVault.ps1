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
        This is used for `keyVaultAdministratorPrincipalId` in Bicep.
    
    .PARAMETER KeyVaultAdministratorPrincipalType
        Specifies the principal type for the Key Vault Administrator role. Valid values: User, Group, ServicePrincipal. Defaults to ServicePrincipal.

    .PARAMETER KeyVaultSecretsUserPrincipalId
        Specifies the Principal ID for the Key Vault Secrets User role assignment. If empty, the role is not assigned.
        
    .PARAMETER KeyVaultSecretsUserPrincipalType
        Specifies the principal type for the Key Vault Secrets User role. Valid values: User, Group, ServicePrincipal. Defaults to ServicePrincipal.

    .PARAMETER KeyVaultCertificatesOfficerPrincipalId
        Specifies the Principal ID for the Key Vault Certificates Officer role assignment. If empty, the role is not assigned.

    .PARAMETER KeyVaultCertificatesOfficerPrincipalType
        Specifies the principal type for the Key Vault Certificates Officer role. Valid values: User, Group, ServicePrincipal. Defaults to ServicePrincipal.
    
    .PARAMETER DeployDefaultAccessPolicy
        Indicates whether to deploy a default access policy. Defaults to false.
        Only applicable when RBAC authorization is disabled. The AdminObjectId is used for this policy.
    
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
        
        Creates a new Key Vault named "kv-app1-dev" with default settings and RBAC authorization, assigning the AdminObjectId as Key Vault Administrator.
    
    .EXAMPLE
        New-EAFKeyVault -ResourceGroupName "rg-security-test" -KeyVaultName "kv-app1-test" -SkuName "premium" -EnableRbacAuthorization $false -DeployDefaultAccessPolicy $true -AdminObjectId "00000000-0000-0000-0000-000000000000" -Department "Finance" -Environment "test"
        
        Creates a new premium Key Vault in the test environment with a default access policy for AdminObjectId.
    
    .EXAMPLE
        New-EAFKeyVault -ResourceGroupName "rg-app-prod" -KeyVaultName "kv-app-prod" -Department "AppTeam" -AdminObjectId "service-principal-object-id" -KeyVaultAdministratorPrincipalType "ServicePrincipal" -KeyVaultSecretsUserPrincipalId "user-object-id" -KeyVaultSecretsUserPrincipalType "User"
        
        Creates a Key Vault with RBAC, assigning a Service Principal as Admin and a User as Secrets User.

    .INPUTS
        None. You cannot pipe objects to New-EAFKeyVault.
    
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
        
        [Parameter(Mandatory = $false)] # Effectively keyVaultAdministratorPrincipalId
        [string]$AdminObjectId = '', 

        [Parameter(Mandatory = $false)]
        [ValidateSet('User', 'Group', 'ServicePrincipal')]
        [string]$KeyVaultAdministratorPrincipalType = 'ServicePrincipal',

        [Parameter(Mandatory = $false)]
        [string]$KeyVaultSecretsUserPrincipalId = '',

        [Parameter(Mandatory = $false)]
        [ValidateSet('User', 'Group', 'ServicePrincipal')]
        [string]$KeyVaultSecretsUserPrincipalType = 'ServicePrincipal',

        [Parameter(Mandatory = $false)]
        [string]$KeyVaultCertificatesOfficerPrincipalId = '',

        [Parameter(Mandatory = $false)]
        [ValidateSet('User', 'Group', 'ServicePrincipal')]
        [string]$KeyVaultCertificatesOfficerPrincipalType = 'ServicePrincipal',
        
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
            
            $keyVaultNameValid = Test-EAFResourceName -ResourceName $KeyVaultName -ResourceType "KeyVault" -Environment $Environment -ThrowOnInvalid $false
            if (-not $keyVaultNameValid) {
                throw [EAFResourceValidationException]::new(
                    "Key Vault name '$KeyVaultName' does not follow EAF naming standards. Should be in format: kv-{name}-{env}",
                    "KeyVault", $KeyVaultName, "NamingConvention", $KeyVaultName
                )
            }
            
            # Step 2: Verify resource group
            Write-Verbose "Checking resource group $ResourceGroupName exists..."
            Write-Progress -Activity "Creating Azure Key Vault" -Status "Verifying resource group" -PercentComplete 10
            Test-EAFResourceGroupExists -ResourceGroupName $ResourceGroupName -ThrowOnNotExist $true
            
            if (-not $Location) {
                $configLocation = Get-EAFConfiguration -ConfigPath "Regions.Default.$Environment"
                $Location = if (-not [string]::IsNullOrEmpty($configLocation)) { $configLocation } else { (Get-AzResourceGroup -Name $ResourceGroupName).Location }
                Write-Verbose "Using location: $Location"
            }
            
            # Step 3: Validate AdminObjectId based on auth model
            Write-Progress -Activity "Creating Azure Key Vault" -Status "Validating configurations" -PercentComplete 15
            if ($EnableRbacAuthorization -and [string]::IsNullOrEmpty($AdminObjectId) -and [string]::IsNullOrEmpty($KeyVaultSecretsUserPrincipalId) -and [string]::IsNullOrEmpty($KeyVaultCertificatesOfficerPrincipalId) ) {
                Write-Warning "RBAC authorization is enabled but no Principal IDs provided for core roles (Administrator, Secrets User, Certificates Officer). Key Vault might be unmanageable initially through these roles."
            }
            if (-not $EnableRbacAuthorization -and $DeployDefaultAccessPolicy -and [string]::IsNullOrEmpty($AdminObjectId)) {
                throw [EAFParameterValidationException]::new(
                    "When RBAC is disabled and DeployDefaultAccessPolicy is true, AdminObjectId must be specified for the default policy.",
                    "KeyVault", "AdminObjectId", "MissingParameter"
                )
            }

            # Step 4: Idempotency check
            Write-Verbose "Checking if Key Vault $KeyVaultName already exists..."
            Write-Progress -Activity "Creating Azure Key Vault" -Status "Checking existing resources" -PercentComplete 20
            $existingKeyVault = Invoke-WithRetry -ScriptBlock { Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName -ErrorAction SilentlyContinue } -MaxRetryCount 3 -ActivityName "Checking Key Vault existence"
            
            if ($existingKeyVault) {
                Write-Verbose "Key Vault $KeyVaultName already exists."
                if ($existingKeyVault.EnablePurgeProtection -ne $EnablePurgeProtection -and $existingKeyVault.EnablePurgeProtection) {
                    Write-Warning "Key Vault $KeyVaultName has purge protection enabled which cannot be disabled."
                }
                if (-not $Force -and -not $PSCmdlet.ShouldProcess($KeyVaultName, "Update existing Key Vault")) {
                    Write-Output "Key Vault $KeyVaultName already exists. Use -Force to update."
                    return $existingKeyVault # Consider standardizing output object
                }
                Write-Verbose "Proceeding with Key Vault update..."
            }
            
            # Step 5: Private Endpoint Validation (Simplified as per previous cmdlets)
            if ($DeployPrivateEndpoint) {
                Write-Verbose "Validating private endpoint parameters..."
                Write-Progress -Activity "Creating Azure Key Vault" -Status "Validating network configuration" -PercentComplete 30
                if ([string]::IsNullOrEmpty($PrivateEndpointVirtualNetworkName) -or [string]::IsNullOrEmpty($PrivateEndpointSubnetName)) {
                    throw [EAFParameterValidationException]::new("PrivateEndpointVirtualNetworkName and PrivateEndpointSubnetName must be specified for private endpoint.", "KeyVault", "PrivateEndpoint", "MissingParameter")
                }
                $effectivePeRg = if ([string]::IsNullOrEmpty($PrivateEndpointVnetResourceGroup)) { $ResourceGroupName } else { $PrivateEndpointVnetResourceGroup }
                Test-EAFNetworkConfiguration -VirtualNetworkName $PrivateEndpointVirtualNetworkName -SubnetName $PrivateEndpointSubnetName -ResourceGroupName $effectivePeRg -ThrowOnInvalid $true
            }
            
            # Step 7: Prepare deployment parameters
            Write-Verbose "Preparing deployment parameters..."
            Write-Progress -Activity "Creating Azure Key Vault" -Status "Preparing deployment" -PercentComplete 50
            $defaultTags = Get-EAFDefaultTags -Environment $Environment -Department $Department -ResourceType "KeyVault"
            $deploymentName = "Deploy-KeyVault-$KeyVaultName-$(Get-Date -Format 'yyyyMMddHHmmss')"
            
            # Map PowerShell params to Bicep params, especially AdminObjectId to keyVaultAdministratorPrincipalId
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
                privateEndpointVnetResourceGroup = if ($DeployPrivateEndpoint) { if ([string]::IsNullOrEmpty($PrivateEndpointVnetResourceGroup)) { $ResourceGroupName } else { $PrivateEndpointVnetResourceGroup } } else { '' }
                
                administratorObjectId = $AdminObjectId # For legacy access policy if RBAC is false
                accessPolicies = $AccessPolicies # For legacy access policy if RBAC is false

                keyVaultAdministratorPrincipalId = $AdminObjectId # Bicep uses this for the Admin role
                keyVaultAdministratorPrincipalType = $KeyVaultAdministratorPrincipalType
                keyVaultSecretsUserPrincipalId = $KeyVaultSecretsUserPrincipalId
                keyVaultSecretsUserPrincipalType = $KeyVaultSecretsUserPrincipalType
                keyVaultCertificatesOfficerPrincipalId = $KeyVaultCertificatesOfficerPrincipalId
                keyVaultCertificatesOfficerPrincipalType = $KeyVaultCertificatesOfficerPrincipalType
                
                initialSecrets = $Secrets # Renamed from 'secrets' to 'initialSecrets' for clarity with Bicep
                environment = $Environment
                department = $Department
                additionalTags = $defaultTags # Bicep expects 'additionalTags'
                dateCreated = $dateCreated # Added to align with Bicep
            }
            
            # Step 9: Deploy Key Vault using Bicep template
            if ($PSCmdlet.ShouldProcess($KeyVaultName, "Deploy Azure Key Vault")) {
                Write-Verbose "Deploying Key Vault $KeyVaultName..."
                Write-Progress -Activity "Creating Azure Key Vault" -Status "Deploying resources" -PercentComplete 70
                
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
                    $errorDetails = $deployment.Properties.Error.Details | ForEach-Object Message | Out-String
                    throw [EAFProvisioningFailedException]::new(
                        "Key Vault deployment failed. State: $($deployment.ProvisioningState). Details: $errorDetails",
                        "KeyVault", $KeyVaultName, $deployment.ProvisioningState, $deployment.CorrelationId
                    )
                }
                
                Write-Verbose "KeyVault $KeyVaultName deployed successfully."
                $keyVaultDetails = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName
                
                $result = [PSCustomObject]@{
                    Name = $keyVaultDetails.VaultName
                    ResourceGroupName = $ResourceGroupName
                    Location = $keyVaultDetails.Location
                    VaultUri = $keyVaultDetails.VaultUri
                    SkuName = $keyVaultDetails.Sku.Name
                    EnableRbacAuthorization = $keyVaultDetails.EnableRbacAuthorization
                    KeyVaultAdministratorPrincipalType = $KeyVaultAdministratorPrincipalType
                    KeyVaultSecretsUserPrincipalType = $KeyVaultSecretsUserPrincipalType
                    KeyVaultCertificatesOfficerPrincipalType = $KeyVaultCertificatesOfficerPrincipalType
                    ProvisioningState = $deployment.ProvisioningState # Use deployment state
                    DeploymentId = $deployment.DeploymentId
                    DeploymentTimestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                    Tags = $keyVaultDetails.Tags
                    KeyVaultReference = $keyVaultDetails
                }
                Write-Progress -Activity "Creating Azure Key Vault" -Status "Completed" -PercentComplete 100
                return $result
            } else {
                Write-Warning "Deployment of Key Vault $KeyVaultName skipped due to ShouldProcess preference."
                return $null
            }
        }
        catch {
            Write-Progress -Activity "Creating Azure Key Vault" -Status "Error" -PercentComplete 100 -Completed
            if ($_.Exception -is [EAFException]) {
                Write-EAFException -Exception $_.Exception -Throw
            } else {
                $wrappedException = [EAFProvisioningFailedException]::new(
                    "Failed to create Key Vault '$KeyVaultName': $($_.Exception.Message)",
                    "KeyVault", $KeyVaultName, "UnknownError", $null, $_.Exception 
                )
                Write-EAFException -Exception $wrappedException -Throw
            }
        }
    }
    
    end {
        Write-Verbose "New-EAFKeyVault operation finished."
        if ($script:EAFHelperModulesLoaded) { # Check if modules were loaded in 'begin'
            $helperModuleNames = @("exceptions", "retry-logic", "validation-helpers", "configuration-helpers", "monitoring-helpers")
            foreach ($helperModuleName in $helperModuleNames) {
                if (Get-Module -Name $helperModuleName -ErrorAction SilentlyContinue) {
                    Remove-Module -Name $helperModuleName -ErrorAction SilentlyContinue
                    Write-Verbose "Unloaded helper module: $helperModuleName"
                }
            }
        }
    }
}
