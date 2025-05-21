// =========================================================
// Key Vault Template - Enterprise Azure Framework (EAF)
// =========================================================

// Core Parameters
@description('Name of the Key Vault.')
param keyVaultName string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Environment (dev, test, prod).')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Department or business unit responsible for the resource.')
param department string

// Key Vault Configuration
@description('SKU name for the Key Vault.')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Enable RBAC authorization for Key Vault access control.')
param enableRbacAuthorization bool = true

@description('Enable soft delete for Key Vault recovery.')
param enableSoftDelete bool = true

@description('Soft delete retention period in days.')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = environment == 'prod' ? 90 : (environment == 'test' ? 30 : 7)

@description('Enable purge protection to prevent purging of deleted items during retention period.')
param enablePurgeProtection bool = environment == 'prod' ? true : false

@description('Enable Key Vault for deployment (allows Azure deployments to access secrets/certificates).')
param enabledForDeployment bool = false

@description('Enable Key Vault for disk encryption (allows Azure Disk Encryption to access secrets).')
param enabledForDiskEncryption bool = false

@description('Enable Key Vault for template deployment (allows ARM templates to access secrets).')
param enabledForTemplateDeployment bool = false

// Security Parameters
@description('Object ID of the AAD user or service principal for initial access policy. Only used when RBAC authorization is disabled.')
param administratorObjectId string = ''

@description('Array of access policies to assign to Key Vault. Only used when RBAC authorization is disabled.')
param accessPolicies array = []

@description('Principal ID for Key Vault Administrator role assignment. Only used when RBAC authorization is enabled.')
param keyVaultAdministratorPrincipalId string = ''

@description('Principal type for Key Vault Administrator role assignment.')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param keyVaultAdministratorPrincipalType string = 'ServicePrincipal'

@description('Principal ID for Key Vault Secrets User role assignment. Only used when RBAC authorization is enabled.')
param keyVaultSecretsUserPrincipalId string = ''

@description('Principal type for Key Vault Secrets User role assignment.')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param keyVaultSecretsUserPrincipalType string = 'ServicePrincipal'

@description('Principal ID for Key Vault Certificates Officer role assignment. Only used when RBAC authorization is enabled.')
param keyVaultCertificatesOfficerPrincipalId string = ''

@description('Principal type for Key Vault Certificates Officer role assignment.')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param keyVaultCertificatesOfficerPrincipalType string = 'ServicePrincipal'

// Network Configuration
@description('Enable public network access to Key Vault.')
param publicNetworkAccess bool = environment == 'dev' ? true : false

@description('Network access control action (Allow/Deny).')
@allowed([
  'Allow'
  'Deny'
])
param networkAclDefaultAction string = environment == 'prod' ? 'Deny' : 'Allow'

@description('Allowed IP ranges in CIDR notation.')
param ipRules array = []

@description('Virtual network subnet resource IDs to allow.')
param virtualNetworkRules array = []

@description('Enable private endpoint for Key Vault.')
param enablePrivateEndpoint bool = environment == 'prod' ? true : false

@description('Virtual network name for private endpoint.')
param privateEndpointVnetName string = ''

@description('Subnet name for private endpoint.')
param privateEndpointSubnetName string = ''

@description('Resource group of virtual network for private endpoint.')
param privateEndpointVnetResourceGroup string = resourceGroup().name

// Monitoring and Diagnostics
@description('Enable monitoring with Log Analytics.')
param enableMonitoring bool = true

@description('Log Analytics workspace resource ID. If empty, a new workspace will be created.')
param existingLogAnalyticsWorkspaceId string = ''

@description('Log Analytics workspace retention days.')
param logAnalyticsRetentionDays int = environment == 'prod' ? 90 : 30

@description('Enable availability alerts.')
param enableAvailabilityAlerts bool = environment == 'prod' ? true : false

@description('Email addresses for alerts.')
param alertEmailAddresses array = []

// Backup and Recovery
@description('Enable automatic backup.')
param enableBackup bool = environment == 'prod' ? true : false

@description('Storage account name for backups.')
param backupStorageAccountName string = ''

@description('Storage container name for backups.')
param backupContainerName string = 'keyvaultbackups'

@description('Backup retention days.')
@minValue(7)
@maxValue(365)
param backupRetentionDays int = environment == 'prod' ? 90 : 30

