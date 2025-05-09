@description('Name of the App Service.')
param appServiceName string

@description('Name of the App Service Plan.')
param appServicePlanName string = '${appServiceName}-plan'

@description('SKU name for the App Service Plan.')
@allowed([
  'F1'
  'D1'
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'P1v2'
  'P2v2'
  'P3v2'
])
param skuName string = 'S1'

@description('SKU capacity for the App Service Plan.')
param skuCapacity int = 1

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Runtime stack of the web app.')
@allowed([
  'dotnet'
  'node'
  'python'
  'java'
  'php'
])
param runtimeStack string = 'dotnet'

@description('Runtime version.')
param runtimeVersion string = '6.0'

@description('Boolean indicating whether the App Service should be configured for HTTPS-only traffic.')
param httpsOnly bool = true

@description('Enable Always On for the App Service.')
param alwaysOn bool = true

@description('Enable deployment slots.')
param enableDeploymentSlots bool = false

@description('Number of deployment slots to create.')
@minValue(0)
@maxValue(5)
param deploymentSlotsCount int = 1

@description('Names of deployment slots to create.')
param deploymentSlotNames array = ['staging']

@description('Enable auto-swap for the staging slot.')
param enableAutoSwap bool = false

@description('Enable auto-scale for the App Service Plan.')
param enableAutoScale bool = false

@description('Minimum instance count for auto-scaling.')
@minValue(1)
@maxValue(20)
param autoScaleMinInstanceCount int = 1

@description('Maximum instance count for auto-scaling.')
@minValue(1)
@maxValue(20)
param autoScaleMaxInstanceCount int = 5

@description('Default instance count for auto-scaling.')
@minValue(1)
@maxValue(20)
param autoScaleDefaultInstanceCount int = 2

@description('CPU percentage threshold for scale out.')
@minValue(50)
@maxValue(90)
param cpuPercentageScaleOut int = 70

@description('CPU percentage threshold for scale in.')
@minValue(20)
@maxValue(40)
param cpuPercentageScaleIn int = 30

@description('Enable container deployment.')
param enableContainerDeployment bool = false

@description('Container registry server.')
param containerRegistryServer string = ''

@description('Container registry username.')
param containerRegistryUsername string = ''

@description('Container registry password.')
@secure()
param containerRegistryPassword string = ''

@description('Container image and tag.')
param containerImageAndTag string = ''

@description('Enable custom domain.')
param enableCustomDomain bool = false

@description('Custom domain name.')
param customDomainName string = ''

@description('Enable SSL binding.')
param enableSslBinding bool = false

@description('SSL certificate thumbprint.')
param sslCertificateThumbprint string = ''

@description('Enable backup for the App Service.')
param enableBackup bool = false

@description('Storage account name for backups.')
param backupStorageAccountName string = ''

@description('Storage account container name for backups.')
param backupStorageContainerName string = 'appservicebackups'

@description('Backup schedule in cron expression format.')
param backupSchedule string = '0 0 * * *'

@description('Backup retention period in days.')
@minValue(1)
@maxValue(365)
param backupRetentionPeriodDays int = 30

@description('Environment (dev, test, prod).')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Department or team responsible for the resource.')
param department string

@description('Date of creation or last update (YYYY-MM-DD).')
param dateCreated string = utcNow('yyyy-MM-dd')

// Required tags for compliance
var resourceTags = {
  Environment: environment
  Department: department
  CreatedDate: dateCreated
  ResourceType: 'AppService'
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2021-02-01' = {
  name: appServicePlanName
  location: location
  tags: resourceTags
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  kind: 'app'
  properties: {
    reserved: runtimeStack == 'node' || runtimeStack == 'python' || runtimeStack == 'php' || enableContainerDeployment // For Linux App Service Plan
    targetWorkerCount: skuCapacity
    targetWorkerSizeId: 0
  }
}

