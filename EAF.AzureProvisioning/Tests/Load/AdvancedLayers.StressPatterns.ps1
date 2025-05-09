        try {
            # Create output directory if it doesn't exist
            if (-not (Test-Path $OutputDirectory)) {
                New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
            }
            
            # Export summary report
            $summaryPath = Join-Path $OutputDirectory "pattern_test_summary.txt"
            @"
Attention Mechanism Pattern Test Summary
=====================================

Test Configuration:
-----------------
Variant: $($Results.Variant)
Pattern Type: $($Results.Pattern)
Duration: $($Results.TimePoints[-1]) seconds
Total Time Points: $($Results.TimePoints.Count)
Failure Points: $($Results.FailurePoints.Count)

Performance Summary:
-----------------
* Success Rate: $([Math]::Round(($Results.Metrics | Where-Object Success).Count / $Results.Metrics.Count * 100, 2))%
* Average Latency: $([Math]::Round(($Results.Metrics | Where-Object Success | Measure-Object -Property Latency -Average).Average, 2)) ms
* Peak Memory Usage: $([Math]::Round(($Results.Metrics | Measure-Object -Property MemoryUsage -Maximum).Maximum / 1MB, 2)) MB

Failure Analysis:
--------------
"@ | Out-File $summaryPath
            
            if ($Results.FailurePoints.Count -gt 0) {
                foreach ($failure in $Results.FailurePoints) {
                    @"
Time Point: $($failure.TimePoint) seconds
Config:
  * Batch Size: $($failure.Config.BatchSize)
  * Sequence Length: $($failure.Config.SeqLength)
Error: $($failure.Error)

"@ | Add-Content $summaryPath
                }
            } else {
                "No failures detected during pattern test.`n" | Add-Content $summaryPath
            }
            
            # Add prediction analysis
            @"
Predictive Analysis:
-----------------
"@ | Add-Content $summaryPath
            
            $lastPrediction = $Results.Predictions[-1]
            @"
Final State:
* Failure Likelihood: $([Math]::Round($lastPrediction.FailureLikelihood * 100, 2))%
* Predicted Cause: $($lastPrediction.PredictedCause)
* Time to Failure: $(if ($lastPrediction.TimeToFailure) { "$($lastPrediction.TimeToFailure) seconds" } else { "Not imminent" })

"@ | Add-Content $summaryPath
            
            # Export metrics as CSV
            $csvPath = Join-Path $OutputDirectory "pattern_metrics.csv"
            $csvData = foreach ($i in 0..($Results.TimePoints.Count-1)) {
                [PSCustomObject]@{
                    TimePoint = $Results.TimePoints[$i]
                    Latency = $Results.Metrics[$i].Latency
                    MemoryUsageMB = $Results.Metrics[$i].MemoryUsage / 1MB
                    BatchSize = $Results.Metrics[$i].BatchSize
                    SequenceLength = $Results.Metrics[$i].SequenceLength
                    Success = $Results.Metrics[$i].Success
                    FailureLikelihood = $Results.Predictions[$i].FailureLikelihood
                    PredictedCause = $Results.Predictions[$i].PredictedCause
                }
            }
            $csvData | Export-Csv -Path $csvPath -NoTypeInformation
            
            # Generate pattern analysis
            $analysisPath = Join-Path $OutputDirectory "pattern_analysis.txt"
            $analysis = Analyze-StressPattern -Results $Results
            $analysis | Out-File $analysisPath
            
            Write-Host "Pattern test results exported to: $OutputDirectory"
        }
        catch {
            Write-Error "Failed to export pattern results: $_"
        }
    }
}

