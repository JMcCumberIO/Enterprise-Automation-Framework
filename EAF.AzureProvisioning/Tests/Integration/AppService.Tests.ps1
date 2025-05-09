# Integration tests for App Service deployment
BeforeAll {
    Import-Module "$PSScriptRoot/../Mocks/MockAzResources.psm1" -Force
    $config = Get-Content -Raw -Path "$PSScriptRoot/test-config-appservice.json" | ConvertFrom-Json
}
Describe 'EAF App Service Deployment' {
    It 'Should deploy an App Service with the correct name' {
        $app = Get-AzWebApp -Name $config.appServiceName -ResourceGroupName $config.resourceGroup
        $app.Name | Should -Be $config.appServiceName
    }
    It 'Should be in the correct location' {
        $app = Get-AzWebApp -Name $config.appServiceName -ResourceGroupName $config.resourceGroup
        $app.Location | Should -Be $config.location
    }
}
