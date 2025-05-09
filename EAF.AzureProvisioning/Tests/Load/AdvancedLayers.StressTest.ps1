            New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
        }
        
        # Export summary report
        $summaryPath = Join-Path $OutputDirectory "stress_test_summary.txt"
        @"
Attention Mechanism Stress Test Summary
=====================================

Test Configuration:
-----------------
Max Stress Level: $($Results.MaxStressLevel)
Duration per Level: $($Results.DurationPerLevel) seconds
Base Configuration:
  * Batch Size: $($Results.BaseConfig.BatchSize)
  * Sequence Length: $($Results.BaseConfig.SeqLength)
  * Model Dimension: $($Results.BaseConfig.ModelDim)
Start Time: $($Results.StartTime)

Results by Variant:
-----------------
"@ | Out-File $summaryPath
        
        foreach ($variant in $Results.Results.Keys) {
            $variantResults = $Results.Results[$variant]
            $metrics = $Results.StabilityMetrics[$variant]
            
            @"

$variant Attention:
  * Stability Threshold: Level $($variantResults.StabilityThreshold)
  * Failure Mode: $($variantResults.FailureMode)
  * Stability Score: $($metrics.StabilityScore)%
  * Scaling Efficiency: $($metrics.ScalingEfficiency)%
  * Recovery Capability: $($metrics.RecoveryCapability)%
  
  Maximum Sustainable Load:
    - Batch Size: $($variantResults.MaxSustainableLoad.BatchSize)
    - Sequence Length: $($variantResults.MaxSustainableLoad.SequenceLength)
    - Tokens per Second: $([Math]::Round($variantResults.MaxSustainableLoad.TokensPerSecond, 2))
    
  Recommended Settings:
    - Batch Size: $($metrics.RecommendedSettings.BatchSize)
    - Sequence Length: $($metrics.RecommendedSettings.SequenceLength)
    - Chunk Size: $($metrics.RecommendedSettings.ChunkSize)
    - Expected Throughput: $($metrics.RecommendedSettings.ExpectedThroughput) tokens/sec
    - Max Memory Usage: $($metrics.RecommendedSettings.MaxMemoryUsage) MB
"@ | Add-Content $summaryPath
        }
        
        # Export detailed metrics as CSV
        $csvPath = Join-Path $OutputDirectory "stress_test_metrics.csv"
        $csvData = foreach ($variant in $Results.Results.Keys) {
            $variantResults = $Results.Results[$variant]
            $metrics = $Results.StabilityMetrics[$variant]
            
            foreach ($level in $variantResults.Levels.Keys) {
                $levelResults = $variantResults.Levels[$level]
                
                [PSCustomObject]@{
                    Variant = $variant
                    StressLevel = $level
                    BatchSize = $levelResults.Config.BatchSize
                    SequenceLength = $levelResults.Config.SeqLength
                    CompletedBatches = $levelResults.CompletedBatches
                    FailedBatches = $levelResults.FailedBatches
                    AverageLatency = $levelResults.Metrics.AverageLatency
                    Throughput = $levelResults.Metrics.Throughput
                    MemoryUsageMB = $levelResults.Metrics.AverageMemoryUsage / 1MB
                    LatencySpikes = $levelResults.StabilityIndicators.LatencySpikes
                    MemorySpikes = $levelResults.StabilityIndicators.MemorySpikes
                    ErrorBursts = $levelResults.StabilityIndicators.ErrorBursts
                    RecoveryTime = $levelResults.StabilityIndicators.RecoveryTime
                }
            }
        }
        $csvData | Export-Csv -Path $csvPath -NoTypeInformation
        
        # Generate comparative analysis
        $analysisPath = Join-Path $OutputDirectory "comparative_analysis.txt"
        $analysis = Analyze-StressTestResults -Results $Results
        $analysis | Out-File $analysisPath
        
        Write-Host "Stress test results exported to: $OutputDirectory"
    }
    catch {
        Write-Error "Failed to export stress test results: $_"
    }
}