// Certificate Management
@description('Enable certificate management.')
param enableCertificateManagement bool = false

@description('Certificate issuer configurations.')
param certificateIssuers array = []

// Initial Secrets
@description('Array of initial secrets to create in Key Vault {name, value, contentType, enabled}.')
@secure()
param initialSecrets array = []

// Tagging
@description('Additional tags to apply.')
param additionalTags object = {}

// Variables
var resourceTags = union({
  Environment: environment
  Department: department
  CreatedBy: 'EAF'
  CreatedDate: utcNow('yyyy-MM-dd')
  ResourceType: 'KeyVault'
  SecurityTier: environment == 'prod' ? 'Critical' : (environment == 'test' ? 'High' : 'Standard')
  DataClassification: environment == 'prod' ? 'Confidential' : 'Internal'
  CostCenter: '${department}-${environment}'
}, additionalTags)

var lawName = empty(existingLogAnalyticsWorkspaceId) ? '${environment}-${department}-law' : ''

// Role definition IDs
var keyVaultAdministratorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
var keyVaultSecretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
var keyVaultCertificatesOfficerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a4417e6f-fecd-4de8-b567-7b0420556985')

// Key Vault Resource
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  tags: resourceTags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: skuName
    }
    enableRbacAuthorization: enableRbacAuthorization
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: enablePurgeProtection ? true : null
    enabledForDeployment: enabledForDeployment
    enabledForDiskEncryption: enabledForDiskEncryption
    enabledForTemplateDeployment: enabledForTemplateDeployment
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: networkAclDefaultAction
      ipRules: [for ipRule in ipRules: {
        value: ipRule
      }]
      virtualNetworkRules: [for vnetRule in virtualNetworkRules: {
        id: vnetRule
      }]
    }
    accessPolicies: !enableRbacAuthorization ? concat(
      !empty(administratorObjectId) ? [
        {
          tenantId: subscription().tenantId
          objectId: administratorObjectId
          permissions: {
            keys: [
              'Get'
              'List'
              'Update'
              'Create'
              'Import'
              'Delete'
              'Recover'
              'Backup'
              'Restore'
            ]
            secrets: [
              'Get'
              'List'
              'Set'
              'Delete'
              'Recover'
              'Backup'
              'Restore'
            ]
            certificates: [
              'Get'
              'List'
              'Update'
              'Create'
              'Import'
              'Delete'
              'Recover'
              'Backup'
              'Restore'
              'ManageContacts'
              'ManageIssuers'
              'GetIssuers'
              'ListIssuers'
              'SetIssuers'
              'DeleteIssuers'
            ]
          }
        }
      ] : [], 
      accessPolicies
    ) : []
  }
}

// RBAC Role Assignments (if RBAC authorization is enabled)
resource keyVaultAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableRbacAuthorization && !empty(keyVaultAdministratorPrincipalId)) {
  name: guid(keyVault.id, keyVaultAdministratorPrincipalId, 'KeyVaultAdministrator')
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultAdministratorRoleId
    principalId: keyVaultAdministratorPrincipalId
    principalType: keyVaultAdministratorPrincipalType // Updated
  }
}

resource keyVaultSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableRbacAuthorization && !empty(keyVaultSecretsUserPrincipalId)) {
  name: guid(keyVault.id, keyVaultSecretsUserPrincipalId, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleId
    principalId: keyVaultSecretsUserPrincipalId
    principalType: keyVaultSecretsUserPrincipalType // Updated
  }
}

resource keyVaultCertificatesOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableRbacAuthorization && !empty(keyVaultCertificatesOfficerPrincipalId)) {
  name: guid(keyVault.id, keyVaultCertificatesOfficerPrincipalId, 'KeyVaultCertificatesOfficer')
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultCertificatesOfficerRoleId
    principalId: keyVaultCertificatesOfficerPrincipalId
    principalType: keyVaultCertificatesOfficerPrincipalType // Updated
  }
}

// Log Analytics Workspace for Monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableMonitoring && empty(existingLogAnalyticsWorkspaceId)) {
  name: lawName
  location: location
  tags: resourceTags
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

