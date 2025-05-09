# Retry Logic Module for EAF.AzureProvisioning
# This module provides robust retry mechanism for handling transient Azure service failures

using namespace System
using namespace System.Management.Automation

# Import custom exception types if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'EAFTransientException').Type) {
    $exceptionModulePath = Join-Path -Path $PSScriptRoot -ChildPath "exceptions.psm1"
    if (Test-Path $exceptionModulePath) {
        Import-Module $exceptionModulePath -Force
    }
}

# Define common Azure error codes that are considered transient and retryable
$script:TransientErrorCodes = @(
    # Azure Resource Manager errors
    'ResourceGroupBeingDeleted',
    'ResourceGroupQuotaExceeded',
    'DeploymentQuotaExceeded',
    'TooManyRequests',
    'OperationNotAllowed',
    'SubscriptionNotRegistered',
    
    # Networking errors
    'NetworkingInternalOperationError',
    'InternalLoadBalancerError',
    
    # Storage errors
    'StorageTransientError',
    'ServerBusy',
    
    # Service-specific errors
    'ServiceUnavailable',
    'ServiceTimeout',
    'GatewayTimeout',
    'RequestTimeout',
    
    # HTTP status codes
    '408', # Request Timeout
    '429', # Too Many Requests
    '500', # Internal Server Error
    '502', # Bad Gateway
    '503', # Service Unavailable
    '504'  # Gateway Timeout
)

<#
.SYNOPSIS
    Determines if an error is transient and retryable based on error codes or patterns.
    
.DESCRIPTION
    The Test-TransientError function examines an error object to determine if it represents
    a transient failure that can be retried. It checks against common Azure error codes and patterns.
    
.PARAMETER Error
    The error object to examine. This can be a PowerShell ErrorRecord or Exception.
    
.EXAMPLE
    try {
        Get-AzResource -ResourceGroupName "mygroup" -ErrorAction Stop
    }
    catch {
        if (Test-TransientError -Error $_) {
            Write-Verbose "Encountered a transient error, can retry operation"
        }
    }
    
.OUTPUTS
    [bool] Returns $true if the error is considered transient and retryable, otherwise $false.
#>
function Test-TransientError {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [object]$Error
    )
    
    # Convert the error to an ErrorRecord if it's not already
    $errorRecord = $Error
    if ($Error -is [Exception]) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $Error,
            "TransientErrorCheck",
            [System.Management.Automation.ErrorCategory]::NotSpecified,
            $null
        )
    }
    
    # Check if it's already identified as a transient error
    if ($errorRecord.Exception -is [EAFTransientException]) {
        return $true
    }
    
    # Extract the error message and details for analysis
    $errorMessage = $errorRecord.Exception.Message
    $errorDetails = $null
    if ($errorRecord.ErrorDetails) {
        $errorDetails = $errorRecord.ErrorDetails.Message
    }
    
    # Try to extract error code from Azure errors
    $errorCode = $null
    
    # Check in exception message for error code pattern
    if ($errorMessage -match "Code:\s*([A-Za-z0-9]+)") {
        $errorCode = $matches[1]
    }
    
    # Look for error code in ErrorDetails JSON (common in Azure RM responses)
    if ($errorDetails -and $errorDetails -match '"code"\s*:\s*"([^"]+)"') {
        $errorCode = $matches[1]
    }
    
    # Check if the error status code is in the HTTP response
    $responseStatusCode = $null
    if ($errorRecord.Exception.PSObject.Properties.Name -contains 'Response') {
        $responseStatusCode = $errorRecord.Exception.Response.StatusCode.ToString()
    }
    
    # Check if the identified error code is in our list of transient errors
    if ($errorCode -and $script:TransientErrorCodes -contains $errorCode) {
        return $true
    }
    
    # Check if the status code is in our list of transient errors
    if ($responseStatusCode -and $script:TransientErrorCodes -contains $responseStatusCode) {
        return $true
    }
    
    # Check for common transient error message patterns
    $transientPatterns = @(
        'throttled',
        'timeout',
        'timed out',
        'too many requests',
        'rate limit',
        'server busy',
        'service unavailable',
        'temporarily unavailable',
        'connection was closed',
        'connection timed out',
        'internal server error',
        'gateway timeout',
        'socket timeout',
        'please retry',
        'operation timed out'
    )
    
    foreach ($pattern in $transientPatterns) {
        if ($errorMessage -match $pattern -or ($errorDetails -and $errorDetails -match $pattern)) {
            return $true
        }
    }
    
    # Not identified as a transient error
    return $false
}

