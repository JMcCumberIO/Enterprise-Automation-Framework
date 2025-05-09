# Load Testing for Advanced Attention Mechanisms

function Start-AttentionLoadTest {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Config,
        
        [Parameter(Mandatory=$false)]
        [int]$Duration = 300, # Duration in seconds
        
        [Parameter(Mandatory=$false)]
        [int]$ConcurrentBatches = 4,
        
        [Parameter(Mandatory=$false)]
        [string[]]$Variants = @("Linear", "LSH", "Sparse", "Reversible"),
        
        [Parameter(Mandatory=$false)]
        [string]$OutputDirectory
    )
    
    try {
        $results = @{
            StartTime = Get-Date
            Duration = $Duration
            Config = $Config
            ConcurrentBatches = $ConcurrentBatches
            Results = @{}
            Metrics = @{}
        }
        
        Write-Host "Starting load test with configuration:"
        Write-Host "  Duration: $Duration seconds"
        Write-Host "  Concurrent Batches: $ConcurrentBatches"
        Write-Host "  Sequence Length: $($Config.SeqLength)"
        Write-Host "  Model Dimension: $($Config.ModelDim)"
        
        foreach ($variant in $Variants) {
            Write-Host "`nTesting $variant attention..."
            
            $variantResults = Test-AttentionVariant `
                -Variant $variant `
                -Config $Config `
                -Duration $Duration `
                -ConcurrentBatches $ConcurrentBatches
            
            $results.Results[$variant] = $variantResults
            $results.Metrics[$variant] = Calculate-LoadMetrics -Results $variantResults
            
            # Report progress
            Write-Host "  Completed: $($variantResults.CompletedBatches) batches"
            Write-Host "  Average Latency: $([Math]::Round($results.Metrics[$variant].AverageLatency, 2)) ms"
            Write-Host "  Throughput: $([Math]::Round($results.Metrics[$variant].Throughput, 2)) tokens/sec"
            Write-Host "  Error Rate: $([Math]::Round($results.Metrics[$variant].ErrorRate * 100, 2))%"
        }
        
        # Export results if directory specified
        if ($OutputDirectory) {
            Export-LoadTestResults -Results $results -OutputDirectory $OutputDirectory
        }
        
        return $results
    }
    catch {
        Write-Error "Failed in attention load test: $_"
        return $null
    }
}

