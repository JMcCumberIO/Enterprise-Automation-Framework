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
        Specifies the name of the virtual machine. Must follow naming convention.
    
    .PARAMETER Location
        Specifies the Azure region where the VM will be deployed. Defaults to the resource group's location.
    
    .PARAMETER VmSize
        Specifies the size of the virtual machine. Defaults to Standard_D2s_v3.
    
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
    
    .PARAMETER Environment
        Specifies the deployment environment (dev, test, prod). Defaults to dev.
    
    .PARAMETER Department
        Specifies the department or team responsible for the VM.
    
    .PARAMETER EnableBootDiagnostics
        Indicates whether boot diagnostics should be enabled. Defaults to true.
    .PARAMETER BootDiagnosticsStorageAccountName
        Specifies an existing storage account for boot diagnostics. If not provided, a new one will be created.

    .PARAMETER EnableManagedIdentity
        Indicates whether a managed identity should be enabled for the VM. Defaults to true.
    
    .PARAMETER ManagedIdentityType
        Specifies the type of managed identity. Valid values: SystemAssigned, UserAssigned, SystemAssigned,UserAssigned, None.
        Defaults to SystemAssigned.
    
    .PARAMETER UserAssignedIdentityId
        Specifies the resource ID of the user-assigned managed identity to assign to the VM.
        Only required when ManagedIdentityType is UserAssigned or SystemAssigned,UserAssigned.
    
    .PARAMETER EnableBackup
        Indicates whether VM backup should be enabled. Defaults to false.
    
    .PARAMETER BackupPolicyType
        Specifies the backup policy type. Valid values: Daily, Weekly.
        Defaults to Daily.
    
    .PARAMETER BackupRetentionDays
        Specifies the number of days to retain backups. Range: 7-180 days.
        Defaults to 30.
    
    .PARAMETER BackupTime
        Specifies the time of day for backups in HH:MM format. Defaults to 23:00.
    
    .PARAMETER AddDataDisks
        Indicates whether data disks should be added to the VM. Defaults to false.
    
    .PARAMETER DataDisksCount
        Specifies the number of data disks to add. Range: 1-16.
        Defaults to 1.
    
    .PARAMETER DataDiskSizeGB
        Specifies the size of data disks in GB. 
        Valid values: 32, 64, 128, 256, 512, 1024, 2048, 4096.
        Defaults to 128.
    
    .PARAMETER DataDiskStorageType
        Specifies the storage account type for data disks.
        Valid values: Standard_LRS, StandardSSD_LRS, Premium_LRS.
        Defaults to StandardSSD_LRS.
    
    .PARAMETER DataDiskCaching
        Specifies the caching type for data disks.
        Valid values: None, ReadOnly, ReadWrite.
        Defaults to ReadOnly.
    
    .PARAMETER Force
        Forces the command to run without asking for user confirmation.
    
    .EXAMPLE
        New-EAFVM -ResourceGroupName "rg-app1-dev" -VmName "vm-app1-dev" -OsType Windows -AdminUsername "adminuser" -AdminPassword $securePassword -VirtualNetworkName "vnet-dev" -SubnetName "subnet-app" -Department "IT"
        
        Creates a new Windows VM named "vm-app1-dev" in the resource group "rg-app1-dev".

    .EXAMPLE
        New-EAFVM -ResourceGroupName "rg-app1-dev" -VmName "vm-db-dev" -OsType Linux -AdminUsername "adminuser" -AdminPassword $securePassword -VirtualNetworkName "vnet-dev" -SubnetName "subnet-data" -Department "IT" -AddDataDisks $true -DataDisksCount 2 -DataDiskSizeGB 512 -DataDiskStorageType "Premium_LRS"
        
        Creates a new Linux VM with two premium data disks of 512 GB each.

    .EXAMPLE
        New-EAFVM -ResourceGroupName "rg-app1-prod" -VmName "vm-app1-prod" -OsType Windows -AdminUsername "adminuser" -AdminPassword $securePassword -VirtualNetworkName "vnet-prod" -SubnetName "subnet-app" -Department "IT" -Environment "prod" -EnableBackup $true -BackupRetentionDays 90 -BackupPolicyType "Weekly"
        
        Creates a new Windows VM in production with weekly backups retained for 90 days.
    
    .EXAMPLE
        New-EAFVM -ResourceGroupName "rg-app1-dev" -VmName "vm-app1-dev" -VmSize "Standard_B2s" -OsType Linux -AdminUsername "adminuser" -AdminPassword $securePassword -VirtualNetworkName "vnet-dev" -SubnetName "subnet-app" -Department "IT" -Environment "test"
        
        Creates a new Linux VM with a specific size in the test environment.
    
    .EXAMPLE
        $vmParams = @{
            ResourceGroupName = "rg-app1-dev"
            VmName = "vm-app1-dev"
            OsType = "Windows"
            AdminUsername = "adminuser"
            AdminPassword = $securePassword
            VirtualNetworkName = "vnet-dev"
            SubnetName = "subnet-app"
            Department = "IT"
        }
        New-EAFVM @vmParams
        
        Creates a new VM using splatting for parameters.
    
    .INPUTS
        None. You cannot pipe objects to New-EAFVM.
    
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
        [ValidatePattern('^vm-[a-zA-Z0-9]+-(?:dev|test|prod)$')]
        [string]$VmName,
        
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Location,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Standard_B2s', 'Standard_D2s_v3', 'Standard_D4s_v3', 'Standard_D8s_v3')]
        [string]$VmSize = 'Standard_D2s_v3',
        
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
        [ValidateSet('dev', 'test', 'prod')]
        [string]$Environment = 'dev',
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Department,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableBootDiagnostics = $true,
        
        [Parameter(Mandatory = $false)]
        [string]$BootDiagnosticsStorageAccountName = '',
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableManagedIdentity = $true,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('SystemAssigned', 'UserAssigned', 'SystemAssigned,UserAssigned', 'None')]
        [string]$ManagedIdentityType = 'SystemAssigned',
        
        [Parameter(Mandatory = $false)]
        [string]$UserAssignedIdentityId = '',
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableBackup = $false,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Daily', 'Weekly')]
        [string]$BackupPolicyType = 'Daily',
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(7, 180)]
        [int]$BackupRetentionDays = 30,
        
        [Parameter(Mandatory = $false)]
        [ValidatePattern('^([01][0-9]|2[0-3]):([0-5][0-9])$')]
        [string]$BackupTime = '23:00',
        
        [Parameter(Mandatory = $false)]
        [bool]$AddDataDisks = $false,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 16)]
        [int]$DataDisksCount = 1,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet(32, 64, 128, 256, 512, 1024, 2048, 4096)]
        [int]$DataDiskSizeGB = 128,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Standard_LRS', 'StandardSSD_LRS', 'Premium_LRS')]
        [string]$DataDiskStorageType = 'StandardSSD_LRS',
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('None', 'ReadOnly', 'ReadWrite')]
        [string]$DataDiskCaching = 'ReadOnly',
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    begin {
        try {
            Write-Verbose "Checking for required Az modules..."
            $modules = @('Az.Compute', 'Az.Network', 'Az.Resources', 'Az.RecoveryServices')
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
        $templatePath = Join-Path -Path $PSScriptRoot -ChildPath "..\Templates\vm.bicep"
        if (-not (Test-Path -Path $templatePath)) {
            Write-Error "VM Bicep template not found at: $templatePath"
            return
        }
        
        Write-Verbose "Using Bicep template: $templatePath"
        $dateCreated = Get-Date -Format "yyyy-MM-dd"
    }
    
    process {
        Write-Progress -Activity "Creating Azure VM" -Status "Initializing" -PercentComplete 0
        
        try {
            # Step 1: Verify resource group exists
            Write-Verbose "Checking resource group $ResourceGroupName exists..."
            Write-Progress -Activity "Creating Azure VM" -Status "Verifying resource group" -PercentComplete 10
            
            $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
            if (-not $resourceGroup) {
                throw "Resource group '$ResourceGroupName' not found. Please create it first."
            }
            
            # Use resource group location if not specified
            if (-not $Location) {
                $Location = $resourceGroup.Location
                Write-Verbose "Using resource group location: $Location"
            }
            
            # Step 2: Check if VM already exists (idempotency)
            Write-Verbose "Checking if VM $VmName already exists..."
            Write-Progress -Activity "Creating Azure VM" -Status "Checking existing resources" -PercentComplete 20
            
            $existingVm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName -ErrorAction SilentlyContinue
            if ($existingVm) {
                Write-Verbose "VM $VmName already exists"
                if (-not $Force -and -not $PSCmdlet.ShouldProcess($VmName, "Update existing VM")) {
                    Write-Output "VM $VmName already exists. Use -Force to update or modify existing configuration."
                    return $existingVm
                }
                Write-Verbose "Proceeding with VM update..."
            }
            
            # Step 3: Validate parameters and prerequisites
            Write-Verbose "Validating parameters and prerequisites..."
            Write-Progress -Activity "Creating Azure VM" -Status "Validating parameters" -PercentComplete 25
            
            # Validate backup parameters
            if ($EnableBackup) {
                Write-Verbose "Validating backup configuration..."
                
                if ($BackupRetentionDays -lt 7 -or $BackupRetentionDays -gt 180) {
                    throw "Backup retention days must be between 7 and 180."
                }
                
                if ($BackupPolicyType -eq 'Weekly' -and $BackupRetentionDays -lt 7) {
                    throw "Weekly backup policy requires a minimum retention period of 7 days."
                }
                
                # Check if the Recovery Services module is installed
                if (-not (Get-Module -ListAvailable -Name 'Az.RecoveryServices')) {
                    Write-Warning "Az.RecoveryServices module is required for backup. Please install using: Install-Module Az.RecoveryServices -Force"
                }
            }
            
            # Validate managed identity parameters
            if ($EnableManagedIdentity) {
                Write-Verbose "Validating managed identity configuration..."
                
                if (($ManagedIdentityType -eq 'UserAssigned' -or $ManagedIdentityType -eq 'SystemAssigned,UserAssigned') -and [string]::IsNullOrEmpty($UserAssignedIdentityId)) {
                    throw "UserAssignedIdentityId is required when ManagedIdentityType is UserAssigned or SystemAssigned,UserAssigned."
                }
            }
            
            # Validate data disk parameters
            if ($AddDataDisks) {
                Write-Verbose "Validating data disk configuration..."
                
                if ($DataDisksCount -lt 1 -or $DataDisksCount -gt 16) {
                    throw "DataDisksCount must be between 1 and 16."
                }
                
                if ($DataDiskSizeGB -lt 32 -or $DataDiskSizeGB -gt 4096) {
                    throw "DataDiskSizeGB must be one of the allowed values: 32, 64, 128, 256, 512, 1024, 2048, 4096."
                }
                
                if ($DataDiskStorageType -eq 'Premium_LRS' -and $VmSize -notmatch '^Standard_D') {
                    Write-Warning "Premium storage is recommended for VM sizes with premium storage support."
                }
            }

            # Step 4: Validate virtual network and subnet
            Write-Verbose "Validating virtual network $VirtualNetworkName and subnet $SubnetName..."
            Write-Progress -Activity "Creating Azure VM" -Status "Validating network prerequisites" -PercentComplete 30
            
            $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VirtualNetworkName -ErrorAction SilentlyContinue
            if (-not $vnet) {
                throw "Virtual network '$VirtualNetworkName' not found in resource group '$ResourceGroupName'."
            }
            
            $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $SubnetName }
            if (-not $subnet) {
                throw "Subnet '$SubnetName' not found in virtual network '$VirtualNetworkName'."
            }
            
            # Step 5: Prepare deployment parameters
            Write-Verbose "Preparing deployment parameters..."
            Write-Progress -Activity "Creating Azure VM" -Status "Preparing deployment" -PercentComplete 40
            
            # Convert SecureString to plain text for template deployment
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword)
            $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            
            $deploymentName = "Deploy-VM-$VmName-$(Get-Date -Format 'yyyyMMddHHmmss')"
            
            $templateParams = @{
                vmName = $VmName
                vmSize = $VmSize
                osType = $OsType
                adminUsername = $AdminUsername
                adminPassword = $plainPassword
                location = $Location
                virtualNetworkName = $VirtualNetworkName
                subnetName = $SubnetName
                environment = $Environment
                department = $Department
                dateCreated = $dateCreated
                enableBootDiagnostics = $EnableBootDiagnostics
                bootDiagnosticsStorageAccountName = $BootDiagnosticsStorageAccountName
                
                # Managed identity parameters
                enableManagedIdentity = $EnableManagedIdentity
                managedIdentityType = $ManagedIdentityType
                userAssignedIdentityId = $UserAssignedIdentityId
                
                # Backup configuration
                enableBackup = $EnableBackup
                backupPolicyType = $BackupPolicyType
                backupRetentionDays = $BackupRetentionDays
                backupTime = $BackupTime
                
                # Data disk configuration
                addDataDisks = $AddDataDisks
                dataDisksCount = $DataDisksCount
                dataDiskSizeGB = $DataDiskSizeGB
                dataDiskStorageType = $DataDiskStorageType
                dataDiskCaching = $DataDiskCaching
            }
            
            # Step 5: Deploy VM using Bicep template
            if ($PSCmdlet.ShouldProcess($VmName, "Deploy Azure VM")) {
                Write-Verbose "Deploying VM $VmName..."
                Write-Progress -Activity "Creating Azure VM" -Status "Deploying resources" -PercentComplete 60
                
                $deployment = New-AzResourceGroupDeployment `
                    -ResourceGroupName $ResourceGroupName `
                    -Name $deploymentName `
                    -TemplateFile $templatePath `
                    -TemplateParameterObject $templateParams `
                    -Verbose:$VerbosePreference
                
                Write-Progress -Activity "Creating Azure VM" -Status "Deployment complete" -PercentComplete 100
                
                if ($deployment.ProvisioningState -eq 'Succeeded') {
                    Write-Verbose "VM $VmName deployed successfully"
                    
                    # Get the VM details
                    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName
                    $publicIp = Get-AzPublicIpAddress | Where-Object { $_.Name -eq "$VmName-pip" }
                    
                    # Return custom object with deployment details
                    $result = [PSCustomObject]@{
                        Name = $vm.Name
                        ResourceGroupName = $ResourceGroupName
                        Location = $vm.Location
                        VmSize = $vm.HardwareProfile.VmSize
                        OsType = $OsType
                        AdminUsername = $AdminUsername
                        PublicIPAddress = $publicIp.IpAddress
                        PublicIPAddress = $publicIp.IpAddress
                        FQDN = $publicIp.DnsSettings.Fqdn
                        ProvisioningState = $vm.ProvisioningState
                        
                        # Managed Identity details
                        ManagedIdentityEnabled = $EnableManagedIdentity
                        ManagedIdentityType = $ManagedIdentityType
                        ManagedIdentityPrincipalId = $deployment.Outputs.managedIdentityPrincipalId.Value
                        
                        # Backup details
                        BackupEnabled = $EnableBackup
                        BackupPolicyType = $EnableBackup ? $BackupPolicyType : ''
                        BackupRetentionDays = $EnableBackup ? $BackupRetentionDays : 0
                        BackupVaultName = $deployment.Outputs.backupVaultName.Value
                        
                        # Data Disk details
                        DataDisksAdded = $AddDataDisks
                        DataDisksCount = $deployment.Outputs.dataDisksCount.Value
                        DataDiskSizeGB = $AddDataDisks ? $DataDiskSizeGB : 0
                        DataDiskStorageType = $AddDataDisks ? $DataDiskStorageType : ''
                        
                        # Deployment details
                        DeploymentId = $deployment.DeploymentName
                        DeploymentTimestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        VMReference = $vm
                    
                    return $result
                }
                else {
                    throw "Deployment failed with state: $($deployment.ProvisioningState)"
                }
            }
        }
        catch {
            Write-Progress -Activity "Creating Azure VM" -Status "Error" -PercentComplete 100 -Completed
            Write-Error ("Error creating VM " + $VmName + ": " + ${_})
            throw $_
        }
        finally {
            Write-Progress -Activity "Creating Azure VM" -Completed
        }
    }
    
    end {
        Write-Verbose "New-EAFVM operation completed"
    }
}

