# Performance Benchmarking for Advanced Attention Variants

function Measure-AttentionPerformance {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Variant,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Config,
        
        [Parameter(Mandatory=$false)]
        [int]$NumTrials = 5
    )
    
    try {
        $results = @{
            Variant = $Variant
            InitTime = 0
            ForwardTime = 0
            MemoryUsage = 0
            Config = $Config
        }
        
        # Warmup
        $layer = $null
        switch ($Variant) {
            "Linear" {
                $layer = Add-EfficientAttention -Name "bench_linear" `
                    -InputShape @($Config.SeqLength, $Config.ModelDim) `
                    -NumHeads $Config.NumHeads `
                    -Variant "Linear" `
                    -ChunkSize $Config.BlockSize
            }
            "LSH" {
                $layer = Add-EfficientAttention -Name "bench_lsh" `
                    -InputShape @($Config.SeqLength, $Config.ModelDim) `
                    -NumHeads $Config.NumHeads `
                    -Variant "LSH" `
                    -ChunkSize $Config.BlockSize
            }
            "Sparse" {
                $layer = Add-EfficientAttention -Name "bench_sparse" `
                    -InputShape @($Config.SeqLength, $Config.ModelDim) `
                    -NumHeads $Config.NumHeads `
                    -Variant "Sparse" `
                    -ChunkSize $Config.BlockSize
            }
            "Reversible" {
                $layer = Add-ReversibleAttention -Name "bench_rev" `
                    -InputShape @($Config.SeqLength, $Config.ModelDim) `
                    -NumHeads $Config.NumHeads `
                    -AttentionType "Linear" `
                    -ChunkSize $Config.BlockSize
            }
        }
        
        $input = New-Object 'double[,,]' $Config.BatchSize,$Config.SeqLength,$Config.ModelDim
        
        # Initialize input with random values
        $random = New-Object Random
        for ($b = 0; $b -lt $Config.BatchSize; $b++) {
            for ($s = 0; $s -lt $Config.SeqLength; $s++) {
                for ($d = 0; $d -lt $Config.ModelDim; $d++) {
                    $input[$b,$s,$d] = $random.NextDouble() - 0.5
                }
            }
        }
        
        # Measure initialization time
        $initWatch = [System.Diagnostics.Stopwatch]::StartNew()
        switch ($Variant) {
            "Linear" {
                $layer = Add-EfficientAttention -Name "bench_linear" `
                    -InputShape @($Config.SeqLength, $Config.ModelDim) `
                    -NumHeads $Config.NumHeads `
                    -Variant "Linear" `
                    -ChunkSize $Config.BlockSize
            }
            "LSH" {
                $layer = Add-EfficientAttention -Name "bench_lsh" `
                    -InputShape @($Config.SeqLength, $Config.ModelDim) `
                    -NumHeads $Config.NumHeads `
                    -Variant "LSH" `
                    -ChunkSize $Config.BlockSize
            }
            "Sparse" {
                $layer = Add-EfficientAttention -Name "bench_sparse" `
                    -InputShape @($Config.SeqLength, $Config.ModelDim) `
                    -NumHeads $Config.NumHeads `
                    -Variant "Sparse" `
                    -ChunkSize $Config.BlockSize
            }
            "Reversible" {
                $layer = Add-ReversibleAttention -Name "bench_rev" `
                    -InputShape @($Config.SeqLength, $Config.ModelDim) `
                    -NumHeads $Config.NumHeads `
                    -AttentionType "Linear" `
                    -ChunkSize $Config.BlockSize
            }
        }
        $initWatch.Stop()
        $results.InitTime = $initWatch.ElapsedMilliseconds
        
        # Measure forward pass time and memory usage
        $totalForwardTime = 0
        $totalMemoryUsage = 0
        
        for ($trial = 0; $trial -lt $NumTrials; $trial++) {
            # Clear memory before measurement
            [System.GC]::Collect()
            $startMemory = [System.GC]::GetTotalMemory($true)
            
            $forwardWatch = [System.Diagnostics.Stopwatch]::StartNew()
            switch ($Variant) {
                "Linear" {
                    $output = EfficientAttentionForward -Layer $layer -Input $input -Training $true
                }
                "LSH" {
                    $output = EfficientAttentionForward -Layer $layer -Input $input -Training $true
                }
                "Sparse" {
                    $output = EfficientAttentionForward -Layer $layer -Input $input -Training $true
                }
                "Reversible" {
                    $output = ReversibleAttentionForward -Layer $layer -Input $input -Training $true
                }
            }
            $forwardWatch.Stop()
            
            $endMemory = [System.GC]::GetTotalMemory($true)
            $totalForwardTime += $forwardWatch.ElapsedMilliseconds
            $totalMemoryUsage += ($endMemory - $startMemory)
        }
        
        $results.ForwardTime = $totalForwardTime / $NumTrials
        $results.MemoryUsage = $totalMemoryUsage / $NumTrials
        
        return $results
    }
    catch {
        Write-Error "Failed in attention performance measurement: $_"
        return $null
    }
}

