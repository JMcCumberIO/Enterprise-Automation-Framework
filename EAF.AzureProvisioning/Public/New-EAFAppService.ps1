function New-EAFAppService {
    <#
    .SYNOPSIS
        Creates a new Azure App Service using EAF standards.
    
    .DESCRIPTION
        The New-EAFAppService cmdlet creates a new Azure App Service according to Enterprise Azure Framework (EAF) 
        standards. It provisions an App Service with proper naming, tagging, security settings, and diagnostic configurations.
        
        This cmdlet uses the appService.bicep template to ensure consistent App Service deployments across the organization.
    
    .PARAMETER ResourceGroupName
        Specifies the name of the resource group where the App Service will be deployed.
    
    .PARAMETER AppServiceName
        Specifies the name of the App Service. Must follow naming convention app-{name}-{env}.
    
    .PARAMETER Location
        Specifies the Azure region where the App Service will be deployed. Defaults to the resource group's location.
    
    .PARAMETER AppServicePlanName
        Specifies the name of the App Service Plan. If not provided, it will use {AppServiceName}-plan.
    
    .PARAMETER SkuName
        Specifies the SKU name for the App Service Plan. Defaults to S1.
        Valid values: F1, D1, B1, B2, B3, S1, S2, S3, P1v2, P2v2, P3v2
    
    .PARAMETER SkuCapacity
        Specifies the SKU capacity for the App Service Plan. Defaults to 1.
    
    .PARAMETER RuntimeStack
        Specifies the runtime stack of the web app. 
        Valid values: dotnet, node, python, java, php
        Defaults to dotnet.
    
    .PARAMETER RuntimeVersion
        Specifies the runtime version. Defaults to 6.0.
    
    .PARAMETER HttpsOnly
        Indicates whether the App Service should be configured for HTTPS-only traffic. Defaults to true.
    
    .PARAMETER AlwaysOn
        Indicates whether Always On should be enabled for the App Service. Defaults to true.
    
    .PARAMETER EnableDeploymentSlots
        Indicates whether deployment slots should be enabled. Defaults to false.
    
    .PARAMETER DeploymentSlotsCount
        Specifies the number of deployment slots to create. Range: 0-5. Defaults to 1.
    
    .PARAMETER DeploymentSlotNames
        Specifies an array of deployment slot names to create. Defaults to ['staging'].
    
    .PARAMETER EnableAutoSwap
        Indicates whether auto-swap should be enabled for the staging slot. Defaults to false.
    
    .PARAMETER EnableAutoScale
        Indicates whether auto-scaling should be enabled. Defaults to false.
    
    .PARAMETER AutoScaleMinInstanceCount
        Specifies the minimum instance count for auto-scaling. Range: 1-20. Defaults to 1.
    
    .PARAMETER AutoScaleMaxInstanceCount
        Specifies the maximum instance count for auto-scaling. Range: 1-20. Defaults to 5.
    
    .PARAMETER AutoScaleDefaultInstanceCount
        Specifies the default instance count for auto-scaling. Range: 1-20. Defaults to 2.
    
    .PARAMETER CpuPercentageScaleOut
        Specifies the CPU percentage threshold for scaling out. Range: 50-90. Defaults to 70.
    
    .PARAMETER CpuPercentageScaleIn
        Specifies the CPU percentage threshold for scaling in. Range: 20-40. Defaults to 30.
    
    .PARAMETER EnableContainerDeployment
        Indicates whether container deployment should be enabled. Defaults to false.
    
    .PARAMETER ContainerRegistryServer
        Specifies the container registry server (e.g., myregistry.azurecr.io).
    
    .PARAMETER ContainerRegistryUsername
        Specifies the username for the container registry.
    
    .PARAMETER ContainerRegistryPassword
        Specifies the password for the container registry as a SecureString.
    
    .PARAMETER ContainerImageAndTag
        Specifies the container image and tag (e.g., myimage:latest).
    
    .PARAMETER EnableCustomDomain
        Indicates whether a custom domain should be enabled. Defaults to false.
    
    .PARAMETER CustomDomainName
        Specifies the custom domain name to use (e.g., api.example.com).
    
    .PARAMETER EnableSslBinding
        Indicates whether SSL binding should be enabled for the custom domain. Defaults to false.
    
    .PARAMETER SslCertificateThumbprint
        Specifies the thumbprint of the SSL certificate to use.
    
    .PARAMETER EnableBackup
        Indicates whether backups should be enabled. Defaults to false.
    
    .PARAMETER BackupStorageAccountName
        Specifies the name of the storage account to use for backups.
    
    .PARAMETER BackupStorageContainerName
        Specifies the name of the storage container to use for backups. Defaults to 'appservicebackups'.
    
    .PARAMETER BackupSchedule
        Specifies the backup schedule in cron expression format. Defaults to '0 0 * * *' (daily at midnight).
    
    .PARAMETER BackupRetentionPeriodDays
        Specifies the number of days to retain backups. Range: 1-365. Defaults to 30.

    .PARAMETER BackupSasTokenExpiryPeriod
        Specifies the SAS token expiry period for App Service backups, in ISO 8601 duration format (e.g., 'P1Y' for 1 year, 'P30D' for 30 days). Defaults to 'P1Y'.
    
    .PARAMETER Environment
        Specifies the deployment environment (dev, test, prod). Defaults to dev.
    
    .PARAMETER Department
        Specifies the department or team responsible for the App Service.
    
    .PARAMETER Force
        Forces the command to run without asking for user confirmation.
    
    .EXAMPLE
        New-EAFAppService -ResourceGroupName "rg-webapps-dev" -AppServiceName "app-api-dev" -Department "IT"
        
        Creates a new App Service named "app-api-dev" in the resource group "rg-webapps-dev" with default settings.
    
    .EXAMPLE
        New-EAFAppService -ResourceGroupName "rg-webapps-test" -AppServiceName "app-api-test" -SkuName "P1v2" -RuntimeStack "node" -RuntimeVersion "16" -Department "Marketing" -Environment "test" -EnableDeploymentSlots $true -DeploymentSlotNames @('staging', 'qa')
        
        Creates a new Node.js App Service with two deployment slots named "staging" and "qa".
    
    .EXAMPLE
        New-EAFAppService -ResourceGroupName "rg-webapps-prod" -AppServiceName "app-api-prod" -Department "IT" -EnableBackup $true -BackupSasTokenExpiryPeriod "P90D"
        
        Creates a new App Service in production with backups enabled and SAS tokens for backup storage expiring in 90 days.
    
    .INPUTS
        None. You cannot pipe objects to New-EAFAppService.
    
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
        [ValidatePattern('^app-[a-zA-Z0-9]+-(?:dev|test|prod)$')]
        [string]$AppServiceName,
        
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Location,
        
        [Parameter(Mandatory = $false)]
        [string]$AppServicePlanName = "$AppServiceName-plan",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('F1', 'D1', 'B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1v2', 'P2v2', 'P3v2')]
        [string]$SkuName = 'S1',
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10)]
        [int]$SkuCapacity = 1,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('dotnet', 'node', 'python', 'java', 'php')]
        [string]$RuntimeStack = 'dotnet',
        
        [Parameter(Mandatory = $false)]
        [string]$RuntimeVersion = '6.0',
        
        [Parameter(Mandatory = $false)]
        [bool]$HttpsOnly = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$AlwaysOn = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableDeploymentSlots = $false,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 5)]
        [int]$DeploymentSlotsCount = 1,
        
        [Parameter(Mandatory = $false)]
        [string[]]$DeploymentSlotNames = @('staging'),
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableAutoSwap = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableAutoScale = $false,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 20)]
        [int]$AutoScaleMinInstanceCount = 1,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 20)]
        [int]$AutoScaleMaxInstanceCount = 5,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 20)]
        [int]$AutoScaleDefaultInstanceCount = 2,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(50, 90)]
        [int]$CpuPercentageScaleOut = 70,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(20, 40)]
        [int]$CpuPercentageScaleIn = 30,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableContainerDeployment = $false,
        
        [Parameter(Mandatory = $false)]
        [string]$ContainerRegistryServer = '',
        
        [Parameter(Mandatory = $false)]
        [string]$ContainerRegistryUsername = '',
        
        [Parameter(Mandatory = $false)]
        [SecureString]$ContainerRegistryPassword,
        
        [Parameter(Mandatory = $false)]
        [string]$ContainerImageAndTag = '',
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableCustomDomain = $false,
        
        [Parameter(Mandatory = $false)]
        [string]$CustomDomainName = '',
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableSslBinding = $false,
        
        [Parameter(Mandatory = $false)]
        [string]$SslCertificateThumbprint = '',
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableBackup = $false,
        
        [Parameter(Mandatory = $false)]
        [string]$BackupStorageAccountName = '',
        
        [Parameter(Mandatory = $false)]
        [string]$BackupStorageContainerName = 'appservicebackups',
        
        [Parameter(Mandatory = $false)]
        [string]$BackupSchedule = '0 0 * * *',
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 365)]
        [int]$BackupRetentionPeriodDays = 30,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$BackupSasTokenExpiryPeriod = 'P1Y', # Default to 1 year
        
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
            $modules = @('Az.Websites', 'Az.Resources', 'Az.Storage', 'Az.Monitor')
            foreach ($module in $modules) {
                if (-not (Get-Module -ListAvailable -Name $module)) {
                    throw [EAFDependencyException]::new(
                        "Required module $module is not installed. Please install using: Install-Module $module -Force",
                        "AppService",
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
        $templatePath = Join-Path -Path $PSScriptRoot -ChildPath "..\Templates\appService.bicep"
        if (-not (Test-Path -Path $templatePath)) {
            throw [EAFDependencyException]::new(
                "App Service Bicep template not found at: $templatePath",
                "AppService",
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
        Write-Progress -Activity "Creating Azure App Service" -Status "Initializing" -PercentComplete 0
        
        try {
            # Step 1: Validate parameters
            Write-Verbose "Validating parameters..."
            Write-Progress -Activity "Creating Azure App Service" -Status "Validating parameters" -PercentComplete 5
            
            # Validate app service name using our validation helper
            $appServiceNameValid = Test-EAFResourceName -ResourceName $AppServiceName -ResourceType "AppService" -Environment $Environment -ThrowOnInvalid $false
            if (-not $appServiceNameValid) {
                throw [EAFResourceValidationException]::new(
                    "App Service name '$AppServiceName' does not follow EAF naming standards. Should be in format: app-{name}-{env}",
                    "AppService",
                    $AppServiceName,
                    "NamingConvention",
                    $AppServiceName
                )
            }
            
            # Step 2: Verify resource group exists using our validation helper
            Write-Verbose "Checking resource group $ResourceGroupName exists..."
            Write-Progress -Activity "Creating Azure App Service" -Status "Verifying resource group" -PercentComplete 10
            
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
            
            # Set default SKU from configuration if not explicitly specified
            if ($SkuName -eq 'S1') {  # If using the default value
                $configSku = Get-EAFDefaultSKU -ResourceType "AppService" -Environment $Environment -ThrowOnInvalid $false -ErrorAction SilentlyContinue
                if (-not [string]::IsNullOrEmpty($configSku)) {
                    $SkuName = $configSku
                    Write-Verbose "Using SKU from configuration: $SkuName"
                }
            }
            
            # Step 3: Check if App Service already exists (idempotency)
            Write-Verbose "Checking if App Service $AppServiceName already exists..."
            Write-Progress -Activity "Creating Azure App Service" -Status "Checking existing resources" -PercentComplete 15
            
            # Use retry logic for potential transient failures
            $existingAppService = Invoke-WithRetry -ScriptBlock {
                Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $AppServiceName -ErrorAction SilentlyContinue
            } -MaxRetryCount 3 -ActivityName "Checking App Service existence"
            if ($existingAppService) {
                Write-Verbose "App Service $AppServiceName already exists"
                if (-not $Force -and -not $PSCmdlet.ShouldProcess($AppServiceName, "Update existing App Service")) {
                    Write-Output "App Service $AppServiceName already exists. Use -Force to update or modify existing configuration."
                    return $existingAppService
                }
                Write-Verbose "Proceeding with App Service update..."
            }
            
            # Step 3: Validate parameters and prerequisites
            Write-Verbose "Validating parameters and prerequisites..."
            Write-Progress -Activity "Creating Azure App Service" -Status "Validating parameters" -PercentComplete 20
            
            # Validate container deployment parameters
            if ($EnableContainerDeployment) {
                Write-Verbose "Validating container deployment configuration..."
                
                if ([string]::IsNullOrEmpty($ContainerRegistryServer)) {
                    throw "ContainerRegistryServer is required when EnableContainerDeployment is true."
                }
                
                if ([string]::IsNullOrEmpty($ContainerImageAndTag)) {
                    throw "ContainerImageAndTag is required when EnableContainerDeployment is true."
                }
                
                if ((-not [string]::IsNullOrEmpty($ContainerRegistryUsername)) -and ($null -eq $ContainerRegistryPassword)) {
                    throw "ContainerRegistryPassword is required when ContainerRegistryUsername is provided."
                }
                
                Write-Verbose "Container deployment configuration validated successfully."
            }
            
            # Validate deployment slots parameters
            if ($EnableDeploymentSlots) {
                Write-Verbose "Validating deployment slots configuration..."
                
                if ($DeploymentSlotsCount -lt 1) {
                    Write-Warning "DeploymentSlotsCount must be at least 1 when EnableDeploymentSlots is true. Setting to 1."
                    $DeploymentSlotsCount = 1
                }
                
                if ($DeploymentSlotNames.Count -eq 0) {
                    Write-Warning "DeploymentSlotNames cannot be empty when EnableDeploymentSlots is true. Using default ['staging']."
                    $DeploymentSlotNames = @('staging')
                }
                
                if ($EnableAutoSwap -and -not $DeploymentSlotNames.Contains('staging')) {
                    Write-Warning "Auto-swap requires a 'staging' slot. Auto-swap will not be configured."
                    $EnableAutoSwap = $false
                }
            }
            
            # Validate custom domain and SSL parameters
            if ($EnableCustomDomain) {
                Write-Verbose "Validating custom domain configuration..."
                
                if ([string]::IsNullOrEmpty($CustomDomainName)) {
                    throw "CustomDomainName is required when EnableCustomDomain is true."
                }
                
                if ($EnableSslBinding -and [string]::IsNullOrEmpty($SslCertificateThumbprint)) {
                    throw "SslCertificateThumbprint is required when EnableSslBinding is true."
                }
            }
            
            # Validate backup parameters
            if ($EnableBackup) {
                Write-Verbose "Validating backup configuration..."
                
                if ([string]::IsNullOrEmpty($BackupStorageAccountName)) {
                    throw "BackupStorageAccountName is required when EnableBackup is true."
                }
                
                # Verify the storage account exists
                try {
                    $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $BackupStorageAccountName -ErrorAction SilentlyContinue
                    if (-not $storageAccount) {
                        throw "Storage account '$BackupStorageAccountName' not found in resource group '$ResourceGroupName'."
                    }
                }
                catch {
                    Write-Warning "Could not verify storage account: ${_}"
                }
                
                if ($BackupRetentionPeriodDays -lt 1 -or $BackupRetentionPeriodDays -gt 365) {
                    throw "BackupRetentionPeriodDays must be between 1 and 365."
                }
            }
            
            # Step 4: Prepare deployment parameters
            Write-Verbose "Preparing deployment parameters..."
            Write-Progress -Activity "Creating Azure App Service" -Status "Preparing deployment" -PercentComplete 40
            
            $deploymentName = "Deploy-AppService-$AppServiceName-$(Get-Date -Format 'yyyyMMddHHmmss')"
            
            # Convert SecureString to plain text for container registry password if needed
            $containerRegistryPasswordText = ''
            if ($EnableContainerDeployment -and $null -ne $ContainerRegistryPassword) {
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ContainerRegistryPassword)
                $containerRegistryPasswordText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            }
            
            $templateParams = @{
                appServiceName = $AppServiceName
                appServicePlanName = $AppServicePlanName
                skuName = $SkuName
                skuCapacity = $SkuCapacity
                location = $Location
                runtimeStack = $RuntimeStack
                runtimeVersion = $RuntimeVersion
                httpsOnly = $HttpsOnly
                alwaysOn = $AlwaysOn
                environment = $Environment
                department = $Department
                dateCreated = $dateCreated
                
                # Deployment slots parameters
                enableDeploymentSlots = $EnableDeploymentSlots
                deploymentSlotsCount = $DeploymentSlotsCount
                deploymentSlotNames = $DeploymentSlotNames
                enableAutoSwap = $EnableAutoSwap
                
                # Auto-scale parameters
                enableAutoScale = $EnableAutoScale
                autoScaleMinInstanceCount = $AutoScaleMinInstanceCount
                autoScaleMaxInstanceCount = $AutoScaleMaxInstanceCount
                autoScaleDefaultInstanceCount = $AutoScaleDefaultInstanceCount
                cpuPercentageScaleOut = $CpuPercentageScaleOut
                cpuPercentageScaleIn = $CpuPercentageScaleIn
                
                # Container deployment parameters
                enableContainerDeployment = $EnableContainerDeployment
                containerRegistryServer = $ContainerRegistryServer
                containerRegistryUsername = $ContainerRegistryUsername
                containerRegistryPassword = $containerRegistryPasswordText
                containerImageAndTag = $ContainerImageAndTag
                
                # Custom domain and SSL parameters
                enableCustomDomain = $EnableCustomDomain
                customDomainName = $CustomDomainName
                enableSslBinding = $EnableSslBinding
                sslCertificateThumbprint = $SslCertificateThumbprint
                
                # Backup parameters
                enableBackup = $EnableBackup
                backupStorageAccountName = $BackupStorageAccountName
                backupStorageContainerName = $BackupStorageContainerName
                backupSchedule = $BackupSchedule
                backupRetentionPeriodDays = $BackupRetentionPeriodDays
                backupSasTokenExpiryPeriod = $BackupSasTokenExpiryPeriod # New parameter added here
            }
            
            # Step 5: Deploy App Service using Bicep template
            if ($PSCmdlet.ShouldProcess($AppServiceName, "Deploy Azure App Service")) {
                Write-Verbose "Deploying App Service $AppServiceName..."
                Write-Progress -Activity "Creating Azure App Service" -Status "Deploying resources" -PercentComplete 60
                
                $deployment = New-AzResourceGroupDeployment `
                    -ResourceGroupName $ResourceGroupName `
                    -Name $deploymentName `
                    -TemplateFile $templatePath `
                    -TemplateParameterObject $templateParams `
                    -Verbose:$VerbosePreference
                
                Write-Progress -Activity "Creating Azure App Service" -Status "Deployment complete" -PercentComplete 100
                
                if ($deployment.ProvisioningState -eq 'Succeeded') {
                    Write-Verbose "App Service $AppServiceName deployed successfully"
                    
                    # Get the App Service details
                    $appService = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $AppServiceName
                    
                    # Get App Insights instrumentation key
                    $appInsightsKey = $deployment.Outputs.appInsightsInstrumentationKey.Value
                    $appServiceUrl = $deployment.Outputs.appServiceUrl.Value
                    
                    Write-Verbose "App Service URL: $appServiceUrl"
                    Write-Verbose "App Insights instrumentation key retrieved"
                    
                    # Return custom object with deployment details
                    # Get deployment slot details if enabled
                    $deploymentSlots = @()
                    $deploymentSlotsUrls = @()
                    
                    if ($EnableDeploymentSlots -and $deployment.Outputs.deploymentSlotsEnabled.Value) {
                        $deploymentSlots = $deployment.Outputs.deploymentSlots.Value
                        $deploymentSlotsUrls = $deployment.Outputs.deploymentSlotsUrls.Value
                        
                        Write-Verbose "Deployment slots created: $($deploymentSlots -join ', ')"
                    }
                    
                    # Return custom object with deployment details
                    $result = [PSCustomObject]@{
                        Name = $appService.Name
                        ResourceGroupName = $ResourceGroupName
                        Location = $appService.Location
                        AppServicePlanName = $appService.ServerFarmId.Split('/')[-1]  # Extract name from ID
                        SkuName = $SkuName
                        SkuCapacity = $SkuCapacity
                        RuntimeStack = $RuntimeStack
                        RuntimeVersion = $RuntimeVersion
                        HttpsOnly = $appService.HttpsOnly
                        URL = $appServiceUrl
                        AppInsightsKey = $appInsightsKey
                        
                        # Deployment slots details
                        DeploymentSlotsEnabled = $EnableDeploymentSlots -and $deployment.Outputs.deploymentSlotsEnabled.Value
                        DeploymentSlots = $deploymentSlots
                        DeploymentSlotsUrls = $deploymentSlotsUrls
                        AutoSwapEnabled = $EnableAutoSwap
                        
                        # Auto-scale details
                        AutoScalingEnabled = $EnableAutoScale -and $deployment.Outputs.autoScalingEnabled.Value
                        AutoScaleMinInstances = if ($EnableAutoScale) { $AutoScaleMinInstanceCount } else { 0 }
                        AutoScaleMaxInstances = if ($EnableAutoScale) { $AutoScaleMaxInstanceCount } else { 0 }
                        
                        # Container deployment details
                        ContainerDeploymentEnabled = $EnableContainerDeployment -and $deployment.Outputs.containerDeploymentEnabled.Value
                        ContainerRegistryServer = if ($EnableContainerDeployment) { $ContainerRegistryServer } else { '' }
                        ContainerImage = if ($EnableContainerDeployment) { $ContainerImageAndTag } else { '' }
                        
                        # Custom domain details
                        CustomDomainEnabled = $EnableCustomDomain -and $deployment.Outputs.customDomainEnabled.Value
                        CustomDomainName = if ($EnableCustomDomain) { $CustomDomainName } else { '' }
                        SslBindingEnabled = $EnableSslBinding
                        
                        # Backup details
                        BackupEnabled = $EnableBackup -and $deployment.Outputs.backupEnabled.Value
                        BackupStorageAccount = if ($EnableBackup) { $BackupStorageAccountName } else { '' }
                        BackupRetentionDays = if ($EnableBackup) { $BackupRetentionPeriodDays } else { 0 }
                        BackupSasTokenExpiryPeriod = if ($EnableBackup) { $BackupSasTokenExpiryPeriod } else { '' } # Added to output
                        
                        # General deployment details
                        ProvisioningState = $appService.State
                        DeploymentId = $deployment.DeploymentName
                        DeploymentTimestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        AppServiceReference = $appService
                    }
                    
                    return $result
                }
                else {
                    throw "Deployment failed with state: $($deployment.ProvisioningState)"
                }
            }
        }
        catch {
            # Main error handling - ensure we write proper errors
            if ($_.Exception -is [EAFException]) {
                Write-EAFException -Exception $_.Exception -Throw
            }
            else {
                Write-Error "Error creating App Service $AppServiceName: $_"
            }
            Write-Progress -Activity "Creating Azure App Service" -Status "Error" -PercentComplete 100 -Completed
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
        
        Write-Verbose "New-EAFAppService completed."
    }
}