function Analyze-StressPattern {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Results
    )
    
    try {
        $analysis = @"
Pattern Analysis Report
=====================

1. Pattern Response Analysis:
--------------------------
"@
        # Analyze response to pattern
        $patternResponse = switch ($Results.Pattern) {
            "Spike" {
                $spikeRecoveries = 0
                $totalSpikes = 0
                
                for ($i = 1; $i -lt $Results.Metrics.Count - 1; $i++) {
                    if ($Results.Metrics[$i].Latency -gt $Results.Metrics[$i-1].Latency * 1.5) {
                        $totalSpikes++
                        if ($Results.Metrics[$i+1].Success) {
                            $spikeRecoveries++
                        }
                    }
                }
                
                @"

Spike Pattern Response:
* Total Spikes: $totalSpikes
* Successful Recoveries: $spikeRecoveries
* Recovery Rate: $([Math]::Round($spikeRecoveries / [Math]::Max(1, $totalSpikes) * 100, 2))%
* Average Recovery Time: $([Math]::Round(($Results.Metrics | Where-Object { $_.Success } | Measure-Object -Property Latency -Average).Average, 2)) ms
"@
            }
            "Wave" {
                $peakLatency = ($Results.Metrics | Measure-Object -Property Latency -Maximum).Maximum
                $troughLatency = ($Results.Metrics | Where-Object Success | Measure-Object -Property Latency -Minimum).Minimum
                $latencyRange = $peakLatency - $troughLatency
                
                @"

Wave Pattern Response:
* Peak Latency: $([Math]::Round($peakLatency, 2)) ms
* Trough Latency: $([Math]::Round($troughLatency, 2)) ms
* Latency Range: $([Math]::Round($latencyRange, 2)) ms
* Stability: $([Math]::Round(100 - ($latencyRange / $troughLatency * 100), 2))%
"@
            }
            "Step" {
                $steps = $Results.Metrics | Group-Object BatchSize
                $maxStableStep = ($steps | Where-Object { 
                    ($_.Group | Where-Object Success).Count -eq $_.Count 
                } | Measure-Object -Property Name -Maximum).Maximum
                
                @"

Step Pattern Response:
* Total Steps: $($steps.Count)
* Max Stable Batch Size: $maxStableStep
* Stability Threshold: $([Math]::Round($maxStableStep / $Results.Metrics[0].BatchSize, 2))x base load
"@
            }
            "Chaos" {
                $successfulConfigs = $Results.Metrics | Where-Object Success
                $failedConfigs = $Results.Metrics | Where-Object { -not $_.Success }
                
                $maxStableBatch = ($successfulConfigs | Measure-Object -Property BatchSize -Maximum).Maximum
                $maxStableSeq = ($successfulConfigs | Measure-Object -Property SequenceLength -Maximum).Maximum
                
                @"

Chaos Pattern Response:
* Successful Configurations: $($successfulConfigs.Count)
* Failed Configurations: $($failedConfigs.Count)
* Max Stable Batch Size: $maxStableBatch
* Max Stable Sequence Length: $maxStableSeq
* Chaos Tolerance: $([Math]::Round($successfulConfigs.Count / $Results.Metrics.Count * 100, 2))%
"@
            }
        }
        
        $analysis += $patternResponse
        
        $analysis += @"

2. Performance Stability Analysis:
------------------------------
* Latency Stability:
  - Mean: $([Math]::Round(($Results.Metrics | Where-Object Success | Measure-Object -Property Latency -Average).Average, 2)) ms
  - Standard Deviation: $([Math]::Round(($Results.Metrics | Where-Object Success | ForEach-Object { [Math]::Pow($_.Latency - ($Results.Metrics | Where-Object Success | Measure-Object -Property Latency -Average).Average, 2) } | Measure-Object -Average).Average, 2)) ms
  - Coefficient of Variation: $([Math]::Round(($Results.Metrics | Where-Object Success | ForEach-Object { [Math]::Pow($_.Latency - ($Results.Metrics | Where-Object Success | Measure-Object -Property Latency -Average).Average, 2) } | Measure-Object -Average).Average / ($Results.Metrics | Where-Object Success | Measure-Object -Property Latency -Average).Average * 100, 2))%

* Memory Stability:
  - Mean Usage: $([Math]::Round(($Results.Metrics | Where-Object Success | Measure-Object -Property MemoryUsage -Average).Average / 1MB, 2)) MB
  - Peak Usage: $([Math]::Round(($Results.Metrics | Measure-Object -Property MemoryUsage -Maximum).Maximum / 1MB, 2)) MB
  - Growth Rate: $([Math]::Round(($Results.Metrics[-1].MemoryUsage - $Results.Metrics[0].MemoryUsage) / $Results.Metrics[0].MemoryUsage * 100, 2))%

3. Predictive Analysis Accuracy:
-----------------------------
"@
        
        # Analyze prediction accuracy
        $correctPredictions = 0
        $totalPredictions = 0
        
        for ($i = 0; $i -lt $Results.Predictions.Count - 1; $i++) {
            if ($Results.Predictions[$i].FailureLikelihood -gt 0.8) {
                $totalPredictions++
                # Check if failure occurred within predicted time
                $actualFailure = $Results.FailurePoints | Where-Object { 
                    $_.TimePoint -gt $Results.TimePoints[$i] -and 
                    $_.TimePoint -le ($Results.TimePoints[$i] + $Results.Predictions[$i].TimeToFailure)
                }
                if ($actualFailure) {
                    $correctPredictions++
                }
            }
        }
        
        $analysis += @"

* High-Risk Predictions: $totalPredictions
* Correct Predictions: $correctPredictions
* Prediction Accuracy: $([Math]::Round($correctPredictions / [Math]::Max(1, $totalPredictions) * 100, 2))%

4. Recommendations:
----------------
"@
        
        # Generate recommendations based on pattern performance
        $recommendations = switch ($Results.Pattern) {
            "Spike" {
                if (($spikeRecoveries / [Math]::Max(1, $totalSpikes)) -gt 0.8) {
                    "* Handles load spikes well - suitable for bursty workloads"
                } else {
                    "* Consider implementing load shedding for spike management"
                }
            }
            "Wave" {
                if (($latencyRange / $troughLatency) -lt 0.5) {
                    "* Good stability under varying load - suitable for dynamic workloads"
                } else {
                    "* Consider implementing adaptive batch sizing"
                }
            }
            "Step" {
                if ($maxStableStep -gt $Results.Metrics[0].BatchSize * 2) {
                    "* Good scaling characteristics - suitable for growing workloads"
                } else {
                    "* Consider implementing gradual load increase mechanisms"
                }
            }
            "Chaos" {
                if (($successfulConfigs.Count / $Results.Metrics.Count) -gt 0.7) {
                    "* High resilience to unpredictable loads - suitable for varied workloads"
                } else {
                    "* Consider implementing more robust error handling"
                }
            }
        }
        
        $analysis += "`n$recommendations`n"
        # Add failure prevention guidance
        if ($Results.FailurePoints.Count -gt 0) {
            $analysis += @"

* Implement circuit breakers at:
  - Batch Size: $([Math]::Floor($maxStableBatch * 0.8))
  - Sequence Length: $([Math]::Floor($maxStableSeq * 0.8))
  
  - Latency exceeding: $([Math]::Round(($Results.Metrics | Where-Object Success | Measure-Object -Property Latency -Average).Average * 1.5, 2)) ms
  - Memory usage above: $([Math]::Round(($Results.Metrics | Measure-Object -Property MemoryUsage -Maximum).Maximum / 1MB * 0.8, 2)) MB
"@
        }
        
        return $analysis
    }
    catch {
        Write-Error "Failed to analyze stress pattern: $_"
        return $null
    }
}

# Example usage
$baseConfig = @{
    BatchSize = 16
    SeqLength = 512
    ModelDim = 64
    NumHeads = 8
    BlockSize = 64
}

$outputDirectory = Join-Path $PSScriptRoot "pattern_test_results"

# Test different patterns
$patterns = @("Spike", "Wave", "Step", "Chaos")
foreach ($pattern in $patterns) {
    $patternResults = Test-StressPattern -Variant "Linear" -Pattern $pattern -OutputDirectory $outputDirectory
}

