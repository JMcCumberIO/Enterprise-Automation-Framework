# Monitoring Helper Functions for EAF.AzureProvisioning
# This module provides functions for configuring diagnostic settings, log analytics, and metrics

using namespace System
using namespace System.Management.Automation

# Import custom exception types if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'EAFResourceValidationException').Type) {
    $exceptionModulePath = Join-Path -Path $PSScriptRoot -ChildPath "exceptions.psm1"
    if (Test-Path $exceptionModulePath) {
        Import-Module $exceptionModulePath -Force
    }
}

# Import configuration helpers if not already loaded
if (-not (Get-Command -Name 'Get-EAFConfiguration' -ErrorAction SilentlyContinue)) {
    $configModulePath = Join-Path -Path $PSScriptRoot -ChildPath "configuration-helpers.psm1"
    if (Test-Path $configModulePath) {
        Import-Module $configModulePath -Force
    }
}

<#
.SYNOPSIS
    Gets or creates a Log Analytics workspace for the specified environment and department.
    
.DESCRIPTION
    The Get-EAFLogAnalyticsWorkspace function retrieves an existing Log Analytics workspace or
    creates a new one if it doesn't exist, based on EAF naming conventions and configuration.
    
.PARAMETER ResourceGroupName
    The name of the resource group where the workspace should be located.
    
.PARAMETER Environment
    The deployment environment (dev, test, prod).
    
.PARAMETER Department
    The department or business unit responsible for the resource.
    
.PARAMETER Location
    The Azure region for the workspace. If not provided, uses the default region from EAF configuration.
    
.PARAMETER SkuName
    The SKU for the Log Analytics workspace. Default is PerGB2018.
    
.PARAMETER RetentionInDays
    The number of days to retain data in the workspace.
    
.PARAMETER Tags
    Additional tags to apply to the workspace.
    
.PARAMETER CreateIfNotExist
    If set to $true, creates the workspace if it doesn't exist. Default is $true.
    
.EXAMPLE
    Get-EAFLogAnalyticsWorkspace -ResourceGroupName "rg-monitoring-prod" -Environment "prod" -Department "IT"
    
.EXAMPLE
    $workspace = Get-EAFLogAnalyticsWorkspace -ResourceGroupName "rg-monitoring-dev" -Environment "dev" -Department "Marketing" -RetentionInDays 30
    
.OUTPUTS
    [Microsoft.Azure.Commands.OperationalInsights.Models.PSWorkspace] The Log Analytics workspace object.