// Auto-scale settings
resource autoScaleSettings 'Microsoft.Insights/autoscalesettings@2021-05-01-preview' = if (enableAutoScale) {
  name: '${appServicePlanName}-autoscale'
  location: location
  tags: resourceTags
  properties: {
    enabled: true
    targetResourceUri: appServicePlan.id
    profiles: [
      {
        name: 'Auto-scale profile'
        capacity: {
          minimum: string(autoScaleMinInstanceCount)
          maximum: string(autoScaleMaxInstanceCount)
          default: string(autoScaleDefaultInstanceCount)
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: cpuPercentageScaleOut
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT10M'
            }
          }
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: cpuPercentageScaleIn
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT10M'
            }
          }
          {
            metricTrigger: {
              metricName: 'MemoryPercentage'
              metricResourceUri: appServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 80
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT10M'
            }
          }
        ]
      }
    ]
    predictiveAutoscalePolicy: {
      scaleMode: 'Disabled'
    }
    notifications: [
      {
        email: {
          sendToSubscriptionAdministrator: true
          sendToSubscriptionCoAdministrators: true
          customEmails: []
        }
      }
    ]
  }
}

// App Service
// Application Insights (moved up to avoid circular dependencies)
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${appServiceName}-insights'
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: workspace.id
  }
  dependsOn: [
    workspace
  ]
}

// App Service
resource appService 'Microsoft.Web/sites@2021-02-01' = {
  name: appServiceName
  location: location
  tags: resourceTags
  kind: contains(runtimeStack, 'node') || contains(runtimeStack, 'python') || contains(runtimeStack, 'php') || enableContainerDeployment ? 'app,linux' : 'app'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: httpsOnly
    siteConfig: {
      alwaysOn: alwaysOn
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      linuxFxVersion: enableContainerDeployment && !empty(containerRegistryServer) && !empty(containerImageAndTag)
        ? 'DOCKER|${containerRegistryServer}/${containerImageAndTag}' 
        : (contains(runtimeStack, 'node') || contains(runtimeStack, 'python') || contains(runtimeStack, 'php') ? '${runtimeStack}|${runtimeVersion}' : '')
      netFrameworkVersion: contains(runtimeStack, 'dotnet') ? 'v${runtimeVersion}' : ''
      javaVersion: contains(runtimeStack, 'java') ? runtimeVersion : null
      webSocketsEnabled: true
      appSettings: concat([
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${appInsights.properties.InstrumentationKey}'
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
      ], 
      (!enableContainerDeployment) ? [
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ] : [],
      (enableContainerDeployment && !empty(containerRegistryServer)) ? [
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://${containerRegistryServer}'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_USERNAME'
          value: containerRegistryUsername
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_PASSWORD'
          value: containerRegistryPassword
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'true'
        }
      ] : [])
      cors: {
        allowedOrigins: [
          'https://*.${environment}.example.com'
        ]
        supportCredentials: false
      }
      ipSecurityRestrictions: [
        {
          ipAddress: 'Any'
          action: 'Allow'
          priority: 1
          name: 'Allow all'
          description: 'Allow all access'
        }
      ]
    }
  }
}

// App Service Custom Domain
resource customDomain 'Microsoft.Web/sites/hostNameBindings@2021-02-01' = if (enableCustomDomain && !empty(customDomainName)) {
  name: '${appServiceName}/${customDomainName}'
  properties: {
    hostNameType: 'Verified'
    sslState: enableSslBinding && !empty(sslCertificateThumbprint) ? 'SniEnabled' : 'Disabled'
    thumbprint: enableSslBinding && !empty(sslCertificateThumbprint) ? sslCertificateThumbprint : null
  }
  dependsOn: [
    appService
  ]
}

// App Service Backup Configuration
resource backupConfiguration 'Microsoft.Web/sites/config@2021-02-01' = if (enableBackup && !empty(backupStorageAccountName)) {
  name: '${appServiceName}/backup'
  properties: {
    backupSchedule: {
      frequencyInterval: 1
      frequencyUnit: 'Day'
      keepAtLeastOneBackup: true
      retentionPeriodInDays: backupRetentionPeriodDays
      startTime: dateTimeAdd(utcNow(), 'PT1H')
    }
    enabled: true
    storageAccountUrl: 'https://${backupStorageAccountName}.blob.${environment().suffixes.storage}/${backupStorageContainerName}?${listAccountSas(resourceId('Microsoft.Storage/storageAccounts', backupStorageAccountName), '2021-04-01', {
      signedServices: 'b'
      signedResourceTypes: 'sco'
      signedPermission: 'rwdl'
      signedExpiry: dateTimeAdd(utcNow(), 'P10Y')
    }).accountSasToken}'
  }
  dependsOn: [
    appService
  ]
}

