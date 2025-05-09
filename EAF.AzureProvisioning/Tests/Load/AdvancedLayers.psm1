true)
    
    try {
        $batchSize = $Input.GetLength(0)
        $sequenceLength = $Input.GetLength(1)
        $outputSequence = New-Object 'double[,,]' $batchSize,$sequenceLength,$Layer.Config.Units
        
        # Initialize states if needed
        if (-not $Layer.State.Cell -or -not $Layer.State.Hidden) {
            $Layer.State.Cell = New-Object 'double[]' $Layer.Config.Units
            $Layer.State.Hidden = New-Object 'double[]' $Layer.Config.Units
        }
        
        # Process sequence
        for ($t = 0; $t -lt $sequenceLength; $t++) {
            $xt = Get-Slice -Input $Input -TimeStep $t
            
            # Apply dropout if enabled
            if ($Layer.Dropout -and $Training) {
                $xt = Apply-Dropout -Input $xt -Dropout $Layer.Dropout -Training $Training
            }
            
            # Apply recurrent dropout if enabled
            if ($Layer.RecurrentDropout -and $Training) {
                $Layer.State.Hidden = Apply-Dropout -Input $Layer.State.Hidden -Dropout $Layer.RecurrentDropout -Training $Training
            }
            
            # Gates
            $inputGate = Sigmoid-Activation -Input (
                Matrix-Add -A (Matrix-Multiply -A $xt -B $Layer.Gates.Input.Kernel) `
                          -B (Matrix-Multiply -A $Layer.State.Hidden -B $Layer.Gates.Input.Recurrent) `
                          -C $Layer.Gates.Input.Bias
            )
            
            $forgetGate = Sigmoid-Activation -Input (
                Matrix-Add -A (Matrix-Multiply -A $xt -B $Layer.Gates.Forget.Kernel) `
                          -B (Matrix-Multiply -A $Layer.State.Hidden -B $Layer.Gates.Forget.Recurrent) `
                          -C $Layer.Gates.Forget.Bias
            )
            
            $cellGate = Tanh-Activation -Input (
                Matrix-Add -A (Matrix-Multiply -A $xt -B $Layer.Gates.Cell.Kernel) `
                          -B (Matrix-Multiply -A $Layer.State.Hidden -B $Layer.Gates.Cell.Recurrent) `
                          -C $Layer.Gates.Cell.Bias
            )
            
            $outputGate = Sigmoid-Activation -Input (
                Matrix-Add -A (Matrix-Multiply -A $xt -B $Layer.Gates.Output.Kernel) `
                          -B (Matrix-Multiply -A $Layer.State.Hidden -B $Layer.Gates.Output.Recurrent) `
                          -C $Layer.Gates.Output.Bias
            )
            
            # Update states
            $Layer.State.Cell = Matrix-Add -A (Matrix-Multiply -A $forgetGate -B $Layer.State.Cell) `
                                         -B (Matrix-Multiply -A $inputGate -B $cellGate)
            
            $Layer.State.Hidden = Matrix-Multiply -A $outputGate -B (Tanh-Activation -Input $Layer.State.Cell)
            
            # Store output
            Set-Slice -Output $outputSequence -TimeStep $t -Value $Layer.State.Hidden
        }
        
        return $outputSequence
    }
    catch {
        Write-Error "Failed in LSTM forward pass: $_"
        return $null
    }
}

function AttentionForward {
    param ($Layer, $Input, $Training = $true)
    
    try {
        $config = $Layer.Config
        $batchSize = $Input.GetLength(0)
        $seqLength = $Input.GetLength(1)
        
        # Linear transformations
        $query = Matrix-Multiply -A $Input -B $Layer.Weights.Query
        $key = Matrix-Multiply -A $Input -B $Layer.Weights.Key
        $value = Matrix-Multiply -A $Input -B $Layer.Weights.Value
        
        # Split heads
        $query = Split-Heads -Input $query -NumHeads $config.NumHeads
        $key = Split-Heads -Input $key -NumHeads $config.NumHeads
        $value = Split-Heads -Input $value -NumHeads $config.NumHeads
        
        # Scale dot-product attention
        $scale = [Math]::Sqrt($config.KeyDim)
        $scores = Matrix-Multiply -A $query -B (Matrix-Transpose -M $key)
        $scores = Matrix-Scale -M $scores -Scale (1.0 / $scale)
        
        # Apply causal mask if needed
        if ($config.UseCausalMask) {
            $scores = Apply-CausalMask -Scores $scores
        }
        
        # Attention weights
        $weights = Softmax-Activation -Input $scores
        
        # Apply dropout if enabled
        if ($Layer.Dropout -and $Training) {
            $weights = Apply-Dropout -Input $weights -Dropout $Layer.Dropout -Training $Training
        }
        
        # Compute attention output
        $attention = Matrix-Multiply -A $weights -B $value
        
        # Merge heads
        $output = Merge-Heads -Input $attention -NumHeads $config.NumHeads
        
        # Final linear transformation
        $output = Matrix-Multiply -A $output -B $Layer.Weights.Output
        
        return $output
    }
    catch {
        Write-Error "Failed in attention forward pass: $_"
        return $null
    }
}

# Helper functions for attention mechanism
function Split-Heads {
    param ($Input, $NumHeads)
    
    $batchSize = $Input.GetLength(0)
    $seqLength = $Input.GetLength(1)
    $depth = $Input.GetLength(2)
    $depthPerHead = $depth / $NumHeads
    
    $output = New-Object 'double[,,,]' $batchSize,$NumHeads,$seqLength,$depthPerHead
    
    for ($b = 0; $b -lt $batchSize; $b++) {
        for ($h = 0; $h -lt $NumHeads; $h++) {
            for ($s = 0; $s -lt $seqLength; $s++) {
                for ($d = 0; $d -lt $depthPerHead; $d++) {
                    $output[$b,$h,$s,$d] = $Input[$b,$s,$h * $depthPerHead + $d]
                }
            }
        }
    }
    
    return $output
}

function Merge-Heads {
    param ($Input, $NumHeads)
    
    $batchSize = $Input.GetLength(0)
    $seqLength = $Input.GetLength(2)
    $depthPerHead = $Input.GetLength(3)
    $depth = $NumHeads * $depthPerHead
    
    $output = New-Object 'double[,,]' $batchSize,$seqLength,$depth
    
    for ($b = 0; $b -lt $batchSize; $b++) {
        for ($h = 0; $h -lt $NumHeads; $h++) {
            for ($s = 0; $s -lt $seqLength; $s++) {
                for ($d = 0; $d -lt $depthPerHead; $d++) {
                    $output[$b,$s,$h * $depthPerHead + $d] = $Input[$b,$h,$s,$d]
                }
            }
        }
    }
    
    return $output
}

function Apply-CausalMask {
    param ($Scores)
    
    $seqLength = $Scores.GetLength(2)
    
    for ($i = 0; $i -lt $seqLength; $i++) {
        for ($j = $i + 1; $j -lt $seqLength; $j++) {
            $Scores[0,0,$i,$j] = [double]::NegativeInfinity
        }
    }
    
    return $Scores
}

# Activation functions
function Sigmoid-Activation {
    param ($Input)
    return $Input | ForEach-Object { 1 / (1 + [Math]::Exp(-$_)) }
}

function Tanh-Activation {
    param ($Input)
    return $Input | ForEach-Object { [Math]::Tanh($_) }
}

function Softmax-Activation {
    param ($Input)
    
    $maxVal = ($Input | Measure-Object -Maximum).Maximum
    $expValues = $Input | ForEach-Object { [Math]::Exp($_ - $maxVal) }
    $sumExp = ($expValues | Measure-Object -Sum).Sum
    
    return $expValues | ForEach-Object { $_ / $sumExp }
}

# Matrix operations for 3D tensors
function Matrix-Multiply3D {
    param ($A, $B)
    
    $batchSize = $A.GetLength(0)
    $seqLength = $A.GetLength(1)
    $featuresA = $A.GetLength(2)
    $featuresB = $B.GetLength(2)
    
    $result = New-Object 'double[,,]' $batchSize,$seqLength,$featuresB
    
    for ($b = 0; $b -lt $batchSize; $b++) {
        for ($s = 0; $s -lt $seqLength; $s++) {
            for ($i = 0; $i -lt $featuresB; $i++) {
                $sum = 0
                for ($j = 0; $j -lt $featuresA; $j++) {
                    $sum += $A[$b,$s,$j] * $B[$b,$j,$i]
                }
                $result[$b,$s,$i] = $sum
            }
        }
    }
    
    return $result
}

# Export functions
Export-ModuleMember -Function @(
    'Add-ConvolutionalLayer',
    'Add-LSTMLayer',
    'Add-AttentionLayer',
    'ConvForward',
    'LSTMForward',
    'AttentionForward'
)

function Add-ResidualConnection {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [array]$InputShape,
        
        [Parameter(Mandatory=$false)]
        [bool]$ProjectShortcut = $false
    )
    
    try {
        $layer = @{
            Name = $Name
            Type = "Residual"
            Config = @{
                InputShape = $InputShape
                ProjectShortcut = $ProjectShortcut
            }
            Parameters = @{}
            
            # Add projection layer if shapes don't match
            if ($ProjectShortcut) {
                Weights = New-Object 'double[,]' $InputShape[-1],$InputShape[-1]
            }
        }
        
        return $layer
    }
    catch {
        Write-Error "Failed to create residual connection: $_"
        return $null
    }
}

function ResidualForward {
    param (
        [Parameter(Mandatory=$true)]
        $Layer,
        
        [Parameter(Mandatory=$true)]
        $Input,
        
        [Parameter(Mandatory=$true)]
        $TransformedInput,
        
        [bool]$Training = $true
    )
    
    try {
        $shape = Get-TensorShape -Input $Input
        $output = New-Object 'double[,,]' $shape[0],$shape[1],$shape[2]
        
        # Project shortcut if needed
        if ($Layer.Config.ProjectShortcut) {
            $shortcut = Matrix-Multiply3D -A $Input -B $Layer.Weights
        }
        else {
            $shortcut = $Input
        }
        
        # Add residual connection
        for ($b = 0; $b -lt $shape[0]; $b++) {
            for ($i = 0; $i -lt $shape[1]; $i++) {
                for ($j = 0; $j -lt $shape[2]; $j++) {
                    $output[$b,$i,$j] = $shortcut[$b,$i,$j] + $TransformedInput[$b,$i,$j]
                }
            }
        }
        
        return $output
    }
    catch {
        Write-Error "Failed in residual forward pass: $_"
        return $null
    }
}

function Add-LayerNormalization {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [array]$InputShape,
        
        [Parameter(Mandatory=$false)]
        [double]$Epsilon = 1e-5
    )
    
    try {
        $layer = @{
            Name = $Name
            Type = "LayerNorm"
            Config = @{
                InputShape = $InputShape
                Epsilon = $Epsilon
            }
            Parameters = @{
                Gamma = New-Object 'double[]' $InputShape[-1]  # Scale parameter
                Beta = New-Object 'double[]' $InputShape[-1]   # Shift parameter
            }
            CachedValues = @{}
        }
        
        # Initialize parameters
        for ($i = 0; $i -lt $InputShape[-1]; $i++) {
            $layer.Parameters.Gamma[$i] = 1.0
            $layer.Parameters.Beta[$i] = 0.0
        }
        
        return $layer
    }
    catch {
        Write-Error "Failed to create layer normalization: $_"
        return $null
    }
}

function LayerNormForward {
    param (
        [Parameter(Mandatory=$true)]
        $Layer,
        
        [Parameter(Mandatory=$true)]
        $Input,
        
        [bool]$Training = $true
    )
    
    try {
        $shape = Get-TensorShape -Input $Input
        $output = New-Object 'double[,,]' $shape[0],$shape[1],$shape[2]
        
        # Normalize each sequence position independently
        for ($b = 0; $b -lt $shape[0]; $b++) {
            for ($i = 0; $i -lt $shape[1]; $i++) {
                # Calculate mean
                $mean = 0
                for ($j = 0; $j -lt $shape[2]; $j++) {
                    $mean += $Input[$b,$i,$j]
                }
                $mean /= $shape[2]
                
                # Calculate variance
                $variance = 0
                for ($j = 0; $j -lt $shape[2]; $j++) {
                    $variance += [Math]::Pow($Input[$b,$i,$j] - $mean, 2)
                }
                $variance /= $shape[2]
                
                # Normalize and scale
                for ($j = 0; $j -lt $shape[2]; $j++) {
                    $normalized = ($Input[$b,$i,$j] - $mean) / [Math]::Sqrt($variance + $Layer.Config.Epsilon)
                    $output[$b,$i,$j] = $normalized * $Layer.Parameters.Gamma[$j] + $Layer.Parameters.Beta[$j]
                }
            }
        }
        
        if ($Training) {
            $Layer.CachedValues.Input = $Input
            $Layer.CachedValues.Mean = $mean
            $Layer.CachedValues.Variance = $variance
        }
        
        return $output
    }
    catch {
        Write-Error "Failed in layer normalization forward pass: $_"
        return $null
    }
}

# Matrix operations helper for residual connections
function Matrix-Multiply3D {
    param (
        [Parameter(Mandatory=$true)]
        $A,
        
        [Parameter(Mandatory=$true)]
        $B
    )
    
    try {
        $shapeA = Get-TensorShape -Input $A
        $shapeB = Get-TensorShape -Input $B
        
        $output = New-Object 'double[,,]' $shapeA[0],$shapeA[1],$shapeB[-1]
        
        for ($b = 0; $b -lt $shapeA[0]; $b++) {
            for ($i = 0; $i -lt $shapeA[1]; $i++) {
                for ($j = 0; $j -lt $shapeB[-1]; $j++) {
                    $sum = 0
                    for ($k = 0; $k -lt $shapeA[-1]; $k++) {
                        $sum += $A[$b,$i,$k] * $B[$k,$j]
                    }
                    $output[$b,$i,$j] = $sum
                }
            }
        }
        
        return $output
    }
    catch {
        Write-Error "Failed in matrix multiplication: $_"
        return $null
    }
}

# Export additional functions
Export-ModuleMember -Function @(
    'Add-ResidualConnection',
    'ResidualForward',
    'Add-LayerNormalization',
    'LayerNormForward'
)

function Add-CrossAttention {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [array]$DecoderShape,
        
        [Parameter(Mandatory=$true)]
        [array]$EncoderShape,
        
        [Parameter(Mandatory=$true)]
        [int]$NumHeads,
        
        [Parameter(Mandatory=$false)]
        [double]$DropoutRate = 0.1
    )
    
    try {
        $decoderDim = $DecoderShape[-1]
        $encoderDim = $EncoderShape[-1]
        $d_k = [Math]::Floor($decoderDim / $NumHeads)
        
        $layer = @{
            Name = $Name
            Type = "CrossAttention"
            Config = @{
                DecoderShape = $DecoderShape
                EncoderShape = $EncoderShape
                NumHeads = $NumHeads
                HeadDim = $d_k
                DropoutRate = $DropoutRate
            }
            Weights = @{
                # Decoder projections
                Query = New-Object 'double[,]' $decoderDim,($NumHeads * $d_k)
                
                # Encoder projections
                Key = New-Object 'double[,]' $encoderDim,($NumHeads * $d_k)
                Value = New-Object 'double[,]' $encoderDim,($NumHeads * $d_k)
                
                # Output projection
                Output = New-Object 'double[,]' ($NumHeads * $d_k),$decoderDim
            }
            LayerNorm = @{
                Decoder = Add-LayerNormalization -Name "$Name.DecoderNorm" -InputShape @($decoderDim)
                Output = Add-LayerNormalization -Name "$Name.OutputNorm" -InputShape @($decoderDim)
            }
            CachedValues = @{}
        }
        
        # Initialize weights with scaled normal distribution
        $scale = [Math]::Sqrt(2.0 / $decoderDim)
        $random = New-Object Random
        
        foreach ($weightMatrix in @($layer.Weights.Query, $layer.Weights.Key, $layer.Weights.Value, $layer.Weights.Output)) {
            for ($i = 0; $i -lt $weightMatrix.GetLength(0); $i++) {
                for ($j = 0; $j -lt $weightMatrix.GetLength(1); $j++) {
                    # Box-Muller transform for normal distribution
                    $u1 = $random.NextDouble()
                    $u2 = $random.NextDouble()
                    $z = [Math]::Sqrt(-2 * [Math]::Log($u1)) * [Math]::Cos(2 * [Math]::PI * $u2)
                    $weightMatrix[$i,$j] = $z * $scale
                }
            }
        }
        
        return $layer
    }
    catch {
        Write-Error "Failed to create cross-attention layer: $_"
        return $null
    }
}

function CrossAttentionForward {
    param (
        [Parameter(Mandatory=$true)]
        $Layer,
        
        [Parameter(Mandatory=$true)]
        $DecoderInput,
        
        [Parameter(Mandatory=$true)]
        $EncoderOutput,
        
        [bool]$Training = $true
    )
    
    try {
        $batchSize = $DecoderInput.GetLength(0)
        $decoderLength = $DecoderInput.GetLength(1)
        $encoderLength = $EncoderOutput.GetLength(1)
        $numHeads = $Layer.Config.NumHeads
        $headDim = $Layer.Config.HeadDim
        
        # Layer normalize inputs
        $normalizedDecoder = LayerNormForward -Layer $Layer.LayerNorm.Decoder -Input $DecoderInput -Training $Training
        
        # Linear projections
        $query = Matrix-Multiply3D -A $normalizedDecoder -B $Layer.Weights.Query
        $key = Matrix-Multiply3D -A $EncoderOutput -B $Layer.Weights.Key
        $value = Matrix-Multiply3D -A $EncoderOutput -B $Layer.Weights.Value
        
        # Reshape for multi-head attention
        $query = Reshape-ForAttention -Input $query -BatchSize $batchSize -SeqLength $decoderLength -NumHeads $numHeads -HeadDim $headDim
        $key = Reshape-ForAttention -Input $key -BatchSize $batchSize -SeqLength $encoderLength -NumHeads $numHeads -HeadDim $headDim
        $value = Reshape-ForAttention -Input $value -BatchSize $batchSize -SeqLength $encoderLength -NumHeads $numHeads -HeadDim $headDim
        
        # Scale dot-product attention
        $scale = [Math]::Sqrt($headDim)
        $scores = Matrix-MultiplyAttention -Q $query -K $key
        $scores = Matrix-Scale -M $scores -Scale (1.0 / $scale)
        
        # Attention weights
        $weights = Softmax-Activation4D -Input $scores
        
        # Apply dropout if training
        if ($Training -and $Layer.Config.DropoutRate -gt 0) {
            $weights = Apply-Dropout4D -Input $weights -Rate $Layer.Config.DropoutRate
        }
        
        # Compute attention output
        $attention = Matrix-MultiplyAttention -Q $weights -K $value
        
        # Reshape back
        $attention = Reshape-FromAttention -Input $attention -BatchSize $batchSize -SeqLength $decoderLength -NumHeads $numHeads -HeadDim $headDim
        
        # Final linear transformation
        $output = Matrix-Multiply3D -A $attention -B $Layer.Weights.Output
        
        # Final layer normalization
        $output = LayerNormForward -Layer $Layer.LayerNorm.Output -Input $output -Training $Training
        
        if ($Training) {
            $Layer.CachedValues.Query = $query
            $Layer.CachedValues.Key = $key
            $Layer.CachedValues.Value = $value
            $Layer.CachedValues.Weights = $weights
            $Layer.CachedValues.Attention = $attention
        }
        
        return $output
    }
    catch {
        Write-Error "Failed in cross-attention forward pass: $_"
        return $null
    }
}

# Matrix operation specifically for cross-attention
function Matrix-MultiplyAttentionCross {
    param (
        [Parameter(Mandatory=$true)]
        $Q,
        
        [Parameter(Mandatory=$true)]
        $K,
        
        [Parameter(Mandatory=$true)]
        $V
    )
    
    try {
        $batchSize = $Q.GetLength(0)
        $numHeads = $Q.GetLength(1)
        $queryLength = $Q.GetLength(2)
        $keyLength = $K.GetLength(2)
        $headDim = $Q.GetLength(3)
        
        # Compute attention scores
        $scores = New-Object 'double[,,,]' $batchSize,$numHeads,$queryLength,$keyLength
        
        for ($b = 0; $b -lt $batchSize; $b++) {
            for ($h = 0; $h -lt $numHeads; $h++) {
                for ($q = 0; $q -lt $queryLength; $q++) {
                    for ($k = 0; $k -lt $keyLength; $k++) {
                        $sum = 0
                        for ($d = 0; $d -lt $headDim; $d++) {
                            $sum += $Q[$b,$h,$q,$d] * $K[$b,$h,$k,$d]
                        }
                        $scores[$b,$h,$q,$k] = $sum
                    }
                }
            }
        }
        
        return $scores
    }
    catch {
        Write-Error "Failed in cross-attention matrix multiplication: $_"
        return $null
    }
}

# Export additional functions
Export-ModuleMember -Function @(
    'Add-CrossAttention',
    'CrossAttentionForward'
)

function Add-EfficientAttention {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [array]$InputShape,
        
        [Parameter(Mandatory=$true)]
        [int]$NumHeads,
        
        [Parameter(Mandatory=$false)]
        [string]$Variant = "Linear", # Linear, LSH, or Sparse
        
        [Parameter(Mandatory=$false)]
        [int]$ChunkSize = 64,
        
        [Parameter(Mandatory=$false)]
        [double]$DropoutRate = 0.1
    )
    
    try {
        $d_model = $InputShape[-1]
        $d_k = [Math]::Floor($d_model / $NumHeads)
        
        $layer = @{
            Name = $Name
            Type = "EfficientAttention"
            Config = @{
                InputShape = $InputShape
                NumHeads = $NumHeads
                HeadDim = $d_k
                Variant = $Variant
                ChunkSize = $ChunkSize
                DropoutRate = $DropoutRate
            }
            Weights = @{
                Query = New-Object 'double[,]' $d_model,($NumHeads * $d_k)
                Key = New-Object 'double[,]' $d_model,($NumHeads * $d_k)
                Value = New-Object 'double[,]' $d_model,($NumHeads * $d_k)
                Output = New-Object 'double[,]' ($NumHeads * $d_k),$d_model
            }
            LayerNorm = Add-LayerNormalization -Name "$Name.LayerNorm" -InputShape @($d_model)
            CachedValues = @{}
        }
        
        # Initialize weights
        $scale = [Math]::Sqrt(2.0 / $d_model)
        $random = New-Object Random
        
        foreach ($weightMatrix in @($layer.Weights.Query, $layer.Weights.Key, $layer.Weights.Value, $layer.Weights.Output)) {
            for ($i = 0; $i -lt $weightMatrix.GetLength(0); $i++) {
                for ($j = 0; $j -lt $weightMatrix.GetLength(1); $j++) {
                    $u1 = $random.NextDouble()
                    $u2 = $random.NextDouble()
                    $z = [Math]::Sqrt(-2 * [Math]::Log($u1)) * [Math]::Cos(2 * [Math]::PI * $u2)
                    $weightMatrix[$i,$j] = $z * $scale
                }
            }
        }
        
        return $layer
    }
    catch {
        Write-Error "Failed to create efficient attention layer: $_"
        return $null
    }
}

function EfficientAttentionForward {
    param (
        [Parameter(Mandatory=$true)]
        $Layer,
        
        [Parameter(Mandatory=$true)]
        $Input,
        
        [bool]$Training = $true
    )
    
    try {
        $batchSize = $Input.GetLength(0)
        $seqLength = $Input.GetLength(1)
        $numHeads = $Layer.Config.NumHeads
        $headDim = $Layer.Config.HeadDim
        $chunkSize = $Layer.Config.ChunkSize
        
        # Layer normalize input
        $normalizedInput = LayerNormForward -Layer $Layer.LayerNorm -Input $Input -Training $Training
        
        # Linear projections
        $query = Matrix-Multiply3D -A $normalizedInput -B $Layer.Weights.Query
        $key = Matrix-Multiply3D -A $normalizedInput -B $Layer.Weights.Key
        $value = Matrix-Multiply3D -A $normalizedInput -B $Layer.Weights.Value
        
        # Reshape for multi-head attention
        $query = Reshape-ForAttention -Input $query -BatchSize $batchSize -SeqLength $seqLength -NumHeads $numHeads -HeadDim $headDim
        $key = Reshape-ForAttention -Input $key -BatchSize $batchSize -SeqLength $seqLength -NumHeads $numHeads -HeadDim $headDim
        $value = Reshape-ForAttention -Input $value -BatchSize $batchSize -SeqLength $seqLength -NumHeads $numHeads -HeadDim $headDim
        
        # Choose attention implementation based on variant
        switch ($Layer.Config.Variant) {
            "Linear" {
                $attention = Linear-Attention -Query $query -Key $key -Value $value -ChunkSize $chunkSize
            }
            "LSH" {
                $attention = LSH-Attention -Query $query -Key $key -Value $value -NumHashes 8
            }
            "Sparse" {
                $attention = Sparse-Attention -Query $query -Key $key -Value $value -BlockSize 64
            }
            default {
                throw "Unsupported attention variant: $($Layer.Config.Variant)"
            }
        }
        
        # Apply dropout if training
        if ($Training -and $Layer.Config.DropoutRate -gt 0) {
            $attention = Apply-Dropout4D -Input $attention -Rate $Layer.Config.DropoutRate
        }
        
        # Reshape back
        $attention = Reshape-FromAttention -Input $attention -BatchSize $batchSize -SeqLength $seqLength -NumHeads $numHeads -HeadDim $headDim
        
        # Final linear transformation
        $output = Matrix-Multiply3D -A $attention -B $Layer.Weights.Output
        
        if ($Training) {
            $Layer.CachedValues.Query = $query
            $Layer.CachedValues.Key = $key
            $Layer.CachedValues.Value = $value
            $Layer.CachedValues.Attention = $attention
        }
        
        return $output
    }
    catch {
        Write-Error "Failed in efficient attention forward pass: $_"
        return $null
    }
}

function Linear-Attention {
    param ($Query, $Key, $Value, $ChunkSize)
    
    try {
        $batchSize = $Query.GetLength(0)
        $numHeads = $Query.GetLength(1)
        $seqLength = $Query.GetLength(2)
        $headDim = $Query.GetLength(3)
        
        # Apply positive random feature transform
        $Query = Feature-Map -Input $Query
        $Key = Feature-Map -Input $Key
        
        $output = New-Object 'double[,,,]' $batchSize,$numHeads,$seqLength,$headDim
        
        # Process in chunks to save memory
        for ($start = 0; $start -lt $seqLength; $start += $ChunkSize) {
            $end = [Math]::Min($start + $ChunkSize, $seqLength)
            $currentChunkSize = $end - $start
            
            # Compute key-value matrix for the current chunk
            $kvMatrix = Matrix-MultiplyChunk -A $Key -B $Value -Start $start -Size $currentChunkSize
            
            # Compute query-key-value attention for the chunk
            $chunkOutput = Matrix-MultiplyChunk -A $Query -B $kvMatrix -Start $start -Size $currentChunkSize
            
            # Copy chunk output to final output
            for ($b = 0; $b -lt $batchSize; $b++) {
                for ($h = 0; $h -lt $numHeads; $h++) {
                    for ($s = 0; $s -lt $currentChunkSize; $s++) {
                        for ($d = 0; $d -lt $headDim; $d++) {
                            $output[$b,$h,$start + $s,$d] = $chunkOutput[$b,$h,$s,$d]
                        }
                    }
                }
            }
        }
        
        return $output
    }
    catch {
        Write-Error "Failed in linear attention computation: $_"
        return $null
    }
}

function Feature-Map {
    param ($Input)
    
    try {
        $shape = Get-TensorShape -Input $Input
        $output = New-Object 'double[,,,]' $shape[0],$shape[1],$shape[2],$shape[3]
        
        # Apply ELU + 1 feature map
        for ($b = 0; $b -lt $shape[0]; $b++) {
            for ($h = 0; $h -lt $shape[1]; $h++) {
                for ($s = 0; $s -lt $shape[2]; $s++) {
                    for ($d = 0; $d -lt $shape[3]; $d++) {
                        $x = $Input[$b,$h,$s,$d]
                        $output[$b,$h,$s,$d] = if ($x -gt 0) { $x + 1 } else { [Math]::Exp($x) }
                    }
                }
            }
        }
        
        return $output
    }
    catch {
        Write-Error "Failed in feature map computation: $_"
        return $null
    }
}

function Matrix-MultiplyChunk {
    param ($A, $B, $Start, $Size)
    
    try {
        $batchSize = $A.GetLength(0)
        $numHeads = $A.GetLength(1)
        $headDim = $A.GetLength(3)
        
        $output = New-Object 'double[,,,]' $batchSize,$numHeads,$Size,$headDim
        
        for ($b = 0; $b -lt $batchSize; $b++) {
            for ($h = 0; $h -lt $numHeads; $h++) {
                for ($i = 0; $i -lt $Size; $i++) {
                    for ($j = 0; $j -lt $headDim; $j++) {
                        $sum = 0
                        for ($k = 0; $k -lt $headDim; $k++) {
                            $sum += $A[$b,$h,$Start + $i,$k] * $B[$b,$h,$k,$j]
                        }
                        $output[$b,$h,$i,$j] = $sum
                    }
                }
            }
        }
        
        return $output
    }
    catch {
        Write-Error "Failed in chunk matrix multiplication: $_"
        return $null
    }
}

# Export additional functions
Export-ModuleMember -Function @(
    'Add-EfficientAttention',
    'EfficientAttentionForward'
)
                        # Calculate relative position and clip to max range
                        $relPos = $j - $i
                        $clippedPos = [Math]::Max(-$Layer.Config.MaxRelativePosition, 
                                     [Math]::Min($Layer.Config.MaxRelativePosition, $relPos))
                        
                        # Convert to positive index for embedding lookup
                        $embeddingIndex = $clippedPos + $Layer.Config.MaxRelativePosition
                        
                        # Compute attention score with relative position
                        $sum = 0
                        for ($d = 0; $d -lt $headDim; $d++) {
                            $sum += $Query[$b,$h,$i,$d] * ($Key[$b,$h,$j,$d] + $Layer.Embeddings[$h,$embeddingIndex,$d])
                        }
                        $scores[$b,$h,$i,$j] = $sum
                    }
                }
            }
        }
        
        return $scores
    }
    catch {
        Write-Error "Failed in relative positional encoding forward pass: $_"
        return $null
    }
}

# Export additional functions
Export-ModuleMember -Function @(
    'Add-RelativePositionalEncoding',
    'RelativePositionalEncodingForward'
)

function LSH-Attention {
    param (
        [Parameter(Mandatory=$true)]
        $Query,
        
        [Parameter(Mandatory=$true)]
        $Key,
        
        [Parameter(Mandatory=$true)]
        $Value,
        
        [Parameter(Mandatory=$true)]
        [int]$NumHashes,
        
        [Parameter(Mandatory=$false)]
        [int]$BucketSize = 64,
        
        [Parameter(Mandatory=$false)]
        [int]$NumRounds = 4
    )
    
    try {
        $batchSize = $Query.GetLength(0)
        $numHeads = $Query.GetLength(1)
        $seqLength = $Query.GetLength(2)
        $headDim = $Query.GetLength(3)
        
        $output = New-Object 'double[,,,]' $batchSize,$numHeads,$seqLength,$headDim
        
        # Initialize random rotation matrices for LSH
        $rotations = @()
        $random = New-Object Random
        for ($r = 0; $r -lt $NumRounds; $r++) {
            $rotation = New-Object 'double[,]' $headDim,$NumHashes
            for ($i = 0; $i -lt $headDim; $i++) {
                for ($j = 0; $j -lt $NumHashes; $j++) {
                    $u1 = $random.NextDouble()
                    $u2 = $random.NextDouble()
                    $rotation[$i,$j] = [Math]::Sqrt(-2 * [Math]::Log($u1)) * [Math]::Cos(2 * [Math]::PI * $u2)
                }
            }
            $rotations += $rotation
        }
        
        # Process each batch and head independently
        for ($b = 0; $b -lt $batchSize; $b++) {
            for ($h = 0; $h -lt $numHeads; $h++) {
                # Compute hashes for each round
                for ($r = 0; $r -lt $NumRounds; $r++) {
                    $queryHashes = Compute-LSH-Hashes -Input $Query[$b,$h,*,*] -Rotation $rotations[$r]
                    $keyHashes = Compute-LSH-Hashes -Input $Key[$b,$h,*,*] -Rotation $rotations[$r]
                    
                    # Group by hash buckets
                    $buckets = Group-By-Hashes -QueryHashes $queryHashes -KeyHashes $keyHashes -BucketSize $BucketSize
                    
                    # Process each bucket
                    foreach ($bucket in $buckets.Keys) {
                        $queryIndices = $buckets[$bucket].QueryIndices
                        $keyIndices = $buckets[$bucket].KeyIndices
                        
                        if ($queryIndices.Count -gt 0 -and $keyIndices.Count -gt 0) {
                            # Compute attention for current bucket
                            $bucketScores = Compute-Bucket-Attention `
                                -Query $Query[$b,$h,$queryIndices,*] `
                                -Key $Key[$b,$h,$keyIndices,*] `
                                -Value $Value[$b,$h,$keyIndices,*]
                            
                            # Accumulate results
                            for ($qi = 0; $qi -lt $queryIndices.Count; $qi++) {
                                $qIdx = $queryIndices[$qi]
                                for ($d = 0; $d -lt $headDim; $d++) {
                                    $output[$b,$h,$qIdx,$d] += $bucketScores[$qi,$d] / $NumRounds
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return $output
    }
    catch {
        Write-Error "Failed in LSH attention computation: $_"
        return $null
    }
}

function Compute-LSH-Hashes {
    param (
        [Parameter(Mandatory=$true)]
        $Input,
        
        [Parameter(Mandatory=$true)]
        $Rotation
    )
    
    try {
        $seqLength = $Input.GetLength(0)
        $headDim = $Input.GetLength(1)
        $numHashes = $Rotation.GetLength(1)
        
        $hashes = New-Object 'long[]' $seqLength
        
        for ($s = 0; $s -lt $seqLength; $s++) {
            $hash = 0
            
            # Compute hash bits using random rotation
            for ($h = 0; $h -lt $numHashes; $h++) {
                $sum = 0
                for ($d = 0; $d -lt $headDim; $d++) {
                    $sum += $Input[$s,$d] * $Rotation[$d,$h]
                }
                
                # Set hash bit based on sign
                if ($sum -gt 0) {
                    $hash = $hash -bor (1L -shl $h)
                }
            }
            
            $hashes[$s] = $hash
        }
        
        return $hashes
    }
    catch {
        Write-Error "Failed in LSH hash computation: $_"
        return $null
    }
}

function Group-By-Hashes {
    param (
        [Parameter(Mandatory=$true)]
        [long[]]$QueryHashes,
        
        [Parameter(Mandatory=$true)]
        [long[]]$KeyHashes,
        
        [Parameter(Mandatory=$true)]
        [int]$BucketSize
    )
    
    try {
        $buckets = @{}
        
        # Group queries by hash
        for ($i = 0; $i -lt $QueryHashes.Length; $i++) {
            $hash = $QueryHashes[$i]
            if (-not $buckets.ContainsKey($hash)) {
                $buckets[$hash] = @{
                    QueryIndices = [System.Collections.ArrayList]@()
                    KeyIndices = [System.Collections.ArrayList]@()
                }
            }
            [void]$buckets[$hash].QueryIndices.Add($i)
        }
        
        # Group keys by hash
        for ($i = 0; $i -lt $KeyHashes.Length; $i++) {
            $hash = $KeyHashes[$i]
            if ($buckets.ContainsKey($hash)) {
                [void]$buckets[$hash].KeyIndices.Add($i)
            }
        }
        
        # Sort and limit bucket sizes
        foreach ($hash in $buckets.Keys) {
            if ($buckets[$hash].KeyIndices.Count -gt $BucketSize) {
                $buckets[$hash].KeyIndices = $buckets[$hash].KeyIndices[0..($BucketSize-1)]
            }
        }
        
        return $buckets
    }
    catch {
        Write-Error "Failed in hash bucket grouping: $_"
        return $null
    }
}

function Compute-Bucket-Attention {
    param (
        [Parameter(Mandatory=$true)]
        $Query,
        
        [Parameter(Mandatory=$true)]
        $Key,
        
        [Parameter(Mandatory=$true)]
        $Value
    )
    
    try {
        $numQueries = $Query.GetLength(0)
        $numKeys = $Key.GetLength(0)
        $headDim = $Query.GetLength(1)
        
        $scores = New-Object 'double[,]' $numQueries,$numKeys
        
        # Compute attention scores
        for ($q = 0; $q -lt $numQueries; $q++) {
            for ($k = 0; $k -lt $numKeys; $k++) {
                $sum = 0
                for ($d = 0; $d -lt $headDim; $d++) {
                    $sum += $Query[$q,$d] * $Key[$k,$d]
                }
                $scores[$q,$k] = $sum / [Math]::Sqrt($headDim)
            }
        }
        
        # Apply softmax
        for ($q = 0; $q -lt $numQueries; $q++) {
            $maxScore = [double]::NegativeInfinity
            for ($k = 0; $k -lt $numKeys; $k++) {
                if ($scores[$q,$k] -gt $maxScore) {
                    $maxScore = $scores[$q,$k]
                }
            }
            
            $expSum = 0
            for ($k = 0; $k -lt $numKeys; $k++) {
                $scores[$q,$k] = [Math]::Exp($scores[$q,$k] - $maxScore)
                $expSum += $scores[$q,$k]
            }
            
            for ($k = 0; $k -lt $numKeys; $k++) {
                $scores[$q,$k] /= $expSum
            }
        }
        
        # Compute weighted values
        $output = New-Object 'double[,]' $numQueries,$headDim
        
        for ($q = 0; $q -lt $numQueries; $q++) {
            for ($d = 0; $d -lt $headDim; $d++) {
                $sum = 0
                for ($k = 0; $k -lt $numKeys; $k++) {
                    $sum += $scores[$q,$k] * $Value[$k,$d]
                }
                $output[$q,$d] = $sum
            }
        }
        
        return $output
    }
    catch {
        Write-Error "Failed in bucket attention computation: $_"
        return $null
    }
}

# Export additional functions
Export-ModuleMember -Function @(
    'LSH-Attention'
)

function Sparse-Attention {
    param (
        [Parameter(Mandatory=$true)]
        $Query,
        
        [Parameter(Mandatory=$true)]
        $Key,
        
        [Parameter(Mandatory=$true)]
        $Value,
        
        [Parameter(Mandatory=$true)]
        [int]$BlockSize,
        
        [Parameter(Mandatory=$false)]
        [string]$Pattern = "Block", # Block, Local, Strided
        
        [Parameter(Mandatory=$false)]
        [int]$Stride = 128,
        
        [Parameter(Mandatory=$false)]
        [int]$WindowSize = 256
    )
    
    try {
        $batchSize = $Query.GetLength(0)
        $numHeads = $Query.GetLength(1)
        $seqLength = $Query.GetLength(2)
        $headDim = $Query.GetLength(3)
        
        $output = New-Object 'double[,,,]' $batchSize,$numHeads,$seqLength,$headDim
        
        # Generate attention mask based on pattern
        $mask = switch ($Pattern) {
            "Block" {
                Generate-BlockMask -SeqLength $seqLength -BlockSize $BlockSize
            }
            "Local" {
                Generate-LocalMask -SeqLength $seqLength -WindowSize $WindowSize
            }
            "Strided" {
                Generate-StridedMask -SeqLength $seqLength -Stride $Stride -WindowSize $WindowSize
            }
            default {
                throw "Unsupported attention pattern: $Pattern"
            }
        }
        
        # Process each batch and head independently
        for ($b = 0; $b -lt $batchSize; $b++) {
            for ($h = 0; $h -lt $numHeads; $h++) {
                # Process blocks according to mask
                for ($i = 0; $i -lt $seqLength; $i += $BlockSize) {
                    $blockEnd = [Math]::Min($i + $BlockSize, $seqLength)
                    
                    # Find allowed attention connections for current block
                    $validConnections = Get-ValidConnections -Mask $mask -StartIdx $i -EndIdx $blockEnd
                    
                    foreach ($connection in $validConnections) {
                        $startKey = $connection.Start
                        $endKey = $connection.End
                        
                        # Compute attention scores for current block
                        $scores = Compute-BlockScores `
                            -Query $Query[$b,$h,$i..($blockEnd-1),*] `
                            -Key $Key[$b,$h,$startKey..($endKey-1),*] `
                            -HeadDim $headDim
                        
                        # Apply softmax within block
                        $scores = Apply-BlockSoftmax -Scores $scores
                        
                        # Compute weighted values
                        $blockOutput = Compute-BlockOutput `
                            -Scores $scores `
                            -Values $Value[$b,$h,$startKey..($endKey-1),*] `
                            -HeadDim $headDim
                        
                        # Accumulate results
                        for ($qi = 0; $qi -lt ($blockEnd - $i); $qi++) {
                            for ($d = 0; $d -lt $headDim; $d++) {
                                $output[$b,$h,$i + $qi,$d] += $blockOutput[$qi,$d]
                            }
                        }
                    }
                }
            }
        }
        
        return $output
    }
    catch {
        Write-Error "Failed in sparse attention computation: $_"
        return $null
    }
}

function Generate-BlockMask {
    param (
        [Parameter(Mandatory=$true)]
        [int]$SeqLength,
        
        [Parameter(Mandatory=$true)]
        [int]$BlockSize
    )
    
    try {
        $numBlocks = [Math]::Ceiling($SeqLength / $BlockSize)
        $mask = New-Object 'bool[,]' $numBlocks,$numBlocks
        
        # Create block diagonal pattern
        for ($i = 0; $i -lt $numBlocks; $i++) {
            for ($j = [Math]::Max(0, $i - 1); $j -le [Math]::Min($numBlocks - 1, $i + 1); $j++) {
                $mask[$i,$j] = $true
            }
        }
        
        return $mask
    }
    catch {
        Write-Error "Failed to generate block mask: $_"
        return $null
    }
}

function Generate-LocalMask {
    param (
        [Parameter(Mandatory=$true)]
        [int]$SeqLength,
        
        [Parameter(Mandatory=$true)]
        [int]$WindowSize
    )
    
    try {
        $mask = New-Object 'bool[,]' $SeqLength,$SeqLength
        $halfWindow = [Math]::Floor($WindowSize / 2)
        
        # Create sliding window pattern
        for ($i = 0; $i -lt $SeqLength; $i++) {
            $start = [Math]::Max(0, $i - $halfWindow)
            $end = [Math]::Min($SeqLength - 1, $i + $halfWindow)
            
            for ($j = $start; $j -le $end; $j++) {
                $mask[$i,$j] = $true
            }
        }
        
        return $mask
    }
    catch {
        Write-Error "Failed to generate local mask: $_"
        return $null
    }
}

function Generate-StridedMask {
    param (
        [Parameter(Mandatory=$true)]
        [int]$SeqLength,
        
        [Parameter(Mandatory=$true)]
        [int]$Stride,
        
        [Parameter(Mandatory=$true)]
        [int]$WindowSize
    )
    
    try {
        $mask = New-Object 'bool[,]' $SeqLength,$SeqLength
        $halfWindow = [Math]::Floor($WindowSize / 2)
        
        # Create strided pattern with local windows
        for ($i = 0; $i -lt $SeqLength; $i++) {
            # Local window
            $localStart = [Math]::Max(0, $i - $halfWindow)
            $localEnd = [Math]::Min($SeqLength - 1, $i + $halfWindow)
            
            for ($j = $localStart; $j -le $localEnd; $j++) {
                $mask[$i,$j] = $true
            }
            
            # Strided connections
            for ($s = 0; $s -lt $SeqLength; $s += $Stride) {
                if ($s -ge $localStart -and $s -le $localEnd) {
                    continue
                }
                $mask[$i,$s] = $true
            }
        }
        
        return $mask
    }
    catch {
        Write-Error "Failed to generate strided mask: $_"
        return $null
    }
}

function Get-ValidConnections {
    param (
        [Parameter(Mandatory=$true)]
        $Mask,
        
        [Parameter(Mandatory=$true)]
        [int]$StartIdx,
        
        [Parameter(Mandatory=$true)]
        [int]$EndIdx
    )
    
    try {
        $connections = [System.Collections.ArrayList]@()
        $blockIdx = [Math]::Floor($StartIdx / $BlockSize)
        
        for ($j = 0; $j -lt $Mask.GetLength(1); $j++) {
            if ($Mask[$blockIdx,$j]) {
                $keyStart = $j * $BlockSize
                $keyEnd = [Math]::Min(($j + 1) * $BlockSize, $SeqLength)
                
                [void]$connections.Add(@{
                    Start = $keyStart
                    End = $keyEnd
                })
            }
        }
        
        return $connections
    }
    catch {
        Write-Error "Failed to get valid connections: $_"
        return $null
    }
}

function Compute-BlockScores {
    param (
        [Parameter(Mandatory=$true)]
        $Query,
        
        [Parameter(Mandatory=$true)]
        $Key,
        
        [Parameter(Mandatory=$true)]
        [int]$HeadDim
    )
    
    try {
        $numQueries = $Query.GetLength(0)
        $numKeys = $Key.GetLength(0)
        
        $scores = New-Object 'double[,]' $numQueries,$numKeys
        
        # Compute attention scores
        for ($q = 0; $q -lt $numQueries; $q++) {
            for ($k = 0; $k -lt $numKeys; $k++) {
                $sum = 0
                for ($d = 0; $d -lt $HeadDim; $d++) {
                    $sum += $Query[$q,$d] * $Key[$k,$d]
                }
                $scores[$q,$k] = $sum / [Math]::Sqrt($HeadDim)
            }
        }
        
        return $scores
    }
    catch {
        Write-Error "Failed to compute block scores: $_"
        return $null
    }
}

function Apply-BlockSoftmax {
    param (
        [Parameter(Mandatory=$true)]
        $Scores
    )
    
    try {
        $numQueries = $Scores.GetLength(0)
        $numKeys = $Scores.GetLength(1)
        
        $output = New-Object 'double[,]' $numQueries,$numKeys
        
        # Apply softmax per query
        for ($q = 0; $q -lt $numQueries; $q++) {
            $maxScore = [double]::NegativeInfinity
            for ($k = 0; $k -lt $numKeys; $k++) {
                if ($Scores[$q,$k] -gt $maxScore) {
                    $maxScore = $Scores[$q,$k]
                }
            }
            
            $expSum = 0
            for ($k = 0; $k -lt $numKeys; $k++) {
                $output[$q,$k] = [Math]::Exp($Scores[$q,$k] - $maxScore)
                $expSum += $output[$q,$k]
            }
            
            for ($k = 0; $k -lt $numKeys; $k++) {
                $output[$q,$k] /= $expSum
            }
        }
        
        return $output
    }
    catch {
        Write-Error "Failed to apply block softmax: $_"
        return $null
    }
}

function Compute-BlockOutput {
    param (
        [Parameter(Mandatory=$true)]
        $Scores,
        
        [Parameter(Mandatory=$true)]
        $Values,
        
        [Parameter(Mandatory=$true)]
        [int]$HeadDim
    )
    
    try {
        $numQueries = $Scores.GetLength(0)
        $numKeys = $Scores.GetLength(1)
        
        $output = New-Object 'double[,]' $numQueries,$HeadDim
        
        # Compute weighted values
        for ($q = 0; $q -lt $numQueries; $q++) {
            for ($d = 0; $d -lt $HeadDim; $d++) {
                $sum = 0
                for ($k = 0; $k -lt $numKeys; $k++) {
                    $sum += $Scores[$q,$k] * $Values[$k,$d]
                }
                $output[$q,$d] = $sum
            }
        }
        
        return $output
    }
    catch {
        Write-Error "Failed to compute block output: $_"
        return $null
    }
}

# Export additional functions
Export-ModuleMember -Function @(
    'Sparse-Attention'
)

function Add-ReversibleAttention {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [array]$InputShape,
        
        [Parameter(Mandatory=$true)]
        [int]$NumHeads,
        
        [Parameter(Mandatory=$false)]
        [string]$AttentionType = "Linear", # Linear, LSH, or Sparse
        
        [Parameter(Mandatory=$false)]
        [int]$ChunkSize = 64,
        
        [Parameter(Mandatory=$false)]
        [double]$DropoutRate = 0.1
    )
    
    try {
        $d_model = $InputShape[-1]
        
        # Create two parallel attention streams
        $layer = @{
            Name = $Name
            Type = "ReversibleAttention"
            Config = @{
                InputShape = $InputShape
                NumHeads = $NumHeads
                AttentionType = $AttentionType
                ChunkSize = $ChunkSize
                DropoutRate = $DropoutRate
            }
            Streams = @{
                F = Add-EfficientAttention -Name "$Name.F" `
                                         -InputShape $InputShape `
                                         -NumHeads $NumHeads `
                                         -Variant $AttentionType `
                                         -ChunkSize $ChunkSize `
                                         -DropoutRate $DropoutRate
                
                G = Add-EfficientAttention -Name "$Name.G" `
                                         -InputShape $InputShape `
                                         -NumHeads $NumHeads `
                                         -Variant $AttentionType `
                                         -ChunkSize $ChunkSize `
                                         -DropoutRate $DropoutRate
            }
            CachedValues = @{}
        }
        
        return $layer
    }
    catch {
        Write-Error "Failed to create reversible attention layer: $_"
        return $null
    }
}

function ReversibleAttentionForward {
    param (
        [Parameter(Mandatory=$true)]
        $Layer,
        
        [Parameter(Mandatory=$true)]
        $Input,
        
        [bool]$Training = $true
    )
    
    try {
        $batchSize = $Input.GetLength(0)
        $seqLength = $Input.GetLength(1)
        $d_model = $Input.GetLength(2)
        
        # Split input into two streams
        $x1 = New-Object 'double[,,]' $batchSize,$seqLength,($d_model/2)
        $x2 = New-Object 'double[,,]' $batchSize,$seqLength,($d_model/2)
        
        # Split along feature dimension
        for ($b = 0; $b -lt $batchSize; $b++) {
            for ($s = 0; $s -lt $seqLength; $s++) {
                for ($d = 0; $d -lt $d_model/2; $d++) {
                    $x1[$b,$s,$d] = $Input[$b,$s,$d]
                    $x2[$b,$s,$d] = $Input[$b,$s,$d + $d_model/2]
                }
            }
        }
        
        if ($Training) {
            $Layer.CachedValues.X1 = $x1.Clone()
            $Layer.CachedValues.X2 = $x2.Clone()
        }
        
        # Reversible transformation
        # y1 = x1 + F(x2)
        $fx2 = EfficientAttentionForward -Layer $Layer.Streams.F -Input $x2 -Training $Training
        $y1 = Add-Tensors -A $x1 -B $fx2
        
        # y2 = x2 + G(y1)
        $gy1 = EfficientAttentionForward -Layer $Layer.Streams.G -Input $y1 -Training $Training
        $y2 = Add-Tensors -A $x2 -B $gy1
        
        if ($Training) {
            $Layer.CachedValues.Y1 = $y1.Clone()
            $Layer.CachedValues.Y2 = $y2.Clone()
            $Layer.CachedValues.FX2 = $fx2.Clone()
            $Layer.CachedValues.GY1 = $gy1.Clone()
        }
        
        # Merge streams
        $output = New-Object 'double[,,]' $batchSize,$seqLength,$d_model
        for ($b = 0; $b -lt $batchSize; $b++) {
            for ($s = 0; $s -lt $seqLength; $s++) {
                for ($d = 0; $d -lt $d_model/2; $d++) {
                    $output[$b,$s,$d] = $y1[$b,$s,$d]
                    $output[$b,$s,$d + $d_model/2] = $y2[$b,$s,$d]
                }
            }
        }
        
        return $output
    }
    catch {
        Write-Error "Failed in reversible attention forward pass: $_"
        return $null
    }
}

function Add-Tensors {
    param (
        [Parameter(Mandatory=$true)]
        $A,
        
        [Parameter(Mandatory=$true)]
        $B
    )
    
    try {
        $shape = Get-TensorShape -Input $A
        $output = New-Object 'double[,,]' $shape[0],$shape[1],$shape[2]
        
        for ($i = 0; $i -lt $shape[0]; $i++) {
            for ($j = 0; $j -lt $shape[1]; $j++) {
                for ($k = 0; $k -lt $shape[2]; $k++) {
                    $output[$i,$j,$k] = $A[$i,$j,$k] + $B[$i,$j,$k]
                }
            }
        }
        
        return $output
    }
    catch {
        Write-Error "Failed in tensor addition: $_"
        return $null
    }
}

# Export additional functions
Export-ModuleMember -Function @(
    'Add-ReversibleAttention',
    'ReversibleAttentionForward'
)
