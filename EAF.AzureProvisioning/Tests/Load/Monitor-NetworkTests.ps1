# Real-time Network Test Monitor for EAF.AzureProvisioning
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "../../TestResults/LoadTests",
    
    [Parameter(Mandatory = $false)]
    [int]$RefreshIntervalSeconds = 5,
    
    [Parameter(Mandatory = $false)]
    [switch]$EnableAlerts,
    
    [Parameter(Mandatory = $false)]
    [string]$MetricsLogPath = "metrics.json"
)

# Create output directory if it doesn't exist
$OutputPath = Join-Path $PSScriptRoot $OutputPath
if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$MetricsLogPath = Join-Path $OutputPath $MetricsLogPath

# Initialize monitoring data
$monitoringData = @{
    StartTime = Get-Date
    LatestUpdate = Get-Date
    Operations = @{
        Total = 0
        Success = 0
        Failed = 0
        SuccessRate = 0
    }
    Network = @{
        AverageLatency = 0
        MaxLatency = 0
        MinLatency = [int]::MaxValue
        ConnectionErrors = 0
        Throughput = @()
        CurrentConnections = 0
    }
    Resources = @{
        CPU = 0
        Memory = 0
        Handles = 0
    }
    Alerts = [System.Collections.ArrayList]::new()
}

# Alert thresholds
$alertThresholds = @{
    LatencyMs = 2000
    ErrorRate = 0.2
    MinThroughputKBps = 50
    MaxConnectionErrors = 10
    MaxMemoryGrowthMB = 100
}

