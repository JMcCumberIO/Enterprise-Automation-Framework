    foreach ($key in $Point1.Keys) {
        if ($Point2.ContainsKey($key) -and $Point1[$key] -is [ValueType] -and $Point2[$key] -is [ValueType]) {
            $sumSquared += [Math]::Pow($Point1[$key] - $Point2[$key], 2)
        }
    }
    
    return [Math]::Sqrt($sumSquared)
}

function Get-MLEvaluation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = "SecurityML",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("HTML", "JSON")]
        [string]$Format = "HTML"
    )
    
    try {
        $evaluation = @{
            GeneratedAt = Get-Date
            PatternRecognition = @{
                TotalPatterns = $script:MLStore.TrainingData.Count
                FeatureCount = $script:MLStore.PatternRecognition.Features.Count
                ClusterCount = $script:MLStore.PatternRecognition.Clusters.Count
                AnomalyCount = @($script:MLStore.TrainingData | Where-Object { $_.IsAnomaly }).Count
            }
            AnomalyDetection = @{
                BaselineSize = $script:MLStore.AnomalyDetection.Baseline.Count
                MovingAverage = $script:MLStore.AnomalyDetection.MovingAverage
                StandardDeviation = $script:MLStore.AnomalyDetection.StandardDeviation
                LastUpdate = $script:MLStore.AnomalyDetection.LastUpdate
            }
            Prediction = @{
                TimeSeriesCount = $script:MLStore.Prediction.TimeSeriesData.Count
                ModelCount = $script:MLStore.Prediction.Models.Count
                LastUpdate = $script:MLStore.Prediction.LastUpdate
            }
            Performance = @{
                PatternAccuracy = 0.0
                AnomalyPrecision = 0.0
                PredictionAccuracy = 0.0
            }
        }
        
        # Calculate pattern recognition accuracy
        if ($script:MLStore.TrainingData.Count -gt 0) {
            $correctPatterns = @($script:MLStore.TrainingData | 
                Where-Object { $_.Category -eq "Known" -and -not $_.IsAnomaly }).Count
            $evaluation.Performance.PatternAccuracy = $correctPatterns / $script:MLStore.TrainingData.Count
        }
        
        # Calculate anomaly detection precision
        $anomalies = @($script:MLStore.TrainingData | Where-Object { $_.IsAnomaly })
        if ($anomalies.Count -gt 0) {
            $truePositives = @($anomalies | Where-Object { $_.Features.ZScore -gt $script:MLConfig.Anomaly.SensitivityThreshold }).Count
            $evaluation.Performance.AnomalyPrecision = $truePositives / $anomalies.Count
        }
        
        # Calculate prediction accuracy
        if ($script:MLStore.Prediction.TimeSeriesData.Count -gt 0) {
            $predictions = @($script:MLStore.Prediction.TimeSeriesData | 
                Where-Object { $_.Confidence -ge $script:MLConfig.Prediction.MinConfidence })
            if ($predictions.Count -gt 0) {
                $accuratePredictions = @($predictions | 
                    Where-Object { [Math]::Abs($_.PredictedValue - $_.ActualValue) / $_.ActualValue -le 0.1 }).Count
                $evaluation.Performance.PredictionAccuracy = $accuratePredictions / $predictions.Count
            }
        }
        
        # Generate evaluation report
        $reportPath = Join-Path $OutputPath "MLEvaluation-$(Get-Date -Format 'yyyyMMdd-HHmmss').$Format"
        
        switch ($Format) {
            "HTML" {
                $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security ML Evaluation Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .section { margin: 20px 0; padding: 10px; background-color: #f5f5f5; }
        .metric { font-size: 24px; font-weight: bold; }
        .metric-label { font-size: 14px; color: #666; }
        .chart { margin: 20px 0; height: 300px; }
        .performance { display: flex; justify-content: space-between; }
        .performance-item { text-align: center; padding: 10px; }
    </style>
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
</head>
<body>
    <h1>Security ML Evaluation Report</h1>
    
    <div class="section">
        <h2>Pattern Recognition</h2>
        <div class="performance">
            <div class="performance-item">
                <div class="metric">$($evaluation.PatternRecognition.TotalPatterns)</div>
                <div class="metric-label">Total Patterns</div>
            </div>
            <div class="performance-item">
                <div class="metric">$($evaluation.PatternRecognition.FeatureCount)</div>
                <div class="metric-label">Features</div>
            </div>
            <div class="performance-item">
                <div class="metric">$($evaluation.PatternRecognition.ClusterCount)</div>
                <div class="metric-label">Clusters</div>
            </div>
            <div class="performance-item">
                <div class="metric">$($evaluation.PatternRecognition.AnomalyCount)</div>
                <div class="metric-label">Anomalies</div>
            </div>
        </div>
        <div id="patternChart" class="chart"></div>
    </div>
    
    <div class="section">
        <h2>Anomaly Detection</h2>
        <div class="performance">
            <div class="performance-item">
                <div class="metric">$($evaluation.AnomalyDetection.BaselineSize)</div>
                <div class="metric-label">Baseline Size</div>
            </div>
            <div class="performance-item">
                <div class="metric">$($evaluation.AnomalyDetection.MovingAverage.ToString('F2'))</div>
                <div class="metric-label">Moving Average</div>
            </div>
            <div class="performance-item">
                <div class="metric">$($evaluation.AnomalyDetection.StandardDeviation.ToString('F2'))</div>
                <div class="metric-label">Standard Deviation</div>
            </div>
        </div>
        <div id="anomalyChart" class="chart"></div>
    </div>
    
    <div class="section">
        <h2>Performance Metrics</h2>
        <div class="performance">
            <div class="performance-item">
                <div class="metric">$($evaluation.Performance.PatternAccuracy.ToString('P1'))</div>
                <div class="metric-label">Pattern Accuracy</div>
            </div>
            <div class="performance-item">
                <div class="metric">$($evaluation.Performance.AnomalyPrecision.ToString('P1'))</div>
                <div class="metric-label">Anomaly Precision</div>
            </div>
            <div class="performance-item">
                <div class="metric">$($evaluation.Performance.PredictionAccuracy.ToString('P1'))</div>
                <div class="metric-label">Prediction Accuracy</div>
            </div>
        </div>
        <div id="performanceChart" class="chart"></div>
    </div>
    
    <script>
        // Pattern distribution chart
        var patternData = [{
            type: 'pie',
            labels: ['Normal Patterns', 'Anomalies'],
            values: [
                $($evaluation.PatternRecognition.TotalPatterns - $evaluation.PatternRecognition.AnomalyCount),
                $($evaluation.PatternRecognition.AnomalyCount)
            ],
            marker: {
                colors: ['#5cb85c', '#d9534f']
            }
        }];
        
        // Performance metrics chart
        var performanceData = [{
            type: 'bar',
            x: ['Pattern Accuracy', 'Anomaly Precision', 'Prediction Accuracy'],
            y: [
                $($evaluation.Performance.PatternAccuracy),
                $($evaluation.Performance.AnomalyPrecision),
                $($evaluation.Performance.PredictionAccuracy)
            ],
            marker: {
                color: ['#5cb85c', '#d9534f', '#5bc0de']
            }
        }];
        
        Plotly.newPlot('patternChart', patternData);
        Plotly.newPlot('performanceChart', performanceData);
    </script>
</body>
</html>
"@
                $htmlReport | Out-File -FilePath $reportPath -Force
            }
            "JSON" {
                $evaluation | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Force
            }
        }
        
        Write-Verbose "ML evaluation report generated: $reportPath"
        return $reportPath
    }
    catch {
        Write-Error "Failed to generate ML evaluation: $_"
        return $null
    }
}

function Stop-SecurityML {
    [CmdletBinding()]
    param()
    
    try {
        # Generate final evaluation
        $evaluationPath = Get-MLEvaluation
        
        # Clear ML stores
        $script:MLStore.Patterns.Clear()
        $script:MLStore.Models.Clear()
        $script:MLStore.Predictions.Clear()
        $script:MLStore.TrainingData.Clear()
        
        if ($script:MLStore.PatternRecognition) {
            $script:MLStore.PatternRecognition.Features.Clear()
            $script:MLStore.PatternRecognition.Clusters.Clear()
        }
        
        if ($script:MLStore.AnomalyDetection) {
            $script:MLStore.AnomalyDetection.Baseline.Clear()
        }
        
        if ($script:MLStore.Prediction) {
            $script:MLStore.Prediction.TimeSeriesData.Clear()
            $script:MLStore.Prediction.Models.Clear()
        }
        
        Write-Verbose "Security ML stopped. Final evaluation: $evaluationPath"
        return $true
    }
    catch {
        Write-Error "Failed to stop security ML: $_"
        return $false
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Start-SecurityML',
    'Add-SecurityPattern',
    'Add-AnomalyData',
    'Get-SecurityPrediction',
    'Get-MLEvaluation',
    'Stop-SecurityML'
)
