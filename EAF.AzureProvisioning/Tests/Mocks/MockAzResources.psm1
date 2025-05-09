# MockAzResources.psm1
# Provides mock implementations of Az PowerShell cmdlets for unit/integration testing

function Get-AzVM {
    param([string]$Name, [string]$ResourceGroupName)
    return @{ Name = $Name; ResourceGroupName = $ResourceGroupName; HardwareProfile = @{ VmSize = 'Standard_B2s' } }
}

function Get-AzWebApp {
    param([string]$Name, [string]$ResourceGroupName)
    return @{ Name = $Name; ResourceGroupName = $ResourceGroupName; Location = 'eastus' }
}

function Get-AzStorageAccount {
    param([string]$Name, [string]$ResourceGroupName)
    return @{ StorageAccountName = $Name; ResourceGroupName = $ResourceGroupName; Sku = @{ Name = 'Standard_LRS' } }
}

function Get-AzKeyVault {
    param([string]$VaultName, [string]$ResourceGroupName)
    return @{ VaultName = $VaultName; ResourceGroupName = $ResourceGroupName; Location = 'eastus' }
}