function Compare-AttentionVariants {
    param (
        [Parameter(Mandatory=$true)]
        [array]$Configs,
        
        [Parameter(Mandatory=$false)]
        [int]$NumTrials = 5
    )
    
    try {
        $variants = @("Linear", "LSH", "Sparse", "Reversible")
        $results = @()
        
        foreach ($config in $Configs) {
            Write-Host "Testing configuration: BatchSize=$($config.BatchSize), SeqLength=$($config.SeqLength), ModelDim=$($config.ModelDim)"
            
            foreach ($variant in $variants) {
                Write-Host "  Measuring $variant attention..."
                $variantResults = Measure-AttentionPerformance -Variant $variant -Config $config -NumTrials $NumTrials
                
                if ($variantResults) {
                    $results += $variantResults
                    
                    Write-Host "    Init Time: $($variantResults.InitTime) ms"
                    Write-Host "    Forward Time: $($variantResults.ForwardTime) ms"
                    Write-Host "    Memory Usage: $([Math]::Round($variantResults.MemoryUsage / 1MB, 2)) MB"
                }
            }
        }
        
        return $results
    }
    catch {
        Write-Error "Failed in attention variant comparison: $_"
        return $null
    }
}

# Example configurations for benchmarking
$benchmarkConfigs = @(
    @{
        BatchSize = 8
        SeqLength = 512
        ModelDim = 64
        NumHeads = 8
        BlockSize = 64
        Description = "Base Configuration"
    },
    @{
        BatchSize = 4
        SeqLength = 1024
        ModelDim = 64
        NumHeads = 8
        BlockSize = 128
        Description = "Long Sequence"
    },
    @{
        BatchSize = 2
        SeqLength = 2048
        ModelDim = 64
        NumHeads = 8
        BlockSize = 256
        Description = "Very Long Sequence"
    },
    @{
        BatchSize = 16
        SeqLength = 256
        ModelDim = 128
        NumHeads = 16
        BlockSize = 32
        Description = "High Dimension"
    }
)

# Run benchmarks
Write-Host "Starting attention mechanism benchmarks..."
$benchmarkResults = Compare-AttentionVariants -Configs $benchmarkConfigs -NumTrials 5

# Analyze and report results
Write-Host "`nBenchmark Summary:"
foreach ($config in $benchmarkConfigs) {
    Write-Host "`n$($config.Description):"
    Write-Host "Configuration: BatchSize=$($config.BatchSize), SeqLength=$($config.SeqLength), ModelDim=$($config.ModelDim)"
    
    $configResults = $benchmarkResults | Where-Object { 
        $_.Config.BatchSize -eq $config.BatchSize -and 
        $_.Config.SeqLength -eq $config.SeqLength -and 
        $_.Config.ModelDim -eq $config.ModelDim 
    }
    
    Write-Host "`nVariant      Init(ms)  Forward(ms)  Memory(MB)"
    Write-Host "----------------------------------------"
    foreach ($result in $configResults) {
        $memoryMB = [Math]::Round($result.MemoryUsage / 1MB, 2)
        Write-Host ("{0,-12}{1,-10}{2,-12}{3,-10}" -f $result.Variant, $result.InitTime, $result.ForwardTime, $memoryMB)
    }
}