function Analyze-StressTestResults {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Results
    )
    
    try {
        $analysis = @"
Comparative Analysis of Attention Mechanisms
=========================================

1. Overall Stability Rankings:
---------------------------
"@
        # Rank variants by stability score
        $stabilityRankings = $Results.StabilityMetrics.GetEnumerator() | 
            Sort-Object { $_.Value.StabilityScore } -Descending |
            ForEach-Object { "  * $($_.Key): $($_.Value.StabilityScore)% stable" }
        $analysis += "`n" + ($stabilityRankings -join "`n")
        
        $analysis += @"

2. Performance Characteristics:
---------------------------
"@
        foreach ($variant in $Results.Results.Keys) {
            $metrics = $Results.StabilityMetrics[$variant]
            $results = $Results.Results[$variant]
            
            $analysis += @"

$variant Attention:
  * Scaling Efficiency: $($metrics.ScalingEfficiency)%
  * Recovery Capability: $($metrics.RecoveryCapability)%
  * Primary Failure Mode: $($results.FailureMode)
"@
        }
        
        $analysis += @"

3. Use Case Recommendations:
-------------------------
"@
        foreach ($variant in $Results.Results.Keys) {
            $metrics = $Results.StabilityMetrics[$variant]
            $results = $Results.Results[$variant]
            
            $recommendation = switch ($variant) {
                "Linear" {
                    if ($metrics.ScalingEfficiency -gt 80) {
                        "Best for general use cases with moderate sequence lengths"
                    } else {
                        "Suitable for short to medium sequences with stable memory usage"
                    }
                }
                "LSH" {
                    if ($metrics.StabilityScore -gt 70) {
                        "Optimal for very long sequences with memory constraints"
                    } else {
                        "Consider for long sequences with adequate memory resources"
                    }
                }
                "Sparse" {
                    if ($metrics.RecoveryCapability -gt 80) {
                        "Ideal for structured patterns and local attention needs"
                    } else {
                        "Best for scenarios with predictable attention patterns"
                    }
                }
                "Reversible" {
                    if ($metrics.StabilityScore -gt 80) {
                        "Recommended for memory-critical applications"
                    } else {
                        "Consider when memory efficiency is the primary concern"
                    }
                }
            }
            
            $analysis += @"

$variant Attention:
  * Recommended Use Case: $recommendation
  * Optimal Sequence Length: Up to $($results.MaxSustainableLoad.SequenceLength) tokens
  * Maximum Batch Size: $($metrics.RecommendedSettings.BatchSize)
  * Expected Throughput: $($metrics.RecommendedSettings.ExpectedThroughput) tokens/sec
"@
        }
        
        $analysis += @"

4. Resource Utilization Comparison:
-------------------------------
"@
        foreach ($variant in $Results.Results.Keys) {
            $metrics = $Results.StabilityMetrics[$variant]
            
            $analysis += @"

$variant Attention:
  * Memory Efficiency: $([Math]::Round($metrics.RecommendedSettings.ExpectedThroughput / $metrics.RecommendedSettings.MaxMemoryUsage, 2)) tokens/sec/MB
  * Computational Efficiency: $([Math]::Round($metrics.ScalingEfficiency / 100 * $metrics.RecommendedSettings.ExpectedThroughput, 2)) effective tokens/sec
  * Resource Balance: $([Math]::Round(($metrics.StabilityScore + $metrics.ScalingEfficiency + $metrics.RecoveryCapability) / 3, 2))%
"@
        }
        
        return $analysis
    }
    catch {
        Write-Error "Failed to analyze stress test results: $_"
        return $null
    }
}

# Example usage
$stressTestConfig = @{
    BatchSize = 16
    SeqLength = 512
    ModelDim = 64
    NumHeads = 8
    BlockSize = 64
}

$outputDirectory = Join-Path $PSScriptRoot "stress_test_results"
$stressTestResults = Start-AttentionStressTest -BaseConfig $stressTestConfig -MaxStressLevel 5 -DurationPerLevel 60 -OutputDirectory $outputDirectory

