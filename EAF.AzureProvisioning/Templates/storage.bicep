// =========================================================
// Storage Account Template - Enterprise Azure Framework (EAF)
// =========================================================

// Core Parameters
@description('Name of the storage account')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment (dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Department or team responsible for the resource')
param department string

// Storage Configuration
@description('Storage Account type')
@allowed([
  'StorageV2'
  'BlockBlobStorage'
  'FileStorage'
])
param storageAccountType string = 'StorageV2'

@description('Storage Account replication type')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
  'Premium_ZRS'
])
param sku string = environment == 'prod' ? 'Standard_GRS' : 'Standard_LRS'

@description('Storage Account access tier')
@allowed([
  'Hot'
  'Cool'
])
param accessTier string = environment == 'prod' ? 'Hot' : 'Cool'

// Security Configuration
@description('Enable blob public access')
param allowBlobPublicAccess bool = false

@description('Enable shared key access')
param allowSharedKeyAccess bool = environment != 'prod'

@description('Require secure transfer (HTTPS)')
param supportsHttpsTrafficOnly bool = true

@description('Minimum TLS version')
@allowed([
  'TLS1_2'
])
param minimumTlsVersion string = 'TLS1_2'

@description('Enable infrastructure encryption (double encryption)')
param enableInfrastructureEncryption bool = environment == 'prod'

@description('Enable customer-managed key for encryption')
param enableCustomerManagedKey bool = environment == 'prod'

@description('Key Vault name containing customer-managed key')
param keyVaultName string = ''

@description('Key name in Key Vault')
param keyName string = ''

@description('Key version in Key Vault')
param keyVersion string = ''

// Data Protection
@description('Enable hierarchical namespace (Data Lake Storage Gen2)')
param enableHierarchicalNamespace bool = false

@description('Enable blob versioning')
param enableBlobVersioning bool = environment == 'prod'

@description('Enable blob change feed')
param enableChangeFeed bool = environment == 'prod'

@description('Enable blob soft delete')
param enableBlobSoftDelete bool = true

@description('Blob soft delete retention days')
@minValue(1)
@maxValue(365)
param blobSoftDeleteRetentionDays int = 7 // Restored from interruption

@description('Enable container soft delete') // Assuming this was meant to be container soft delete
@minValue(1)
@maxValue(365)
param containerSoftDeleteRetentionDays int = environment == 'prod' ? 30 : 7

@description('Enable file share soft delete')
param enableFileSoftDelete bool = true

@description('File share soft delete retention days')
@minValue(1)
@maxValue(365)
param fileSoftDeleteRetentionDays int = environment == 'prod' ? 30 : 7 // Restored from interruption and assumed value

// Network Configuration
@description('Default network action')
@allowed([
  'Allow'
  'Deny'
])
param defaultNetworkAction string = environment == 'prod' ? 'Deny' : 'Allow'

@description('Allowed IP address ranges in CIDR notation')
param ipRules array = []

@description('Allowed virtual network subnet resource IDs')
param virtualNetworkRules array = []

@description('Deploy private endpoint')
param deployPrivateEndpoint bool = environment == 'prod'

@description('Virtual network name for private endpoint')
param privateEndpointVnetName string = ''

@description('Subnet name for private endpoint')
param privateEndpointSubnetName string = ''

@description('Resource group of virtual network for private endpoint')
param privateEndpointVnetResourceGroup string = resourceGroup().name

@description('Private DNS zone name for blob storage')
param privateDnsZoneName string = 'privatelink.blob.${environment().suffixes.storage}'

// Service Configuration
@description('Enable static website hosting')
param enableStaticWebsite bool = false

@description('Index document for static website')
param indexDocument string = 'index.html'

@description('Error document for static website')
param errorDocument string = 'error.html'

@description('Enable CORS for blob service')
param enableCors bool = false

@description('CORS rules configuration')
param corsRules array = enableCors ? [
  {
    allowedOrigins: ['*']
    allowedMethods: ['GET', 'HEAD', 'POST', 'PUT', 'DELETE']
    allowedHeaders: ['*']
    exposedHeaders: ['*']
    maxAgeInSeconds: 200
  }
] : []

// Storage Content
@description('Containers to create')
param containers array = []

@description('File shares to create')
param fileShares array = []

// Lifecycle Management
@description('Enable lifecycle management')
param enableLifecycleManagement bool = true

@description('Days after which to move blobs to cool tier')
@minValue(0)
@maxValue(99999)
param coolTierAfterDays int = environment == 'prod' ? 90 : 30

@description('Days after which to move blobs to archive tier')
@minValue(0)
@maxValue(99999)
param archiveTierAfterDays int = environment == 'prod' ? 180 : 60

@description('Days after which to delete blobs')
@minValue(0)
@maxValue(99999)
param deleteAfterDays int = environment == 'prod' ? 365 : 90

// Monitoring and Diagnostics
@description('Enable monitoring with Log Analytics')
param enableMonitoring bool = true

@description('Existing Log Analytics workspace resource ID')
param existingLogAnalyticsWorkspaceId string = ''

@description('Log Analytics workspace retention days')
param logAnalyticsRetentionDays int = environment == 'prod' ? 90 : 30

@description('Enable alerts for storage account')
param enableAlerts bool = environment == 'prod'

@description('Email addresses for alerts')
param alertEmailAddresses array = []

// Tags
@description('Additional tags to apply to resources')
param additionalTags object = {}

// Variables
var tags = union({
  Environment: environment
  Department: department
  CreatedBy: 'EAF'
  CreatedDate: utcNow('yyyy-MM-dd')
  ResourceType: 'StorageAccount'
  SecurityTier: environment == 'prod' ? 'Critical' : (environment == 'test' ? 'High' : 'Standard')
  DataClassification: environment == 'prod' ? 'Confidential' : 'Internal'
  CostCenter: '${department}-${environment}'
}, additionalTags)

var lawName = empty(existingLogAnalyticsWorkspaceId) ? '${environment}-${department}-law' : ''
