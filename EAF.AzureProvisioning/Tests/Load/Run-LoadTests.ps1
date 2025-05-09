
# Start network analysis if enabled
$networkAnalysis = $null
if ($config.LoadTest.EnableNetworkAnalysis) {
    Write-Host "`nInitializing Network Analysis..."
    Import-Module (Join-Path $PSScriptRoot "NetworkAnalysis.psm1") -Force
    
    $networkAnalysis = Start-NetworkAnalysis `
        -OutputPath (Join-Path $OutputPath "NetworkAnalysis") `
        -EnablePacketCapture:$config.LoadTest.NetworkSimulation.EnablePacketCapture `
        -EnableSecurityAnalysis:$config.LoadTest.NetworkSimulation.EnableSecurityAnalysis
    
    if (-not $networkAnalysis) {
        Write-Warning "Failed to initialize network analysis. Continuing without network analysis."
    }
}

try {
    # Run network tests with analysis
    if ($networkAnalysis) {
        Write-Host "`nRunning Network Tests with Analysis..."
        
        # Register traffic analysis handler
        $null = Register-ObjectEvent -InputObject $networkAnalysis -EventName "TrafficEvent" -Action {
            Analyze-NetworkTraffic -Operation $Event.SourceEventArgs.Operation `
                -Request $Event.SourceEventArgs.Request `
                -Response $Event.SourceEventArgs.Response
        }
        
        # Register security analysis handler
        $null = Register-ObjectEvent -InputObject $networkAnalysis -EventName "SecurityEvent" -Action {
            Analyze-SecurityProtocol -Protocol $Event.SourceEventArgs.Protocol `
                -Certificate $Event.SourceEventArgs.Certificate `
                -HostName $Event.SourceEventArgs.HostName
        }
    }
    
    # Run the tests
    $testResults = Invoke-Pester -Configuration $pesterConfig
    
    # Generate network analysis report
    if ($networkAnalysis) {
        Write-Host "`nGenerating Network Analysis Report..."
        $reportPath = Get-NetworkAnalysisReport -Format HTML
        Write-Host "Network analysis report generated at: $reportPath"
        
        # Add network analysis results to metrics
        $metrics.NetworkAnalysis = @{
            TotalRequests = $networkAnalysis.TrafficStore.Count
            SecurityEvents = $networkAnalysis.SecurityStore.Count
            Patterns = $networkAnalysis.Metrics.Patterns
            AverageLatency = ($networkAnalysis.Metrics.Traffic.Values | 
                Measure-Object -Property AverageDuration -Average).Average
        }
        
        # Add network analysis section to HTML report
        $htmlReport += @"
        <div class="network-analysis">
            <h2>Network Analysis Results</h2>
            <div class="summary">
                <p>Total Requests: $($metrics.NetworkAnalysis.TotalRequests)</p>
                <p>Security Events: $($metrics.NetworkAnalysis.SecurityEvents)</p>
                <p>Average Latency: $($metrics.NetworkAnalysis.AverageLatency.ToString('N2'))ms</p>
            </div>
            <div class="patterns">
                <h3>Traffic Patterns</h3>
                <table>
                    <tr><th>Pattern</th><th>Count</th></tr>
                    $(foreach ($pattern in $metrics.NetworkAnalysis.Patterns.GetEnumerator()) {
                        "<tr><td>$($pattern.Key)</td><td>$($pattern.Value)</td></tr>"
                    })
                </table>
            </div>
            <div id="networkChart" class="chart"></div>
            <script>
                var networkData = {
                    x: $(ConvertTo-Json @($metrics.NetworkAnalysis.Patterns.Keys)),
                    y: $(ConvertTo-Json @($metrics.NetworkAnalysis.Patterns.Values)),
                    type: 'bar',
                    name: 'Traffic Patterns'
                };
                Plotly.newPlot('networkChart', [networkData]);
            </script>
        </div>
"@
    }
}
finally {
    # Stop network analysis
    if ($networkAnalysis) {
        Stop-NetworkAnalysis
        Get-EventSubscriber | Where-Object { 
            $_.SourceObject -eq $networkAnalysis 
        } | Unregister-Event
    }
}
recision),
                        $($metrics.SecurityML.Performance.PredictionAccuracy)
                    ],
                    type: 'bar',
                    marker: {
                        color: ['#5cb85c', '#d9534f', '#5bc0de']
                    }
                };
                
                var patternData = {
                    values: [
                        $($metrics.SecurityML.Patterns.Total - $metrics.SecurityML.Patterns.Anomalies),
                        $($metrics.SecurityML.Patterns.Anomalies)
                    ],
                    labels: ['Normal Patterns', 'Anomalies'],
                    type: 'pie',
                    marker: {
                        colors: ['#5cb85c', '#d9534f']
                    }
                };
                
                Plotly.newPlot('mlChart', [mlData]);
                Plotly.newPlot('patternChart', [patternData]);
            </script>
        </div>
