# Secure Configuration Helper Functions for EAF.AzureProvisioning
# This module provides secure configuration management for sensitive values

using namespace System
using namespace System.Management.Automation
using namespace System.Security.Cryptography
using namespace System.Text

# Import custom exception types if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'EAFResourceValidationException').Type) {
    $exceptionModulePath = Join-Path -Path $PSScriptRoot -ChildPath "exceptions.psm1"
    if (Test-Path $exceptionModulePath) {
        Import-Module $exceptionModulePath -Force
    }
}

# Initialize secure configuration storage
$script:SecureConfigStore = @{}

<#
.SYNOPSIS
    Sets a secure configuration value.
    
.DESCRIPTION
    The Set-EAFSecureConfiguration function stores sensitive configuration values
    securely either in memory or persisted in Azure Key Vault.
    
.PARAMETER ConfigPath
    The dot-notation path that identifies the configuration.
    
.PARAMETER SecureValue
    The secure string value to store.
    
.PARAMETER KeyVaultName
    If specified, stores the secret in the specified Azure Key Vault.
    
.PARAMETER Force
    If set, overwrites existing values without prompting.
    
.EXAMPLE
    $securePassword = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
    Set-EAFSecureConfiguration -ConfigPath "Database.ConnectionString" -SecureValue $securePassword
    
.EXAMPLE
    $secureApiKey = Read-Host -AsSecureString -Prompt "Enter API Key"
    Set-EAFSecureConfiguration -ConfigPath "API.Key" -SecureValue $secureApiKey -KeyVaultName "kv-myapp-dev"
#>
function Set-EAFSecureConfiguration {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$SecureValue,
        
        [Parameter(Mandatory = $false)]
        [string]$KeyVaultName,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    try {
        # Check if the configuration already exists
        if ($script:SecureConfigStore.ContainsKey($ConfigPath) -and -not $Force) {
            if (-not $PSCmdlet.ShouldProcess($ConfigPath, "Overwrite existing secure configuration")) {
                Write-Verbose "Operation canceled by user."
                return $false
            }
        }
        
        # Determine storage type
        if (-not [string]::IsNullOrEmpty($KeyVaultName)) {
            # Store in Azure Key Vault
            Write-Verbose "Storing secure configuration in Azure Key Vault: $KeyVaultName"
            
            # Convert secret name to valid Key Vault format
            $secretName = $ConfigPath.Replace('.', '-').Replace(' ', '').ToLower()
            
            # Check if KeyVault exists and is accessible
            try {
                $keyVault = Get-AzKeyVault -VaultName $KeyVaultName -ErrorAction Stop
                
                # Store the secret in Key Vault
                Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $secretName -SecretValue $SecureValue -ErrorAction Stop | Out-Null
                
                # Store reference in secure config store
                $script:SecureConfigStore[$ConfigPath] = @{
                    Type = 'KeyVault'
                    VaultName = $KeyVaultName
                    SecretName = $secretName
                    LastModified = (Get-Date).ToString('o')
                }
            }
            catch {
                throw [EAFResourceValidationException]::new(
                    "Failed to store secret in Key Vault '$KeyVaultName': $($_.Exception.Message)",
                    "SecureConfiguration",
                    $ConfigPath,
                    "KeyVaultAccess",
                    $_.Exception.Message
                )
            }
        }
        else {
            # Store in memory
            Write-Verbose "Storing secure configuration in memory: $ConfigPath"
            
            # Store a copy of the secure string
            $script:SecureConfigStore[$ConfigPath] = @{
                Type = 'Memory'
                Value = $SecureValue.Copy()
                LastModified = (Get-Date).ToString('o')
            }
        }
        
        return $true
    }
    catch {
        if ($_.Exception -is [EAFResourceValidationException]) {
            throw
        }
        
        throw [EAFResourceValidationException]::new(
            "Failed to set secure configuration '$ConfigPath': $($_.Exception.Message)",
            "SecureConfiguration",
            $ConfigPath,
            "SetFailed",
            $_.Exception.Message
        )
    }
}

<#
.SYNOPSIS
    Gets a secure configuration value.
    
