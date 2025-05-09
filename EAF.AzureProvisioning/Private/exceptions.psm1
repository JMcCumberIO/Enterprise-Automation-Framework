# Custom Exception Classes for EAF.AzureProvisioning Module
# This module defines custom exception types for common error scenarios in the EAF.AzureProvisioning module

using namespace System
using namespace System.Management.Automation

# Base exception class for all EAF Azure Provisioning exceptions
class EAFException : Exception {
    [string] $ResourceType
    [string] $ResourceName
    [string] $ErrorCategory
    [datetime] $Timestamp

    EAFException([string]$message) : base($message) {
        $this.Timestamp = Get-Date
    }

    EAFException([string]$message, [string]$resourceType, [string]$resourceName) : base($message) {
        $this.ResourceType = $resourceType
        $this.ResourceName = $resourceName
        $this.Timestamp = Get-Date
    }
}

# Exception for Resource Validation errors (naming conventions, parameter validation)
class EAFResourceValidationException : EAFException {
    [string] $ValidationRule
    [string] $ProvidedValue

    EAFResourceValidationException([string]$message) : base($message) {
        $this.ErrorCategory = "ValidationError"
    }

    EAFResourceValidationException([string]$message, [string]$resourceType, [string]$resourceName) : base($message, $resourceType, $resourceName) {
        $this.ErrorCategory = "ValidationError"
    }

    EAFResourceValidationException([string]$message, [string]$resourceType, [string]$resourceName, [string]$validationRule, [string]$providedValue) : base($message, $resourceType, $resourceName) {
        $this.ErrorCategory = "ValidationError"
        $this.ValidationRule = $validationRule
        $this.ProvidedValue = $providedValue
    }
}

# Exception for when a resource already exists
class EAFResourceExistsException : EAFException {
    [string] $ResourceId
    [string] $ExistingState

    EAFResourceExistsException([string]$message) : base($message) {
        $this.ErrorCategory = "ResourceExists"
    }

    EAFResourceExistsException([string]$message, [string]$resourceType, [string]$resourceName) : base($message, $resourceType, $resourceName) {
        $this.ErrorCategory = "ResourceExists"
    }

    EAFResourceExistsException([string]$message, [string]$resourceType, [string]$resourceName, [string]$resourceId, [string]$existingState) : base($message, $resourceType, $resourceName) {
        $this.ErrorCategory = "ResourceExists"
        $this.ResourceId = $resourceId
        $this.ExistingState = $existingState
    }
}

# Exception for Azure resource provisioning failures
class EAFProvisioningFailedException : EAFException {
    [string] $ProvisioningState
    [string] $DeploymentId
    [string] $ErrorDetails

    EAFProvisioningFailedException([string]$message) : base($message) {
        $this.ErrorCategory = "ProvisioningFailed"
    }

    EAFProvisioningFailedException([string]$message, [string]$resourceType, [string]$resourceName) : base($message, $resourceType, $resourceName) {
        $this.ErrorCategory = "ProvisioningFailed"
    }

    EAFProvisioningFailedException([string]$message, [string]$resourceType, [string]$resourceName, [string]$provisioningState, [string]$deploymentId, [string]$errorDetails) : base($message, $resourceType, $resourceName) {
        $this.ErrorCategory = "ProvisioningFailed"
        $this.ProvisioningState = $provisioningState
        $this.DeploymentId = $deploymentId
        $this.ErrorDetails = $errorDetails
    }
}

# Exception for network configuration errors
class EAFNetworkConfigurationException : EAFException {
    [string] $NetworkResource
    [string] $NetworkDetail

    EAFNetworkConfigurationException([string]$message) : base($message) {
        $this.ErrorCategory = "NetworkConfigurationError"
    }

    EAFNetworkConfigurationException([string]$message, [string]$resourceType, [string]$resourceName) : base($message, $resourceType, $resourceName) {
        $this.ErrorCategory = "NetworkConfigurationError"
    }

    EAFNetworkConfigurationException([string]$message, [string]$resourceType, [string]$resourceName, [string]$networkResource, [string]$networkDetail) : base($message, $resourceType, $resourceName) {
        $this.ErrorCategory = "NetworkConfigurationError"
        $this.NetworkResource = $networkResource
        $this.NetworkDetail = $networkDetail
    }
}

# Exception for authentication and authorization errors
class EAFAuthorizationException : EAFException {
    [string] $Principal
    [string] $RequiredPermission

    EAFAuthorizationException([string]$message) : base($message) {
        $this.ErrorCategory = "AuthorizationError"
    }

    EAFAuthorizationException([string]$message, [string]$resourceType, [string]$resourceName) : base($message, $resourceType, $resourceName) {
        $this.ErrorCategory = "AuthorizationError"
    }

    EAFAuthorizationException([string]$message, [string]$resourceType, [string]$resourceName, [string]$principal, [string]$requiredPermission) : base($message, $resourceType, $resourceName) {
        $this.ErrorCategory = "AuthorizationError"
        $this.Principal = $principal
        $this.RequiredPermission = $requiredPermission
    }
}

