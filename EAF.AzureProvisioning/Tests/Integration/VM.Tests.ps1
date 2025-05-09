# Integration tests for VM deployment
Describe 'EAF VM Deployment' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../Mocks/MockAzResources.psm1" -Force
        $config = Get-Content -Raw -Path "$PSScriptRoot/test-config-vm.json" | ConvertFrom-Json
    }
    It 'Should deploy a VM with the correct name' {
        $vm = Get-AzVM -Name $config.vmName -ResourceGroupName $config.resourceGroup
        $vm.Name | Should -Be $config.vmName
    }
    It 'Should have the correct size' {
        $vm = Get-AzVM -Name $config.vmName -ResourceGroupName $config.resourceGroup
        $vm.HardwareProfile.VmSize | Should -Be $config.vmSize
    }
}