// Application Insights for Monitoring (Optional, depends on if Key Vault itself needs App Insights or just LAW)
resource appInsights 'Microsoft.Insights/components@2020-02-02' = if (enableMonitoring) {
  name: '${keyVaultName}-insights'
  location: location
  tags: resourceTags
  kind: 'web' // Generic kind, can be 'other' if not web-related
  properties: {
    Application_Type: 'other' // Changed from 'web' as Key Vault is not a web app
    Request_Source: 'rest' // Or other relevant source
    WorkspaceResourceId: empty(existingLogAnalyticsWorkspaceId) ? logAnalyticsWorkspace.id : existingLogAnalyticsWorkspaceId
    DisableIpMasking: false // Consider if IP masking is needed
    Flow_Type: 'Bluefield' // Default, may not be relevant
    IngestionMode: 'LogAnalytics'
  }
}

// Diagnostic Settings
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring) {
  name: '${keyVaultName}-diagnostics'
  scope: keyVault
  properties: {
    workspaceId: empty(existingLogAnalyticsWorkspaceId) ? logAnalyticsWorkspace.id : existingLogAnalyticsWorkspaceId
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
        retentionPolicy: {
          days: logAnalyticsRetentionDays
          enabled: true
        }
      }
      {
        category: 'AzurePolicyEvaluationDetails'
        enabled: true
        retentionPolicy: {
          days: logAnalyticsRetentionDays
          enabled: true
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: logAnalyticsRetentionDays
          enabled: true
        }
      }
    ]
  }
}

// Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2022-06-01' = if (enableMonitoring && enableAvailabilityAlerts && length(alertEmailAddresses) > 0) {
  name: '${keyVaultName}-ag'
  location: 'global' // Action groups are global
  tags: resourceTags
  properties: {
    groupShortName: 'KVAlerts-${keyVaultName}' // More specific short name
    enabled: true
    emailReceivers: [for email in alertEmailAddresses: {
      name: 'Email_${replace(email, '@', '_')}' // Create a valid name from email
      emailAddress: email
      useCommonAlertSchema: true
    }]
    // Potentially add SMS or other receivers here if needed
  }
}

// Metric Alerts (Example: Availability and Latency)
resource availabilityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring && enableAvailabilityAlerts) {
  name: '${keyVaultName}-AvailabilityAlert'
  location: 'global' // Alerts are global
  tags: resourceTags
  properties: {
    description: 'Alert when Key Vault availability drops below threshold.'
    severity: 1 // Critical
    enabled: true
    scopes: [ keyVault.id ]
    evaluationFrequency: 'PT1M' // Evaluate every minute
    windowSize: 'PT5M' // Over the last 5 minutes
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'AvailabilityCriterion'
          metricNamespace: 'Microsoft.KeyVault/vaults'
          metricName: 'Availability'
          operator: 'LessThan'
          threshold: 99 // Alert if availability is less than 99%
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: length(alertEmailAddresses) > 0 ? [
      {
        actionGroupId: actionGroup.id
      }
    ] : []
  }
}

resource latencyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring && enableAvailabilityAlerts) {
  name: '${keyVaultName}-LatencyAlert'
  location: 'global'
  tags: resourceTags
  properties: {
    description: 'Alert when Key Vault API latency is high.'
    severity: 2 // Warning
    enabled: true
    scopes: [ keyVault.id ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'LatencyCriterion'
          metricNamespace: 'Microsoft.KeyVault/vaults'
          metricName: 'ServiceApiLatency'
          operator: 'GreaterThan'
          threshold: environment == 'prod' ? 500 : 1000 // Example thresholds (ms)
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: length(alertEmailAddresses) > 0 ? [
      {
        actionGroupId: actionGroup.id
      }
    ] : []
  }
}

// Outputs
output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultName string = keyVault.name
output keyVaultResourceId string = keyVault.id // Duplicate of keyVaultId, consider removing one
output rbacEnabled bool = enableRbacAuthorization
output softDeleteEnabled bool = enableSoftDelete
output purgeProtectionEnabled bool = enablePurgeProtection
output privateEndpointEnabled bool = enablePrivateEndpoint
output monitoringEnabled bool = enableMonitoring
output logAnalyticsWorkspaceName string = enableMonitoring && empty(existingLogAnalyticsWorkspaceId) ? logAnalyticsWorkspace.name : ''
output appInsightsName string = enableMonitoring ? appInsights.name : ''