function Write-MonitorLog {
    param (
        [string]$Message,
        [string]$Level = "Info",
        [switch]$NoConsole
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    if (-not $NoConsole) {
        switch ($Level) {
            "Error" { Write-Host $logMessage -ForegroundColor Red }
            "Warning" { Write-Host $logMessage -ForegroundColor Yellow }
            "Success" { Write-Host $logMessage -ForegroundColor Green }
            default { Write-Host $logMessage }
        }
    }
    
    Add-Content -Path (Join-Path $OutputPath "monitor.log") -Value $logMessage
}

function Add-Alert {
    param (
        [string]$Type,
        [string]$Message,
        [ValidateSet("Critical", "Warning", "Info")]
        [string]$Severity = "Warning"
    )
    
    $alert = @{
        Timestamp = Get-Date
        Type = $Type
        Message = $Message
        Severity = $Severity
    }
    
    [void]$monitoringData.Alerts.Add($alert)
    Write-MonitorLog -Message "ALERT: $Message" -Level $(
        switch ($Severity) {
            "Critical" { "Error" }
            "Warning" { "Warning" }
            default { "Info" }
        }
    )
}

function Update-Dashboard {
    param (
        [hashtable]$Data
    )
    
    Clear-Host
    Write-Host "====================================="
    Write-Host "EAF Network Test Monitor"
    Write-Host "====================================="
    Write-Host
    
    # Runtime Information
    $runtime = (Get-Date) - $Data.StartTime
    Write-Host "Runtime: $($runtime.ToString('hh\:mm\:ss'))"
    Write-Host "Last Update: $($Data.LatestUpdate.ToString('HH:mm:ss'))"
    Write-Host
    
    # Operation Statistics
    Write-Host "Operations" -ForegroundColor Cyan
    Write-Host "----------"
    Write-Host "Total: $($Data.Operations.Total)"
    Write-Host "Success: $($Data.Operations.Success)" -ForegroundColor Green
    Write-Host "Failed: $($Data.Operations.Failed)" -ForegroundColor Red
    Write-Host "Success Rate: $($Data.Operations.SuccessRate.ToString('P2'))"
    Write-Host
    
    # Network Statistics
    Write-Host "Network Performance" -ForegroundColor Cyan
    Write-Host "------------------"
    Write-Host "Average Latency: $($Data.Network.AverageLatency.ToString('N0'))ms"
    Write-Host "Min/Max Latency: $($Data.Network.MinLatency.ToString('N0'))ms / $($Data.Network.MaxLatency.ToString('N0'))ms"
    Write-Host "Connection Errors: $($Data.Network.ConnectionErrors)"
    Write-Host "Active Connections: $($Data.Network.CurrentConnections)"
    
    if ($Data.Network.Throughput.Count -gt 0) {
        $avgThroughput = ($Data.Network.Throughput | Measure-Object -Average).Average
        Write-Host "Average Throughput: $($avgThroughput.ToString('N2')) KB/s"
    }
    Write-Host
    
    # Resource Usage
    Write-Host "Resource Usage" -ForegroundColor Cyan
    Write-Host "--------------"
    Write-Host "CPU: $($Data.Resources.CPU.ToString('N1'))%"
    Write-Host "Memory: $($Data.Resources.Memory)MB"
    Write-Host "Handles: $($Data.Resources.Handles)"
    Write-Host
    
    # Recent Alerts
    if ($Data.Alerts.Count -gt 0) {
        Write-Host "Recent Alerts" -ForegroundColor Yellow
        Write-Host "-------------"
        $Data.Alerts | Select-Object -Last 5 | ForEach-Object {
            $color = switch ($_.Severity) {
                "Critical" { "Red" }
                "Warning" { "Yellow" }
                default { "White" }
            }
            Write-Host "$($_.Timestamp.ToString('HH:mm:ss')) - $($_.Message)" -ForegroundColor $color
        }
    }
}

function Export-Metrics {
    param (
        [hashtable]$Data,
        [string]$Path
    )
    
    $metrics = @{
        Timestamp = Get-Date
        Operations = $Data.Operations
        Network = $Data.Network
        Resources = $Data.Resources
        Alerts = @($Data.Alerts)
    }
    
    $metrics | ConvertTo-Json | Add-Content -Path $Path
}

try {
    Write-MonitorLog "Starting network test monitor..."
    Write-MonitorLog "Output directory: $OutputPath"
    Write-MonitorLog "Refresh interval: $RefreshIntervalSeconds seconds"
    Write-MonitorLog "Alerts enabled: $EnableAlerts"
    
    while ($true) {
        # Update timestamp
        $monitoringData.LatestUpdate = Get-Date
        
        # Get current process metrics
        $process = Get-Process -Id $PID
        $monitoringData.Resources.CPU = $process.CPU
        $monitoringData.Resources.Memory = [math]::Round($process.WorkingSet64 / 1MB, 2)
        $monitoringData.Resources.Handles = $process.HandleCount
        
        # Read latest metrics from test output
        if (Test-Path $MetricsLogPath) {
            $latestMetrics = Get-Content $MetricsLogPath -Tail 1 | ConvertFrom-Json
            
            if ($latestMetrics) {
                # Update operation counts
                $monitoringData.Operations.Total = $latestMetrics.TotalOperations
                $monitoringData.Operations.Success = $latestMetrics.SuccessfulOperations
                $monitoringData.Operations.Failed = $latestMetrics.FailedOperations
                $monitoringData.Operations.SuccessRate = if ($monitoringData.Operations.Total -gt 0) {
                    $monitoringData.Operations.Success / $monitoringData.Operations.Total
                } else { 0 }
                
                # Update network metrics
                $monitoringData.Network.AverageLatency = $latestMetrics.AverageLatency
                $monitoringData.Network.MaxLatency = [math]::Max($monitoringData.Network.MaxLatency, $latestMetrics.CurrentLatency)
                $monitoringData.Network.MinLatency = [math]::Min($monitoringData.Network.MinLatency, $latestMetrics.CurrentLatency)
                $monitoringData.Network.ConnectionErrors = $latestMetrics.ConnectionErrors
                $monitoringData.Network.CurrentConnections = $latestMetrics.ActiveConnections
                $monitoringData.Network.Throughput += $latestMetrics.CurrentThroughput
                
                # Keep only last 100 throughput measurements
                if ($monitoringData.Network.Throughput.Count -gt 100) {
                    $monitoringData.Network.Throughput = $monitoringData.Network.Throughput | Select-Object -Last 100
                }
                
                # Check for alerts if enabled
                if ($EnableAlerts) {
                    # Check latency
                    if ($latestMetrics.CurrentLatency -gt $alertThresholds.LatencyMs) {
                        Add-Alert -Type "HighLatency" -Message "High latency detected: $($latestMetrics.CurrentLatency)ms" -Severity "Warning"
                    }
                    
                    # Check error rate
                    if ($monitoringData.Operations.SuccessRate -lt (1 - $alertThresholds.ErrorRate)) {
                        Add-Alert -Type "HighErrorRate" -Message "High error rate: $((1 - $monitoringData.Operations.SuccessRate).ToString('P2'))" -Severity "Critical"
                    }
                    
                    # Check throughput
                    $currentThroughput = $latestMetrics.CurrentThroughput
                    if ($currentThroughput -lt $alertThresholds.MinThroughputKBps) {
                        Add-Alert -Type "LowThroughput" -Message "Low throughput: $($currentThroughput.ToString('N2')) KB/s" -Severity "Warning"
                    }
                    
                    # Check connection errors
                    if ($latestMetrics.ConnectionErrors -gt $alertThresholds.MaxConnectionErrors) {
                        Add-Alert -Type "ConnectionErrors" -Message "High number of connection errors: $($latestMetrics.ConnectionErrors)" -Severity "Critical"
                    }
                    
                    # Check memory growth
                    $memoryGrowthMB = $monitoringData.Resources.Memory - $initialMemory
                    if ($memoryGrowthMB -gt $alertThresholds.MaxMemoryGrowthMB) {
                        Add-Alert -Type "MemoryGrowth" -Message "High memory growth: $($memoryGrowthMB.ToString('N0'))MB" -Severity "Warning"
                    }
                }
            }
        }
        
        # Update dashboard
        Update-Dashboard -Data $monitoringData
        
        # Export current metrics
        Export-Metrics -Data $monitoringData -Path (Join-Path $OutputPath "monitor-metrics.json")
        
        # Wait for next update
        Start-Sleep -Seconds $RefreshIntervalSeconds
    }
}
catch {
    Write-MonitorLog "Error in monitor: $($_.Exception.Message)" -Level "Error"
    throw
}
finally {
    Write-MonitorLog "Monitor stopped"
}