function Test-AttentionVariant {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Variant,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Config,
        
        [Parameter(Mandatory=$true)]
        [int]$Duration,
        
        [Parameter(Mandatory=$true)]
        [int]$ConcurrentBatches
    )
    
    try {
        $layer = switch ($Variant) {
            "Linear" {
                Add-EfficientAttention -Name "load_linear" -InputShape @($Config.SeqLength, $Config.ModelDim) -NumHeads $Config.NumHeads -Variant "Linear" -ChunkSize $Config.BlockSize
            }
            "LSH" {
                Add-EfficientAttention -Name "load_lsh" -InputShape @($Config.SeqLength, $Config.ModelDim) -NumHeads $Config.NumHeads -Variant "LSH" -ChunkSize $Config.BlockSize
            }
            "Sparse" {
                Add-EfficientAttention -Name "load_sparse" -InputShape @($Config.SeqLength, $Config.ModelDim) -NumHeads $Config.NumHeads -Variant "Sparse" -ChunkSize $Config.BlockSize
            }
            "Reversible" {
                Add-ReversibleAttention -Name "load_rev" -InputShape @($Config.SeqLength, $Config.ModelDim) -NumHeads $Config.NumHeads -AttentionType "Linear" -ChunkSize $Config.BlockSize
            }
        }
        
        $results = @{
            StartTime = Get-Date
            CompletedBatches = 0
            FailedBatches = 0
            Latencies = [System.Collections.ArrayList]@()
            MemoryUsage = [System.Collections.ArrayList]@()
            Errors = [System.Collections.ArrayList]@()
        }
        
        $jobs = @()
        $endTime = (Get-Date).AddSeconds($Duration)
        
        # Start concurrent batch processing
        for ($i = 0; $i -lt $ConcurrentBatches; $i++) {
            $jobs += Start-Job -ScriptBlock {
                param ($Layer, $Config, $EndTime)
                
                $batchResults = @{
                    CompletedBatches = 0
                    FailedBatches = 0
                    Latencies = [System.Collections.ArrayList]@()
                    Errors = [System.Collections.ArrayList]@()
                }
                
                while ((Get-Date) -lt $EndTime) {
                    try {
                        # Create input tensor
                        $input = New-Object 'double[,,]' $Config.BatchSize,$Config.SeqLength,$Config.ModelDim
                        
                        # Initialize with random values
                        $random = New-Object Random
                        for ($b = 0; $b -lt $Config.BatchSize; $b++) {
                            for ($s = 0; $s -lt $Config.SeqLength; $s++) {
                                for ($d = 0; $d -lt $Config.ModelDim; $d++) {
                                    $input[$b,$s,$d] = $random.NextDouble() - 0.5
                                }
                            }
                        }
                        
                        # Process batch
                        $sw = [System.Diagnostics.Stopwatch]::StartNew()
                        $output = switch ($Layer.Type) {
                            "ReversibleAttention" {
                                ReversibleAttentionForward -Layer $Layer -Input $input -Training $true
                            }
                            default {
                                EfficientAttentionForward -Layer $Layer -Input $input -Training $true
                            }
                        }
                        $sw.Stop()
                        
                        # Record results
                        $batchResults.CompletedBatches++
                        [void]$batchResults.Latencies.Add($sw.ElapsedMilliseconds)
                    }
                    catch {
                        $batchResults.FailedBatches++
                        [void]$batchResults.Errors.Add($_.Exception.Message)
                    }
                }
                
                return $batchResults
            } -ArgumentList $layer,$Config,$endTime
        }
        
        # Monitor memory usage during test
        while ((Get-Date) -lt $endTime) {
            [void]$results.MemoryUsage.Add([System.GC]::GetTotalMemory($false))
            Start-Sleep -Milliseconds 100
        }
        
        # Collect results from all jobs
        foreach ($job in $jobs) {
            $jobResults = Receive-Job -Job $job -Wait
            $results.CompletedBatches += $jobResults.CompletedBatches
            $results.FailedBatches += $jobResults.FailedBatches
            $results.Latencies.AddRange($jobResults.Latencies)
            $results.Errors.AddRange($jobResults.Errors)
        }
        
        return $results
    }
    catch {
        Write-Error "Failed in attention variant load test: $_"
        return $null
    }
}

function Calculate-LoadMetrics {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Results
    )
    
    try {
        $metrics = @{
            TotalBatches = $Results.CompletedBatches + $Results.FailedBatches
            SuccessRate = 0
            ErrorRate = 0
            AverageLatency = 0
            P95Latency = 0
            P99Latency = 0
            MaxLatency = 0
            MinLatency = 0
            Throughput = 0
            AverageMemoryUsage = 0
            PeakMemoryUsage = 0
        }
        
        if ($metrics.TotalBatches -gt 0) {
            $metrics.SuccessRate = $Results.CompletedBatches / $metrics.TotalBatches
            $metrics.ErrorRate = $Results.FailedBatches / $metrics.TotalBatches
        }
        
        if ($Results.Latencies.Count -gt 0) {
            $sortedLatencies = $Results.Latencies | Sort-Object
            $metrics.AverageLatency = ($Results.Latencies | Measure-Object -Average).Average
            $metrics.P95Latency = $sortedLatencies[[Math]::Floor($sortedLatencies.Count * 0.95)]
            $metrics.P99Latency = $sortedLatencies[[Math]::Floor($sortedLatencies.Count * 0.99)]
            $metrics.MaxLatency = ($sortedLatencies | Measure-Object -Maximum).Maximum
            $metrics.MinLatency = ($sortedLatencies | Measure-Object -Minimum).Minimum
            
            # Calculate throughput (tokens per second)
            $totalTime = ($Results.Latencies | Measure-Object -Sum).Sum / 1000 # Convert to seconds
            $totalTokens = $Results.CompletedBatches * $Config.BatchSize * $Config.SeqLength
            $metrics.Throughput = $totalTokens / $totalTime
        }
        
        if ($Results.MemoryUsage.Count -gt 0) {
            $metrics.AverageMemoryUsage = ($Results.MemoryUsage | Measure-Object -Average).Average
            $metrics.PeakMemoryUsage = ($Results.MemoryUsage | Measure-Object -Maximum).Maximum
        }
        
        return $metrics
    }
    catch {
        Write-Error "Failed to calculate load metrics: $_"
        return $null
    }
}

