                        # Update biased first moment estimate
                        $m[$i] = $OptConfig.Beta1 * $m[$i] + (1 - $OptConfig.Beta1) * $grad[$i]
                        
                        # Update biased second moment estimate
                        $v[$i] = $OptConfig.Beta2 * $v[$i] + (1 - $OptConfig.Beta2) * ($grad[$i] * $grad[$i])
                        
                        # Compute bias-corrected first moment estimate
                        $mHat = $m[$i] / (1 - [Math]::Pow($OptConfig.Beta1, $OptConfig.Step))
                        
                        # Compute bias-corrected second moment estimate
                        $vHat = $v[$i] / (1 - [Math]::Pow($OptConfig.Beta2, $OptConfig.Step))
                        
                        # Update parameters
                        $Gradients[$paramName][$i] = $mHat / ([Math]::Sqrt($vHat) + $OptConfig.Epsilon)
                    }
                }
                
                # Apply decay
                $OptConfig.CurrentLearningRate = $OptConfig.InitialLearningRate * 
                    [Math]::Pow($OptConfig.DecayRate, [Math]::Floor($OptConfig.Step / $OptConfig.DecaySteps))
            }
            
            "RMSprop" {
                foreach ($paramName in $Gradients.Keys) {
                    if (-not $OptConfig.Parameters.ContainsKey($paramName)) {
                        $OptConfig.Parameters[$paramName] = @{
                            Cache = New-Object 'double[]' $Gradients[$paramName].Length
                        }
                    }
                    
                    $cache = $OptConfig.Parameters[$paramName].Cache
                    $grad = $Gradients[$paramName]
                    
                    for ($i = 0; $i -lt $grad.Length; $i++) {
                        # Update moving average of squared gradients
                        $cache[$i] = $OptConfig.Beta1 * $cache[$i] + (1 - $OptConfig.Beta1) * ($grad[$i] * $grad[$i])
                        
                        # Update gradients
                        $Gradients[$paramName][$i] = $grad[$i] / ([Math]::Sqrt($cache[$i]) + $OptConfig.Epsilon)
                    }
                }
                
                # Apply decay
                $OptConfig.CurrentLearningRate = $OptConfig.InitialLearningRate * 
                    [Math]::Pow($OptConfig.DecayRate, [Math]::Floor($OptConfig.Step / $OptConfig.DecaySteps))
            }
        }
        
        return $Gradients
    }
    catch {
        Write-Error "Failed to update learning rate: $_"
        return $null
    }
}

function Add-Dropout {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [double]$Rate,
        
        [Parameter(Mandatory=$true)]
        [array]$InputShape
    )
    
    try {
        $layer = @{
            Name = $Name
            Type = "Dropout"
            Config = @{
                Rate = $Rate
                InputShape = $InputShape
            }
            CachedMask = $null
        }
        
        return $layer
    }
    catch {
        Write-Error "Failed to create dropout layer: $_"
        return $null
    }
}

function Apply-Dropout {
    param (
        [Parameter(Mandatory=$true)]
        $Layer,
        
        [Parameter(Mandatory=$true)]
        $Input,
        
        [bool]$Training = $true
    )
    
    try {
        if (-not $Training -or $Layer.Config.Rate -eq 0) {
            return $Input
        }
        
        $shape = Get-TensorShape -Input $Input
        $mask = New-Object 'double[]' $shape
        
        # Generate dropout mask
        $random = New-Object Random
        for ($i = 0; $i -lt $mask.Length; $i++) {
            $mask[$i] = if ($random.NextDouble() -gt $Layer.Config.Rate) { 1.0 / (1.0 - $Layer.Config.Rate) } else { 0.0 }
        }
        
        $Layer.CachedMask = $mask
        
        # Apply mask
        $output = New-Object 'double[]' $shape
        for ($i = 0; $i -lt $output.Length; $i++) {
            $output[$i] = $Input[$i] * $mask[$i]
        }
        
        return $output
    }
    catch {
        Write-Error "Failed to apply dropout: $_"
        return $null
    }
}

function Get-TensorShape {
    param (
        [Parameter(Mandatory=$true)]
        $Input
    )
    
    try {
        $shape = @()
        $current = $Input
        
        while ($current -is [array]) {
            $shape += $current.Length
            if ($current.Length -gt 0) {
                $current = $current[0]
            }
            else {
                break
            }
        }
        
        return $shape
    }
    catch {
        Write-Error "Failed to get tensor shape: $_"
        return $null
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Add-BatchNormalization',
    'BatchNormForward',
    'Add-AdaptiveLearningRate',
    'Update-LearningRate',
    'Add-Dropout',
    'Apply-Dropout'
)
