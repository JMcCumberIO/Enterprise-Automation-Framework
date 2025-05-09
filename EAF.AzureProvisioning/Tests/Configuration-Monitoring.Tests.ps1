# Unit Tests for Configuration Monitoring Module

Describe "Configuration Monitoring Tests" {
    BeforeAll {
        # Import required modules
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\Private\configuration-monitoring-helpers.psm1"
        Import-Module -Name $modulePath -Force
        
        # Define test variables
        $script:testConfigPath = "Test.Configuration"
        $script:testOldValue = "OldValue"
        $script:testNewValue = "NewValue"
    }
    
    BeforeEach {
        # Reset monitoring store between tests
        $monitoringStore = Get-Variable -Name "script:ConfigurationMonitoringStore" -ValueOnly
        $monitoringStore.Changes.Clear()
        $monitoringStore.Errors.Clear()
        $monitoringStore.ValidationEvents.Clear()
        $monitoringStore.AccessEvents.Clear()
        $monitoringStore.Metrics.AccessCount.Clear()
        $monitoringStore.Metrics.ValidationFailures.Clear()
        $monitoringStore.Metrics.LastAccess.Clear()
        $monitoringStore.Metrics.PerformanceMetrics.Clear()
    }
    
    AfterAll {
        # Clean up any test data
        Get-ChildItem -Path "Variable:script:*" | Remove-Variable -Scope Script
        
        # Remove the module
        Remove-Module -Name "configuration-monitoring-helpers" -ErrorAction SilentlyContinue
    }
    
    Context "Change tracking" {
        It "Should track configuration changes" {
            # Act
            Write-EAFConfigurationChange -ConfigPath $script:testConfigPath -ChangeType "Update" -OldValue $script:testOldValue -NewValue $script:testNewValue
            
            # Get monitoring store
            $monitoringStore = Get-Variable -Name "script:ConfigurationMonitoringStore" -ValueOnly
            
            # Assert
            $monitoringStore.Changes.Count | Should -Be 1
            $change = $monitoringStore.Changes[0]
            $change.ConfigPath | Should -Be $script:testConfigPath
            $change.ChangeType | Should -Be "Update"
            $change.OldValue | Should -Be $script:testOldValue
            $change.NewValue | Should -Be $script:testNewValue
        }
        
        It "Should handle multiple change types" {
            # Act
            Write-EAFConfigurationChange -ConfigPath $script:testConfigPath -ChangeType "Create" -NewValue $script:testNewValue
            Write-EAFConfigurationChange -ConfigPath $script:testConfigPath -ChangeType "Update" -OldValue $script:testOldValue -NewValue $script:testNewValue
            Write-EAFConfigurationChange -ConfigPath $script:testConfigPath -ChangeType "Delete" -OldValue $script:testNewValue
            
            # Get monitoring store
            $monitoringStore = Get-Variable -Name "script:ConfigurationMonitoringStore" -ValueOnly
            
            # Assert
            $monitoringStore.Changes.Count | Should -Be 3
            $monitoringStore.Changes[0].ChangeType | Should -Be "Create"
            $monitoringStore.Changes[1].ChangeType | Should -Be "Update"
            $monitoringStore.Changes[2].ChangeType | Should -Be "Delete"
        }
        
        It "Should track access operations" {
            # Act
            Write-EAFConfigurationChange -ConfigPath $script:testConfigPath -ChangeType "Access"
            
            # Get monitoring store
            $monitoringStore = Get-Variable -Name "script:ConfigurationMonitoringStore" -ValueOnly
            
            # Assert
            $monitoringStore.Changes.Count | Should -Be 1
            $monitoringStore.AccessEvents.Count | Should -Be 1
            $monitoringStore.Metrics.AccessCount[$script:testConfigPath] | Should -Be 1
            $monitoringStore.Metrics.LastAccess[$script:testConfigPath] | Should -Not -BeNullOrEmpty
        }
        
        It "Should enforce limits on stored changes" {
            # Arrange
            Set-EAFConfigurationMonitoringSettings -MaxEventsStored 5
            
            # Act - Create 10 events
            1..10 | ForEach-Object {
                Write-EAFConfigurationChange -ConfigPath "$script:testConfigPath.$_" -ChangeType "Update" -NewValue $_
            }
            
            # Get monitoring store
            $monitoringStore = Get-Variable -Name "script:ConfigurationMonitoringStore" -ValueOnly
            
            # Assert - Should only keep the last 5
            $monitoringStore.Changes.Count | Should -Be 5
            $monitoringStore.Changes[0].ConfigPath | Should -Be "$script:testConfigPath.6"
            $monitoringStore.Changes[4].ConfigPath | Should -Be "$script:testConfigPath.10"
        }
    }
    
    Context "Validation tracking" {
        It "Should track validation successes" {
            # Act
            Write-EAFConfigurationValidation -ConfigPath $script:testConfigPath -ValidationRule "Range" -IsValid $true -ValidationMessage "Value is within range"
            
            # Get monitoring store
            $monitoringStore = Get-Variable -Name "script:ConfigurationMonitoringStore" -ValueOnly
            
            # Assert
            $monitoringStore.ValidationEvents.Count | Should -Be 1
            $validation = $monitoringStore.ValidationEvents[0]
            $validation.ConfigPath | Should -Be $script:testConfigPath
            $validation.ValidationRule | Should -Be "Range"
            $validation.IsValid | Should -BeTrue
            $validation.ValidationMessage | Should -Be "Value is within range"
        }
        
        It "Should track validation failures" {
            # Act
            Write-EAFConfigurationValidation -ConfigPath $script:testConfigPath -ValidationRule "Range" -IsValid $false -ValidationMessage "Value is out of range"
            
            # Get monitoring store
            $monitoringStore = Get-Variable -Name "script:ConfigurationMonitoringStore" -ValueOnly
            
            # Assert
            $monitoringStore.ValidationEvents.Count | Should -Be 1
            $monitoringStore.Errors.Count | Should -Be 1 # Failures are also logged as errors
            $monitoringStore.Metrics.ValidationFailures[$script:testConfigPath] | Should -Be 1
            
            $validation = $monitoringStore.ValidationEvents[0]
            $validation.IsValid | Should -BeFalse
            $validation.ValidationMessage | Should -Be "Value is out of range"
        }
        
        It "Should count multiple validation failures" {
            # Act
            Write-EAFConfigurationValidation -ConfigPath $script:testConfigPath -ValidationRule "Range" -IsValid $false
            Write-EAFConfigurationValidation -ConfigPath $script:testConfigPath -ValidationRule "Pattern" -IsValid $false
            Write-EAFConfigurationValidation -ConfigPath $script:testConfigPath -ValidationRule "Required" -IsValid $false
            
            # Get monitoring store
            $monitoringStore = Get-Variable -Name "script:ConfigurationMonitoringStore" -ValueOnly
            
            # Assert
            $monitoringStore.ValidationEvents.Count | Should -Be 3
            $monitoringStore.Errors.Count | Should -Be 3
            $monitoringStore.Metrics.ValidationFailures[$script:testConfigPath] | Should -Be 3
        }
    }
    
    Context "Error tracking" {
        It "Should track configuration errors" {
            # Act
            Write-EAFConfigurationError -ConfigPath $script:testConfigPath -ErrorType "AccessDenied" -ErrorMessage "Cannot access configuration"
            
            # Get monitoring store
            $monitoringStore = Get-Variable -Name "script:ConfigurationMonitoringStore" -ValueOnly
            
            # Assert
            $monitoringStore.Errors.Count | Should -Be 1
            $configError = $monitoringStore.Errors[0]
            $configError.ConfigPath | Should -Be $script:testConfigPath
            $configError.ErrorType | Should -Be "AccessDenied"
            $configError.ErrorMessage | Should -Be "Cannot access configuration"
        }
        
        It "Should handle exception objects" {
            # Arrange
            $exception = [System.InvalidOperationException]::new("Test operation not valid")
            
            # Act
            Write-EAFConfigurationError -ConfigPath $script:testConfigPath -ErrorType "OperationFailed" -ErrorMessage "Operation failed" -Exception $exception
            
            # Get monitoring store
            $monitoringStore = Get-Variable -Name "script:ConfigurationMonitoringStore" -ValueOnly
            
            # Assert
            $monitoringStore.Errors.Count | Should -Be 1
            $configError = $monitoringStore.Errors[0]
            $configError.Exception | Should -Be $exception
            $configError.ExceptionMessage | Should -Be "Test operation not valid"
        }
    }
    
    Context "Performance metrics" {
        It "Should track performance metrics" {
            # Act
            Write-EAFConfigurationPerformance -ConfigPath $script:testConfigPath -OperationType "Read" -DurationMs 123
            
            # Get monitoring store
            $monitoringStore = Get-Variable -Name "script:ConfigurationMon

itoringStore" -ValueOnly
            
            # Assert
            $metrics = $monitoringStore.Metrics.PerformanceMetrics["$script:testConfigPath/Read"]
            $metrics | Should -Not -BeNullOrEmpty
            $metrics.OperationCount | Should -Be 1
            $metrics.TotalDurationMs | Should -Be 123
            $metrics.MinDurationMs | Should -Be 123
            $metrics.MaxDurationMs | Should -Be 123
            $metrics.AverageDurationMs | Should -Be 123
        }
        
        It "Should calculate correct performance statistics" {
            # Act
            Write-EAFConfigurationPerformance -ConfigPath $script:testConfigPath -OperationType "Read" -DurationMs 100
            Write-EAFConfigurationPerformance -ConfigPath $script:testConfigPath -OperationType "Read" -DurationMs 200
            Write-EAFConfigurationPerformance -ConfigPath $script:testConfigPath -OperationType "Read" -DurationMs 300
            
            # Get monitoring store
            $monitoringStore = Get-Variable -Name "script:ConfigurationMonitoringStore" -ValueOnly
            
            # Assert
            $metrics = $monitoringStore.Metrics.PerformanceMetrics["$script:testConfigPath/Read"]
            $metrics.OperationCount | Should -Be 3
            $metrics.TotalDurationMs | Should -Be 600
            $metrics.MinDurationMs | Should -Be 100
            $metrics.MaxDurationMs | Should -Be 300
            $metrics.AverageDurationMs | Should -Be 200
        }
        
        It "Should track metrics for different operation types" {
            # Act
            Write-EAFConfigurationPerformance -ConfigPath $script:testConfigPath -OperationType "Read" -DurationMs 100
            Write-EAFConfigurationPerformance -ConfigPath $script:testConfigPath -OperationType "Write" -DurationMs 200
            
            # Get monitoring store
            $monitoringStore = Get-Variable -Name "script:ConfigurationMonitoringStore" -ValueOnly
            
            # Assert
            $readMetrics = $monitoringStore.Metrics.PerformanceMetrics["$script:testConfigPath/Read"]
            $writeMetrics = $monitoringStore.Metrics.PerformanceMetrics["$script:testConfigPath/Write"]
            
            $readMetrics | Should -Not -BeNullOrEmpty
            $writeMetrics | Should -Not -BeNullOrEmpty
            $readMetrics.OperationCount | Should -Be 1
            $writeMetrics.OperationCount | Should -Be 1
        }
    }
    
    Context "Monitoring retrieval" {
        BeforeEach {
            # Create some test data
            Write-EAFConfigurationChange -ConfigPath $script:testConfigPath -ChangeType "Update" -OldValue "Old" -NewValue "New"
            Write-EAFConfigurationValidation -ConfigPath $script:testConfigPath -ValidationRule "Test" -IsValid $false
            Write-EAFConfigurationError -ConfigPath $script:testConfigPath -ErrorType "Test" -ErrorMessage "Test error"
            Write-EAFConfigurationPerformance -ConfigPath $script:testConfigPath -OperationType "Read" -DurationMs 100
        }
        
        It "Should retrieve all monitoring data" {
            # Act
            $monitoring = Get-EAFConfigurationMonitoring -MetricType All
            
            # Assert
            $monitoring.Changes.Count | Should -Be 1
            $monitoring.ValidationEvents.Count | Should -Be 1
            $monitoring.Errors.Count | Should -Be 1
            $monitoring.PerformanceMetrics.Count | Should -Be 1
            $monitoring.Summary.TotalChanges | Should -Be 1
            $monitoring.Summary.TotalValidationFailures | Should -Be 1
            $monitoring.Summary.TotalErrors | Should -Be 1
        }
        
        It "Should filter by configuration path" {
            # Arrange
            Write-EAFConfigurationChange -ConfigPath "Other.Path" -ChangeType "Update" -NewValue "Test"
            
            # Act
            $monitoring = Get-EAFConfigurationMonitoring -MetricType All -ConfigPath $script:testConfigPath
            
            # Assert
            $monitoring.Changes.Count | Should -Be 1
            $monitoring.Changes[0].ConfigPath | Should -Be $script:testConfigPath
        }
        
        It "Should filter by time range" {
            # Arrange
            $startTime = Get-Date
            Start-Sleep -Milliseconds 100
            Write-EAFConfigurationChange -ConfigPath $script:testConfigPath -ChangeType "New" -NewValue "New"
            Start-Sleep -Milliseconds 100
            $endTime = Get-Date
            Start-Sleep -Milliseconds 100
            Write-EAFConfigurationChange -ConfigPath $script:testConfigPath -ChangeType "Another" -NewValue "Another"
            
            # Act
            $monitoring = Get-EAFConfigurationMonitoring -MetricType Changes -StartTime $startTime -EndTime $endTime
            
            # Assert
            $monitoring.Count | Should -Be 1
            $monitoring[0].ChangeType | Should -Be "New"
        }
    }
    
    Context "Settings management" {
        It "Should update monitoring settings" {
            # Act
            Set-EAFConfigurationMonitoringSettings -MaxEventsStored 1000 -EnableFileLogging $true -LogFilePath "test.log"
            
            # Get monitoring store
            $monitoringStore = Get-Variable -Name "script:ConfigurationMonitoringStore" -ValueOnly
            
            # Assert
            $monitoringStore.Settings.MaxEventsStored | Should -Be 1000
            $monitoringStore.Settings.EnableFileLogging | Should -BeTrue
            $monitoringStore.Settings.LogFilePath | Should -Be "test.log"
        }
        
        It "Should maintain existing settings when updating partial settings" {
            # Arrange
            Set-EAFConfigurationMonitoringSettings -MaxEventsStored 1000 -EnableFileLogging $true -LogFilePath "test.log"
            
            # Act
            Set-EAFConfigurationMonitoringSettings -MaxEventsStored 500
            
            # Get monitoring store
            $monitoringStore = Get-Variable -Name "script:ConfigurationMonitoringStore" -ValueOnly
            
            # Assert
            $monitoringStore.Settings.MaxEventsStored | Should -Be 500
            $monitoringStore.Settings.EnableFileLogging | Should -BeTrue
            $monitoringStore.Settings.LogFilePath | Should -Be "test.log"
        }
    }
}
