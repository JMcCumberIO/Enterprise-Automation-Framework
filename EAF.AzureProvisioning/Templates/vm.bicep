@allowed([
  'None'
  'ReadOnly'
  'ReadWrite'
])
param osDiskCaching string = 'ReadWrite'

// Data Disks
@description('Add data disks to VM.')
param addDataDisks bool = false

@description('Data disk configurations [{lun, diskSizeGB, diskType, caching}]')
param dataDisks array = []

// Availability Configuration
@description('Enable availability zone.')
param enableAvailabilityZone bool = environment == 'prod'

@description('Availability zone number (only applicable if availability zones are enabled).')
@allowed([
  '1'
  '2'
  '3'
])
param availabilityZone string = '1'

var computedAvailabilityZone = enableAvailabilityZone ? [availabilityZone] : null

// Security Configuration
@description('Enable managed identity.')
param enableManagedIdentity bool = environment == 'prod'

@description('Allowed source IP ranges for RDP/SSH access. Must be explicitly set for production.')
param allowedSourceIPRanges array = environment == 'prod' ? [] : ['*']

@description('The time zone for the virtual machine. Default is Central Standard Time.')
param timeZone string = 'Central Standard Time'

// Public IP Configuration
@description('Enable public IP.')
param enablePublicIP bool = false

//============================================
// PARAMETERS
//============================================

// Core Parameters
@description('Name of the virtual machine.')
param vmName string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Environment (dev, test, prod).')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string

@description('Department or team responsible for the resource.')
param department string

// VM Configuration
@description('Size of the virtual machine.')
param vmSize string = environment == 'prod' ? 'Standard_D4s_v3' : (environment == 'test' ? 'Standard_D2s_v3' : 'Standard_B2s')

@description('Type of OS.')
@allowed([
  'Windows'
  'Linux'
])
param osType string = 'Windows'

@description('OS image publisher.')
param imagePublisher string = osType == 'Windows' ? 'MicrosoftWindowsServer' : 'Canonical'

@description('OS image offer.')
param imageOffer string = osType == 'Windows' ? 'WindowsServer' : 'UbuntuServer'

@description('OS image SKU.')
param imageSku string = osType == 'Windows' ? '2022-Datacenter' : '20.04-LTS'

@description('OS image version.')
param imageVersion string = 'latest'

// Authentication
@description('Admin username.')
param adminUsername string

@description('Admin password.')
@secure()
param adminPassword string

@description('SSH public key for Linux VMs.')
param sshPublicKey string = ''

// Storage Configuration
@description('OS disk type.')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
])
param osDiskType string = environment == 'prod' ? 'Premium_LRS' : 'StandardSSD_LRS'

@description('OS disk size in GB.')
param osDiskSizeGB int = osType == 'Windows' ? 128 : 64

@description('OS disk caching type.')
@allowed([
  'None'
  'ReadOnly'
  'ReadWrite'
])
param osDiskCaching string = 'ReadWrite'

// Data Disks
@description('Add data disks to VM.')
param addDataDisks bool = false

@description('Data disk configurations [{lun, diskSizeGB, diskType, caching}].')
param dataDisks array = []

// Availability Configuration
@description('Enable availability zone.')
param enableAvailabilityZone bool = environment == 'prod'

@description('Availability zone number (only applicable if availability zones are enabled).')
@allowed([
  '1'
  '2'
  '3'
])
param availabilityZone string = '1'

var computedAvailabilityZone = enableAvailabilityZone ? [availabilityZone] : null

// Security Configuration
@description('Enable managed identity.')
param enableManagedIdentity bool = environment == 'prod'

@description('Allowed source IP ranges for RDP/SSH access. Must be explicitly set for production.')
param allowedSourceIPRanges array = environment == 'prod' ? [] : ['*']

@description('The time zone for the virtual machine. Default is Central Standard Time.')
param timeZone string = 'Central Standard Time'

// Public IP Configuration
@description('Enable public IP.')
param enablePublicIP bool = false

//============================================
// PARAMETERS
//============================================

// Core Parameters
@description('Name of the virtual machine.')
param vmName string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Environment (dev, test, prod).')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string

@description('Department or team responsible for the resource.')
param department string

// VM Configuration
@description('Size of the virtual machine.')
param vmSize string = environment == 'prod' ? 'Standard_D4s_v3' : (environment == 'test' ? 'Standard_D2s_v3' : 'Standard_B2s')

@description('Type of OS.')
@allowed([
  'Windows'
  'Linux'
])
param osType string = 'Windows'

@description('OS image publisher.')
param imagePublisher string = osType == 'Windows' ? 'MicrosoftWindowsServer' : 'Canonical'

@description('OS image offer.')
param imageOffer string = osType == 'Windows' ? 'WindowsServer' : 'UbuntuServer'

@description('OS image SKU.')
param imageSku string = osType == 'Windows' ? '2022-Datacenter' : '20.04-LTS'

@description('OS image version.')
param imageVersion string = 'latest'

// Authentication
@description('Admin username.')
param adminUsername string

