function New-EAFVM {
    <#
    .SYNOPSIS
        Creates a new Azure Virtual Machine using EAF standards.
    
    .DESCRIPTION
        The New-EAFVM cmdlet creates a new Azure Virtual Machine according to Enterprise Azure Framework (EAF) 
        standards. It provisions a VM with proper naming, tagging, security settings, and diagnostic configurations.
        
        This cmdlet uses the vm.bicep template to ensure consistent VM deployments across the organization.
    
    .PARAMETER ResourceGroupName
        Specifies the name of the resource group where the VM will be deployed.
    
    .PARAMETER VmName
        Specifies the name of the virtual machine. Must follow EAF naming convention (e.g., vm-appname-dev).
    
    .PARAMETER Location
        Specifies the Azure region where the VM will be deployed. Defaults to the resource group's location or EAF configuration.
    
    .PARAMETER VmSize
        Specifies the size of the virtual machine. Defaults to an EAF-configured size or a global default.
    
    .PARAMETER OsType
        Specifies the operating system type (Windows or Linux).
    
    .PARAMETER AdminUsername
        Specifies the administrator username for the VM.
    
    .PARAMETER AdminPassword
        Specifies the secure string containing the administrator password.
    
    .PARAMETER VirtualNetworkName
        Specifies the name of the virtual network where the VM will be connected.
    
    .PARAMETER SubnetName
        Specifies the name of the subnet within the virtual network.
    
    .PARAMETER VnetResourceGroupName
        Specifies the resource group of the virtual network. Defaults to the VM's resource group.

    .PARAMETER Environment
        Specifies the deployment environment (dev, test, prod). Defaults to dev.
    
    .PARAMETER Department
        Specifies the department or team responsible for the VM.
    
    .PARAMETER EnableBootDiagnostics
        Indicates whether boot diagnostics should be enabled. Defaults to true.
    .PARAMETER BootDiagnosticsStorageAccountName
        Specifies an existing storage account for boot diagnostics. If not provided, a new one will be created by the Bicep template.

    .PARAMETER EnableManagedIdentity
        Indicates whether a managed identity should be enabled for the VM. Defaults to true.
    
    .PARAMETER ManagedIdentityType
        Specifies the type of managed identity. Valid values: SystemAssigned, UserAssigned, SystemAssigned,UserAssigned, None.
        Defaults to SystemAssigned.
    
    .PARAMETER UserAssignedIdentityId
        Specifies the resource ID of the user-assigned managed identity to assign to the VM.
        Only required when ManagedIdentityType is UserAssigned or SystemAssigned,UserAssigned.
    
    .PARAMETER EnableBackup
        Indicates whether VM backup should be enabled. Defaults to false. (Note: Bicep template must support this)
    
    .PARAMETER AddDataDisks
        Indicates whether data disks should be added to the VM. Defaults to false.
    
    .PARAMETER DataDisks
        Array of hashtables defining data disks, e.g., @{lun=0; diskSizeGB=100; storageType='Premium_LRS'; caching='ReadOnly'}.
        Overrides DataDisksCount, DataDiskSizeGB, DataDiskStorageType, DataDiskCaching if provided.

    .PARAMETER DataDisksCount
        Specifies the number of data disks to add if $DataDisks is not provided. Range: 1-16.
        Defaults to 1.
    
    .PARAMETER DataDiskSizeGB
        Specifies the size of data disks in GB if $DataDisks is not provided.
        Defaults to 128.
    
    .PARAMETER DataDiskStorageType
        Specifies the storage account type for data disks if $DataDisks is not provided.
        Valid values: Standard_LRS, StandardSSD_LRS, Premium_LRS.
        Defaults to StandardSSD_LRS.
    
    .PARAMETER DataDiskCaching
        Specifies the caching type for data disks if $DataDisks is not provided.
        Valid values: None, ReadOnly, ReadWrite.
        Defaults to ReadOnly.
    
    .PARAMETER Force
        Forces the command to run without asking for user confirmation.
    
    .EXAMPLE
        New-EAFVM -ResourceGroupName "rg-app1-dev" -VmName "vm-app1-dev" -OsType Windows -AdminUsername "adminuser" -AdminPassword $securePassword -VirtualNetworkName "vnet-dev" -SubnetName "subnet-app" -Department "IT"
        
        Creates a new Windows VM named "vm-app1-dev".

    .EXAMPLE
        $customDataDisks = @(
            @{lun=0; diskSizeGB=50; storageType='Standard_LRS'; caching='None'},
            @{lun=1; diskSizeGB=200; storageType='Premium_LRS'; caching='ReadOnly'}
        )
        New-EAFVM -ResourceGroupName "rg-db-prod" -VmName "vm-sql-prod" -OsType Windows -AdminUsername "sqladmin" -AdminPassword $securePass -VirtualNetworkName "vnet-prod" -SubnetName "subnet-db" -Department "DBA" -Environment "prod" -DataDisks $customDataDisks
        
        Creates a new VM in production with custom data disks.
    
    .INPUTS
        None. You cannot pipe objects to New-EAFVM.
    
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
        # [ValidatePattern('^vm-[a-zA-Z0-9]+-(?:dev|test|prod)$')] # Validation handled by Test-EAFResourceName
        [string]$VmName,
        
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Location,
        
        [Parameter(Mandatory = $false)]
        # Removed ValidateSet to make VmSize less restrictive
        [string]$VmSize = 'Standard_D2s_v3', # Default, might be overridden by Get-EAFDefaultSKU
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Windows', 'Linux')]
        [string]$OsType,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AdminUsername,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [SecureString]$AdminPassword,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VirtualNetworkName,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SubnetName,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$VnetResourceGroupName = $ResourceGroupName, # Defaults to VM's RG
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$Environment = 'dev',
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Department,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableBootDiagnostics = $true,
        
        [Parameter(Mandatory = $false)]
        [string]$BootDiagnosticsStorageAccountName = '', # Bicep can create one if empty
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableManagedIdentity = $true,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('SystemAssigned', 'UserAssigned', 'SystemAssigned,UserAssigned', 'None')]
        [string]$ManagedIdentityType = 'SystemAssigned',
        
        [Parameter(Mandatory = $false)]
        [string]$UserAssignedIdentityId = '', # Bicep needs array: userAssignedIdentities
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableBackup = $false, # Bicep parameters for backup are not in the provided vm.bicep
        
        [Parameter(Mandatory = $false)]
        [bool]$AddDataDisks = $false,

        [Parameter(Mandatory = $false)]
        [array]$DataDisks = @(), # Takes precedence

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 16)]
        [int]$DataDisksCount = 1, # Used if DataDisks is empty
        
        [Parameter(Mandatory = $false)]
        # Removed ValidateSet to make DataDiskSizeGB less restrictive
        [int]$DataDiskSizeGB = 128, # Used if DataDisks is empty
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Standard_LRS', 'StandardSSD_LRS', 'Premium_LRS')]
        [string]$DataDiskStorageType = 'StandardSSD_LRS', # Used if DataDisks is empty
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('None', 'ReadOnly', 'ReadWrite')]
        [string]$DataDiskCaching = 'ReadOnly', # Used if DataDisks is empty
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    begin {
        Write-Verbose "Initializing New-EAFVM operation..."
        # Import helper modules
        $modulePath = Split-Path -Path $PSScriptRoot -Parent
        $privateModulePath = Join-Path -Path $modulePath -ChildPath "Private"
        
        $script:EAFHelperModulesLoaded = $false
        $helperModules = @(
            "exceptions.psm1",
            "retry-logic.psm1",
            "validation-helpers.psm1",
            "configuration-helpers.psm1",
            "monitoring-helpers.psm1" 
        )
        
        foreach ($helperModuleFile in $helperModules) {
            $helperModulePath = Join-Path -Path $privateModulePath -ChildPath $helperModuleFile
            if (Test-Path -Path $helperModulePath) {
                Import-Module -Name $helperModulePath -Force -ErrorAction Stop
                Write-Verbose "Loaded helper module: $helperModuleFile"
            } else {
                Write-Warning "Helper module not found: $helperModulePath" 
            }
        }
        $script:EAFHelperModulesLoaded = $true

        # Check for required Azure PowerShell modules
        try {
            Write-Verbose "Checking for required Az modules..."
            # Az.RecoveryServices might be needed if backup is handled by script, but Bicep handles it.
            $requiredAzModules = @('Az.Compute', 'Az.Network', 'Az.Resources') 
            foreach ($azModule in $requiredAzModules) {
                if (-not (Get-Module -ListAvailable -Name $azModule)) {
                    throw [EAFDependencyException]::new(
                        "Required module $azModule is not installed. Please install using: Install-Module $azModule -Force",
                        "VirtualMachine", "AzureModule", $azModule, "NotInstalled"
                    )
                }
            }
            Write-Verbose "All required Az modules are available."
        }
        catch {
            Write-EAFException -Exception $_.Exception -ErrorCategory NotInstalled -Throw 
            return 
        }
        
        # Initialize Bicep template path
        $script:templatePath = Join-Path -Path $PSScriptRoot -ChildPath "..\Templates\vm.bicep"
        if (-not (Test-Path -Path $script:templatePath)) {
            throw [EAFDependencyException]::new(
                "VM Bicep template not found at: $($script:templatePath)",
                "VirtualMachine", "BicepTemplate", $script:templatePath, "NotFound"
            )
        }
        Write-Verbose "Using Bicep template: $($script:templatePath)"
    }
    
    process {
        Write-Progress -Activity "Creating Azure VM" -Status "Initializing" -PercentComplete 0
        $plainPassword = $null 

        try {
            # Step 1: Verify resource group exists
            Write-Verbose "Checking resource group $ResourceGroupName exists..."
            Write-Progress -Activity "Creating Azure VM" -Status "Verifying resource group" -PercentComplete 5
            Test-EAFResourceGroupExists -ResourceGroupName $ResourceGroupName -ThrowOnNotExist $true
            
            # Step 2: Determine Location
            Write-Progress -Activity "Creating Azure VM" -Status "Determining location" -PercentComplete 10
            if (-not $PSBoundParameters.ContainsKey('Location') -or [string]::IsNullOrEmpty($Location)) {
                $configLocation = Get-EAFConfiguration -ConfigPath "Regions.Default.$Environment" -ErrorAction SilentlyContinue
                if (-not [string]::IsNullOrEmpty($configLocation)) {
                    $Location = $configLocation
                    Write-Verbose "Using location from EAF configuration: $Location"
                } else {
                    $resourceGroupDetails = Get-AzResourceGroup -Name $ResourceGroupName
                    $Location = $resourceGroupDetails.Location
                    Write-Verbose "Using resource group location: $Location"
                }
            }

            # Step 3: Determine VmSize
            Write-Progress -Activity "Creating Azure VM" -Status "Determining VM size" -PercentComplete 15
            if ($PSBoundParameters.ContainsKey('VmSize') -and $VmSize -eq 'Standard_D2s_v3') { # Default value
                 $defaultVmSize = Get-EAFDefaultSKU -ResourceType "VirtualMachine" -Environment $Environment -ErrorAction SilentlyContinue
                 if(-not [string]::IsNullOrEmpty($defaultVmSize)) {
                     $VmSize = $defaultVmSize
                     Write-Verbose "Using VM size from EAF configuration: $VmSize"
                 }
            }

            # Step 4: Validate VM Name
            Write-Verbose "Validating VM name $VmName..."
            Write-Progress -Activity "Creating Azure VM" -Status "Validating name" -PercentComplete 20
            # Assuming Test-EAFResourceName has a pattern for VMs e.g. vm-myvm-dev
            Test-EAFResourceName -ResourceName $VmName -ResourceType "VirtualMachine" -Environment $Environment -ThrowOnInvalid $true
            
            # Step 5: Validate Network Configuration
            Write-Verbose "Validating network VNet '$VirtualNetworkName'/Subnet '$SubnetName' in RG '$VnetResourceGroupName'..."
            Write-Progress -Activity "Creating Azure VM" -Status "Validating network" -PercentComplete 25
            Test-EAFNetworkConfiguration -VirtualNetworkName $VirtualNetworkName -SubnetName $SubnetName -ResourceGroupName $VnetResourceGroupName -ThrowOnInvalid $true

            # Step 6: Check if VM already exists (Idempotency)
            Write-Progress -Activity "Creating Azure VM" -Status "Checking existing VM" -PercentComplete 30
            $existingVm = Invoke-WithRetry -ScriptBlock {
                Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName -ErrorAction SilentlyContinue
            } -MaxRetryCount 3 -ActivityName "Checking VM existence"
            
            if ($existingVm) {
                Write-Verbose "VM $VmName already exists in resource group $ResourceGroupName."
                if (-not $Force -and -not $PSCmdlet.ShouldProcess($VmName, "Update existing VM configuration (Note: Some properties like OS disk cannot be changed. Review Bicep output for details.)")) {
                    Write-Warning "VM $VmName already exists. No changes will be made. Use -Force to attempt an update."
                    return $existingVm # Consider returning a standardized EAF object
                }
                Write-Verbose "Proceeding with VM update/reconfiguration as -Force or -Confirm was provided."
            }
            
            # Step 7: Internal Parameter Validations
            Write-Progress -Activity "Creating Azure VM" -Status "Internal parameter validation" -PercentComplete 35
            if ($EnableManagedIdentity -and ($ManagedIdentityType -match 'UserAssigned') -and [string]::IsNullOrEmpty($UserAssignedIdentityId)) {
                 throw [EAFParameterValidationException]::new(
                    "UserAssignedIdentityId is required when ManagedIdentityType includes 'UserAssigned'.",
                    "VirtualMachine", "UserAssignedIdentityId", "MissingParameter"
                )
            }
            # Bicep handles data disk creation logic based on $DataDisks or individual params
            # If $DataDisks is empty, construct it from other parameters
            $finalDataDisks = $DataDisks
            if ($AddDataDisks -and $DataDisks.Count -eq 0) {
                $finalDataDisks = @()
                for ($i = 0; $i -lt $DataDisksCount; $i++) {
                    $finalDataDisks += @{
                        lun          = $i
                        diskSizeGB   = $DataDiskSizeGB
                        storageType  = $DataDiskStorageType # Bicep should use param osDiskType or similar
                        caching      = $DataDiskCaching
                        createOption = 'Empty' # Bicep should handle this
                    }
                }
            }


            # Step 8: Prepare deployment parameters
            Write-Verbose "Preparing deployment parameters..."
            Write-Progress -Activity "Creating Azure VM" -Status "Preparing deployment" -PercentComplete 40
            
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword)
            $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR) # Zero out BSTR immediately
            
            $deploymentName = "Deploy-VM-$VmName-$(Get-Date -Format 'yyyyMMddHHmmss')"
            $defaultTags = Get-EAFDefaultTags -Environment $Environment -Department $Department -ResourceType "VirtualMachine"

            # Map UserAssignedIdentityId to the array structure expected by Bicep if type includes UserAssigned
            $userAssignedIdentitiesForBicep = @{}
            if ($EnableManagedIdentity -and ($ManagedIdentityType -match 'UserAssigned') -and -not [string]::IsNullOrEmpty($UserAssignedIdentityId)) {
                # Assuming UserAssignedIdentityId is a single string ID. Bicep expects an object like:
                # '/subscriptions/.../resourceGroups/.../providers/Microsoft.ManagedIdentity/userAssignedIdentities/myIdentity': {}
                $userAssignedIdentitiesForBicep = @{ "$UserAssignedIdentityId" = @{} }

            }
            
            $templateParams = @{
                vmName = $VmName
                location = $Location
                vmSize = $VmSize
                osType = $OsType
                adminUsername = $AdminUsername
                adminPassword = $plainPassword # Plain text password
                vnetName = $VirtualNetworkName # Renamed from virtualNetworkName
                subnetName = $SubnetName
                vnetResourceGroupName = $VnetResourceGroupName

                # Parameters from repaired vm.bicep
                environment = $Environment
                department = $Department
                additionalTags = $defaultTags 
                
                enableAcceleratedNetworking = $true # Default from vm.bicep, could be param
                # bootDiagnosticsStorageAccountName = $BootDiagnosticsStorageAccountName # Already a param
                enableBootDiagnostics = $EnableBootDiagnostics
                
                enableMonitoring = $true # Default from vm.bicep, could be param
                existingLogAnalyticsWorkspaceId = '' # Default from vm.bicep, could be param
                logAnalyticsRetentionDays = ($Environment -eq 'prod' ? 90 : 30) # Default from vm.bicep

                enableManagedIdentity = $EnableManagedIdentity
                managedIdentityType = $ManagedIdentityType 
                userAssignedIdentities = $userAssignedIdentitiesForBicep # Processed for Bicep

                # Data Disks - Bicep expects `dataDisks` array
                addDataDisks = $AddDataDisks 
                dataDisks = $finalDataDisks # Use the processed $finalDataDisks array

                # Parameters from original New-EAFVM that might need mapping or are covered by vm.bicep defaults
                # osDiskType, osDiskSizeGB, osDiskCaching - These are defined in vm.bicep
                # imagePublisher, imageOffer, imageSku, imageVersion - Defined in vm.bicep
                # enableAvailabilityZone, availabilityZone - Defined in vm.bicep
                # timeZone - Defined in vm.bicep

                # Network related params from vm.bicep that are not direct inputs to New-EAFVM yet
                nsgName = "${VmName}-nsg" # Default from vm.bicep
                publicIPName = "${VmName}-pip" # Default from vm.bicep
                nicName = "${VmName}-nic" # Default from vm.bicep
                diagnosticsStorageName = "diag$(Get-Random -Maximum 999999)$(Get-Date -Format 'yyyyMMddHHmmss')" # Simplified unique name
                lawName = "law-${Environment}-${VmName}" # Default from vm.bicep
                
                # sshPublicKey is in vm.bicep, if OsType is Linux, may need to add as param to New-EAFVM
                sshPublicKey = ''
            }
            
            # Step 9: Deploy VM using Bicep template
            if ($PSCmdlet.ShouldProcess($VmName, "Deploy Azure Virtual Machine")) {
                Write-Verbose "Deploying VM $VmName via Bicep template $($script:templatePath)..."
                Write-Progress -Activity "Creating Azure VM" -Status "Deploying resources" -PercentComplete 60
                
                $deployment = Invoke-WithRetry -ScriptBlock {
                    New-AzResourceGroupDeployment `
                        -ResourceGroupName $ResourceGroupName `
                        -Name $deploymentName `
                        -TemplateFile $script:templatePath `
                        -TemplateParameterObject $templateParams `
                        -Verbose:$VerbosePreference -ErrorAction Stop 
                } -MaxRetryCount 3 -ActivityName "VM Bicep Deployment"
                
                # Clear plain text password from memory immediately after deployment call
                $plainPassword = $null
                Remove-Variable -Name plainPassword -ErrorAction SilentlyContinue -Scope Script
                
                Write-Progress -Activity "Creating Azure VM" -Status "Deployment complete" -PercentComplete 90
                
                if ($deployment.ProvisioningState -eq 'Succeeded') {
                    Write-Verbose "VM $VmName Bicep deployment reported success."
                    
                    $vmDetails = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName -Status -ErrorAction SilentlyContinue
                    $nicId = $vmDetails.NetworkProfile.NetworkInterfaces[0].Id
                    $nic = Get-AzNetworkInterface -ResourceId $nicId -ErrorAction SilentlyContinue
                    $publicIpId = $nic.IpConfigurations[0].PublicIpAddress.Id
                    $publicIp = if (-not [string]::IsNullOrEmpty($publicIpId)) { Get-AzPublicIpAddress -ResourceId $publicIpId -ErrorAction SilentlyContinue } else { $null }

                    $result = [PSCustomObject]@{
                        Name = $vmDetails.Name
                        ResourceGroupName = $ResourceGroupName
                        Location = $vmDetails.Location
                        VmSize = $vmDetails.HardwareProfile.VmSize
                        OsType = $vmDetails.StorageProfile.OsDisk.OsType
                        AdminUsername = $AdminUsername # From input
                        PowerState = $vmDetails.Statuses[1].DisplayStatus # Typically the second status is PowerState
                        PublicIPAddress = $publicIp.IpAddress
                        Fqdn = $publicIp.DnsSettings.Fqdn
                        PrivateIPAddress = $nic.IpConfigurations[0].PrivateIpAddress
                        ProvisioningState = $vmDetails.ProvisioningState
                        ManagedIdentityEnabled = $EnableManagedIdentity 
                        ManagedIdentityType = $ManagedIdentityType 
                        ManagedIdentityPrincipalId = $vmDetails.Identity.PrincipalId # If SystemAssigned
                        Tags = $vmDetails.Tags
                        DeploymentId = $deployment.DeploymentId
                        DeploymentTimestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        VMReference = $vmDetails
                    }
                    Write-Progress -Activity "Creating Azure VM" -Status "Completed" -PercentComplete 100
                    return $result
                } else {
                    $errorDetails = $deployment.Properties.Error.Details | ForEach-Object { $_.Message } | Out-String
                    throw [EAFProvisioningFailedException]::new(
                        "Bicep deployment for VM '$VmName' failed with state: $($deployment.ProvisioningState). Details: $errorDetails",
                        "VirtualMachine", $VmName, $deployment.ProvisioningState, $deployment.CorrelationId
                    )
                }
            } else {
                 Write-Warning "Deployment of VM $VmName skipped due to ShouldProcess preference."
                 return $null
            }
        }
        catch {
            Write-Progress -Activity "Creating Azure VM" -Status "Error" -PercentComplete 100 -Completed
            if ($_.Exception -is [EAFException]) {
                Write-EAFException -Exception $_.Exception -Throw
            } else {
                $wrappedException = [EAFProvisioningFailedException]::new(
                    "Failed to create VM '$VmName': $($_.Exception.Message)",
                    "VirtualMachine", $VmName, "UnknownError", $null, $_.Exception 
                )
                Write-EAFException -Exception $wrappedException -Throw
            }
        }
        finally {
            # Ensure plainPassword is cleared if an error occurred before its explicit clearing
            if ($null -ne $plainPassword) { 
                $plainPassword = $null; Remove-Variable -Name plainPassword -ErrorAction SilentlyContinue -Scope Script 
            }
            Write-Progress -Activity "Creating Azure VM" -Completed
        }
    }
    
    end {
        Write-Verbose "New-EAFVM operation finished."
        if ($script:EAFHelperModulesLoaded) {
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
