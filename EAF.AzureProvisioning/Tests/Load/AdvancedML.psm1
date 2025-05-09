
function Forward-Propagate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Network,
        
        [Parameter(Mandatory = $true)]
        [array]$Input
    )
    
    try {
        $activations = [List[object]]::new()
        $activations.Add($Input)
        
        # Process each layer
        for ($i = 1; $i -lt $Network.Layers.Count; $i++) {
            $layer = $Network.Layers[$i]
            $previousActivation = $activations[-1]
            
            # Calculate layer input
            $layerInput = Matrix-Multiply -A $previousActivation -B $layer.Weights
            $layerInput = Add-BiasVector -Input $layerInput -Bias $layer.Biases
            
            # Apply activation function
            $activation = switch ($layer.Activation) {
                "ReLU" { Apply-ReLU -Input $layerInput }
                "Sigmoid" { Apply-Sigmoid -Input $layerInput }
                "Tanh" { Apply-Tanh -Input $layerInput }
                "Softmax" { Apply-Softmax -Input $layerInput }
                default { $layerInput }
            }
            
            $activations.Add($activation)
        }
        
        return $activations
    }
    catch {
        Write-Error "Failed in forward propagation: $_"
        return $null
    }
}

function Backward-Propagate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Network,
        
        [Parameter(Mandatory = $true)]
        [array]$Output,
        
        [Parameter(Mandatory = $true)]
        [array]$Labels
    )
    
    try {
        $gradients = @{
            Weights = [List[object]]::new()
            Biases = [List[object]]::new()
        }
        
        # Calculate output layer error
        $outputError = Calculate-OutputError -Predicted $Output[-1] -Actual $Labels
        
        # Backpropagate through layers
        for ($i = $Network.Layers.Count - 1; $i -gt 0; $i--) {
            $layer = $Network.Layers[$i]
            $previousActivation = $Output[$i - 1]
            
            # Calculate gradients
            $weightGradient = Matrix-Multiply -A (Matrix-Transpose -M $previousActivation) -B $outputError
            $biasGradient = Calculate-BiasGradient -Error $outputError
            
            $gradients.Weights.Insert(0, $weightGradient)
            $gradients.Biases.Insert(0, $biasGradient)
            
            if ($i -gt 1) {
                # Calculate error for next layer
                $outputError = Matrix-Multiply -A $outputError -B (Matrix-Transpose -M $layer.Weights)
                $outputError = Multiply-ElementWise -A $outputError -B (Calculate-ActivationDerivative -Input $Output[$i - 1] -Function $layer.Activation)
            }
        }
        
        return $gradients
    }
    catch {
        Write-Error "Failed in backward propagation: $_"
        return $null
    }
}

function Update-NetworkParameters {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Network,
        
        [Parameter(Mandatory = $true)]
        [object]$Gradients,
        
        [Parameter(Mandatory = $true)]
        [double]$LearningRate
    )
    
    try {
        for ($i = 1; $i -lt $Network.Layers.Count; $i++) {
            $layer = $Network.Layers[$i]
            
            # Update weights
            $layer.Weights = Matrix-Subtract -A $layer.Weights -B (Matrix-Scale -M $Gradients.Weights[$i - 1] -Scale $LearningRate)
            
            # Update biases
            $layer.Biases = Vector-Subtract -A $layer.Biases -B (Vector-Scale -V $Gradients.Biases[$i - 1] -Scale $LearningRate)
        }
    }
    catch {
        Write-Error "Failed to update network parameters: $_"
    }
}

# Activation functions and their derivatives
function Apply-ReLU {
    param ([array]$Input)
    return $Input | ForEach-Object { [Math]::Max(0, $_) }
}

function Apply-Sigmoid {
    param ([array]$Input)
    return $Input | ForEach-Object { 1 / (1 + [Math]::Exp(-$_)) }
}

function Apply-Tanh {
    param ([array]$Input)
    return $Input | ForEach-Object { [Math]::Tanh($_) }
}

function Apply-Softmax {
    param ([array]$Input)
    $expValues = $Input | ForEach-Object { [Math]::Exp($_) }
    $sum = ($expValues | Measure-Object -Sum).Sum
    return $expValues | ForEach-Object { $_ / $sum }
}