@description('Admin password.')
@secure()
param adminPassword string

@description('SSH public key for Linux VMs.')
param sshPublicKey string = ''

// Storage Configuration
@description('OS disk type.')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
])
param osDiskType string = environment == 'prod' ? 'Premium_LRS' : 'StandardSSD_LRS'

@description('OS disk size in GB.')
param osDiskSizeGB int = osType == 'Windows' ? 128 : 64

@description('OS disk caching type.')
@allowed([
  'None'
  'ReadOnly'
  'ReadWrite'
])
param osDiskCaching string = 'ReadWrite'

// Data Disks
@description('Add data disks to VM.')
param addDataDisks bool = false

@description('Data disk configurations [{lun, diskSizeGB, diskType, caching}].')
param dataDisks array = []

// Network Configuration
@description('Virtual network name.')
param vnetName string

@description('Subnet name.')
param subnetName string

@description('Resource group containing the virtual network.')
param vnetResourceGroupName string = resourceGroup().name

@description('Enable public IP.')
param enablePublicIP bool = false

@description('Public IP SKU.')
@allowed([
  'Basic'
  'Standard'
])
param publicIPSku string = environment == 'prod' ? 'Standard' : 'Basic'

@description('Allowed source IP ranges for RDP/SSH access. Must be explicitly set for production.')
param allowedSourceIPRanges array = environment == 'prod' ? [] : ['*']

// Update NSG rules to handle empty `allowedSourceIPRanges`
resource nsg 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: concat([
      {
        name: osType == 'Windows' ? 'AllowRDP' : 'AllowSSH'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: osType == 'Windows' ? '3389' : '22'
          sourceAddressPrefix: empty(allowedSourceIPRanges) ? 'Deny' : null
          sourceAddressPrefixes: !empty(allowedSourceIPRanges) ? allowedSourceIPRanges : null
          destinationAddressPrefix: '*'
          description: 'Allow remote administration'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          description: 'Default deny rule for all inbound traffic'
        }
      }
    ], environment == 'prod' ? [
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          priority: 900
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          description: 'Allow Azure Load Balancer traffic'
        }
      }
    ] : [])
  }
}

// Public IP Address
resource publicIP 'Microsoft.Network/publicIPAddresses@2022-07-01' = if (enablePublicIP) {
  name: publicIPName
  location: location
  tags: tags
  sku: {
    name: publicIPSku
  }
  properties: {
    publicIPAllocationMethod: publicIPSku == 'Standard' ? 'Static' : 'Dynamic'
    deleteOption: 'Delete'
    dnsSettings: {
      domainNameLabel: toLower('${vmName}-${uniqueString(resourceGroup().id)}')
    }
  }
}

// Network Interface
resource nic 'Microsoft.Network/networkInterfaces@2022-07-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    enableAcceleratedNetworking: enableAcceleratedNetworking
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: resourceId(vnetResourceGroupName, 'Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: enablePublicIP ? {
            id: publicIP.id
          } : null
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// Boot Diagnostics Storage Account (if needed)
resource diagnosticsStorage 'Microsoft.Storage/storageAccounts@2022-05-01' = if (enableBootDiagnostics && empty(bootDiagnosticsStorageAccountName)) {
  name: diagnosticsStorageName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableMonitoring && empty(existingLogAnalyticsWorkspaceId)) {
  name: lawName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: environment == 'prod' ? 10 : 5
    }
  }
}

// Virtual Machine
resource vm 'Microsoft.Compute/virtualMachines@2022-08-01' = {
  name: vmName
  location: location
  tags: tags
  zones: computedAvailabilityZone
  identity: enableManagedIdentity ? {
    type: managedIdentityType
    userAssignedIdentities: managedIdentityType == 'UserAssigned' || managedIdentityType == 'SystemAssigned, UserAssigned' ? {
      for id in userAssignedIdentities: id: {}
    } : null
  } : null
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: osType == 'Linux' ? {
        disablePasswordAuthentication: !empty(sshPublicKey)
        ssh: !empty(sshPublicKey) ? {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        } : null
      } : null
      windowsConfiguration: osType == 'Windows' ? {
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
          assessmentMode: 'ImageDefault'
        }
        timeZone: timeZone // Use the parameter here
      } : null
    }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSku
        version: imageVersion
      }
      osDisk: {
        name: '${vmName}-osdisk'
        createOption: 'FromImage'
        deleteOption: 'Delete'
        diskSizeGB: osDiskSizeGB
        managedDisk: {
          storageAccountType: osDiskType
        }
        caching: osDiskCaching
      }
      dataDisks: addDataDisks ? [for (disk, i) in dataDisks: {
        name: '${vmName}-datadisk-${i}'
        diskSizeGB: disk.diskSizeGB
        lun: disk.lun
        createOption: 'Empty'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: contains(disk, 'diskType') ? disk.diskType : 'StandardSSD_LRS'
        }
        caching: contains(disk, 'caching') ? disk.caching : 'ReadOnly'
      }] : []
    }
  }
}