# Exception for dependency validation errors
class EAFDependencyException : EAFException {
    [string] $DependencyType
    [string] $DependencyName
    [string] $DependencyState

    EAFDependencyException([string]$message) : base($message) {
        $this.ErrorCategory = "DependencyError"
    }

    EAFDependencyException([string]$message, [string]$resourceType, [string]$resourceName) : base($message, $resourceType, $resourceName) {
        $this.ErrorCategory = "DependencyError"
    }

    EAFDependencyException([string]$message, [string]$resourceType, [string]$resourceName, [string]$dependencyType, [string]$dependencyName, [string]$dependencyState) : base($message, $resourceType, $resourceName) {
        $this.ErrorCategory = "DependencyError"
        $this.DependencyType = $dependencyType
        $this.DependencyName = $dependencyName
        $this.DependencyState = $dependencyState
    }
}

# Exception for rate limiting or transient errors (useful for retry logic)
class EAFTransientException : EAFException {
    [int] $RetryAfterSeconds
    [int] $AttemptCount

    EAFTransientException([string]$message) : base($message) {
        $this.ErrorCategory = "TransientError"
    }

    EAFTransientException([string]$message, [string]$resourceType, [string]$resourceName) : base($message, $resourceType, $resourceName) {
        $this.ErrorCategory = "TransientError"
    }

    EAFTransientException([string]$message, [string]$resourceType, [string]$resourceName, [int]$retryAfterSeconds, [int]$attemptCount) : base($message, $resourceType, $resourceName) {
        $this.ErrorCategory = "TransientError"
        $this.RetryAfterSeconds = $retryAfterSeconds
        $this.AttemptCount = $attemptCount
    }
}

# Helper function to write EAF exceptions with appropriate error record
function Write-EAFException {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [EAFException]$Exception,
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.ErrorCategory]$ErrorCategory = [System.Management.Automation.ErrorCategory]::NotSpecified,
        
        [Parameter(Mandatory = $false)]
        [string]$ErrorId = $Exception.ErrorCategory,
        
        [Parameter(Mandatory = $false)]
        [object]$TargetObject = $null,
        
        [Parameter(Mandatory = $false)]
        [switch]$Throw
    )
    
    $errorRecord = New-Object System.Management.Automation.ErrorRecord(
        $Exception,
        $ErrorId,
        $ErrorCategory,
        $TargetObject
    )
    
    if ($Throw) {
        throw $errorRecord
    } else {
        Write-Error -ErrorRecord $errorRecord
    }
}

# Export helper functions
Export-ModuleMember -Function Write-EAFException

# Now we need to add example usage to document how to use these exceptions:

<#
.EXAMPLE - Using custom exceptions in EAF module functions

# Example 1: Validation error during parameter validation
try {
    # Validate name pattern
    if ($KeyVaultName -notmatch '^kv-[a-zA-Z0-9]+-(?:dev|test|prod)$') {
        throw [EAFResourceValidationException]::new(
            "Key Vault name '$KeyVaultName' does not follow the required naming pattern 'kv-{name}-{env}'.",
            "KeyVault",
            $KeyVaultName,
            "NamingConvention",
            $KeyVaultName
        )
    }
}
catch [EAFResourceValidationException] {
    # Handle validation errors specifically
    Write-EAFException -Exception $_ -ErrorCategory InvalidArgument -Throw
}
catch {
    # Handle other errors
    throw $_
}

# Example 2: Handling existing resources
try {
    $existingKeyVault = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName -ErrorAction SilentlyContinue
    
    if ($existingKeyVault) {
        if (-not $Force -and -not $PSCmdlet.ShouldProcess($KeyVaultName, "Update existing Key Vault")) {
            throw [EAFResourceExistsException]::new(
                "Key Vault $KeyVaultName already exists. Use -Force to update or modify existing configuration.",
                "KeyVault",
                $KeyVaultName,
                $existingKeyVault.ResourceId,
                $existingKeyVault.ProvisioningState
            )
        }
    }
}
catch [EAFResourceExistsException] {
    # Handle resource exists errors
    Write-EAFException -Exception $_ -ErrorCategory ResourceExists -TargetObject $existingKeyVault
    return $existingKeyVault
}

# Example 3: Provisioning failures
try {
    $deployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $templatePath
    
    if ($deployment.ProvisioningState -ne 'Succeeded') {
        throw [EAFProvisioningFailedException]::new(
            "Failed to provision Key Vault $KeyVaultName. Deployment state: $($deployment.ProvisioningState)",
            "KeyVault",
            $KeyVaultName,
            $deployment.ProvisioningState,
            $deployment.DeploymentName,
            $deployment.Error
        )
    }
}
catch [EAFProvisioningFailedException] {
    # Handle provisioning failures with custom logic
    Write-EAFException -Exception $_ -ErrorCategory ResourceUnavailable -Throw
}

#>

