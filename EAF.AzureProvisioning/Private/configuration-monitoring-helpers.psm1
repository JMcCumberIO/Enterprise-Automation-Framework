# Configuration Monitoring Helper Functions for EAF.AzureProvisioning
# This module provides centralized logging and tracking for configuration changes and usage

using namespace System
using namespace System.Management.Automation
using namespace System.Collections.Generic

# Import custom exception types if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'EAFResourceValidationException').Type) {
    $exceptionModulePath = Join-Path -Path $PSScriptRoot -ChildPath "exceptions.psm1"
    if (Test-Path $exceptionModulePath) {
        Import-Module $exceptionModulePath -Force
    }
}

# Initialize logging and monitoring storage
$script:ConfigurationMonitoringStore = @{
    Changes = [System.Collections.ArrayList]::new()
    Errors = [System.Collections.ArrayList]::new()
    ValidationEvents = [System.Collections.ArrayList]::new()
    AccessEvents = [System.Collections.ArrayList]::new()
    Metrics = @{
        AccessCount = @{}
        ValidationFailures = @{}
        LastAccess = @{}
        PerformanceMetrics = @{}
    }
    Settings = @{
        MaxEventsStored = 1000
        EnableFileLogging = $false
        LogFilePath = ""
        EnableEventLogging = $false
        EnableTelemetry = $false
        RetentionDays = 30
    }
}

<#
.SYNOPSIS
    Logs configuration change events.
    
.DESCRIPTION
    The Write-EAFConfigurationChange function records changes to configuration settings,
    providing a comprehensive audit trail of modifications.
    
.PARAMETER ConfigPath
    The dot-notation path to the configuration setting.
    
.PARAMETER ChangeType
    The type of change (Create, Update, Delete, Access).
    
.PARAMETER OldValue
    The previous value of the configuration (if applicable).
    
.PARAMETER NewValue
    The new value of the configuration (if applicable).
    
.PARAMETER User
    The user who made the change. Defaults to current user.
    
.PARAMETER Source
    The source of the change (UI, API, Script, etc.).
    
.PARAMETER AdditionalData
    Additional metadata to record with the change.
    
.EXAMPLE
    Write-EAFConfigurationChange -ConfigPath "Security.KeyVault.SoftDeleteRetention.dev" -ChangeType "Update" -OldValue 7 -NewValue 14