function Export-LoadTestResults {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Results,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputDirectory
    )
    
    try {
        # Create output directory if it doesn't exist
        if (-not (Test-Path $OutputDirectory)) {
            New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
        }
        
        # Export summary report
        $summaryPath = Join-Path $OutputDirectory "load_test_summary.txt"
        @"
Attention Mechanism Load Test Summary
===================================

Test Configuration:
-----------------
Duration: $($Results.Duration) seconds
Concurrent Batches: $($Results.ConcurrentBatches)
Sequence Length: $($Results.Config.SeqLength)
Model Dimension: $($Results.Config.ModelDim)
Start Time: $($Results.StartTime)

Results by Variant:
-----------------
"@ | Out-File $summaryPath
        
        foreach ($variant in $Results.Results.Keys) {
            $metrics = $Results.Metrics[$variant]
            @"

$variant Attention:
  * Completed Batches: $($Results.Results[$variant].CompletedBatches)
  * Failed Batches: $($Results.Results[$variant].FailedBatches)
  * Success Rate: $([Math]::Round($metrics.SuccessRate * 100, 2))%
  * Latency (ms):
    - Average: $([Math]::Round($metrics.AverageLatency, 2))
    - P95: $([Math]::Round($metrics.P95Latency, 2))
    - P99: $([Math]::Round($metrics.P99Latency, 2))
    - Min: $([Math]::Round($metrics.MinLatency, 2))
    - Max: $([Math]::Round($metrics.MaxLatency, 2))
  * Throughput: $([Math]::Round($metrics.Throughput, 2)) tokens/sec
  * Memory Usage (MB):
    - Average: $([Math]::Round($metrics.AverageMemoryUsage / 1MB, 2))
    - Peak: $([Math]::Round($metrics.PeakMemoryUsage / 1MB, 2))
"@ | Add-Content $summaryPath
        }
        
        # Export detailed metrics as CSV
        $csvPath = Join-Path $OutputDirectory "load_test_metrics.csv"
        $csvData = foreach ($variant in $Results.Results.Keys) {
            [PSCustomObject]@{
                Variant = $variant
                CompletedBatches = $Results.Results[$variant].CompletedBatches
                FailedBatches = $Results.Results[$variant].FailedBatches
                SuccessRate = $Results.Metrics[$variant].SuccessRate
                AverageLatency = $Results.Metrics[$variant].AverageLatency
                P95Latency = $Results.Metrics[$variant].P95Latency
                P99Latency = $Results.Metrics[$variant].P99Latency
                MinLatency = $Results.Metrics[$variant].MinLatency
                MaxLatency = $Results.Metrics[$variant].MaxLatency
                Throughput = $Results.Metrics[$variant].Throughput
                AverageMemoryMB = $Results.Metrics[$variant].AverageMemoryUsage / 1MB
                PeakMemoryMB = $Results.Metrics[$variant].PeakMemoryUsage / 1MB
            }
        }
        $csvData | Export-Csv -Path $csvPath -NoTypeInformation
        
        # Export detailed latency distributions
        $distributionsPath = Join-Path $OutputDirectory "latency_distributions"
        New-Item -ItemType Directory -Path $distributionsPath -Force | Out-Null
        
        foreach ($variant in $Results.Results.Keys) {
            $latencyPath = Join-Path $distributionsPath "$variant`_latencies.csv"
            $Results.Results[$variant].Latencies | 
                ForEach-Object { [PSCustomObject]@{ Latency = $_ } } | 
                Export-Csv -Path $latencyPath -NoTypeInformation
        }
        
        Write-Host "Load test results exported to: $OutputDirectory"
    }
    catch {
        Write-Error "Failed to export load test results: $_"
    }
}

# Example usage
$loadTestConfig = @{
    BatchSize = 16
    SeqLength = 512
    ModelDim = 64
    NumHeads = 8
    BlockSize = 64
}

$outputDirectory = Join-Path $PSScriptRoot "load_test_results"
$loadTestResults = Start-AttentionLoadTest -Config $loadTestConfig -Duration 300 -ConcurrentBatches 4 -OutputDirectory $outputDirectory