<#
.SYNOPSIS
    Calculates delay for next retry attempt using exponential backoff with jitter.
    
.DESCRIPTION
    The Get-RetryBackoffDelay function calculates the appropriate delay before the next 
    retry attempt using exponential backoff with jitter to prevent thundering herd problems.
    
.PARAMETER RetryCount
    The current retry attempt number (starting from 1).
    
.PARAMETER BaseDelayMs
    The base delay in milliseconds. Default is 1000 (1 second).
    
.PARAMETER MaxDelayMs
    The maximum delay in milliseconds. Default is 60000 (60 seconds).
    
.PARAMETER JitterFactor
    The jitter factor to apply (0-1). Default is 0.2 (20% jitter).
    
.EXAMPLE
    $delayMs = Get-RetryBackoffDelay -RetryCount 3 -BaseDelayMs 1000 -MaxDelayMs 30000
    Start-Sleep -Milliseconds $delayMs
    
.OUTPUTS
    [int] The calculated delay in milliseconds.
#>
function Get-RetryBackoffDelay {
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory = $true)]
        [int]$RetryCount,
        
        [Parameter(Mandatory = $false)]
        [int]$BaseDelayMs = 1000,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxDelayMs = 60000,
        
        [Parameter(Mandatory = $false)]
        [double]$JitterFactor = 0.2
    )
    
    # Calculate the exponential backoff: baseDelay * 2^retryCount
    $exponentialDelay = $BaseDelayMs * [Math]::Pow(2, $RetryCount - 1)
    
    # Apply a maximum cap to the delay
    $cappedDelay = [Math]::Min($exponentialDelay, $MaxDelayMs)
    
    # Apply jitter: random value between (1-jitter)*delay and (1+jitter)*delay
    $jitterMin = $cappedDelay * (1 - $JitterFactor)
    $jitterMax = $cappedDelay * (1 + $JitterFactor)
    $jitteredDelay = Get-Random -Minimum $jitterMin -Maximum $jitterMax
    
    # Return as integer milliseconds
    return [int]$jitteredDelay
}

<#
.SYNOPSIS
    Executes a script block with configurable retry logic for transient errors.
    
.DESCRIPTION
    The Invoke-WithRetry function executes a script block and automatically retries 
    if a transient error occurs. It uses exponential backoff with jitter for retry delays.
    
.PARAMETER ScriptBlock
    The script block to execute with retry logic.
    
.PARAMETER MaxRetryCount
    The maximum number of retry attempts. Default is 3.
    
.PARAMETER BaseDelayMs
    The base delay in milliseconds. Default is 1000 (1 second).
    
.PARAMETER MaxDelayMs
    The maximum delay in milliseconds. Default is 60000 (60 seconds).
    
.PARAMETER RetryableErrorDetectionBlock
    Optional custom script block to determine if an error is retryable. 
    If not provided, the built-in Test-TransientError function is used.
    
.PARAMETER ArgumentList
    Optional arguments to pass to the script block.
    
.PARAMETER ThrowOnLastError
    If set, the last error will be thrown if all retries fail. Default is $true.
    
.PARAMETER ActivityName
    Optional name of the activity being performed, used for progress reporting.
    
.EXAMPLE
    # Basic usage
    $result = Invoke-WithRetry { Get-AzResource -ResourceGroupName "mygroup" }
    
.EXAMPLE
    # With custom parameters
    $result = Invoke-WithRetry -ScriptBlock { 
        Get-AzKeyVault -ResourceGroupName $args[0] -Name $args[1] 
    } -MaxRetryCount 5 -ArgumentList "mygroup", "myvault" -ActivityName "Getting Key Vault"
    
.EXAMPLE
    # With custom error detection
    $result = Invoke-WithRetry -ScriptBlock {
        New-AzResourceGroup -Name "mygroup" -Location "eastus"
    } -RetryableErrorDetectionBlock {
        param($err)
        return $err.Exception.Message -match "already exists"
    }
    
.OUTPUTS
    The result of the script block execution if successful.
