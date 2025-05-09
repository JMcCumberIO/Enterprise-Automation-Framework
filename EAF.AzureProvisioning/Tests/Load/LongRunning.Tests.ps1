            while ((Get-Date) -lt $endTime) {
                $process = Get-Process -Id $PID
                
                $resourceMetrics.CPU.Add(@{
                    Timestamp = Get-Date
                    Percent = $process.CPU
                })
                
                $resourceMetrics.Memory.Add(@{
                    Timestamp = Get-Date
                    WorkingSet = $process.WorkingSet64
                    PrivateBytes = $process.PrivateMemorySize64
                    VirtualBytes = $process.VirtualMemorySize64
                })
                
                $resourceMetrics.Handles.Add(@{
                    Timestamp = Get-Date
                    HandleCount = $process.HandleCount
                })
                
                # Generate some load
                1..10 | ForEach-Object {
                    $configPath = "Test.Resource.$(Get-Date -Format 'yyyyMMddHHmmss').$_"
                    $value = "ResourceTest-$(New-Guid)"
                    $secureValue = ConvertTo-SecureString -String $value -AsPlainText -Force
                    
                    Set-EAFSecureConfiguration -ConfigPath $configPath `
                        -SecureValue $secureValue `
                        -KeyVaultName $script:testKeyVaultName
                }
                
                Start-Sleep -Seconds $samplingInterval.TotalSeconds
            }
            
            # Assert
            # Calculate resource usage trends
            $memoryTrend = @{
                Initial = $resourceMetrics.Memory[0].WorkingSet
                Final = $resourceMetrics.Memory[-1].WorkingSet
                Peak = ($resourceMetrics.Memory | Measure-Object -Property WorkingSet -Maximum).Maximum
                Growth = ($resourceMetrics.Memory[-1].WorkingSet - $resourceMetrics.Memory[0].WorkingSet) / 1MB
            }
            
            $handleTrend = @{
                Initial = $resourceMetrics.Handles[0].HandleCount
                Final = $resourceMetrics.Handles[-1].HandleCount
                Peak = ($resourceMetrics.Handles | Measure-Object -Property HandleCount -Maximum).Maximum
                Growth = $resourceMetrics.Handles[-1].HandleCount - $resourceMetrics.Handles[0].HandleCount
            }
            
            # Memory should not grow significantly
            $memoryTrend.Growth | Should -BeLessThan 100 # Less than 100MB growth
            
            # Handle count should remain stable
            $handleTrend.Growth | Should -BeLessThan 1000 # Less than 1000 handle growth
            
            # Generate resource usage report
            $reportPath = Join-Path $PSScriptRoot "../../TestResults/LoadTests/ResourceUsage-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
            
            $reportContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Resource Usage Report - Long Running Tests</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .summary { background-color: #f5f5f5; padding: 20px; margin-bottom: 20px; }
        .chart { margin: 20px 0; height: 300px; }
    </style>
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
</head>
<body>
    <h1>Resource Usage Report</h1>
    <div class="summary">
        <h2>Memory Usage</h2>
        <p>Initial: $([math]::Round($memoryTrend.Initial/1MB, 2)) MB</p>
        <p>Final: $([math]::Round($memoryTrend.Final/1MB, 2)) MB</p>
        <p>Peak: $([math]::Round($memoryTrend.Peak/1MB, 2)) MB</p>
        <p>Growth: $([math]::Round($memoryTrend.Growth, 2)) MB</p>
        
        <h2>Handle Usage</h2>
        <p>Initial: $($handleTrend.Initial)</p>
        <p>Final: $($handleTrend.Final)</p>
        <p>Peak: $($handleTrend.Peak)</p>
        <p>Growth: $($handleTrend.Growth)</p>
    </div>
    
    <div id="memoryChart" class="chart"></div>
    <div id="handleChart" class="chart"></div>
    
    <script>
        var memoryData = [{
            x: $(ConvertTo-Json @($resourceMetrics.Memory.Timestamp)),
            y: $(ConvertTo-Json @($resourceMetrics.Memory.WorkingSet | ForEach-Object { $_ / 1MB })),
            type: 'scatter',
            name: 'Working Set (MB)'
        }];
        
        var handleData = [{
            x: $(ConvertTo-Json @($resourceMetrics.Handles.Timestamp)),
            y: $(ConvertTo-Json @($resourceMetrics.Handles.HandleCount)),
            type: 'scatter',
            name: 'Handle Count'
        }];
        
        var memoryLayout = {
            title: 'Memory Usage Over Time',
            xaxis: { title: 'Time' },
            yaxis: { title: 'Memory (MB)' }
        };
        
        var handleLayout = {
            title: 'Handle Count Over Time',
            xaxis: { title: 'Time' },
            yaxis: { title: 'Handles' }
        };
        
        Plotly.newPlot('memoryChart', memoryData, memoryLayout);
        Plotly.newPlot('handleChart', handleData, handleLayout);
    </script>
</body>
</html>
"@
            
            $reportContent | Out-File -FilePath $reportPath -Force
            Write-Host "Resource usage report generated at: $reportPath"
        }
    }
    
    Context "Recovery and Resilience" {
        It "Should recover from transient failures" {
            # Arrange
            $operationCount = 100
            $errorRate = 0.2 # 20% error rate
            $results = @{
                Attempts = 0
                Successes = 0
                Recoveries = 0
                FinalFailures = 0
            }
            
            # Mock random failures
            Mock Set-AzKeyVaultSecret -ModuleName "Az.KeyVault.Mocks" {
                if ((Get-Random -Minimum 0 -Maximum 1) -lt $errorRate) {
                    throw "Simulated transient error"
                }
                # Continue with original implementation
                $script:MockKeyVaultStore.Secrets["$VaultName/$Name"] = @{
                    VaultName = $VaultName
                    Name = $Name
                    SecretValue = $SecretValue.Copy()
                    Version = [Guid]::NewGuid().ToString()
                }
            }
            
            # Act
            1..$operationCount | ForEach-Object {
                $configPath = "Test.Recovery.$_"
                $value = "RecoveryTest-$(New-Guid)"
                $secureValue = ConvertTo-SecureString -String $value -AsPlainText -Force
                $maxAttempts = 3
                $attempt = 0
                $success = $false
                
                while (-not $success -and $attempt -lt $maxAttempts) {
                    $attempt++
                    $results.Attempts++
                    
                    try {
                        Set-EAFSecureConfiguration -ConfigPath $configPath `
                            -SecureValue $secureValue `
                            -KeyVaultName $script:testKeyVaultName
                        
                        $success = $true
                        if ($attempt -gt 1) {
                            $results.Recoveries++
                        }
                        $results.Successes++
                    }
                    catch {
                        if ($attempt -eq $maxAttempts) {
                            $results.FinalFailures++
                        }
                        Start-Sleep -Seconds (1 * $attempt) # Exponential backoff
                    }
                }
            }
            
            # Assert
            $results.Successes | Should -BeGreaterThan ($operationCount * 0.9) # 90% success rate
            $results.FinalFailures | Should -BeLessThan ($operationCount * 0.1) # Less than 10% final failures
            
            # Generate recovery report
            $reportPath = Join-Path $PSScriptRoot "../../TestResults/LoadTests/RecoveryReport-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
            $results | ConvertTo-Json | Out-File -FilePath $reportPath -Force
            Write-Host "Recovery report generated at: $reportPath"
        }
    }
}