.DESCRIPTION
    The Get-EAFSecureConfiguration function retrieves a previously stored secure configuration value.
    
.PARAMETER ConfigPath
    The dot-notation path that identifies the configuration.
    
.PARAMETER AsPlainText
    If set, returns the value as plaintext (string) instead of as a SecureString.
    Use with caution as this exposes sensitive information.
    
.EXAMPLE
    $secureValue = Get-EAFSecureConfiguration -ConfigPath "Database.ConnectionString"
    
.EXAMPLE
    $apiKey = Get-EAFSecureConfiguration -ConfigPath "API.Key" -AsPlainText
#>
function Get-EAFSecureConfiguration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$AsPlainText
    )
    
    try {
        # Check if the configuration exists
        if (-not $script:SecureConfigStore.ContainsKey($ConfigPath)) {
            throw [EAFResourceValidationException]::new(
                "Secure configuration not found: $ConfigPath",
                "SecureConfiguration",
                $ConfigPath,
                "NotFound",
                "ConfigurationNotFound"
            )
        }
        
        $secureConfig = $script:SecureConfigStore[$ConfigPath]
        
        if ($secureConfig.Type -eq 'KeyVault') {
            # Retrieve from Key Vault
            Write-Verbose "Retrieving secure configuration from Azure Key Vault: $($secureConfig.VaultName)"
            
            try {
                $secret = Get-AzKeyVaultSecret -VaultName $secureConfig.VaultName -Name $secureConfig.SecretName -ErrorAction Stop
                if (-not $secret) {
                    throw "Secret not found in Key Vault"
                }
                
                if ($AsPlainText) {
                    return $secret.SecretValue | ConvertFrom-SecureString -AsPlainText
                }
                else {
                    return $secret.SecretValue
                }
            }
            catch {
                throw [EAFResourceValidationException]::new(
                    "Failed to retrieve secret from Key Vault: $($_.Exception.Message)",
                    "SecureConfiguration",
                    $ConfigPath,
                    "KeyVaultAccess",
                    $_.Exception.Message
                )
            }
        }
        else {
            # Retrieve from memory
            Write-Verbose "Retrieving secure configuration from memory: $ConfigPath"
            
            if ($AsPlainText) {
                return $secureConfig.Value | ConvertFrom-SecureString -AsPlainText
            }
            else {
                return $secureConfig.Value.Copy()
            }
        }
    }
    catch {
        if ($_.Exception -is [EAFResourceValidationException]) {
            throw
        }
        
        throw [EAFResourceValidationException]::new(
            "Failed to get secure configuration '$ConfigPath': $($_.Exception.Message)",
            "SecureConfiguration",
            $ConfigPath,
            "GetFailed",
            $_.Exception.Message
        )
    }
}

<#
.SYNOPSIS
    Tests if a secure configuration value exists.
    
.DESCRIPTION
    The Test-EAFSecureConfiguration function checks if a secure configuration exists
    and is accessible.
    
.PARAMETER ConfigPath
    The dot-notation path that identifies the configuration.
    
.EXAMPLE
    if (Test-EAFSecureConfiguration -ConfigPath "Database.ConnectionString") {
        # Use the secure configuration
    }