# Matrix operations
function Matrix-Multiply {
    param (
        [Parameter(Mandatory = $true)]
        [array]$A,
        
        [Parameter(Mandatory = $true)]
        [array]$B
    )
    
    $rowsA = $A.GetLength(0)
    $colsA = $A.GetLength(1)
    $colsB = $B.GetLength(1)
    
    $result = New-Object 'double[,]' $rowsA,$colsB
    
    for ($i = 0; $i -lt $rowsA; $i++) {
        for ($j = 0; $j -lt $colsB; $j++) {
            $sum = 0
            for ($k = 0; $k -lt $colsA; $k++) {
                $sum += $A[$i,$k] * $B[$k,$j]
            }
            $result[$i,$j] = $sum
        }
    }
    
    return $result
}

function Matrix-Transpose {
    param ([array]$M)
    
    $rows = $M.GetLength(0)
    $cols = $M.GetLength(1)
    $result = New-Object 'double[,]' $cols,$rows
    
    for ($i = 0; $i -lt $rows; $i++) {
        for ($j = 0; $j -lt $cols; $j++) {
            $result[$j,$i] = $M[$i,$j]
        }
    }
    
    return $result
}

function Matrix-Scale {
    param (
        [Parameter(Mandatory = $true)]
        [array]$M,
        
        [Parameter(Mandatory = $true)]
        [double]$Scale
    )
    
    $rows = $M.GetLength(0)
    $cols = $M.GetLength(1)
    $result = New-Object 'double[,]' $rows,$cols
    
    for ($i = 0; $i -lt $rows; $i++) {
        for ($j = 0; $j -lt $cols; $j++) {
            $result[$i,$j] = $M[$i,$j] * $Scale
        }
    }
    
    return $result
}

function Matrix-Add {
    param (
        [Parameter(Mandatory = $true)]
        [array]$A,
        
        [Parameter(Mandatory = $true)]
        [array]$B
    )
    
    $rows = $A.GetLength(0)
    $cols = $A.GetLength(1)
    $result = New-Object 'double[,]' $rows,$cols
    
    for ($i = 0; $i -lt $rows; $i++) {
        for ($j = 0; $j -lt $cols; $j++) {
            $result[$i,$j] = $A[$i,$j] + $B[$i,$j]
        }
    }
    
    return $result
}

function Matrix-Subtract {
    param (
        [Parameter(Mandatory = $true)]
        [array]$A,
        
        [Parameter(Mandatory = $true)]
        [array]$B
    )
    
    return Matrix-Add -A $A -B (Matrix-Scale -M $B -Scale -1)
}

# Vector operations
function Vector-Add {
    param (
        [Parameter(Mandatory = $true)]
        [array]$A,
        
        [Parameter(Mandatory = $true)]
        [array]$B
    )
    
    $length = $A.Length
    $result = New-Object 'double[]' $length
    
    for ($i = 0; $i -lt $length; $i++) {
        $result[$i] = $A[$i] + $B[$i]
    }
    
    return $result
}

function Vector-Subtract {
    param (
        [Parameter(Mandatory = $true)]
        [array]$A,
        
        [Parameter(Mandatory = $true)]
        [array]$B
    )
    
    return Vector-Add -A $A -B (Vector-Scale -V $B -Scale -1)
}

function Vector-Scale {
    param (
        [Parameter(Mandatory = $true)]
        [array]$V,
        
        [Parameter(Mandatory = $true)]
        [double]$Scale
    )
    
    return $V | ForEach-Object { $_ * $Scale }
}

# Error calculation
function Calculate-OutputError {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Predicted,
        
        [Parameter(Mandatory = $true)]
        [array]$Actual
    )
    
    return Vector-Subtract -A $Predicted -B $Actual
}

function Calculate-BiasGradient {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Error
    )
    
    return ($Error | Measure-Object -Sum).Sum
}

function Calculate-Loss {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Predicted,
        
        [Parameter(Mandatory = $true)]
        [array]$Actual
    )
    
    $squaredError = $Predicted.Zip($Actual, [Func[object,object,double]]{
        param($p, $a)
        return [Math]::Pow($p - $a, 2)
    })
    
    return ($squaredError | Measure-Object -Average).Average
}

function Calculate-Accuracy {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Predicted,
        
        [Parameter(Mandatory = $true)]
        [array]$Actual
    )
    
    $correct = 0
    for ($i = 0; $i -lt $Predicted.Count; $i++) {
        if ([Math]::Abs($Predicted[$i] - $Actual[$i]) -lt 0.1) {
            $correct++
        }
    }
    
    return $correct / $Predicted.Count
}

# Export additional functions
Export-ModuleMember -Function @(
    'Forward-Propagate',
    'Backward-Propagate',
    'Update-NetworkParameters',
    'Calculate-Loss',
    'Calculate-Accuracy'
)
