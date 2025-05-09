# Integration tests for Key Vault deployment
Describe 'EAF Key Vault Deployment' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../Mocks/MockAzResources.psm1" -Force
        $config = Get-Content -Raw -Path "$PSScriptRoot/test-config-keyvault.json" | ConvertFrom-Json
    }
    It 'Should deploy a Key Vault with the correct name' {
        $kv = Get-AzKeyVault -VaultName $config.keyVaultName -ResourceGroupName $config.resourceGroup
        $kv.VaultName | Should -Be $config.keyVaultName
    }
    It 'Should be in the correct location' {
        $kv = Get-AzKeyVault -VaultName $config.keyVaultName -ResourceGroupName $config.resourceGroup
        $kv.Location | Should -Be $config.location
    }
}