#>
function Get-EAFLogAnalyticsWorkspace {
    [CmdletBinding()]
    [OutputType([Microsoft.Azure.Commands.OperationalInsights.Models.PSWorkspace])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$Environment,
        
        [Parameter(Mandatory = $true)]
        [string]$Department,
        
        [Parameter(Mandatory = $false)]
        [string]$Location = '',
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Free', 'Standard', 'Premium', 'PerNode', 'PerGB2018', 'Standalone')]
        [string]$SkuName = 'PerGB2018',
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(30, 730)]
        [int]$RetentionInDays = 0,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Tags = @{},
        
        [Parameter(Mandatory = $false)]
        [bool]$CreateIfNotExist = $true
    )
    
    try {
        # Get workspace name based on EAF naming convention and configuration
        $workspaceNameSuffix = Get-EAFConfiguration -ConfigPath "Monitoring.LogAnalyticsWorkspace.SuffixFormat" -Environment $Environment -Department $Department
        if (-not $workspaceNameSuffix) {
            $workspaceNameSuffix = "$Environment-$Department-law"
        }
        
        $workspaceName = Get-EAFResourceName -BaseName $Department -ResourceType "LogAnalyticsWorkspace" -Environment $Environment
        
        # If no location specified, use default from configuration
        if ([string]::IsNullOrEmpty($Location)) {
            $Location = Get-EAFConfiguration -ConfigPath "Regions.Default.$Environment"
            
            if ([string]::IsNullOrEmpty($Location)) {
                throw [EAFResourceValidationException]::new(
                    "No location specified and no default location found in configuration for environment '$Environment'.",
                    "LogAnalyticsWorkspace",
                    $workspaceName,
                    "Location",
                    "NotSpecified"
                )
            }
        }
        
        # If no retention specified, get from configuration
        if ($RetentionInDays -eq 0) {
            $RetentionInDays = Get-EAFConfiguration -ConfigPath "Monitoring.DiagnosticSettings.RetentionDays.$Environment"
            
            if ($RetentionInDays -eq 0 -or $null -eq $RetentionInDays) {
                # Set defaults based on environment
                $RetentionInDays = switch ($Environment) {
                    'dev' { 30 }
                    'test' { 90 }
                    'prod' { 365 }
                    default { 30 }
                }
            }
        }
        
        # Validate resource group exists
        $rgExists = Test-EAFResourceGroupExists -ResourceGroupName $ResourceGroupName -ThrowOnNotExist $false
        if (-not $rgExists) {
            if ($CreateIfNotExist) {
                Write-Verbose "Resource group '$ResourceGroupName' does not exist. Creating..."
                New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force | Out-Null
            }
            else {
                throw [EAFDependencyException]::new(
                    "Resource group '$ResourceGroupName' does not exist and CreateIfNotExist is set to false.",
                    "LogAnalyticsWorkspace",
                    $workspaceName,
                    "ResourceGroup",
                    $ResourceGroupName,
                    "NotFound"
                )
            }
        }
        
        # Get default tags and add any custom tags
        $defaultTags = Get-EAFDefaultTags -Environment $Environment -Department $Department -ResourceType "LogAnalyticsWorkspace"
        $combinedTags = $defaultTags.Clone()
        
        foreach ($key in $Tags.Keys) {
            $combinedTags[$key] = $Tags[$key]
        }
        
        # Check if workspace already exists
        $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $workspaceName -ErrorAction SilentlyContinue
        
        if (-not $workspace -and $CreateIfNotExist) {
            Write-Verbose "Creating Log Analytics workspace '$workspaceName' in resource group '$ResourceGroupName'..."
            
            $workspace = New-AzOperationalInsightsWorkspace `
                -ResourceGroupName $ResourceGroupName `
                -Name $workspaceName `
                -Location $Location `
                -Sku $SkuName `
                -RetentionInDays $RetentionInDays `
                -Tag $combinedTags
                
            Write-Verbose "Log Analytics workspace created successfully."
        }
        elseif (-not $workspace) {
            throw [EAFDependencyException]::new(
                "Log Analytics workspace '$workspaceName' does not exist and CreateIfNotExist is set to false.",
                "LogAnalyticsWorkspace",
                $workspaceName,
                "LogAnalyticsWorkspace",
                $workspaceName,
                "NotFound"
            )
        }
        else {
            Write-Verbose "Log Analytics workspace '$workspaceName' already exists."
        }
        
        return $workspace
    }
    catch {
        if ($_.Exception -is [EAFDependencyException] -or $_.Exception -is [EAFResourceValidationException]) {
            throw
        }
        
        throw [EAFDependencyException]::new(
            "Error creating or retrieving Log Analytics workspace: $($_.Exception.Message)",
            "LogAnalyticsWorkspace",
            $workspaceName,
            "LogAnalyticsWorkspace",
            "Error",
            $_.Exception.Message
        )
    }
}

<#
.SYNOPSIS
    Enables diagnostic settings for an Azure resource.
    
.DESCRIPTION
    The Enable-EAFDiagnosticSettings function configures diagnostic settings for an Azure resource,
    sending logs and metrics to a Log Analytics workspace based on EAF standards.
    
.PARAMETER ResourceId
    The resource ID of the Azure resource to configure diagnostics for.
    
.PARAMETER LogAnalyticsWorkspaceId
    The resource ID of the Log Analytics workspace to send diagnostics to.
    If not provided, a workspace will be retrieved or created using Get-EAFLogAnalyticsWorkspace.
    
.PARAMETER ResourceGroupName
    The name of the resource group where the Log Analytics workspace should be located.
    Only used if LogAnalyticsWorkspaceId is not provided.
    
.PARAMETER DiagnosticSettingName
    The name for the diagnostic setting. Default is '{resourceName}-diagnostics'.
    
.PARAMETER Categories
    An array of log categories to enable. If empty, all available categories will be enabled.
    
.PARAMETER MetricCategories
    An array of metric categories to enable. If empty, all available metrics will be enabled.
    