#>
function Write-EAFConfigurationChange {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Create', 'Update', 'Delete', 'Access')]
        [string]$ChangeType,
        
        [Parameter(Mandatory = $false)]
        [object]$OldValue,
        
        [Parameter(Mandatory = $false)]
        [object]$NewValue,
        
        [Parameter(Mandatory = $false)]
        [string]$User = $env:USERNAME,
        
        [Parameter(Mandatory = $false)]
        [string]$Source = "PowerShell",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalData
    )
    
    try {
        # Create the change event record
        $changeEvent = @{
            Timestamp = Get-Date
            ConfigPath = $ConfigPath
            ChangeType = $ChangeType
            OldValue = ($OldValue -is [securestring]) ? "<secure>" : $OldValue
            NewValue = ($NewValue -is [securestring]) ? "<secure>" : $NewValue
            User = $User
            Source = $Source
            ComputerName = $env:COMPUTERNAME
            ProcessId = $PID
            AdditionalData = $AdditionalData
            Id = [Guid]::NewGuid().ToString()
        }
        
        # Add to the monitoring store
        [void]$script:ConfigurationMonitoringStore.Changes.Add($changeEvent)
        
        # Enforce maximum event limit
        if ($script:ConfigurationMonitoringStore.Changes.Count -gt $script:ConfigurationMonitoringStore.Settings.MaxEventsStored) {
            $script:ConfigurationMonitoringStore.Changes.RemoveAt(0)
        }
        
        # Write to log file if enabled
        if ($script:ConfigurationMonitoringStore.Settings.EnableFileLogging -and 
            -not [string]::IsNullOrEmpty($script:ConfigurationMonitoringStore.Settings.LogFilePath)) {
            $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$ChangeType] [$ConfigPath] [User: $User] [Source: $Source]"
            Add-Content -Path $script:ConfigurationMonitoringStore.Settings.LogFilePath -Value $logEntry
        }
        
        # Update metrics
        if (-not $script:ConfigurationMonitoringStore.Metrics.AccessCount.ContainsKey($ConfigPath)) {
            $script:ConfigurationMonitoringStore.Metrics.AccessCount[$ConfigPath] = 0
        }
        
        $script:ConfigurationMonitoringStore.Metrics.AccessCount[$ConfigPath]++
        $script:ConfigurationMonitoringStore.Metrics.LastAccess[$ConfigPath] = Get-Date
        
        # For access events, also record in the access events collection
        if ($ChangeType -eq 'Access') {
            $accessEvent = $changeEvent.Clone()
            [void]$script:ConfigurationMonitoringStore.AccessEvents.Add($accessEvent)
            
            # Enforce maximum event limit for access events
            if ($script:ConfigurationMonitoringStore.AccessEvents.Count -gt $script:ConfigurationMonitoringStore.Settings.MaxEventsStored) {
                $script:ConfigurationMonitoringStore.AccessEvents.RemoveAt(0)
            }
        }
        
        # Write to the event log if enabled
        if ($script:ConfigurationMonitoringStore.Settings.EnableEventLogging) {
            $eventMessage = "Configuration change: [$ChangeType] [$ConfigPath] by user [$User] from source [$Source]"
            Write-EventLog -LogName Application -Source "EAF.AzureProvisioning" -EventId 1000 -EntryType Information -Message $eventMessage -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "Failed to log configuration change: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Logs configuration validation events.
    
.DESCRIPTION
    The Write-EAFConfigurationValidation function records validation events for configuration settings,
    whether they pass or fail validation checks.
    
.PARAMETER ConfigPath
    The dot-notation path to the configuration setting.
    
.PARAMETER ValidationRule
    The name or description of the validation rule.
    
.PARAMETER IsValid
    True if validation succeeded, false if it failed.
    
.PARAMETER ValidationMessage
    Details about the validation result.
    
.PARAMETER Value
    The value that was validated.
    
.PARAMETER AdditionalData
    Additional metadata to record with the validation event.
    
.EXAMPLE
    Write-EAFConfigurationValidation -ConfigPath "Security.KeyVault.SoftDeleteRetention.dev" -ValidationRule "Range" -IsValid $false -ValidationMessage "Value must be between 7 and 90 days"
#>
function Write-EAFConfigurationValidation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory = $true)]
        [string]$ValidationRule,
        
        [Parameter(Mandatory = $true)]
        [bool]$IsValid,
        
        [Parameter(Mandatory = $false)]
        [string]$ValidationMessage = "",
        
        [Parameter(Mandatory = $false)]
        [object]$Value,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalData
    )
    
    try {
        # Create the validation event record
        $validationEvent = @{
            Timestamp = Get-Date
            ConfigPath = $ConfigPath
            ValidationRule = $ValidationRule
            IsValid = $IsValid
            ValidationMessage = $ValidationMessage
            Value = ($Value -is [securestring]) ? "<secure>" : $Value
            User = $env:USERNAME
            ComputerName = $env:COMPUTERNAME
            ProcessId = $PID
            AdditionalData = $AdditionalData
            Id = [Guid]::NewGuid().ToString()
        }
        
        # Add to the monitoring store
        [void]$script:ConfigurationMonitoringStore.ValidationEvents.Add($validationEvent)
        
        # Enforce maximum event limit
        if ($script:ConfigurationMonitoringStore.ValidationEvents.Count -gt $script:ConfigurationMonitoringStore.Settings.MaxEventsStored) {
            $script:ConfigurationMonitoringStore.ValidationEvents.RemoveAt(0)
        }
        
        # Update metrics for validation failures
        if (-not $IsValid) {
            if (-not $script:ConfigurationMonitoringStore.Metrics.ValidationFailures.ContainsKey($ConfigPath)) {
                $script:ConfigurationMonitoringStore.Metrics.ValidationFailures[$ConfigPath] = 0
            }
            $script:ConfigurationMonitoringStore.Metrics.ValidationFailures[$ConfigPath]++
            
            # Log validation failures as errors
            $errorEvent = @{
                Timestamp = Get-Date
                ConfigPath = $ConfigPath
                ErrorType = "ValidationError"
                ErrorMessage = $ValidationMessage
                ValidationRule = $ValidationRule
                Value = ($Value -is [securestring]) ? "<secure>" : $Value
                User = $env:USERNAME
                ComputerName = $env:COMPUTERNAME
                AdditionalData = $AdditionalData
                Id = [Guid]::NewGuid().ToString()
            }
            
            [void]$script:ConfigurationMonitoringStore.Errors.Add($errorEvent)
            
            # Enforce maximum event limit for errors
            if ($script:ConfigurationMonitoringStore.Errors.Count -gt $script:ConfigurationMonitoringStore.Settings.MaxEventsStored) {
                $script:ConfigurationMonitoringStore.Errors.RemoveAt(0)
            }
            
            # Write to log file if enabled
            if ($script:ConfigurationMonitoringStore.Settings.EnableFileLogging -and 
                -not [string]::IsNullOrEmpty($script:ConfigurationMonitoringStore.Settings.LogFilePath)) {
                $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [VALIDATION_FAILED] [$ConfigPath] [Rule: $ValidationRule] $ValidationMessage"
                Add-Content -Path $script:ConfigurationMonitoringStore.Settings.LogFilePath -Value $logEntry
            }
            
            # Write to the event log if enabled
            if ($script:ConfigurationMonitoringStore.Settings.EnableEventLogging) {
                $eventMessage = "Configuration validation failed: [$ConfigPath] Rule: [$ValidationRule] - $ValidationMessage"
                Write-EventLog -LogName Application -Source "EAF.AzureProvisioning" -EventId 1002 -EntryType Warning -Message $eventMessage -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Warning "Failed to log configuration validation: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Logs configuration error events.
    
.DESCRIPTION
    The Write-EAFConfigurationError function records errors related to configuration operations.
    
.PARAMETER ConfigPath
    The dot-notation path to the configuration setting.
    
.PARAMETER ErrorType
    The type of error that occurred.
    
.PARAMETER ErrorMessage
    A description of the error.
    
.PARAMETER Exception
    The exception object, if available.
    
.PARAMETER AdditionalData
    Additional metadata to record with the error.
    
.EXAMPLE
    try {
        # Configuration operation that might fail
    }
    catch {
        Write-EAFConfigurationError -ConfigPath "Database.ConnectionString" -ErrorType "AccessDenied" -ErrorMessage "Access denied when trying to read configuration" -Exception $_.Exception
    }
#>
function Write-EAFConfigurationError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory = $true)]
        [string]$ErrorType,
        
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,
        
        [Parameter(Mandatory = $false)]
        [Exception]$Exception,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalData
    )
    
    try {
        # Create the error event record
        $errorEvent = @{
            Timestamp = Get-Date
            ConfigPath = $ConfigPath
            ErrorType = $ErrorType
            ErrorMessage = $ErrorMessage
            Exception = $Exception
            ExceptionMessage = $Exception?.Message
            StackTrace = $Exception?.StackTrace
            User = $env:USERNAME
            ComputerName = $env:COMPUTERNAME
            ProcessId = $PID
            AdditionalData = $AdditionalData
            Id = [Guid]::NewGuid().ToString()
        }
        
        # Add to the monitoring store
        [void]$script:ConfigurationMonitoringStore.Errors.Add($errorEvent)
        
        # Enforce maximum event limit
        if ($script:ConfigurationMonitoringStore.Errors.Count -gt $script:ConfigurationMonitoringStore.Settings.MaxEventsStored) {
            $script:ConfigurationMonitoringStore.Errors.RemoveAt(0)
        }
        
        # Write to log file if enabled
        if ($script:ConfigurationMonitoringStore.Settings.EnableFileLogging -and 
            -not [string]::IsNullOrEmpty($script:ConfigurationMonitoringStore.Settings.LogFilePath)) {
            $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [ERROR] [$ConfigPath] [$ErrorType] $ErrorMessage"
            Add-Content -Path $script:ConfigurationMonitoringStore.Settings.LogFilePath -Value $logEntry
        }
        
        # Write to the event log if enabled
        if ($script:ConfigurationMonitoringStore.Settings.EnableEventLogging) {
            $eventMessage = "Configuration error: [$ErrorType] [$ConfigPath] - $ErrorMessage"
            if ($Exception) {
                $eventMessage += "`nException: $($Exception.Message)"
            }
            Write-EventLog -LogName Application -Source "EAF.AzureProvisioning" -EventId 1001 -EntryType Error -Message $eventMessage -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "Failed to log configuration error: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Records performance metrics for configuration operations.
    
.DESCRIPTION
    The Write-EAFConfigurationPerformance function records performance metrics for configuration operations.
    
.PARAMETER ConfigPath
    The dot-notation path to the configuration setting.


.PARAMETER OperationType
    The type of operation being measured.
    
.PARAMETER DurationMs
    The duration of the operation in milliseconds.
    
.PARAMETER ResourceType
    The type of resource being configured.
    
.PARAMETER AdditionalMetrics
    Additional performance metrics to record.
    
.EXAMPLE
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    # Perform configuration operation
    $stopwatch.Stop()
    Write-EAFConfigurationPerformance -ConfigPath "KeyVault.AccessPolicies" -OperationType "Update" -DurationMs $stopwatch.ElapsedMilliseconds
#>
function Write-EAFConfigurationPerformance {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory = $true)]
        [string]$OperationType,
        
        [Parameter(Mandatory = $true)]
        [int]$DurationMs,
        
        [Parameter(Mandatory = $false)]
        [string]$ResourceType = "",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalMetrics
    )
    
    try {
        # Create performance metric record
        $metricKey = "$ConfigPath/$OperationType"
        
        if (-not $script:ConfigurationMonitoringStore.Metrics.PerformanceMetrics.ContainsKey($metricKey)) {
            $script:ConfigurationMonitoringStore.Metrics.PerformanceMetrics[$metricKey] = @{
                OperationCount = 0
                TotalDurationMs = 0
                MinDurationMs = [int]::MaxValue
                MaxDurationMs = 0
                AverageDurationMs = 0
                LastOperation = $null
                ResourceType = $ResourceType
                AdditionalMetrics = @{}
            }
        }
        
        $metrics = $script:ConfigurationMonitoringStore.Metrics.PerformanceMetrics[$metricKey]
        $metrics.OperationCount++
        $metrics.TotalDurationMs += $DurationMs
        $metrics.MinDurationMs = [Math]::Min($metrics.MinDurationMs, $DurationMs)
        $metrics.MaxDurationMs = [Math]::Max($metrics.MaxDurationMs, $DurationMs)
        $metrics.AverageDurationMs = $metrics.TotalDurationMs / $metrics.OperationCount
        $metrics.LastOperation = Get-Date
        
        if ($AdditionalMetrics) {
            foreach ($key in $AdditionalMetrics.Keys) {
                $metrics.AdditionalMetrics[$key] = $AdditionalMetrics[$key]
            }
        }
    }
    catch {
        Write-Warning "Failed to record performance metrics: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Gets configuration monitoring data and metrics.
    
.DESCRIPTION
    The Get-EAFConfigurationMonitoring function retrieves monitoring data and metrics
    for configuration operations.
    
.PARAMETER MetricType
    The type of metrics to retrieve (Changes, Errors, Validation, Access, Performance, All).
    
.PARAMETER ConfigPath
    Optional filter for a specific configuration path.
    
.PARAMETER StartTime
    Optional start time filter for events.
    
.PARAMETER EndTime
    Optional end time filter for events.
    
.PARAMETER MaxEvents
    Maximum number of events to return.
    
.EXAMPLE
    Get-EAFConfigurationMonitoring -MetricType Performance -ConfigPath "KeyVault"
#>
function Get-EAFConfigurationMonitoring {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet('Changes', 'Errors', 'Validation', 'Access', 'Performance', 'All')]
        [string]$MetricType = 'All',
        
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory = $false)]
        [DateTime]$StartTime,
        
        [Parameter(Mandatory = $false)]
        [DateTime]$EndTime,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxEvents = 100
    )
    
    try {
        $results = @{
            Changes = @()
            Errors = @()
            ValidationEvents = @()
            AccessEvents = @()
            PerformanceMetrics = @{}
            Summary = @{
                TotalChanges = 0
                TotalErrors = 0
                TotalValidationFailures = 0
                TotalAccesses = 0
            }
        }
        
        # Apply time filters
        $timeFilter = {
            param($event)
            $include = $true
            if ($StartTime) { $include = $include -and $event.Timestamp -ge $StartTime }
            if ($EndTime) { $include = $include -and $event.Timestamp -le $EndTime }
            return $include
        }
        
        # Apply config path filter
        $pathFilter = {
            param($event)
            if (-not $ConfigPath) { return $true }
            return $event.ConfigPath -like "*$ConfigPath*"
        }
        
        # Get requested metrics
        switch ($MetricType) {
            'Changes' {
                $results.Changes = @($script:ConfigurationMonitoringStore.Changes | 
                    Where-Object $timeFilter | 
                    Where-Object $pathFilter |
                    Select-Object -Last $MaxEvents)
                $results.Summary.TotalChanges = $results.Changes.Count
            }
            'Errors' {
                $results.Errors = @($script:ConfigurationMonitoringStore.Errors |
                    Where-Object $timeFilter |
                    Where-Object $pathFilter |
                    Select-Object -Last $MaxEvents)
                $results.Summary.TotalErrors = $results.Errors.Count
            }
            'Validation' {
                $results.ValidationEvents = @($script:ConfigurationMonitoringStore.ValidationEvents |
                    Where-Object $timeFilter |
                    Where-Object $pathFilter |
                    Select-Object -Last $MaxEvents)
                $results.Summary.TotalValidationFailures = @($results.ValidationEvents | Where-Object { -not $_.IsValid }).Count
            }
            'Access' {
                $results.AccessEvents = @($script:ConfigurationMonitoringStore.AccessEvents |
                    Where-Object $timeFilter |
                    Where-Object $pathFilter |
                    Select-Object -Last $MaxEvents)
                $results.Summary.TotalAccesses = $results.AccessEvents.Count
            }
            'Performance' {
                if ($ConfigPath) {
                    $results.PerformanceMetrics = $script:ConfigurationMonitoringStore.Metrics.PerformanceMetrics.GetEnumerator() |
                        Where-Object { $_.Key -like "*$ConfigPath*" } |
                        ForEach-Object { @{ $_.Key = $_.Value } }
                }
                else {
                    $results.PerformanceMetrics = $script:ConfigurationMonitoringStore.Metrics.PerformanceMetrics
                }
            }
            'All' {
                $results.Changes = @($script:ConfigurationMonitoringStore.Changes |
                    Where-Object $timeFilter |
                    Where-Object $pathFilter |
                    Select-Object -Last $MaxEvents)
                $results.Errors = @($script:ConfigurationMonitoringStore.Errors |
                    Where-Object $timeFilter |
                    Where-Object $pathFilter |
                    Select-Object -Last $MaxEvents)
                $results.ValidationEvents = @($script:ConfigurationMonitoringStore.ValidationEvents |
                    Where-Object $timeFilter |
                    Where-Object $pathFilter |
                    Select-Object -Last $MaxEvents)
                $results.AccessEvents = @($script:ConfigurationMonitoringStore.AccessEvents |
                    Where-Object $timeFilter |
                    Where-Object $pathFilter |
                    Select-Object -Last $MaxEvents)
                $results.PerformanceMetrics = $script:ConfigurationMonitoringStore.Metrics.PerformanceMetrics
                
                $results.Summary = @{
                    TotalChanges = $results.Changes.Count
                    TotalErrors = $results.Errors.Count
                    TotalValidationFailures = @($results.ValidationEvents | Where-Object { -not $_.IsValid }).Count
                    TotalAccesses = $results.AccessEvents.Count
                }
            }
        }
        
        return $results
    }
    catch {
        Write-Warning "Failed to retrieve configuration monitoring data: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Updates configuration monitoring settings.
    
.DESCRIPTION
    The Set-EAFConfigurationMonitoringSettings function updates the settings for
    configuration monitoring and logging.
    
.PARAMETER MaxEventsStored
    Maximum number of events to keep in memory.
    
.PARAMETER EnableFileLogging
    Whether to enable logging to a file.
    
.PARAMETER LogFilePath
    Path to the log file when file logging is enabled.
    
.PARAMETER EnableEventLogging
    Whether to enable Windows Event Log logging.
    
.PARAMETER EnableTelemetry
    Whether to enable telemetry collection.
    
.PARAMETER RetentionDays
    Number of days to retain monitoring data.
    
.EXAMPLE
    Set-EAFConfigurationMonitoringSettings -MaxEventsStored 2000 -EnableFileLogging -LogFilePath "C:\Logs\EAF.log"
#>
function Set-EAFConfigurationMonitoringSettings {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [int]$MaxEventsStored,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableFileLogging,
        
        [Parameter(Mandatory = $false)]
        [string]$LogFilePath,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableEventLogging,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableTelemetry,
        
        [Parameter(Mandatory = $false)]
        [int]$RetentionDays
    )
    
    try {
        if ($PSBoundParameters.ContainsKey('MaxEventsStored')) {
            $script:ConfigurationMonitoringStore.Settings.MaxEventsStored = $MaxEventsStored
        }
        
        if ($PSBoundParameters.ContainsKey('EnableFileLogging')) {
            $script:ConfigurationMonitoringStore.Settings.EnableFileLogging = $EnableFileLogging
        }
        
        if ($PSBoundParameters.ContainsKey('LogFilePath')) {
            $script:ConfigurationMonitoringStore.Settings.LogFilePath = $LogFilePath
        }
        
        if ($PSBoundParameters.ContainsKey('EnableEventLogging')) {
            $script:ConfigurationMonitoringStore.Settings.EnableEventLogging = $EnableEventLogging
        }
        
        if ($PSBoundParameters.ContainsKey('EnableTelemetry')) {
            $script:ConfigurationMonitoringStore.Settings.EnableTelemetry = $EnableTelemetry
        }
        
        if ($PSBoundParameters.ContainsKey('RetentionDays')) {
            $script:ConfigurationMonitoringStore.Settings.RetentionDays = $RetentionDays
        }
        
        return $true
    }
    catch {
        Write-Warning "Failed to update monitoring settings: $($_.Exception.Message)"
        return $false
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Write-EAFConfigurationChange',
    'Write-EAFConfigurationValidation',
    'Write-EAFConfigurationError',
    'Write-EAFConfigurationPerformance',
    'Get-EAFConfigurationMonitoring',
    'Set-EAFConfigurationMonitoringSettings'
)
