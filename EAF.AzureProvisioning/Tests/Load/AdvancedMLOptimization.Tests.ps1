            # Initialize input with ones
            for ($b = 0; $b -lt $script:batchSize; $b++) {
                for ($i = 0; $i -lt $script:inputShape[0]; $i++) {
                    for ($j = 0; $j -lt $script:inputShape[1]; $j++) {
                        $input[$b,$i,$j] = 1.0
                    }
                }
            }
            
            # Act
            $output = Apply-Dropout -Layer $layer -Input $input -Training $false
            
            # Assert
            $output | Should -Not -BeNullOrEmpty
            
            # All values should remain unchanged during inference
            for ($b = 0; $b -lt $script:batchSize; $b++) {
                for ($i = 0; $i -lt $script:inputShape[0]; $i++) {
                    for ($j = 0; $j -lt $script:inputShape[1]; $j++) {
                        $output[$b,$i,$j] | Should -Be 1.0
                    }
                }
            }
        }
    }
    
    Context "Integration of Optimization Features" {
        It "Should combine batch normalization with dropout" {
            # Arrange
            $bnLayer = Add-BatchNormalization -Name "bn_combined" -InputShape $script:inputShape
            $dropoutLayer = Add-Dropout -Name "dropout_combined" -Rate 0.3 -InputShape $script:inputShape
            
            $input = New-Object 'double[,,]' $script:batchSize,$script:inputShape[0],$script:inputShape[1]
            
            # Initialize input with random values
            $random = New-Object Random
            for ($b = 0; $b -lt $script:batchSize; $b++) {
                for ($i = 0; $i -lt $script:inputShape[0]; $i++) {
                    for ($j = 0; $j -lt $script:inputShape[1]; $j++) {
                        $input[$b,$i,$j] = $random.NextDouble()
                    }
                }
            }
            
            # Act
            $bnOutput = BatchNormForward -Layer $bnLayer -Input $input -Training $true
            $finalOutput = Apply-Dropout -Layer $dropoutLayer -Input $bnOutput -Training $true
            
            # Assert
            $finalOutput | Should -Not -BeNullOrEmpty
            $bnLayer.CachedValues.BatchMean | Should -Not -BeNullOrEmpty
            $bnLayer.CachedValues.BatchVariance | Should -Not -BeNullOrEmpty
            $dropoutLayer.CachedMask | Should -Not -BeNullOrEmpty
        }
        
        It "Should optimize network with Adam and batch normalization" {
            # Arrange
            $bnLayer = Add-BatchNormalization -Name "bn_opt" -InputShape $script:inputShape
            $optimizer = Add-AdaptiveLearningRate -Optimizer "Adam" -InitialLearningRate 0.001
            
            $input = New-Object 'double[,,]' $script:batchSize,$script:inputShape[0],$script:inputShape[1]
            $gradients = @{
                "gamma" = New-Object 'double[]' $script:inputShape[1]
                "beta" = New-Object 'double[]' $script:inputShape[1]
            }
            
            # Initialize input and gradients
            $random = New-Object Random
            for ($b = 0; $b -lt $script:batchSize; $b++) {
                for ($i = 0; $i -lt $script:inputShape[0]; $i++) {
                    for ($j = 0; $j -lt $script:inputShape[1]; $j++) {
                        $input[$b,$i,$j] = $random.NextDouble()
                    }
                }
            }
            
            for ($j = 0; $j -lt $script:inputShape[1]; $j++) {
                $gradients["gamma"][$j] = $random.NextDouble() - 0.5
                $gradients["beta"][$j] = $random.NextDouble() - 0.5
            }
            
            # Act
            $output = BatchNormForward -Layer $bnLayer -Input $input -Training $true
            $updatedGradients = Update-LearningRate -OptConfig $optimizer -Gradients $gradients
            
            # Assert
            $output | Should -Not -BeNullOrEmpty
            $updatedGradients | Should -Not -BeNullOrEmpty
            $optimizer.Step | Should -Be 1
            $optimizer.Parameters["gamma"] | Should -Not -BeNullOrEmpty
            $optimizer.Parameters["beta"] | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle multiple optimization iterations" {
            # Arrange
            $bnLayer = Add-BatchNormalization -Name "bn_multi" -InputShape $script:inputShape
            $dropoutLayer = Add-Dropout -Name "dropout_multi" -Rate 0.2 -InputShape $script:inputShape
            $optimizer = Add-AdaptiveLearningRate -Optimizer "Adam" -InitialLearningRate 0.001
            
            $input = New-Object 'double[,,]' $script:batchSize,$script:inputShape[0],$script:inputShape[1]
            $gradients = @{
                "gamma" = New-Object 'double[]' $script:inputShape[1]
                "beta" = New-Object 'double[]' $script:inputShape[1]
            }
            
            # Act & Assert
            for ($iteration = 0; $iteration -lt 5; $iteration++) {
                # Generate new random input
                $random = New-Object Random
                for ($b = 0; $b -lt $script:batchSize; $b++) {
                    for ($i = 0; $i -lt $script:inputShape[0]; $i++) {
                        for ($j = 0; $j -lt $script:inputShape[1]; $j++) {
                            $input[$b,$i,$j] = $random.NextDouble()
                        }
                    }
                }
                
                # Update gradients
                for ($j = 0; $j -lt $script:inputShape[1]; $j++) {
                    $gradients["gamma"][$j] = $random.NextDouble() - 0.5
                    $gradients["beta"][$j] = $random.NextDouble() - 0.5
                }
                
                # Forward pass
                $bnOutput = BatchNormForward -Layer $bnLayer -Input $input -Training $true
                $finalOutput = Apply-Dropout -Layer $dropoutLayer -Input $bnOutput -Training $true
                
                # Update parameters
                $updatedGradients = Update-LearningRate -OptConfig $optimizer -Gradients $gradients
                
                # Assert
                $finalOutput | Should -Not -BeNullOrEmpty
                $updatedGradients | Should -Not -BeNullOrEmpty
                $optimizer.Step | Should -Be ($iteration + 1)
                $optimizer.CurrentLearningRate | Should -BeLessThan $optimizer.InitialLearningRate
            }
        }
    }
}