#>
function Test-EAFSecureConfiguration {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )
    
    try {
        if (-not $script:SecureConfigStore.ContainsKey($ConfigPath)) {
            return $false
        }
        
        $secureConfig = $script:SecureConfigStore[$ConfigPath]
        
        if ($secureConfig.Type -eq 'KeyVault') {
            # Check if Key Vault secret exists
            try {
                $secret = Get-AzKeyVaultSecret -VaultName $secureConfig.VaultName -Name $secureConfig.SecretName -ErrorAction SilentlyContinue
                return ($null -ne $secret)
            }
            catch {
                Write-Verbose "Error checking Key Vault secret: $($_.Exception.Message)"
                return $false
            }
        }
        else {
            # Memory-based configuration always exists if it's in the store
            return $true
        }
    }
    catch {
        Write-Verbose "Error testing secure configuration: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Removes a secure configuration value.
    
.DESCRIPTION
    The Remove-EAFSecureConfiguration function removes a previously stored secure configuration value.
    
.PARAMETER ConfigPath
    The dot-notation path that identifies the configuration.
    
.PARAMETER RemoveFromKeyVault
    If set, also removes the secret from the Azure Key Vault if stored there.
    
.EXAMPLE
    Remove-EAFSecureConfiguration -ConfigPath "Database.ConnectionString"
    
.EXAMPLE
    Remove-EAFSecureConfiguration -ConfigPath "API.Key" -RemoveFromKeyVault
#>
function Remove-EAFSecureConfiguration {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$RemoveFromKeyVault
    )
    
    try {
        if (-not $script:SecureConfigStore.ContainsKey($ConfigPath)) {
            Write-Warning "Secure configuration not found: $ConfigPath"
            return $false
        }
        
        $secureConfig = $script:SecureConfigStore[$ConfigPath]
        
        # If stored in Key Vault and RemoveFromKeyVault is specified
        if ($secureConfig.Type -eq 'KeyVault' -and $RemoveFromKeyVault) {
            if ($PSCmdlet.ShouldProcess("$($secureConfig.VaultName)/$($secureConfig.SecretName)", "Remove Key Vault Secret")) {
                try {
                    Remove-AzKeyVaultSecret -VaultName $secureConfig.VaultName -Name $secureConfig.SecretName -Force -ErrorAction Stop
                }
                catch {
                    Write-Warning "Failed to remove secret from Key Vault: $($_.Exception.Message)"
                }
            }
        }
        
        # Remove from secure store
        if ($PSCmdlet.ShouldProcess($ConfigPath, "Remove secure configuration")) {
            $script:SecureConfigStore.Remove($ConfigPath)
            return $true
        }
        
        return $false
    }
    catch {
        throw [EAFResourceValidationException]::new(
            "Failed to remove secure configuration '$ConfigPath': $($_.Exception.Message)",
            "SecureConfiguration",
            $ConfigPath,
            "RemoveFailed",
            $_.Exception.Message
        )
    }
}

<#
.SYNOPSIS
    Encrypts sensitive data for secure storage.
    
.DESCRIPTION
    The Protect-EAFSensitiveData function encrypts sensitive data for secure storage
    using Windows DPAPI or AES encryption.
    
.PARAMETER Data
    The sensitive data to encrypt.
    
.PARAMETER UseAES
    If set, uses AES encryption instead of DPAPI.
    Requires a password or key to be specified.
    
.PARAMETER Password
    The password to use for AES encryption.
    Only applicable if UseAES is set.
    
.PARAMETER Scope
    For DPAPI, specifies whether the data should be encrypted for the current user
    or the local machine. Valid values: 'CurrentUser', 'LocalMachine'.
    Default is 'CurrentUser'.
    
.EXAMPLE
    $result = Protect-EAFSensitiveData -Data "My secret data"
    
.EXAMPLE
    $password = Read-Host -AsSecureString -Prompt "Enter encryption password"
    $result = Protect-EAFSensitiveData -Data "API key 12345" -UseAES -Password $password
#>
function Protect-EAFSensitiveData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Data,
        
        [Parameter(Mandatory = $false)]
        [switch]$UseAES,
        
        [Parameter(Mandatory = $false)]
        [securestring]$Password,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$Scope = 'CurrentUser'
    )
    
    try {
        $dataBytes = [Text.Encoding]::UTF8.GetBytes($Data)
        
        if ($UseAES) {
            # AES Encryption
            if ($null -eq $Password) {
                throw "Password is required for AES encryption"
            }
            
            # Convert password to bytes
            $passwordBytes = [Text.Encoding]::UTF8.GetBytes(
                [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
                )
            )
            
            # Generate salt and derive key
            $salt = [byte[]]::new(16)
            $rng = [RandomNumberGenerator]::Create()
            $rng.GetBytes($salt)
            
            $keyDerivation = [Rfc2898DeriveBytes]::new($passwordBytes, $salt, 10000)
            $key = $keyDerivation.Get

