    Context "Attention Layer" {
        It "Should create and initialize attention layer" {
            # Arrange
            $inputShape = @($script:sequenceLength, $script:inputFeatures)
            
            # Act
            $layer = Add-AttentionLayer -Name "attn1" -InputShape $inputShape -NumHeads 8
            
            # Assert
            $layer | Should -Not -BeNullOrEmpty
            $layer.Type | Should -Be "Attention"
            $layer.Weights.Query | Should -Not -BeNullOrEmpty
            $layer.Weights.Key | Should -Not -BeNullOrEmpty
            $layer.Weights.Value | Should -Not -BeNullOrEmpty
            $layer.Weights.Output | Should -Not -BeNullOrEmpty
        }
        
        It "Should compute self-attention" {
            # Arrange
            $inputShape = @($script:sequenceLength, $script:inputFeatures)
            $layer = Add-AttentionLayer -Name "attn2" -InputShape $inputShape -NumHeads 8
            $input = New-Object 'double[,,]' $script:batchSize,$script:sequenceLength,$script:inputFeatures
            
            # Initialize input with random values
            $random = New-Object Random
            for ($b = 0; $b -lt $script:batchSize; $b++) {
                for ($s = 0; $s -lt $script:sequenceLength; $s++) {
                    for ($f = 0; $f -lt $script:inputFeatures; $f++) {
                        $input[$b,$s,$f] = $random.NextDouble()
                    }
                }
            }
            
            # Act
            $output = AttentionForward -Layer $layer -Input $input -Training $true
            
            # Assert
            $output | Should -Not -BeNullOrEmpty
            $output.GetLength(0) | Should -Be $script:batchSize
            $output.GetLength(1) | Should -Be $script:sequenceLength
            $output.GetLength(2) | Should -Be $script:inputFeatures
        }
        
        It "Should apply causal masking correctly" {
            # Arrange
            $inputShape = @($script:sequenceLength, $script:inputFeatures)
            $layer = Add-AttentionLayer -Name "attn3" -InputShape $inputShape -NumHeads 8 -UseCausalMask $true
            $input = New-Object 'double[,,]' $script:batchSize,$script:sequenceLength,$script:inputFeatures
            
            # Initialize input with random values
            $random = New-Object Random
            for ($b = 0; $b -lt $script:batchSize; $b++) {
                for ($s = 0; $s -lt $script:sequenceLength; $s++) {
                    for ($f = 0; $f -lt $script:inputFeatures; $f++) {
                        $input[$b,$s,$f] = $random.NextDouble()
                    }
                }
            }
            
            # Act
            $output = AttentionForward -Layer $layer -Input $input -Training $true
            
            # Assert
            $output | Should -Not -BeNullOrEmpty
            
            # Check that future positions are masked
            $scores = $layer.CachedScores
            for ($i = 0; $i -lt $script:sequenceLength; $i++) {
                for ($j = $i + 1; $j -lt $script:sequenceLength; $j++) {
                    $scores[0,0,$i,$j] | Should -Be ([double]::NegativeInfinity)
                }
            }
        }
    }
    
    Context "Integration Tests" {
        It "Should combine LSTM and Attention layers" {
            # Arrange
            $inputShape = @($script:sequenceLength, $script:inputFeatures)
            $lstmLayer = Add-LSTMLayer -Name "lstm_combined" -InputShape $inputShape
            $attnLayer = Add-AttentionLayer -Name "attn_combined" -InputShape @($script:sequenceLength, $lstmLayer.Config.Units) -NumHeads 8
            
            $input = New-Object 'double[,,]' $script:batchSize,$script:sequenceLength,$script:inputFeatures
            
            # Initialize input with random values
            $random = New-Object Random
            for ($b = 0; $b -lt $script:batchSize; $b++) {
                for ($s = 0; $s -lt $script:sequenceLength; $s++) {
                    for ($f = 0; $f -lt $script:inputFeatures; $f++) {
                        $input[$b,$s,$f] = $random.NextDouble()
                    }
                }
            }
            
            # Act
            $lstmOutput = LSTMForward -Layer $lstmLayer -Input $input -Training $true
            $finalOutput = AttentionForward -Layer $attnLayer -Input $lstmOutput -Training $true
            
            # Assert
            $finalOutput | Should -Not -BeNullOrEmpty
            $finalOutput.GetLength(0) | Should -Be $script:batchSize
            $finalOutput.GetLength(1) | Should -Be $script:sequenceLength
            $finalOutput.GetLength(2) | Should -Be $script:inputFeatures
        }
        
        It "Should handle dropout correctly during training and inference" {
            # Arrange
            $inputShape = @($script:sequenceLength, $script:inputFeatures)
            $lstmLayer = Add-LSTMLayer -Name "lstm_dropout" -InputShape $inputShape -Dropout 0.2
            $attnLayer = Add-AttentionLayer -Name "attn_dropout" -InputShape @($script:sequenceLength, $lstmLayer.Config.Units) -NumHeads 8 -Dropout 0.1
            
            $input = New-Object 'double[,,]' $script:batchSize,$script:sequenceLength,$script:inputFeatures
            
            # Initialize input
            $random = New-Object Random
            for ($b = 0; $b -lt $script:batchSize; $b++) {
                for ($s = 0; $s -lt $script:sequenceLength; $s++) {
                    for ($f = 0; $f -lt $script:inputFeatures; $f++) {
                        $input[$b,$s,$f] = $random.NextDouble()
                    }
                }
            }
            
            # Act - Training
            $trainingLSTMOutput = LSTMForward -Layer $lstmLayer -Input $input -Training $true
            $trainingOutput = AttentionForward -Layer $attnLayer -Input $trainingLSTMOutput -Training $true
            
            # Act - Inference
            $inferenceLSTMOutput = LSTMForward -Layer $lstmLayer -Input $input -Training $false
            $inferenceOutput = AttentionForward -Layer $attnLayer -Input $inferenceLSTMOutput -Training $false
            
            # Assert
            $trainingOutput | Should -Not -BeNullOrEmpty
            $inferenceOutput | Should -Not -BeNullOrEmpty
            
            # Training and inference outputs should be different due to dropout
            $diff = 0
            for ($b = 0; $b -lt $script:batchSize; $b++) {
                for ($s = 0; $s -lt $script:sequenceLength; $s++) {
                    for ($f = 0; $f -lt $script:inputFeatures; $f++) {
                        $diff += [Math]::Abs($trainingOutput[$b,$s,$f] - $inferenceOutput[$b,$s,$f])
                    }
                }
            }
            
            $diff | Should -Not -Be 0
        }
    }
}
            # Assert (continued)
            $finalOutput | Should -Not -BeNullOrEmpty
            $finalOutput.GetLength(0) | Should -Be $script:batchSize
            $finalOutput.GetLength(1) | Should -Be $script:sequenceLength
            $finalOutput.GetLength(2) | Should -Be $script:features
            
            # Check that output is normalized
            for ($b = 0; $b -lt $script:batchSize; $b++) {
                for ($s = 0; $s -lt $script:sequenceLength; $s++) {
                    $mean = 0
                    $variance = 0
                    
                    # Calculate mean
                    for ($f = 0; $f -lt $script:features; $f++) {
                        $mean += $finalOutput[$b,$s,$f]
                    }
                    $mean /= $script:features
                    
                    # Calculate variance
                    for ($f = 0; $f -lt $script:features; $f++) {
                        $variance += [Math]::Pow($finalOutput[$b,$s,$f] - $mean, 2)
                    }
                    $variance /= $script:features
                    
                    # Mean should be close to 0 and variance close to 1
                    $mean | Should -BeLessThan 0.1
                    [Math]::Abs($variance - 1) | Should -BeLessThan 0.1
                }
            }
        }
    }
}

    Context "Multi-Head Attention" {
        BeforeAll {
            $script:attentionConfig = @{
                InputDim = 64
                NumHeads = 8
                SeqLength = 10
                BatchSize = 4
            }
        }
        
        It "Should create multi-head attention layer" {
            # Arrange & Act
            $layer = Add-MultiHeadAttention -Name "mha1" `
                                          -InputShape @($script:attentionConfig.SeqLength, $script:attentionConfig.InputDim) `
                                          -NumHeads $script:attentionConfig.NumHeads
            
            # Assert
            $layer | Should -Not -BeNullOrEmpty
            $layer.Type | Should -Be "MultiHeadAttention"
            $layer.Config.NumHeads | Should -Be $script:attentionConfig.NumHeads
            $layer.Config.HeadDim | Should -Be ($script:attentionConfig.InputDim / $script:attentionConfig.NumHeads)
            
            # Check weight matrices
            $layer.Weights.Query | Should -Not -BeNullOrEmpty
            $layer.Weights.Key | Should -Not -BeNullOrEmpty
            $layer.Weights.Value | Should -Not -BeNullOrEmpty
            $layer.Weights.Output | Should -Not -BeNullOrEmpty
            
            # Check layer normalization
            $layer.LayerNorm | Should -Not -BeNullOrEmpty
            $layer.LayerNorm.Type | Should -Be "LayerNorm"
        }
        
        It "Should perform attention forward pass" {
            # Arrange
            $layer = Add-MultiHeadAttention -Name "mha2" `
                                          -InputShape @($script:attentionConfig.SeqLength, $script:attentionConfig.InputDim) `
                                          -NumHeads $script:attentionConfig.NumHeads
            
            $input = New-Object 'double[,,]' $script:attentionConfig.BatchSize,$script:attentionConfig.SeqLength,$script:attentionConfig.InputDim
            
            # Initialize input with random values
            $random = New-Object Random
            for ($b = 0; $b -lt $script:attentionConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:attentionConfig.SeqLength; $s++) {
                    for ($d = 0; $d -lt $script:attentionConfig.InputDim; $d++) {
                        $input[$b,$s,$d] = $random.NextDouble() - 0.5
                    }
                }
            }
            
            # Act
            $output = MultiHeadAttentionForward -Layer $layer -Input $input -Training $true
            
            # Assert
            $output | Should -Not -BeNullOrEmpty
            $output.GetLength(0) | Should -Be $script:attentionConfig.BatchSize
            $output.GetLength(1) | Should -Be $script:attentionConfig.SeqLength
            $output.GetLength(2) | Should -Be $script:attentionConfig.InputDim
            
            # Check cached values
            $layer.CachedValues.Query | Should -Not -BeNullOrEmpty
            $layer.CachedValues.Key | Should -Not -BeNullOrEmpty
            $layer.CachedValues.Value | Should -Not -BeNullOrEmpty
            $layer.CachedValues.Weights | Should -Not -BeNullOrEmpty
            $layer.CachedValues.Attention | Should -Not -BeNullOrEmpty
        }
        
        It "Should apply causal masking correctly" {
            # Arrange
            $layer = Add-MultiHeadAttention -Name "mha3" `
                                          -InputShape @($script:attentionConfig.SeqLength, $script:attentionConfig.InputDim) `
                                          -NumHeads $script:attentionConfig.NumHeads `
                                          -UseCausalMask $true
            
            $input = New-Object 'double[,,]' $script:attentionConfig.BatchSize,$script:attentionConfig.SeqLength,$script:attentionConfig.InputDim
            
            # Initialize input
            $random = New-Object Random
            for ($b = 0; $b -lt $script:attentionConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:attentionConfig.SeqLength; $s++) {
                    for ($d = 0; $d -lt $script:attentionConfig.InputDim; $d++) {
                        $input[$b,$s,$d] = $random.NextDouble() - 0.5
                    }
                }
            }
            
            # Act
            $output = MultiHeadAttentionForward -Layer $layer -Input $input -Training $true
            
            # Assert
            $output | Should -Not -BeNullOrEmpty
            
            # Check attention weights for causality
            $weights = $layer.CachedValues.Weights
            for ($b = 0; $b -lt $script:attentionConfig.BatchSize; $b++) {
                for ($h = 0; $h -lt $script:attentionConfig.NumHeads; $h++) {
                    for ($i = 0; $i -lt $script:attentionConfig.SeqLength; $i++) {
                        for ($j = $i + 1; $j -lt $script:attentionConfig.SeqLength; $j++) {
                            $weights[$b,$h,$i,$j] | Should -Be 0
                        }
                    }
                }
            }
        }
        
        It "Should handle dropout during training" {
            # Arrange
            $layer = Add-MultiHeadAttention -Name "mha4" `
                                          -InputShape @($script:attentionConfig.SeqLength, $script:attentionConfig.InputDim) `
                                          -NumHeads $script:attentionConfig.NumHeads `
                                          -DropoutRate 0.2
            
            $input = New-Object 'double[,,]' $script:attentionConfig.BatchSize,$script:attentionConfig.SeqLength,$script:attentionConfig.InputDim
            
            # Initialize input
            $random = New-Object Random
            for ($b = 0; $b -lt $script:attentionConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:attentionConfig.SeqLength; $s++) {
                    for ($d = 0; $d -lt $script:attentionConfig.InputDim; $d++) {
                        $input[$b,$s,$d] = $random.NextDouble() - 0.5
                    }
                }
            }
            
            # Act - Training
            $trainingOutput = MultiHeadAttentionForward -Layer $layer -Input $input -Training $true
            
            # Act - Inference
            $inferenceOutput = MultiHeadAttentionForward -Layer $layer -Input $input -Training $false
            
            # Assert
            $trainingOutput | Should -Not -BeNullOrEmpty
            $inferenceOutput | Should -Not -BeNullOrEmpty
            
            # Training and inference outputs should be different due to dropout
            $diff = 0
            for ($b = 0; $b -lt $script:attentionConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:attentionConfig.SeqLength; $s++) {
                    for ($d = 0; $d -lt $script:attentionConfig.InputDim; $d++) {
                        $diff += [Math]::Abs($trainingOutput[$b,$s,$d] - $inferenceOutput[$b,$s,$d])
                    }
                }
            }
            
            $diff | Should -Not -Be 0
        }
    }
            $layer.Encodings.GetLength(1) | Should -Be $script:posEncConfig.DModel
            
            # Check initialization bounds
            $maxVal = [double]::NegativeInfinity
            $minVal = [double]::PositiveInfinity
            
            for ($pos = 0; $pos -lt $script:posEncConfig.MaxSeqLength; $pos++) {
                for ($i = 0; $i -lt $script:posEncConfig.DModel; $i++) {
                    $val = $layer.Encodings[$pos,$i]
                    if ($val -gt $maxVal) { $maxVal = $val }
                    if ($val -lt $minVal) { $minVal = $val }
                }
            }
            
            # Values should be within reasonable bounds for truncated normal distribution
            $maxVal | Should -BeLessThan 3.0
            $minVal | Should -BeGreaterThan -3.0
        }
        
        It "Should add positional encodings to input" {
            # Arrange
            $layer = Add-PositionalEncoding -Name "pos3" `
                                          -InputShape @($script:posEncConfig.SeqLength, $script:posEncConfig.DModel) `
                                          -MaxSeqLength $script:posEncConfig.MaxSeqLength
            
            $input = New-Object 'double[,,]' $script:posEncConfig.BatchSize,$script:posEncConfig.SeqLength,$script:posEncConfig.DModel
            
            # Initialize input with random values
            $random = New-Object Random
            for ($b = 0; $b -lt $script:posEncConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:posEncConfig.SeqLength; $s++) {
                    for ($d = 0; $d -lt $script:posEncConfig.DModel; $d++) {
                        $input[$b,$s,$d] = $random.NextDouble() - 0.5
                    }
                }
            }
            
            # Act
            $output = PositionalEncodingForward -Layer $layer -Input $input -Training $true
            
            # Assert
            $output | Should -Not -BeNullOrEmpty
            $output.GetLength(0) | Should -Be $script:posEncConfig.BatchSize
            $output.GetLength(1) | Should -Be $script:posEncConfig.SeqLength
            $output.GetLength(2) | Should -Be $script:posEncConfig.DModel
            
            # Check that positional encodings were added correctly
            for ($b = 0; $b -lt $script:posEncConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:posEncConfig.SeqLength; $s++) {
                    for ($d = 0; $d -lt $script:posEncConfig.DModel; $d++) {
                        $expected = $input[$b,$s,$d] + $layer.Encodings[$s,$d]
                        [Math]::Abs($output[$b,$s,$d] - $expected) | Should -BeLessThan 1e-6
                    }
                }
            }
        }
    }
    
    Context "Full Transformer Layer Integration" {
        BeforeAll {
            $script:transformerConfig = @{
                BatchSize = 4
                SeqLength = 16
                DModel = 64
                NumHeads = 8
                DropoutRate = 0.1
            }
        }
        
        It "Should combine all components in transformer layer" {
            # Arrange
            # 1. Create layers
            $posEncLayer = Add-PositionalEncoding -Name "pos_transformer" `
                                                -InputShape @($script:transformerConfig.SeqLength, $script:transformerConfig.DModel)
            
            $attnLayer = Add-MultiHeadAttention -Name "mha_transformer" `
                                              -InputShape @($script:transformerConfig.SeqLength, $script:transformerConfig.DModel) `
                                              -NumHeads $script:transformerConfig.NumHeads `
                                              -DropoutRate $script:transformerConfig.DropoutRate
            
            $residualLayer = Add-ResidualConnection -Name "res_transformer" `
                                                  -InputShape @($script:transformerConfig.SeqLength, $script:transformerConfig.DModel)
            
            $lnLayer = Add-LayerNormalization -Name "ln_transformer" `
                                            -InputShape @($script:transformerConfig.SeqLength, $script:transformerConfig.DModel)
            
            # Initialize input
            $input = New-Object 'double[,,]' $script:transformerConfig.BatchSize,$script:transformerConfig.SeqLength,$script:transformerConfig.DModel
            
            $random = New-Object Random
            for ($b = 0; $b -lt $script:transformerConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:transformerConfig.SeqLength; $s++) {
                    for ($d = 0; $d -lt $script:transformerConfig.DModel; $d++) {
                        $input[$b,$s,$d] = $random.NextDouble() - 0.5
                    }
                }
            }
            
            # Act
            # 1. Add positional encodings
            $posEncOutput = PositionalEncodingForward -Layer $posEncLayer -Input $input -Training $true
            
            # 2. Self-attention
            $attnOutput = MultiHeadAttentionForward -Layer $attnLayer -Input $posEncOutput -Training $true
            
            # 3. Residual connection
            $residualOutput = ResidualForward -Layer $residualLayer -Input $posEncOutput -TransformedInput $attnOutput -Training $true
            
            # 4. Layer normalization
            $finalOutput = LayerNormForward -Layer $lnLayer -Input $residualOutput -Training $true
            
            # Assert
            $finalOutput | Should -Not -BeNullOrEmpty
            $finalOutput.GetLength(0) | Should -Be $script:transformerConfig.BatchSize
            $finalOutput.GetLength(1) | Should -Be $script:transformerConfig.SeqLength
            $finalOutput.GetLength(2) | Should -Be $script:transformerConfig.DModel
            
            # Check that layer normalization was applied correctly
            for ($b = 0; $b -lt $script:transformerConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:transformerConfig.SeqLength; $s++) {
                    $mean = 0
                    $variance = 0
                    
                    # Calculate mean
                    for ($d = 0; $d -lt $script:transformerConfig.DModel; $d++) {
                        $mean += $finalOutput[$b,$s,$d]
                    }
                    $mean /= $script:transformerConfig.DModel
                    
                    # Calculate variance
                    for ($d = 0; $d -lt $script:transformerConfig.DModel; $d++) {
                        $variance += [Math]::Pow($finalOutput[$b,$s,$d] - $mean, 2)
                    }
                    $variance /= $script:transformerConfig.DModel
                    
                    # Check normalization statistics
                    $mean | Should -BeLessThan 0.1
                    [Math]::Abs($variance - 1) | Should -BeLessThan 0.1
                }
            }
        }
    }
}
                    }
                }
            }
            
            # Act - Training
            $trainingOutput = CrossAttentionForward -Layer $layer -DecoderInput $decoderInput -EncoderOutput $encoderOutput -Training $true
            
            # Act - Inference
            $inferenceOutput = CrossAttentionForward -Layer $layer -DecoderInput $decoderInput -EncoderOutput $encoderOutput -Training $false
            
            # Assert
            $trainingOutput | Should -Not -BeNullOrEmpty
            $inferenceOutput | Should -Not -BeNullOrEmpty
            
            # Training and inference outputs should be different due to dropout
            $diff = 0
            for ($b = 0; $b -lt $script:crossAttnConfig.BatchSize; $b++) {
                for ($d = 0; $d -lt $script:crossAttnConfig.DecoderLength; $d++) {
                    for ($h = 0; $h -lt $script:crossAttnConfig.DecoderDim; $h++) {
                        $diff += [Math]::Abs($trainingOutput[$b,$d,$h] - $inferenceOutput[$b,$d,$h])
                    }
                }
            }
            
            $diff | Should -Not -Be 0
        }
    }
    
    Context "Encoder-Decoder Integration" {
        BeforeAll {
            $script:encDecConfig = @{
                BatchSize = 4
                SourceLength = 20
                TargetLength = 16
                ModelDim = 64
                NumHeads = 8
                DropoutRate = 0.1
            }
        }
        
        It "Should integrate encoder and decoder with cross-attention" {
            # Arrange
            # 1. Encoder components
            $encPosEnc = Add-PositionalEncoding -Name "enc_pos" `
                                              -InputShape @($script:encDecConfig.SourceLength, $script:encDecConfig.ModelDim)
            
            $encSelfAttn = Add-MultiHeadAttention -Name "enc_self_attn" `
                                                -InputShape @($script:encDecConfig.SourceLength, $script:encDecConfig.ModelDim) `
                                                -NumHeads $script:encDecConfig.NumHeads `
                                                -DropoutRate $script:encDecConfig.DropoutRate
            
            $encResidual = Add-ResidualConnection -Name "enc_residual" `
                                                -InputShape @($script:encDecConfig.SourceLength, $script:encDecConfig.ModelDim)
            
            $encLayerNorm = Add-LayerNormalization -Name "enc_ln" `
                                                 -InputShape @($script:encDecConfig.SourceLength, $script:encDecConfig.ModelDim)
            
            # 2. Decoder components
            $decPosEnc = Add-PositionalEncoding -Name "dec_pos" `
                                              -InputShape @($script:encDecConfig.TargetLength, $script:encDecConfig.ModelDim)
            
            $decSelfAttn = Add-MultiHeadAttention -Name "dec_self_attn" `
                                                -InputShape @($script:encDecConfig.TargetLength, $script:encDecConfig.ModelDim) `
                                                -NumHeads $script:encDecConfig.NumHeads `
                                                -DropoutRate $script:encDecConfig.DropoutRate `
                                                -UseCausalMask $true
            
            $crossAttn = Add-CrossAttention -Name "cross_attn" `
                                          -DecoderShape @($script:encDecConfig.TargetLength, $script:encDecConfig.ModelDim) `
                                          -EncoderShape @($script:encDecConfig.SourceLength, $script:encDecConfig.ModelDim) `
                                          -NumHeads $script:encDecConfig.NumHeads `
                                          -DropoutRate $script:encDecConfig.DropoutRate
            
            $decResidual = Add-ResidualConnection -Name "dec_residual" `
                                                -InputShape @($script:encDecConfig.TargetLength, $script:encDecConfig.ModelDim)
            
            $decLayerNorm = Add-LayerNormalization -Name "dec_ln" `
                                                 -InputShape @($script:encDecConfig.TargetLength, $script:encDecConfig.ModelDim)
            
            # Initialize inputs
            $sourceInput = New-Object 'double[,,]' $script:encDecConfig.BatchSize,$script:encDecConfig.SourceLength,$script:encDecConfig.ModelDim
            $targetInput = New-Object 'double[,,]' $script:encDecConfig.BatchSize,$script:encDecConfig.TargetLength,$script:encDecConfig.ModelDim
            
            $random = New-Object Random
            for ($b = 0; $b -lt $script:encDecConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:encDecConfig.SourceLength; $s++) {
                    for ($d = 0; $d -lt $script:encDecConfig.ModelDim; $d++) {
                        $sourceInput[$b,$s,$d] = $random.NextDouble() - 0.5
                    }
                }
                for ($t = 0; $t -lt $script:encDecConfig.TargetLength; $t++) {
                    for ($d = 0; $d -lt $script:encDecConfig.ModelDim; $d++) {
                        $targetInput[$b,$t,$d] = $random.NextDouble() - 0.5
                    }
                }
            }
            
            # Act
            # 1. Encoder forward pass
            $encPosOutput = PositionalEncodingForward -Layer $encPosEnc -Input $sourceInput -Training $true
            $encAttnOutput = MultiHeadAttentionForward -Layer $encSelfAttn -Input $encPosOutput -Training $true
            $encResOutput = ResidualForward -Layer $encResidual -Input $encPosOutput -TransformedInput $encAttnOutput -Training $true
            $encoderOutput = LayerNormForward -Layer $encLayerNorm -Input $encResOutput -Training $true
            
            # 2. Decoder forward pass
            $decPosOutput = PositionalEncodingForward -Layer $decPosEnc -Input $targetInput -Training $true
            $decAttnOutput = MultiHeadAttentionForward -Layer $decSelfAttn -Input $decPosOutput -Training $true
            $decResOutput = ResidualForward -Layer $decResidual -Input $decPosOutput -TransformedInput $decAttnOutput -Training $true
            $decNormOutput = LayerNormForward -Layer $decLayerNorm -Input $decResOutput -Training $true
            
            # 3. Cross-attention
            $crossOutput = CrossAttentionForward -Layer $crossAttn -DecoderInput $decNormOutput -EncoderOutput $encoderOutput -Training $true
            
            # Assert
            # Check encoder output
            $encoderOutput | Should -Not -BeNullOrEmpty
            $encoderOutput.GetLength(0) | Should -Be $script:encDecConfig.BatchSize
            $encoderOutput.GetLength(1) | Should -Be $script:encDecConfig.SourceLength
            $encoderOutput.GetLength(2) | Should -Be $script:encDecConfig.ModelDim
            
            # Check decoder intermediate output
            $decNormOutput | Should -Not -BeNullOrEmpty
            $decNormOutput.GetLength(0) | Should -Be $script:encDecConfig.BatchSize
            $decNormOutput.GetLength(1) | Should -Be $script:encDecConfig.TargetLength
            $decNormOutput.GetLength(2) | Should -Be $script:encDecConfig.ModelDim
            
            # Check final cross-attention output
            $crossOutput | Should -Not -BeNullOrEmpty
            $crossOutput.GetLength(0) | Should -Be $script:encDecConfig.BatchSize
            $crossOutput.GetLength(1) | Should -Be $script:encDecConfig.TargetLength
            $crossOutput.GetLength(2) | Should -Be $script:encDecConfig.ModelDim
            
            # Check that cross-attention is attending to encoder outputs
            $crossAttn.CachedValues.Weights | Should -Not -BeNullOrEmpty
            $crossAttn.CachedValues.Weights.GetLength(2) | Should -Be $script:encDecConfig.TargetLength
            $crossAttn.CachedValues.Weights.GetLength(3) | Should -Be $script:encDecConfig.SourceLength
        }
    }
}
                    $key[$k,$d] = $random.NextDouble() - 0.5
                    $value[$k,$d] = $random.NextDouble() - 0.5
                }
            }
            
            # Act
            $output = Compute-Bucket-Attention -Query $query -Key $key -Value $value
            
            # Assert
            $output | Should -Not -BeNullOrEmpty
            $output.GetLength(0) | Should -Be $numQueries
            $output.GetLength(1) | Should -Be $headDim
            
            # Check attention properties
            for ($q = 0; $q -lt $numQueries; $q++) {
                $norm = 0
                for ($d = 0; $d -lt $headDim; $d++) {
                    $norm += [Math]::Pow($output[$q,$d], 2)
                }
                $norm = [Math]::Sqrt($norm)
                
                # Output vectors should have reasonable magnitude
                $norm | Should -BeLessThan ([Math]::Sqrt($headDim))
            }
        }
        
        It "Should perform full LSH attention forward pass" {
            # Arrange
            $headDim = $script:lshConfig.ModelDim / $script:lshConfig.NumHeads
            
            $query = New-Object 'double[,,,]' $script:lshConfig.BatchSize,$script:lshConfig.NumHeads,$script:lshConfig.SeqLength,$headDim
            $key = New-Object 'double[,,,]' $script:lshConfig.BatchSize,$script:lshConfig.NumHeads,$script:lshConfig.SeqLength,$headDim
            $value = New-Object 'double[,,,]' $script:lshConfig.BatchSize,$script:lshConfig.NumHeads,$script:lshConfig.SeqLength,$headDim
            
            # Initialize with random values
            $random = New-Object Random
            for ($b = 0; $b -lt $script:lshConfig.BatchSize; $b++) {
                for ($h = 0; $h -lt $script:lshConfig.NumHeads; $h++) {
                    for ($s = 0; $s -lt $script:lshConfig.SeqLength; $s++) {
                        for ($d = 0; $d -lt $headDim; $d++) {
                            $query[$b,$h,$s,$d] = $random.NextDouble() - 0.5
                            $key[$b,$h,$s,$d] = $random.NextDouble() - 0.5
                            $value[$b,$h,$s,$d] = $random.NextDouble() - 0.5
                        }
                    }
                }
            }
            
            # Act
            $output = LSH-Attention -Query $query -Key $key -Value $value `
                                  -NumHashes $script:lshConfig.NumHashes `
                                  -BucketSize $script:lshConfig.BucketSize `
                                  -NumRounds $script:lshConfig.NumRounds
            
            # Assert
            $output | Should -Not -BeNullOrEmpty
            $output.GetLength(0) | Should -Be $script:lshConfig.BatchSize
            $output.GetLength(1) | Should -Be $script:lshConfig.NumHeads
            $output.GetLength(2) | Should -Be $script:lshConfig.SeqLength
            $output.GetLength(3) | Should -Be $headDim
            
            # Verify attention properties
            for ($b = 0; $b -lt $script:lshConfig.BatchSize; $b++) {
                for ($h = 0; $h -lt $script:lshConfig.NumHeads; $h++) {
                    for ($s = 0; $s -lt $script:lshConfig.SeqLength; $s++) {
                        # Check output vector magnitude
                        $norm = 0
                        for ($d = 0; $d -lt $headDim; $d++) {
                            $norm += [Math]::Pow($output[$b,$h,$s,$d], 2)
                        }
                        $norm = [Math]::Sqrt($norm)
                        
                        # Output vectors should have reasonable magnitude
                        $norm | Should -BeLessThan ([Math]::Sqrt($headDim))
                    }
                }
            }
        }
        
        It "Should integrate LSH attention with efficient attention layer" {
            # Arrange
            $layer = Add-EfficientAttention -Name "eff_lsh" `
                                          -InputShape @($script:lshConfig.SeqLength, $script:lshConfig.ModelDim) `
                                          -NumHeads $script:lshConfig.NumHeads `
                                          -Variant "LSH" `
                                          -ChunkSize $script:lshConfig.BucketSize
            
            $input = New-Object 'double[,,]' $script:lshConfig.BatchSize,$script:lshConfig.SeqLength,$script:lshConfig.ModelDim
            
            # Initialize input with random values
            $random = New-Object Random
            for ($b = 0; $b -lt $script:lshConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:lshConfig.SeqLength; $s++) {
                    for ($d = 0; $d -lt $script:lshConfig.ModelDim; $d++) {
                        $input[$b,$s,$d] = $random.NextDouble() - 0.5
                    }
                }
            }
            
            # Act
            $output = EfficientAttentionForward -Layer $layer -Input $input -Training $true
            
            # Assert
            $output | Should -Not -BeNullOrEmpty
            $output.GetLength(0) | Should -Be $script:lshConfig.BatchSize
            $output.GetLength(1) | Should -Be $script:lshConfig.SeqLength
            $output.GetLength(2) | Should -Be $script:lshConfig.ModelDim
            
            # Check that LSH attention was used
            $layer.CachedValues.Query | Should -Not -BeNullOrEmpty
            $layer.CachedValues.Key | Should -Not -BeNullOrEmpty
            $layer.CachedValues.Value | Should -Not -BeNullOrEmpty
            $layer.CachedValues.Attention | Should -Not -BeNullOrEmpty
            
            # Verify attention properties
            for ($b = 0; $b -lt $script:lshConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:lshConfig.SeqLength; $s++) {
                    $norm = 0
                    for ($d = 0; $d -lt $script:lshConfig.ModelDim; $d++) {
                        $norm += [Math]::Pow($output[$b,$s,$d], 2)
                    }
                    $norm = [Math]::Sqrt($norm)
                    
                    # Output vectors should have reasonable magnitude
                    $norm | Should -BeLessThan ([Math]::Sqrt($script:lshConfig.ModelDim))
                }
            }
        }
    }
            # Arrange & Act
            $mask = Generate-StridedMask -SeqLength $script:sparseConfig.SeqLength `
                                       -Stride $script:sparseConfig.Stride `
                                       -WindowSize $script:sparseConfig.WindowSize
            
            # Assert
            $mask | Should -Not -BeNullOrEmpty
            $mask.GetLength(0) | Should -Be $script:sparseConfig.SeqLength
            $mask.GetLength(1) | Should -Be $script:sparseConfig.SeqLength
            
            $halfWindow = [Math]::Floor($script:sparseConfig.WindowSize / 2)
            
            # Check strided pattern with local windows
            for ($i = 0; $i -lt $script:sparseConfig.SeqLength; $i++) {
                # Check local window
                $localStart = [Math]::Max(0, $i - $halfWindow)
                $localEnd = [Math]::Min($script:sparseConfig.SeqLength - 1, $i + $halfWindow)
                
                for ($j = $localStart; $j -le $localEnd; $j++) {
                    $mask[$i,$j] | Should -Be $true
                }
                
                # Check strided connections
                for ($s = 0; $s -lt $script:sparseConfig.SeqLength; $s += $script:sparseConfig.Stride) {
                    if ($s -lt $localStart -or $s -gt $localEnd) {
                        $mask[$i,$s] | Should -Be $true
                    }
                }
            }
        }
        
        It "Should perform sparse attention forward pass with block pattern" {
            # Arrange
            $headDim = $script:sparseConfig.ModelDim / $script:sparseConfig.NumHeads
            
            $query = New-Object 'double[,,,]' $script:sparseConfig.BatchSize,$script:sparseConfig.NumHeads,$script:sparseConfig.SeqLength,$headDim
            $key = New-Object 'double[,,,]' $script:sparseConfig.BatchSize,$script:sparseConfig.NumHeads,$script:sparseConfig.SeqLength,$headDim
            $value = New-Object 'double[,,,]' $script:sparseConfig.BatchSize,$script:sparseConfig.NumHeads,$script:sparseConfig.SeqLength,$headDim
            
            # Initialize with random values
            $random = New-Object Random
            for ($b = 0; $b -lt $script:sparseConfig.BatchSize; $b++) {
                for ($h = 0; $h -lt $script:sparseConfig.NumHeads; $h++) {
                    for ($s = 0; $s -lt $script:sparseConfig.SeqLength; $s++) {
                        for ($d = 0; $d -lt $headDim; $d++) {
                            $query[$b,$h,$s,$d] = $random.NextDouble() - 0.5
                            $key[$b,$h,$s,$d] = $random.NextDouble() - 0.5
                            $value[$b,$h,$s,$d] = $random.NextDouble() - 0.5
                        }
                    }
                }
            }
            
            # Act
            $output = Sparse-Attention -Query $query -Key $key -Value $value `
                                     -BlockSize $script:sparseConfig.BlockSize `
                                     -Pattern "Block"
            
            # Assert
            $output | Should -Not -BeNullOrEmpty
            $output.GetLength(0) | Should -Be $script:sparseConfig.BatchSize
            $output.GetLength(1) | Should -Be $script:sparseConfig.NumHeads
            $output.GetLength(2) | Should -Be $script:sparseConfig.SeqLength
            $output.GetLength(3) | Should -Be $headDim
            
            # Verify sparsity pattern
            $numBlocks = [Math]::Ceiling($script:sparseConfig.SeqLength / $script:sparseConfig.BlockSize)
            for ($b = 0; $b -lt $script:sparseConfig.BatchSize; $b++) {
                for ($h = 0; $h -lt $script:sparseConfig.NumHeads; $h++) {
                    for ($block = 0; $block -lt $numBlocks; $block++) {
                        $blockStart = $block * $script:sparseConfig.BlockSize
                        $blockEnd = [Math]::Min(($block + 1) * $script:sparseConfig.BlockSize, $script:sparseConfig.SeqLength)
                        
                        # Check that block output is not zero
                        $blockSum = 0
                        for ($s = $blockStart; $s -lt $blockEnd; $s++) {
                            for ($d = 0; $d -lt $headDim; $d++) {
                                $blockSum += [Math]::Abs($output[$b,$h,$s,$d])
                            }
                        }
                        $blockSum | Should -BeGreaterThan 0
                    }
                }
            }
        }
        
        It "Should integrate sparse attention with efficient attention layer" {
            # Arrange
            $layer = Add-EfficientAttention -Name "eff_sparse" `
                                          -InputShape @($script:sparseConfig.SeqLength, $script:sparseConfig.ModelDim) `
                                          -NumHeads $script:sparseConfig.NumHeads `
                                          -Variant "Sparse" `
                                          -ChunkSize $script:sparseConfig.BlockSize
            
            $input = New-Object 'double[,,]' $script:sparseConfig.BatchSize,$script:sparseConfig.SeqLength,$script:sparseConfig.ModelDim
            
            # Initialize input with random values
            $random = New-Object Random
            for ($b = 0; $b -lt $script:sparseConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:sparseConfig.SeqLength; $s++) {
                    for ($d = 0; $d -lt $script:sparseConfig.ModelDim; $d++) {
                        $input[$b,$s,$d] = $random.NextDouble() - 0.5
                    }
                }
            }
            
            # Act
            $output = EfficientAttentionForward -Layer $layer -Input $input -Training $true
            
            # Assert
            $output | Should -Not -BeNullOrEmpty
            $output.GetLength(0) | Should -Be $script:sparseConfig.BatchSize
            $output.GetLength(1) | Should -Be $script:sparseConfig.SeqLength
            $output.GetLength(2) | Should -Be $script:sparseConfig.ModelDim
            
            # Check attention properties
            for ($b = 0; $b -lt $script:sparseConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:sparseConfig.SeqLength; $s++) {
                    $norm = 0
                    for ($d = 0; $d -lt $script:sparseConfig.ModelDim; $d++) {
                        $norm += [Math]::Pow($output[$b,$s,$d], 2)
                    }
                    $norm = [Math]::Sqrt($norm)
                    
                    # Output vectors should have reasonable magnitude
                    $norm | Should -BeLessThan ([Math]::Sqrt($script:sparseConfig.ModelDim))
                }
            }
        }
    }
                        $diffX2 += [Math]::Abs($recoveredX2[$b,$s,$d] - $layer.CachedValues.X2[$b,$s,$d])
                    }
                }
            }
            
            # The difference should be very small (floating point precision)
            $diffX2 / ($script:revConfig.BatchSize * $script:revConfig.SeqLength * ($script:revConfig.ModelDim/2)) | Should -BeLessThan 1e-10
            
            # Similarly recover x1 = y1 - F(x2)
            $fx2 = $layer.CachedValues.FX2
            $recoveredX1 = New-Object 'double[,,]' $script:revConfig.BatchSize,$script:revConfig.SeqLength,($script:revConfig.ModelDim/2)
            for ($b = 0; $b -lt $script:revConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:revConfig.SeqLength; $s++) {
                    for ($d = 0; $d -lt $script:revConfig.ModelDim/2; $d++) {
                        $recoveredX1[$b,$s,$d] = $y1[$b,$s,$d] - $fx2[$b,$s,$d]
                    }
                }
            }
            
            # Verify recovered X1 matches original
            $diffX1 = 0
            for ($b = 0; $b -lt $script:revConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:revConfig.SeqLength; $s++) {
                    for ($d = 0; $d -lt $script:revConfig.ModelDim/2; $d++) {
                        $diffX1 += [Math]::Abs($recoveredX1[$b,$s,$d] - $layer.CachedValues.X1[$b,$s,$d])
                    }
                }
            }
            
            # The difference should be very small (floating point precision)
            $diffX1 / ($script:revConfig.BatchSize * $script:revConfig.SeqLength * ($script:revConfig.ModelDim/2)) | Should -BeLessThan 1e-10
        }
    }
    
    Context "Complete Transformer Block Integration" {
        BeforeAll {
            $script:transformerConfig = @{
                BatchSize = 2
                SeqLength = 128
                ModelDim = 64
                NumHeads = 8
                DropoutRate = 0.1
                BlockSize = 32
            }
        }
        
        It "Should combine all attention variants in a transformer block" {
            # Arrange
            # Create layers with different attention variants
            $linearAttn = Add-EfficientAttention -Name "linear_attn" `
                                               -InputShape @($script:transformerConfig.SeqLength, $script:transformerConfig.ModelDim) `
                                               -NumHeads $script:transformerConfig.NumHeads `
                                               -Variant "Linear" `
                                               -ChunkSize $script:transformerConfig.BlockSize
            
            $lshAttn = Add-EfficientAttention -Name "lsh_attn" `
                                            -InputShape @($script:transformerConfig.SeqLength, $script:transformerConfig.ModelDim) `
                                            -NumHeads $script:transformerConfig.NumHeads `
                                            -Variant "LSH" `
                                            -ChunkSize $script:transformerConfig.BlockSize
            
            $sparseAttn = Add-EfficientAttention -Name "sparse_attn" `
                                               -InputShape @($script:transformerConfig.SeqLength, $script:transformerConfig.ModelDim) `
                                               -NumHeads $script:transformerConfig.NumHeads `
                                               -Variant "Sparse" `
                                               -ChunkSize $script:transformerConfig.BlockSize
            
            $revAttn = Add-ReversibleAttention -Name "rev_attn" `
                                             -InputShape @($script:transformerConfig.SeqLength, $script:transformerConfig.ModelDim) `
                                             -NumHeads $script:transformerConfig.NumHeads `
                                             -AttentionType "Linear" `
                                             -ChunkSize $script:transformerConfig.BlockSize
            
            # Add position encodings
            $posEnc = Add-RelativePositionalEncoding -Name "pos_enc" `
                                                   -InputShape @($script:transformerConfig.SeqLength, $script:transformerConfig.ModelDim) `
                                                   -NumHeads $script:transformerConfig.NumHeads
            
            # Initialize input
            $input = New-Object 'double[,,]' $script:transformerConfig.BatchSize,$script:transformerConfig.SeqLength,$script:transformerConfig.ModelDim
            
            $random = New-Object Random
            for ($b = 0; $b -lt $script:transformerConfig.BatchSize; $b++) {
                for ($s = 0; $s -lt $script:transformerConfig.SeqLength; $s++) {
                    for ($d = 0; $d -lt $script:transformerConfig.ModelDim; $d++) {
                        $input[$b,$s,$d] = $random.NextDouble() - 0.5
                    }
                }
            }
            
            # Act
            # 1. Linear attention branch
            $linearOutput = EfficientAttentionForward -Layer $linearAttn -Input $input -Training $true
            
            # 2. LSH attention branch
            $lshOutput = EfficientAttentionForward -Layer $lshAttn -Input $input -Training $true
            
            # 3. Sparse attention branch
            $sparseOutput = EfficientAttentionForward -Layer $sparseAttn -Input $input -Training $true
            
            # 4. Reversible attention branch
            $revOutput = ReversibleAttentionForward -Layer $revAttn -Input $input -Training $true
            
            # Assert
            # Check all outputs maintain the expected shape
            $outputs = @($linearOutput, $lshOutput, $sparseOutput, $revOutput)
            foreach ($output in $outputs) {
                $output | Should -Not -BeNullOrEmpty
                $output.GetLength(0) | Should -Be $script:transformerConfig.BatchSize
                $output.GetLength(1) | Should -Be $script:transformerConfig.SeqLength
                $output.GetLength(2) | Should -Be $script:transformerConfig.ModelDim
            }
            
            # Verify that different attention mechanisms produce different outputs
            foreach ($i in 0..($outputs.Count-2)) {
                for ($j = ($i+1)..($outputs.Count-1)) {
                    $diff = 0
                    for ($b = 0; $b -lt $script:transformerConfig.BatchSize; $b++) {
                        for ($s = 0; $s -lt $script:transformerConfig.SeqLength; $s++) {
                            for ($d = 0; $d -lt $script:transformerConfig.ModelDim; $d++) {
                                $diff += [Math]::Abs($outputs[$i][$b,$s,$d] - $outputs[$j][$b,$s,$d])
                            }
                        }
                    }
                    $diff | Should -Not -Be 0
                }
            }
            
            # Check that all outputs maintain reasonable magnitudes
            foreach ($output in $outputs) {
                for ($b = 0; $b -lt $script:transformerConfig.BatchSize; $b++) {
                    for ($s = 0; $s -lt $script:transformerConfig.SeqLength; $s++) {
                        $norm = 0
                        for ($d = 0; $d -lt $script:transformerConfig.ModelDim; $d++) {
                            $norm += [Math]::Pow($output[$b,$s,$d], 2)
                        }
                        $norm = [Math]::Sqrt($norm)
                        
                        # Output vectors should have reasonable magnitude
                        $norm | Should -BeLessThan ([Math]::Sqrt($script:transformerConfig.ModelDim))
                    }
                }
            }
        }
    }
}