#>
function Invoke-WithRetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxRetryCount = 3,
        
        [Parameter(Mandatory = $false)]
        [int]$BaseDelayMs = 1000,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxDelayMs = 60000,
        
        [Parameter(Mandatory = $false)]
        [scriptblock]$RetryableErrorDetectionBlock,
        
        [Parameter(Mandatory = $false)]
        [object[]]$ArgumentList,
        
        [Parameter(Mandatory = $false)]
        [bool]$ThrowOnLastError = $true,
        
        [Parameter(Mandatory = $false)]
        [string]$ActivityName = "Azure Operation"
    )
    
    $retryCount = 0
    $lastException = $null
    $isRetryable = $false
    
    # If no custom error detection block provided, use the default one
    if (-not $RetryableErrorDetectionBlock) {
        $RetryableErrorDetectionBlock = { param($err) Test-TransientError -Error $err }
    }
    
    # Execute the command with retry logic
    do {
        $retryCount++
        $isRetryable = $false
        
        try {
            # Show progress
            if ($retryCount -gt 1) {
                Write-Progress -Activity $ActivityName -Status "Retry attempt $retryCount of $MaxRetryCount" -PercentComplete (($retryCount - 1) / $MaxRetryCount * 100)
            }
            
            # Execute the script block
            if ($ArgumentList) {
                return & $ScriptBlock @ArgumentList
            }
            else {
                return & $ScriptBlock
            }
        }
        catch {
            $lastException = $_
            
            # Determine if the error is retryable
            $isRetryable = & $RetryableErrorDetectionBlock $_
            
            if ($isRetryable -and $retryCount -le $MaxRetryCount) {
                # Calculate delay with exponential backoff and jitter
                $delayMs = Get-RetryBackoffDelay -RetryCount $retryCount -BaseDelayMs $BaseDelayMs -MaxDelayMs $MaxDelayMs
                
                Write-Verbose "Transient error detected on attempt $retryCount of $MaxRetryCount. Retrying in $($delayMs / 1000) seconds..."
                Write-Verbose "Error: $($_.Exception.Message)"
                
                Start-Sleep -Milliseconds $delayMs
            }
        }
    } while ($isRetryable -and $retryCount -le $MaxRetryCount)
    
    # Hide progress bar when done
    Write-Progress -Activity $ActivityName -Completed
    
    # If we've exhausted our retries and still have an error
    if ($lastException -and $retryCount -gt $MaxRetryCount) {
        Write-Verbose "All $MaxRetryCount retry attempts failed."
        
        # Create a more informative error for transient failures
        if ($isRetryable) {
            $retryError = [EAFTransientException]::new(
                "Operation failed after $MaxRetryCount retry attempts due to transient errors: $($lastException.Exception.Message)",
                "AzureOperation",
                $ActivityName,
                0,  # No specific retry after recommendation
                $retryCount
            )
            
            if ($ThrowOnLastError) {
                # Throw the wrapped error
                Write-EAFException -Exception $retryError -ErrorCategory ConnectionError -Throw
            }
            else {
                # Just log the error but don't throw
                Write-EAFException -Exception $retryError -ErrorCategory ConnectionError
            }
        }
        elseif ($ThrowOnLastError) {
            # Not a transient error, just re-throw the original
            throw $lastException
        }
    }
}

<#
.SYNOPSIS
    Executes an Azure PowerShell command with retry logic for transient errors.
    
.DESCRIPTION
    The Invoke-AzCommandWithRetry function is a specialized wrapper for Azure PowerShell
    commands that need retry logic for transient errors. It provides a simpler interface
    for common Azure operations.
    
.PARAMETER Command
    The Azure PowerShell command to execute as a string.
    
.PARAMETER Parameters
    A hashtable of parameters to pass to the command.
    
.PARAMETER MaxRetryCount
    The maximum number of retry attempts. Default is 3.
    
.PARAMETER ThrowOnLastError
    If set, the last error will be thrown if all retries fail. Default is $true.
    
.EXAMPLE
    # Retry a Get-AzKeyVault command
    $vault = Invoke-AzCommandWithRetry -Command "Get-AzKeyVault" -Parameters @{
        ResourceGroupName = "mygroup"
        VaultName = "myvault"
    }
    
.EXAMPLE
    # Retry a resource deployment
    $deployment = Invoke-AzCommandWithRetry -Command "New-AzResourceGroupDeployment" -