function Export-BenchmarkVisualization {
    param (
        [Parameter(Mandatory=$true)]
        [array]$Results,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    try {
        # Create HTML report with embedded charts
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Attention Mechanism Benchmark Results</title>
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .chart { width: 100%; height: 500px; margin: 20px 0; }
        .metric-card { 
            border: 1px solid #ddd; 
            padding: 15px; 
            margin: 10px 0; 
            border-radius: 5px;
        }
        .summary-table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        .summary-table th, .summary-table td {
            border: 1px solid #ddd;
            padding: 8px;
            text-align: left;
        }
        .summary-table th {
            background-color: #f5f5f5;
        }
    </style>
</head>
<body>
    <h1>Attention Mechanism Benchmark Results</h1>
    
    <div class="metric-card">
        <h2>Performance Overview</h2>
        <div id="performanceChart" class="chart"></div>
    </div>
    
    <div class="metric-card">
        <h2>Memory Usage Comparison</h2>
        <div id="memoryChart" class="chart"></div>
    </div>
    
    <div class="metric-card">
        <h2>Scaling Analysis</h2>
        <div id="scalingChart" class="chart"></div>
    </div>
    
    <div class="metric-card">
        <h2>Detailed Results</h2>
        <table class="summary-table">
            <tr>
                <th>Configuration</th>
                <th>Variant</th>
                <th>Init Time (ms)</th>
                <th>Forward Time (ms)</th>
                <th>Memory Usage (MB)</th>
            </tr>
"@

        # Add rows to the results table
        foreach ($result in $Results) {
            $config = $result.Config
            $memoryMB = [Math]::Round($result.MemoryUsage / 1MB, 2)
            
            $html += @"
            <tr>
                <td>Batch: $($config.BatchSize), Seq: $($config.SeqLength), Dim: $($config.ModelDim)</td>
                <td>$($result.Variant)</td>
                <td>$($result.InitTime)</td>
                <td>$($result.ForwardTime)</td>
                <td>$memoryMB</td>
            </tr>
"@
        }

        $html += @"
        </table>
    </div>
    
    <script>
        // Prepare data for charts
        const results = $(ConvertTo-Json $Results -Compress);
        
        // Performance comparison chart
        const variants = [...new Set(results.map(r => r.Variant))];
        const configs = [...new Set(results.map(r => `Batch: ${r.Config.BatchSize}, Seq: ${r.Config.SeqLength}`))];
        
        const performanceData = variants.map(variant => ({
            name: variant,
            x: configs,
            y: results.filter(r => r.Variant === variant).map(r => r.ForwardTime),
            type: 'bar'
        }));
        
        Plotly.newPlot('performanceChart', performanceData, {
            title: 'Forward Pass Time by Configuration',
            barmode: 'group',
            xaxis: { title: 'Configuration' },
            yaxis: { title: 'Time (ms)' }
        });
        
        // Memory usage chart
        const memoryData = variants.map(variant => ({
            name: variant,
            x: configs,
            y: results.filter(r => r.Variant === variant).map(r => r.MemoryUsage / 1024 / 1024),
            type: 'bar'
        }));
        
        Plotly.newPlot('memoryChart', memoryData, {
            title: 'Memory Usage by Configuration',
            barmode: 'group',
            xaxis: { title: 'Configuration' },
            yaxis: { title: 'Memory (MB)' }
        });
        
        // Scaling analysis chart
        const seqLengths = [...new Set(results.map(r => r.Config.SeqLength))].sort((a, b) => a - b);
        
        const scalingData = variants.map(variant => ({
            name: variant,
            x: seqLengths,
            y: seqLengths.map(seq => {
                const result = results.find(r => r.Variant === variant && r.Config.SeqLength === seq);
                return result ? result.ForwardTime : null;
            }),
            type: 'scatter',
            mode: 'lines+markers'
        }));
        
        Plotly.newPlot('scalingChart', scalingData, {
            title: 'Scaling with Sequence Length',
            xaxis: { title: 'Sequence Length', type: 'log' },
            yaxis: { title: 'Forward Time (ms)', type: 'log' }
        });
    </script>
</body>
</html>
"@

        # Export HTML report
        $html | Out-File -FilePath $OutputPath -Encoding UTF8
        
        Write-Host "Benchmark visualization exported to: $OutputPath"
        
        # Calculate and display key insights
        Write-Host "`nKey Insights:"
        
        # 1. Fastest variant for each configuration
        Write-Host "`nFastest Variants:"
        $Results | Group-Object -Property { "$($_.Config.BatchSize)_$($_.Config.SeqLength)" } | ForEach-Object {
            $fastest = $_.Group | Sort-Object ForwardTime | Select-Object -First 1
            Write-Host "  Batch: $($fastest.Config.BatchSize), Seq: $($fastest.Config.SeqLength) -> $($fastest.Variant) ($($fastest.ForwardTime) ms)"
        }
        
        # 2. Most memory-efficient variant
        Write-Host "`nMost Memory-Efficient Variants:"
        $Results | Group-Object -Property { "$($_.Config.BatchSize)_$($_.Config.SeqLength)" } | ForEach-Object {
            $efficient = $_.Group | Sort-Object MemoryUsage | Select-Object -First 1
            Write-Host "  Batch: $($efficient.Config.BatchSize), Seq: $($efficient.Config.SeqLength) -> $($efficient.Variant) ($([Math]::Round($efficient.MemoryUsage / 1MB, 2)) MB)"
        }
        
        # 3. Scaling efficiency
        Write-Host "`nScaling Efficiency (time increase factor when doubling sequence length):"
        foreach ($variant in ($Results | Select-Object -ExpandProperty Variant -Unique)) {
            $variantResults = $Results | Where-Object { $_.Variant -eq $variant } | Sort-Object { $_.Config.SeqLength }
            if ($variantResults.Count -gt 1) {
                $scalingFactor = $variantResults[-1].ForwardTime / $variantResults[0].ForwardTime
                $lengthFactor = $variantResults[-1].Config.SeqLength / $variantResults[0].Config.SeqLength
                $efficiency = [Math]::Log($scalingFactor, $lengthFactor)
                Write-Host "  $variant -> $([Math]::Round($efficiency, 2))x"
            }
        }
    }
    catch {
        Write-Error "Failed to export benchmark visualization: $_"
    }
}

# Export visualizations for the benchmark results
$visualizationPath = Join-Path $PSScriptRoot "attention_benchmark_results.html"
Export-BenchmarkVisualization -Results $benchmarkResults -OutputPath $visualizationPath


function Export-BenchmarkResults {
    param (
        [Parameter(Mandatory=$true)]
        [array]$Results,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputDirectory,
        
        [Parameter(Mandatory=$false)]
        [string[]]$Formats = @("HTML", "CSV", "JSON")
    )
    
    try {
        # Create output directory if it doesn't exist
        if (-not (Test-Path $OutputDirectory)) {
            New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
        }
        
        # Export in specified formats
        foreach ($format in $Formats) {
            switch ($format) {
                "CSV" {
                    $csvPath = Join-Path $OutputDirectory "attention_benchmark_results.csv"
                    $csvData = $Results | ForEach-Object {
                        [PSCustomObject]@{
                            Variant = $_.Variant
                            BatchSize = $_.Config.BatchSize
                            SequenceLength = $_.Config.SeqLength
                            ModelDimension = $_.Config.ModelDim
                            InitializationTime = $_.InitTime
                            ForwardTime = $_.ForwardTime
                            MemoryUsageMB = [Math]::Round($_.MemoryUsage / 1MB, 2)
                            FLOPs = Calculate-FLOPs -Config $_.Config -Variant $_.Variant
                            EfficiencyScore = Calculate-EfficiencyScore -Result $_
                        }
                    }
                    $csvData | Export-Csv -Path $csvPath -NoTypeInformation
                    Write-Host "CSV results exported to: $csvPath"
                }
                
                "JSON" {
                    $jsonPath = Join-Path $OutputDirectory "attention_benchmark_results.json"
                    $jsonData = $Results | ForEach-Object {
                        @{
                            Variant = $_.Variant
                            Configuration = $_.Config
                            Performance = @{
                                InitializationTime = $_.InitTime
                                ForwardTime = $_.ForwardTime
                                MemoryUsageMB = [Math]::Round($_.MemoryUsage / 1MB, 2)
                                FLOPs = Calculate-FLOPs -Config $_.Config -Variant $_.Variant
                                EfficiencyScore = Calculate-EfficiencyScore -Result $_
                            }
                            Analysis = @{
                                MemoryEfficiency = Calculate-MemoryEfficiency -Result $_
                                ComputationalEfficiency = Calculate-ComputationalEfficiency -Result $_
                                ScalingFactor = Calculate-ScalingFactor -Result $_ -Results $Results
                            }
                        }
                    }
                    $jsonData | ConvertTo-Json -Depth 10 | Out-File $jsonPath
                    Write-Host "JSON results exported to: $jsonPath"
                }
                
                "HTML" {
                    $htmlPath = Join-Path $OutputDirectory "attention_benchmark_results.html"
                    Export-BenchmarkVisualization -Results $Results -OutputPath $htmlPath
                }
            }
        }
        
        # Generate recommendations report
        $recommendationsPath = Join-Path $OutputDirectory "attention_recommendations.txt"
        Export-AttentionRecommendations -Results $Results -OutputPath $recommendationsPath
        
    }
    catch {
        Write-Error "Failed to export benchmark results: $_"
    }
}

function Calculate-FLOPs {
    param ($Config, $Variant)
    
    $seqLength = $Config.SeqLength
    $modelDim = $Config.ModelDim
    $batchSize = $Config.BatchSize
    
    # Base FLOPs for attention computation
    $baseFLOPs = switch ($Variant) {
        "Linear" {
            # Linear attention: O(N*D) complexity
            $batchSize * $seqLength * $modelDim * 4
        }
        "LSH" {
            # LSH attention: O(N*log(N)*D) complexity
            $batchSize * $seqLength * [Math]::Log($seqLength, 2) * $modelDim * 2
        }
        "Sparse" {
            # Sparse attention: O(N*sqrt(N)*D) complexity
            $batchSize * $seqLength * [Math]::Sqrt($seqLength) * $modelDim * 2
        }
        "Reversible" {
            # Reversible attention: Similar to linear but with additional overhead
            $batchSize * $seqLength * $modelDim * 5
        }
        default {
            # Standard attention: O(N^2*D) complexity
            $batchSize * $seqLength * $seqLength * $modelDim
        }
    }
    
    return $baseFLOPs
}

function Calculate-EfficiencyScore {
    param ($Result)
    
    $memoryFactor = 1 / ($Result.MemoryUsage / 1MB)
    $timeFactor = 1 / $Result.ForwardTime
    $flopsFactor = 1 / (Calculate-FLOPs -Config $Result.Config -Variant $Result.Variant)
    
    # Weighted combination of factors
    $score = ($memoryFactor * 0.4 + $timeFactor * 0.4 + $flopsFactor * 0.2) * 1000
    return [Math]::Round($score, 2)
}

function Calculate-MemoryEfficiency {
    param ($Result)
    
    $theoreticalMemory = $Result.Config.BatchSize * $Result.Config.SeqLength * $Result.Config.ModelDim * 4 # 4 bytes per float
    $actualMemory = $Result.MemoryUsage
    
    return [Math]::Round($theoreticalMemory / $actualMemory, 2)
}

function Calculate-ComputationalEfficiency {
    param ($Result)
    
    $flops = Calculate-FLOPs -Config $Result.Config -Variant $Result.Variant
    $timeMs = $Result.ForwardTime
    
    return [Math]::Round($flops / ($timeMs * 1000000), 2) # GFLOPS
}

function Calculate-ScalingFactor {
    param ($Result, $Results)
    
    $variantResults = $Results | Where-Object { $_.Variant -eq $Result.Variant } | Sort-Object { $_.Config.SeqLength }
    if ($variantResults.Count -lt 2) {
        return $null
    }
    
    $baseResult = $variantResults[0]
    $scaleFactor = [Math]::Log($Result.ForwardTime / $baseResult.ForwardTime) / 
                   [Math]::Log($Result.Config.SeqLength / $baseResult.Config.SeqLength)
    
    return [Math]::Round($scaleFactor, 2)
}

function Export-AttentionRecommendations {
    param (
        [Parameter(Mandatory=$true)]
        [array]$Results,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    try {
        $recommendations = @"
Attention Mechanism Recommendations
=================================

General Recommendations:
"@
        
        # Analyze results for each configuration
        $Results | Group-Object -Property { "$($_.Config.BatchSize)_$($_.Config.SeqLength)" } | ForEach-Object {
            $config = $_.Group[0].Config
            $recommendations += @"

Configuration: Batch=$($config.BatchSize), Sequence Length=$($config.SeqLength), Model Dimension=$($config.ModelDim)
---------------------------------------------------------------------------------------------

1. Performance Analysis:
"@
            
            # Sort variants by different metrics
            $bySpeed = $_.Group | Sort-Object ForwardTime
            $byMemory = $_.Group | Sort-Object MemoryUsage
            $byEfficiency = $_.Group | Sort-Object { Calculate-EfficiencyScore -Result $_ }
            
            $recommendations += @"

   * Fastest: $($bySpeed[0].Variant) ($($bySpeed[0].ForwardTime) ms)
   * Most Memory Efficient: $($byMemory[0].Variant) ($([Math]::Round($byMemory[0].MemoryUsage / 1MB, 2)) MB)
   * Best Overall Efficiency: $($byEfficiency[0].Variant) (Score: $(Calculate-EfficiencyScore -Result $byEfficiency[0]))

2. Specific Recommendations:
"@
            
            # Generate specific recommendations based on sequence length
            if ($config.SeqLength -gt 1024) {
                $recommendations += @"

   * For long sequences ($($config.SeqLength) tokens):
     - Preferred: LSH or Sparse attention for better scaling
     - Consider using larger chunk sizes for better throughput
     - Monitor memory usage with LSH attention
"@
            }
            elseif ($config.SeqLength -gt 512) {
                $recommendations += @"

   * For medium sequences ($($config.SeqLength) tokens):
     - Linear attention provides good balance of speed and memory
     - Consider Reversible attention if memory is constrained
     - Sparse attention with small block size can be effective
"@
            }
            else {
                $recommendations += @"

   * For short sequences ($($config.SeqLength) tokens):
     - Linear attention is most efficient
     - Standard attention patterns are viable
     - Focus on minimizing overhead
"@
            }
            
            # Add efficiency metrics
            $recommendations += "`n`n3. Efficiency Metrics:"
            foreach ($result in $_.Group) {
                $recommendations += @"

   $($result.Variant):
     - Memory Efficiency: $(Calculate-MemoryEfficiency -Result $result)x
     - Computational Efficiency: $(Calculate-ComputationalEfficiency -Result $result) GFLOPS
     - Scaling Factor: $(Calculate-ScalingFactor -Result $result -Results $Results)
"@
            }
        }
        
        # Add general guidelines
        $recommendations += @"

General Guidelines:
-----------------
1. For memory-constrained environments:
   - Prefer Reversible attention
   - Use appropriate chunk sizes
   - Monitor peak memory usage

2. For computation-constrained environments:
   - Linear attention for short sequences
   - LSH attention for long sequences
   - Balance chunk size with computational resources

3. For balanced performance:
   - Consider sequence length in variant selection
   - Monitor both memory and computation metrics
   - Adjust configuration based on hardware capabilities
"@
        
        # Export recommendations
        $recommendations | Out-File -FilePath $OutputPath
        Write-Host "Recommendations exported to: $OutputPath"
        
    }
    catch {
        Write-Error "Failed to export attention recommendations: $_"
    }
}

# Export results in multiple formats
$outputDirectory = Join-Path $PSScriptRoot "benchmark_results"
Export-BenchmarkResults -Results $benchmarkResults -OutputDirectory $outputDirectory -Formats @("HTML", "CSV", "JSON")