"@
    }
}
finally {
    # Stop ML analysis
    if ($securityML) {
        Stop-SecurityML
        Get-EventSubscriber | Where-Object { 
            $_.SourceObject -eq $securityML 
        } | Unregister-Event
    }
}

# Add load test configuration for ML
$config.LoadTest.SecurityML = @{
    EnablePatternRecognition = $true
    EnableAnomalyDetection = $true
    EnablePrediction = $true
    Patterns = @{
        MinSampleSize = 100
        ConfidenceThreshold = 0.8
        TimeWindowMinutes = 30
        EnableFeatureLearning = $true
    }
    Anomaly = @{
        BaselineSize = 1000
        SensitivityThreshold = 2.0
        LearningRate = 0.1
        WindowSize = 50
    }
    Prediction = @{
        HistoryWindow = 24 # hours
        ForecastWindow = 6 # hours
        MinConfidence = 0.7
        UpdateInterval = 60 # minutes
    }
    Reporting = @{
        GenerateCharts = $true
        IncludeRawData = $false
        MaxDataPoints = 1000
        RetentionDays = 30
    }
}

# Generate final summary including ML metrics
$summary = @{
    TestResults = @{
        Total = $testResults.TotalCount
        Passed = $testResults.PassedCount
        Failed = $testResults.FailedCount
        Skipped = $testResults.SkippedCount
        Duration = $testResults.Duration
    }
    Security = @{
        Incidents = $metrics.SecurityResponse.TotalIncidents
        Alerts = $metrics.SecurityResponse.TotalAlerts
        Remediations = $metrics.SecurityResponse.RemediationActions
        SuccessfulRemediations = $metrics.SecurityResponse.RemediationSuccess
    }
    ML = @{
        Patterns = $metrics.SecurityML.Patterns
        Performance = $metrics.SecurityML.Performance
    }
    Network = @{
        TotalRequests = $metrics.NetworkAnalysis.TotalRequests
        AverageLatency = $metrics.NetworkAnalysis.AverageLatency
        ErrorRate = ($metrics.NetworkAnalysis.Errors / $metrics.NetworkAnalysis.TotalRequests)
    }
}

# Add final summary to HTML report
$htmlReport += @"
<div class="final-summary">
    <h2>Test Execution Summary</h2>
    <div class="summary-grid">
        <div class="summary-section">
            <h3>Test Results</h3>
            <p>Total Tests: $($summary.TestResults.Total)</p>
            <p class="success">Passed: $($summary.TestResults.Passed)</p>
            <p class="failure">Failed: $($summary.TestResults.Failed)</p>
            <p>Skipped: $($summary.TestResults.Skipped)</p>
            <p>Duration: $($summary.TestResults.Duration.TotalSeconds.ToString('F2'))s</p>
        </div>
        
        <div class="summary-section">
            <h3>Security Metrics</h3>
            <p>Total Incidents: $($summary.Security.Incidents)</p>
            <p>Total Alerts: $($summary.Security.Alerts)</p>
            <p>Remediation Actions: $($summary.Security.Remediations)</p>
            <p>Successful Remediations: $($summary.Security.SuccessfulRemediations)</p>
        </div>
        
        <div class="summary-section">
            <h3>ML Analysis</h3>
            <p>Total Patterns: $($summary.ML.Patterns.Total)</p>
            <p>Anomalies: $($summary.ML.Patterns.Anomalies)</p>
            <p>Pattern Accuracy: $($summary.ML.Performance.PatternAccuracy.ToString('P1'))</p>
            <p>Prediction Accuracy: $($summary.ML.Performance.PredictionAccuracy.ToString('P1'))</p>
        </div>
        
        <div class="summary-section">
            <h3>Network Performance</h3>
            <p>Total Requests: $($summary.Network.TotalRequests)</p>
            <p>Average Latency: $($summary.Network.AverageLatency.ToString('F2'))ms</p>
            <p>Error Rate: $($summary.Network.ErrorRate.ToString('P1'))</p>
        </div>
    </div>
    
    <div id="summaryChart" class="chart"></div>
    <script>
        var summaryData = [{
            type: 'scatter',
            mode: 'lines+markers',
            name: 'Test Progress',
            x: ['Start', 'Security', 'ML', 'Network', 'End'],
            y: [0, 
                $($summary.Security.Incidents), 
                $($summary.ML.Patterns.Total), 
                $($summary.Network.TotalRequests), 
                $($summary.TestResults.Total)],
            marker: { size: 10 }
        }];
        
        var layout = {
            title: 'Test Execution Progress',
            xaxis: { title: 'Test Phase' },
            yaxis: { title: 'Cumulative Operations' }
        };
        
        Plotly.newPlot('summaryChart', summaryData, layout);
    </script>
</div>
"@

Write-Host "`nTest execution completed. Results available at: $OutputPath"