// Deployment Slots
// Validate deployment slots configuration
var validatedDeploymentSlots = enableDeploymentSlots && length(deploymentSlotNames) > 0 
  ? (deploymentSlotsCount < length(deploymentSlotNames) 
      ? take(deploymentSlotNames, deploymentSlotsCount) 
      : deploymentSlotNames)
  : []

resource deploymentSlots 'Microsoft.Web/sites/slots@2021-02-01' = [for (slotName, index) in validatedDeploymentSlots: {
  name: '${appServiceName}/${slotName}'
  location: location
  tags: resourceTags
  kind: contains(runtimeStack, 'node') || contains(runtimeStack, 'python') || contains(runtimeStack, 'php') || enableContainerDeployment ? 'app,linux' : 'app'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: httpsOnly
    autoSwapSlotName: (enableAutoSwap && slotName == 'staging') ? 'production' : null
    siteConfig: {
      alwaysOn: alwaysOn
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      linuxFxVersion: enableContainerDeployment 
        ? 'DOCKER|${containerRegistryServer}/${containerImageAndTag}' 
        : (contains(runtimeStack, 'node') || contains(runtimeStack, 'python') || contains(runtimeStack, 'php') ? '${runtimeStack}|${runtimeVersion}' : '')
      netFrameworkVersion: contains(runtimeStack, 'dotnet') ? 'v${runtimeVersion}' : ''
      javaVersion: contains(runtimeStack, 'java') ? runtimeVersion : null
      webSocketsEnabled: true
      appSettings: concat([
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${appInsights.properties.InstrumentationKey}'
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'SLOT_NAME'
          value: slotName
        }
      ], 
      (!enableContainerDeployment) ? [
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ] : [],
      (enableContainerDeployment && !empty(containerRegistryServer)) ? [
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://${containerRegistryServer}'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_USERNAME'
          value: containerRegistryUsername
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_PASSWORD'
          value: containerRegistryPassword
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'true'
        }
      ] : [])
      cors: {
        allowedOrigins: [
          'https://*.${environment}.example.com'
        ]
        supportCredentials: false
      }
    }
  }
  dependsOn: [
    appService
    appInsights
  ]
}]

// Slot Diagnostics Settings
resource slotDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = [for (slotName, index) in validatedDeploymentSlots: {
  name: '${appServiceName}-${slotName}-diagnostics'
  scope: resourceId('Microsoft.Web/sites/slots', appServiceName, slotName)
  properties: {
    workspaceId: workspace.id
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
  }
  dependsOn: [
    deploymentSlots[index]
    workspace
  ]
}]

// Log Analytics Workspace
resource workspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: '${environment}-${department}-law'
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Diagnostic settings
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${appServiceName}-diagnostics'
  scope: appService
  properties: {
    workspaceId: workspace.id
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AppServiceAuditLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AppServiceIPSecAuditLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
  }
}

// Outputs
output appServiceName string = appService.name
output appServiceUrl string = 'https://${appService.properties.defaultHostName}'
output appServiceId string = appService.id
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output appServicePrincipalId string = appService.identity.principalId
output deploymentSlotsEnabled bool = enableDeploymentSlots && length(validatedDeploymentSlots) > 0
output deploymentSlots array = validatedDeploymentSlots
output deploymentSlotsUrls array = length(validatedDeploymentSlots) > 0 ? [for slotName in validatedDeploymentSlots: 'https://${appServiceName}-${slotName}.azurewebsites.net'] : []
output autoScalingEnabled bool = enableAutoScale
output containerDeploymentEnabled bool = enableContainerDeployment
output customDomainEnabled bool = enableCustomDomain && !empty(customDomainName)
output backupEnabled bool = enableBackup && !empty(backupStorageAccountName)