.PARAMETER RetentionInDays
    The number of days to retain diagnostic data. Default is based on environment.
    
.PARAMETER Environment
    The deployment environment (dev, test, prod).
    
.PARAMETER Department
    The department or business unit responsible for the resource.
    
.EXAMPLE
    Enable-EAFDiagnosticSettings -ResourceId "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod/providers/Microsoft.Storage/storageAccounts/stprodapp" -ResourceGroupName "rg-monitoring-prod" -Environment "prod" -Department "IT"
    
.EXAMPLE
    $workspace = Get-EAFLogAnalyticsWorkspace -ResourceGroupName "rg-monitoring-dev" -Environment "dev" -Department "IT"
    Enable-EAFDiagnosticSettings -ResourceId $storageAccount.Id -LogAnalyticsWorkspaceId $workspace.ResourceId -Categories @('StorageRead', 'StorageWrite', 'StorageDelete')
    
.OUTPUTS
    [Microsoft.Azure.Commands.Insights.OutputClasses.PSServiceDiagnosticSettings] The diagnostic settings object.
#>
function Enable-EAFDiagnosticSettings {
    [CmdletBinding()]
    [OutputType([Microsoft.Azure.Commands.Insights.OutputClasses.PSServiceDiagnosticSettings])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceId,
        
        [Parameter(Mandatory = $false)]
        [string]$LogAnalyticsWorkspaceId = '',
        
        [Parameter(Mandatory = $false)]
        [string]$ResourceGroupName = 'rg-monitoring',
        
        [Parameter(Mandatory = $false)]
        [string]$DiagnosticSettingName = '',
        
        [Parameter(Mandatory = $false)]
        [string[]]$Categories = @(),
        
        [Parameter(Mandatory = $false)]
        [string[]]$MetricCategories = @('AllMetrics'),
        
        [Parameter(Mandatory = $false)]
        [int]$RetentionInDays = 0,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$Environment,
        
        [Parameter(Mandatory = $true)]
        [string]$Department
    )
    
    try {
        # Extract resource name from resource ID for naming
        $resourceName = $ResourceId.Split('/')[-1]
        
        # If diagnostic setting name not provided, use default naming
        if ([string]::IsNullOrEmpty($DiagnosticSettingName)) {
            $DiagnosticSettingName = "$resourceName-diagnostics"
        }
        
        # If Log Analytics workspace ID not provided, get or create one
        if ([string]::IsNullOrEmpty($LogAnalyticsWorkspaceId)) {
            $workspace = Get-EAFLogAnalyticsWorkspace `
                -ResourceGroupName $ResourceGroupName `
                -Environment $Environment `
                -Department $Department
                
            $LogAnalyticsWorkspaceId = $workspace.ResourceId
        }
        
        # If no retention specified, get from configuration
        if ($RetentionInDays -eq 0) {
            $RetentionInDays = Get-EAFConfiguration -ConfigPath "Monitoring.DiagnosticSettings.RetentionDays.$Environment"
            
            if ($RetentionInDays -eq 0 -or $null -eq $RetentionInDays) {
                # Set defaults based on environment
                $RetentionInDays = switch ($Environment) {
                    'dev' { 30 }
                    'test' { 90 }
                    'prod' { 365 }
                    default { 30 }
                }
            }
        }
        
        # Check if the resource exists
        $resource = Get-AzResource -ResourceId $ResourceId -ErrorAction SilentlyContinue
        if (-not $resource) {
            throw [EAFDependencyException]::new(
                "Resource with ID '$ResourceId' not found.",
                "DiagnosticSettings",
                $DiagnosticSettingName,
                "Resource",
                $resourceName,
                "NotFound"
            )
        }
        
        # Check if diagnostic setting already exists
        $existingSettings = Get-AzDiagnosticSetting -ResourceId $ResourceId -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -eq $DiagnosticSettingName }
        
        # If categories not specified, get all available categories for the resource
        if ($Categories.Count -eq 0) {
            $availableCategories = Get-AzDiagnosticSettingCategory -ResourceId $ResourceId | 
                Where-Object { $_.CategoryType -eq 'Logs' }
            
            $Categories = $availableCategories | Select-Object -ExpandProperty Name
        }
        
        # Configure the logs and metrics parameters
        $logs = @()
        foreach ($category in $Categories) {
            $logs += @{
                Category = $category
                Enabled = $true
                RetentionPolicy = @{
                    Enabled = $true
                    Days = $RetentionInDays
                }
            }
        }
        
        $metrics = @()
        foreach ($metricCategory in $MetricCategories) {
            $metrics += @{
                Category = $metricCategory
                Enabled = $true
                RetentionPolicy = @{
                    Enabled = $true
                    Days = $RetentionInDays
                }
            }
        }
        
        # Create or update diagnostic setting
        if ($existingSettings) {
            Write-Verbose "Updating existing diagnostic setting '$DiagnosticSettingName' for '$resourceName'..."
            
            $diagnosticSettings = Set-AzDiagnosticSetting `
                -ResourceId $ResourceId `
                -Name $DiagnosticSettingName `
                -WorkspaceId $LogAnalyticsWorkspaceId `
                -Enabled $true `
                -Category $Categories `
                -MetricCategory $MetricCategories
        }
        else {
            Write-Verbose "Creating new diagnostic setting '$DiagnosticSettingName' for '$resourceName'..."
            
            $diagnosticSettings = New-AzDiagnosticSetting `
                -ResourceId $ResourceId `
                -Name $DiagnosticSettingName `
                -WorkspaceId $LogAnalyticsWorkspaceId `
                -Enabled $true `
                -Category $Categories `
                -MetricCategory $MetricCategories
        }
        
        Write-Verbose "Diagnostic settings configured successfully."
        return $diagnosticSettings
    }
    catch {
        if ($_.Exception -is [EAFDependencyException] -or $_.Exception -is [EAFResourceValidationException]) {
            throw
        }
        
        throw [EAFDependencyException]::new(
            "Error configuring diagnostic settings: $($_.Exception.Message)",
            "DiagnosticSettings",
            $DiagnosticSettingName,
            "DiagnosticSettings",
            "Error",
            $_.Exception.Message
        )
    }
}

<#
.SYNOPSIS
    Creates or updates an Azure Monitor action group.
    
.DESCRIPTION
    The New-EAFActionGroup function creates or updates an action group for Azure Monitor alerts,
    configuring email, SMS, webhook, and other notification methods.
    
.PARAMETER ResourceGroupName
    The name of the resource group where the action group will be created.
    
.PARAMETER ActionGroupName
    The name of the action group. If not provided, a name will be generated based on EAF standards.
    
.PARAMETER ShortName
    A short name for the action group (max 12 characters). This appears in SMS and emails.
    
.PARAMETER EmailRecipients
    An array of email addresses to notify.
    
.PARAMETER EmailSubject
    The subject line to use for email notifications.
    
.PARAMETER SmsRecipients
    A hashtable of SMS recipients. Format: @{Name = 'name'; CountryCode = '1'; PhoneNumber = '1234567890'}
    
.PARAMETER WebhookReceivers
    A hashtable of webhook receivers. Format: @{Name = 'name'; ServiceUri = 'https://example.com/webhook'}
    
.PARAMETER Environment
    The deployment environment (dev, test, prod).
    
.PARAMETER Department
    The department or business unit responsible for the resource.
    
.PARAMETER Location
    The Azure region for the resource. If not provided, uses the default region from EAF configuration.
    
.PARAMETER Tags
    Additional tags to apply to the action group.
    
.EXAMPLE
    New-EAFActionGroup -ResourceGroupName "rg-monitoring-prod" -ShortName "ProdAlert" -EmailRecipients @("oncall@contoso.com") -Environment "prod" -Department "IT"
    
.EXAMPLE
    $params = @{
        ResourceGroupName = "rg-monitoring-dev"
        ShortName = "DevAlert"
        EmailRecipients = @("devteam@contoso.com")
        SmsRecipients = @(
            @{Name = "On-Call"; CountryCode = "1"; PhoneNumber = "5551234567"}
        )
        Environment = "dev"
        Department = "IT"
    }
    New-EAFActionGroup @params
    
.OUTPUTS
    [Microsoft.Azure.Commands.Insights.OutputClasses.PSActionGroupResource] The action group object.
#>
function New-EAFActionGroup {
    [CmdletBinding()]
    [OutputType([Microsoft.Azure.Commands.Insights.OutputClasses.PSActionGroupResource])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $false)]
        [string]$ActionGroupName = '',
        
        [Parameter(Mandatory = $true)]
        [ValidateLength(1, 12)]
        [string]$ShortName,
        
        [Parameter(Mandatory = $false)]
        [string[]]$EmailRecipients = @(),
        
        [Parameter(Mandatory = $false)]
        [string]$EmailSubject = '',
        
        [Parameter(Mandatory = $false)]
        [array]$SmsRecipients = @(),
        
        [Parameter(Mandatory = $false)]
        [array]$WebhookReceivers = @(),
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$Environment,
        
        [Parameter(Mandatory = $true)]
        [string]$Department,
        
        [Parameter(Mandatory = $false)]
        [string]$Location = '',
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Tags = @{}
    )
    
    try {
        # Generate action group name if not provided
        if ([string]::IsNullOrEmpty($ActionGroupName)) {
            $suffix = Get-EAFConfiguration -ConfigPath "Monitoring.Alerts.ActionGroupSuffix"
            if ([string]::IsNullOrEmpty($suffix)) {
                $suffix = "actiongroup"
            }
            
            $ActionGroupName = "ag-$Department-$Environment-$suffix"
        }
        
        # Get default location if not specified
        if ([string]::IsNullOrEmpty($Location)) {
            $Location = Get-EAFConfiguration -ConfigPath "Regions.Default.$Environment"
            
            if ([string]::IsNullOrEmpty($Location)) {
                throw [EAFResourceValidationException]::new(
                    "No location specified and no default location found in configuration for environment '$Environment'.",
                    "ActionGroup",
                    $ActionGroupName,
                    "Location",
                    "NotSpecified"
                )
            }
        }
        
        # Ensure resource group exists
        $rgExists = Test-EAFResourceGroupExists -ResourceGroupName $ResourceGroupName -ThrowOnNotExist $false
        if (-not $rgExists) {
            Write-Verbose "Resource group '$ResourceGroupName' does not exist. Creating..."
            New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force | Out-Null
        }
        
        # Get default tags and add any custom tags
        $defaultTags = Get-EAFDefaultTags -Environment $Environment -Department $Department -ResourceType "ActionGroup"
        $combinedTags = $defaultTags.Clone()
        
        foreach ($key in $Tags.Keys) {
            $combinedTags[$key] = $Tags[$key]
        }
        
        # If no email recipients specified, get from configuration
        if ($EmailRecipients.Count -eq 0) {
            $configEmailRecipients = Get-EAFConfiguration -ConfigPath "Monitoring.Alerts.EmailRecipients.$Environment"
            
            if ($configEmailRecipients -and $configEmailRecipients.Count -gt 0) {
                $EmailRecipients = $configEmailRecipients
            }
        }
        
        # Build the email receiver configuration
        $emailReceiverParams = @()
        foreach ($email in $EmailRecipients) {
            $receiverName = $email -replace '@', '_at_'
            $receiverName = $receiverName -replace '\.', '_'
            
            $emailReceiverParams += New-AzActionGroupReceiver `
                -Name $receiverName `
                -EmailReceiver `
                -EmailAddress $email `
                -UseCommonAlertSchema $true
        }
        
        # Build the SMS receiver configuration
        $smsReceiverParams = @()
        foreach ($sms in $SmsRecipients) {
            $smsReceiverParams += New-AzActionGroupReceiver `
                -Name $sms.Name `
                -SmsReceiver `
                -CountryCode $sms.CountryCode `
                -PhoneNumber $sms.PhoneNumber
        }
        
        # Build the webhook receiver configuration
        $webhookReceiverParams = @()
        foreach ($webhook in $WebhookReceivers) {
            $webhookReceiverParams += New-AzActionGroupReceiver `
                -Name $webhook.Name `
                -WebhookReceiver `
                -ServiceUri $webhook.ServiceUri `
                -UseCommonAlertSchema $true
        }
        
        # Combine all receivers
        $receivers = @() + $emailReceiverParams + $smsReceiverParams + $webhookReceiverParams
        
        # Check if action group already exists
        $existingActionGroup = Get-AzActionGroup -ResourceGroupName $ResourceGroupName -Name $ActionGroupName -ErrorAction SilentlyContinue
        
        if ($existingActionGroup) {
            Write-Verbose "Action group '$ActionGroupName' already exists. Updating..."
            
            $actionGroup = Set-AzActionGroup `
                -ResourceGroupName $ResourceGroupName `
                -Name $ActionGroupName `
                -ShortName $ShortName `
                -Receiver $receivers `
                -Tag $combinedTags
        }
        else {
            Write-Verbose "Creating new action group '$ActionGroupName'..."
            
            $actionGroup = New-AzActionGroup `
                -ResourceGroupName $ResourceGroupName `
                -Name $ActionGroupName `
                -ShortName $ShortName `
                -Receiver $receivers `
                -Tag $combinedTags
        }
        
        Write-Verbose "Action group configured successfully."
        return $actionGroup
    }
    catch {
        if ($_.Exception -is [EAFDependencyException] -or $_.Exception -is [EAFResourceValidationException]) {
            throw
        }
        
        throw [EAFDependencyException]::new(
            "Error creating or updating action group: $($_.Exception.Message)",
            "ActionGroup",
            $ActionGroupName,
            "ActionGroup",
            "Error",
            $_.Exception.Message
        )
    }
}

<#
.SYNOPSIS
    Creates or updates an Azure Monitor metric alert rule.
    
.DESCRIPTION
    The New-EAFMetricAlertRule function creates or updates a metric-based alert rule
    in Azure Monitor, configuring thresholds, conditions, and action groups.
    
.PARAMETER ResourceGroupName
    The name of the resource group where the alert rule will be created.
    
.PARAMETER TargetResourceId
    The resource ID of the Azure resource to monitor.
    
.PARAMETER AlertName
    The name of the alert rule. If not provided, a name will be generated based on the metric and resource.
    
.PARAMETER MetricName
    The name of the metric to monitor.
    
.PARAMETER Condition
    The condition operator for the alert. Valid values: 'GreaterThan', 'GreaterThanOrEqual', 'LessThan', 'LessThanOrEqual'.
    
.PARAMETER Threshold
    The threshold value that activates the alert.
    
.PARAMETER WindowSize
    The time window for the alert evaluation. Default is 5 minutes.
    
.PARAMETER Frequency
    The frequency of evaluating the alert condition. Default is 1 minute.
    
.PARAMETER Severity
    The severity level of the alert. Range: 0-4, where 0 is critical and 4 is verbose. Default is 2.
    
.PARAMETER ActionGroupResourceId
    The resource ID of the action group to trigger when the alert fires.
    If not provided, an action group will be created using New-EAFActionGroup.
    
.PARAMETER Environment
    The deployment environment (dev, test, prod).
    
.PARAMETER Department
    The department or business unit responsible for the resource.
    
.PARAMETER Description
    A description for the alert rule.
    
.PARAMETER Tags
    Additional tags to apply to the alert rule.
    
.EXAMPLE
    New-EAFMetricAlertRule -ResourceGroupName "rg-monitoring-prod" -TargetResourceId "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod/providers/Microsoft.Storage/storageAccounts/stprodapp" -MetricName "Transactions" -Condition "GreaterThan" -Threshold 1000 -Environment "prod" -Department "IT"
    
.EXAMPLE
    $actionGroup = New-EAFActionGroup -ResourceGroupName "rg-monitoring-dev" -ShortName "DevAlert" -EmailRecipients @("devteam@contoso.com") -Environment "dev" -Department "IT"
    
    New-EAFMetricAlertRule -ResourceGroupName "rg-monitoring-dev" -TargetResourceId $storageAccount.Id -AlertName "StorageHighUsage" -MetricName "UsedCapacity" -Condition "GreaterThan" -Threshold 85 -ActionGroupResourceId $actionGroup.Id -Environment "dev" -Department "IT" -Description "Alert when storage usage exceeds 85%"
    
.OUTPUTS
    [Microsoft.Azure.Commands.Insights.OutputClasses.PSMetricAlertResource] The metric alert rule object.
#>
function New-EAFMetricAlertRule {
    [CmdletBinding()]
    [OutputType([Microsoft.Azure.Commands.Insights.OutputClasses.PSMetricAlertResource])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetResourceId,
        
        [Parameter(Mandatory = $false)]
        [string]$AlertName = '',
        
        [Parameter(Mandatory = $true)]
        [string]$MetricName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('GreaterThan', 'GreaterThanOrEqual', 'LessThan', 'LessThanOrEqual')]
        [string]$Condition,
        
        [Parameter(Mandatory = $true)]
        [double]$Threshold,
        
        [Parameter(Mandatory = $false)]
        [TimeSpan]$WindowSize = [TimeSpan]::FromMinutes(5),
        
        [Parameter(Mandatory = $false)]
        [TimeSpan]$Frequency = [TimeSpan]::FromMinutes(1),
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 4)]
        [int]$Severity = 2,
        
        [Parameter(Mandatory = $false)]
        [string]$ActionGroupResourceId = '',
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$Environment,
        
        [Parameter(Mandatory = $true)]
        [string]$Department,
        
        [Parameter(Mandatory = $false)]
        [string]$Description = '',
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Tags = @{}
    )
    
    try {
        # Extract resource name and type from resource ID for naming
        $resourceType = ($TargetResourceId -split '/providers/')[1].Split('/')[0]
        $resourceName = $TargetResourceId.Split('/')[-1]
        
        # If alert name not provided, generate one
        if ([string]::IsNullOrEmpty($AlertName)) {
            $metricNameFormatted = $MetricName -replace '\s', ''
            $AlertName = "Alert-$resourceName-$metricNameFormatted-$Condition"
        }
        
        # Get default location from configuration if needed for action group
        $location = Get-EAFConfiguration -ConfigPath "Regions.Default.$Environment"
        
        # If action group not provided, create a default one
        if ([string]::IsNullOrEmpty($ActionGroupResourceId)) {
            Write-Verbose "No action group provided. Creating a default action group..."
            
            $shortName = "$Environment" + "Alert"
            if ($shortName.Length > 12) {
                $shortName = $shortName.Substring(0, 12)
            }
            
            $actionGroup = New-EAFActionGroup `
                -ResourceGroupName $ResourceGroupName `
                -ShortName $shortName `
                -Environment $Environment `
                -Department $Department
                
            $ActionGroupResourceId = $actionGroup.Id
        }
        
        # Build description if not provided
        if ([string]::IsNullOrEmpty($Description)) {
            $operatorText = switch ($Condition) {
                'GreaterThan' { 'exceeds' }
                'GreaterThanOrEqual' { 'equals or exceeds' }
                'LessThan' { 'falls below' }
                'LessThanOrEqual' { 'equals or falls below' }
            }
            
            $Description = "Alert when '$MetricName' $operatorText $Threshold for resource '$resourceName'"
        }
        
        # Get default tags and add any custom tags
        $defaultTags = Get-EAFDefaultTags -Environment $Environment -Department $Department -ResourceType "MetricAlert"
        $combinedTags = $defaultTags.Clone()
        
        foreach ($key in $Tags.Keys) {
            $combinedTags[$key] = $Tags[$key]
        }
        
        # Ensure resource group exists
        $rgExists = Test-EAFResourceGroupExists -ResourceGroupName $ResourceGroupName -CreateIfNotExist $true -Location $location -ThrowOnNotExist $false
        
        # Create the condition object
        $condition = New-AzMetricAlertRuleV2Criteria `
            -MetricName $MetricName `
            -TimeAggregation 'Average' `
            -Operator $Condition `
            -Threshold $Threshold
        
        # Check if alert rule already exists
        $existingAlert = Get-AzMetricAlertRuleV2 -ResourceGroupName $ResourceGroupName -Name $AlertName -ErrorAction SilentlyContinue
        
        # Format action group for alert
        $actionGroupConfig = @{
            ActionGroupId = $ActionGroupResourceId
            WebhookProperties = @{}
        }
        
        if ($existingAlert) {
            Write-Verbose "Alert rule '$AlertName' already exists. Updating..."
            
            $metricAlert = Update-AzMetricAlertRuleV2 `
                -ResourceGroupName $ResourceGroupName `
                -Name $AlertName `
                -Severity $Severity `
                -WindowSize $WindowSize `
                -Frequency $Frequency `
                -TargetResourceId $TargetResourceId `
                -Condition $condition `
                -ActionGroup $actionGroupConfig `
                -Description $Description `
                -Tag $combinedTags
        }
        else {
            Write-Verbose "Creating new alert rule '$AlertName'..."
            
            $metricAlert = Add-AzMetricAlertRuleV2 `
                -ResourceGroupName $ResourceGroupName `
                -Name $AlertName `
                -Severity $Severity `
                -WindowSize $WindowSize `
                -Frequency $Frequency `
                -TargetResourceId $TargetResourceId `
                -Condition $condition `
                -ActionGroup $actionGroupConfig `
                -Description $Description `
                -Tag $combinedTags
        }
        
        Write-Verbose "Metric alert rule configured successfully."
        return $metricAlert
    }
    catch {
        if ($_.Exception -is [EAFDependencyException] -or $_.Exception -is [EAFResourceValidationException]) {
            throw
        }
        
        throw [EAFDependencyException]::new(
            "Error creating or updating metric alert rule: $($_.Exception.Message)",
            "MetricAlert",
            $AlertName,
            "MetricAlert",
            "Error",
            $_.Exception.Message
        )
    }
}

<#
.SYNOPSIS
    Gets available metric definitions for an Azure resource.
    
.DESCRIPTION
    The Get-EAFResourceMetricDefinitions function retrieves the available metric definitions
    for an Azure resource, which can be used to create metric alerts.
    
.PARAMETER ResourceId
    The resource ID of the Azure resource to get metrics for.
    
.PARAMETER MetricNames
    An optional array of metric names to filter the results.
    
.PARAMETER DetailedOutput
    If set to $true, returns detailed metric information including units, dimensions, etc.
    If $false, returns a simple list of metric names. Default is $false.
    
.EXAMPLE
    Get-EAFResourceMetricDefinitions -ResourceId "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod/providers/Microsoft.Storage/storageAccounts/stprodapp"
    
.EXAMPLE
    Get-EAFResourceMetricDefinitions -ResourceId $storageAccount.Id -DetailedOutput $true | Where-Object { $_.Name.Value -like "*Capacity*" }
    
.OUTPUTS
    [string[]] or [Microsoft.Azure.Management.Monitor.Models.MetricDefinition[]] Metric names or detailed metric definitions.
#>
function Get-EAFResourceMetricDefinitions {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceId,
        
        [Parameter(Mandatory = $false)]
        [string[]]$MetricNames = @(),
        
        [Parameter(Mandatory = $false)]
        [bool]$DetailedOutput = $false
    )
    
    try {
        # Check if the resource exists
        $resource = Get-AzResource -ResourceId $ResourceId -ErrorAction SilentlyContinue
        if (-not $resource) {
            throw [EAFDependencyException]::new(
                "Resource with ID '$ResourceId' not found.",
                "MetricDefinitions",
                "Resource",
                "Resource",
                $ResourceId,
                "NotFound"
            )
        }
        
        # Get metric definitions
        $metricDefinitions = Get-AzMetricDefinition -ResourceId $ResourceId -ErrorAction Stop
        
        # Filter by metric names if provided
        if ($MetricNames.Count -gt 0) {
            $metricDefinitions = $metricDefinitions | Where-Object { $MetricNames -contains $_.Name.Value }
        }
        
        # Return detailed output or just names based on parameter
        if ($DetailedOutput) {
            return $metricDefinitions
        }
        else {
            return $metricDefinitions | Select-Object -ExpandProperty Name | Select-Object -ExpandProperty Value
        }
    }
    catch {
        if ($_.Exception -is [EAFDependencyException]) {
            throw
        }
        
        throw [EAFDependencyException]::new(
            "Error retrieving metric definitions: $($_.Exception.Message)",
            "MetricDefinitions",
            "Resource",
            "MetricDefinitions",
            "Error",
            $_.Exception.Message
        )
    }
}

# Export all functions for use in other modules
Export-ModuleMember -Function @(
    'Get-EAFLogAnalyticsWorkspace',
    'Enable-EAFDiagnosticSettings',
    'New-EAFActionGroup',
    'New-EAFMetricAlertRule',
    'Get-EAFResourceMetricDefinitions'
)

