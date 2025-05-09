# Integration tests for Storage Account deployment
Describe 'EAF Storage Account Deployment' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../Mocks/MockAzResources.psm1" -Force
        $script:config = Get-Content -Raw -Path './test-config-storage.json' | ConvertFrom-Json
    }
    It 'Should deploy a Storage Account with the correct name' {
        $storage = Get-AzStorageAccount -Name $script:config.storageAccountName -ResourceGroupName $script:config.resourceGroup
        $storage.StorageAccountName | Should -Be $script:config.storageAccountName
    }
    It 'Should have the correct SKU' {
        $storage = Get-AzStorageAccount -Name $script:config.storageAccountName -ResourceGroupName $script:config.resourceGroup
        $storage.Sku.Name | Should -Be $script:config.sku
    }
}
