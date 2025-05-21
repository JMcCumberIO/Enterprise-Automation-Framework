#Requires -Modules Pester -Version 5

Describe "New-EAFVM.Unit.Tests" -Tags 'Unit', 'VM' {

    $FunctionUnderTestPath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\Public\New-EAFVM.ps1"
    $PrivateModulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\Private"

    # Common Test Variables
    $TestResourceGroupName = "rg-test-vm-unit"
    $TestVmName = "vm-unittest-dev" 
    $TestLocation = "eastus"
    $TestDepartment = "VMUnit"
    $TestEnvironment = "dev"
    $TestAdminUsername = "testadmin"
    $TestAdminPasswordPlainText = "P@sswOrd123!"
    $TestAdminPassword = ConvertTo-SecureString $TestAdminPasswordPlainText -AsPlainText -Force
    $TestVnetName = "vnet-test-dev"
    $TestSubnetName = "snet-apps-dev"
    $TestVnetResourceGroupName = $TestResourceGroupName 
    $DefaultVmSize = "Standard_D2s_v3"
    $TestUserAssignedIdentityId = "/subscriptions/mockSub/resourceGroups/mockRg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/myTestUAI"


    $MockEAFDefaultTags = @{
        Environment  = $TestEnvironment
        Department   = $TestDepartment
        CreatedDate  = (Get-Date -Format "yyyy-MM-dd")
        ResourceType = "VirtualMachine"
    }

    $MockSuccessfulDeploymentOutput = @{
        ProvisioningState = 'Succeeded'
        Outputs           = @{ 
            managedIdentityPrincipalId = 'mock-msi-principal-id'
        }
        DeploymentId      = "mock-vm-deployment-id"
    }
    
    $MockVMInstance = @{ 
        Name                        = $TestVmName
        ResourceGroupName           = $TestResourceGroupName
        Location                    = $TestLocation
        VMId                        = "mock-vm-guid"
        HardwareProfile             = @{ VmSize = $DefaultVmSize }
        StorageProfile              = @{ OsDisk = @{ OsType = "Windows" } } 
        NetworkProfile              = @{ NetworkInterfaces = @( @{ Id = "mock-nic-id" } ) }
        Identity                    = @{ PrincipalId = "mock-msi-principal-id"; Type = "SystemAssigned" }
        ProvisioningState           = "Succeeded"
        Tags                        = $MockEAFDefaultTags
        Statuses                    = @( 
            @{ DisplayStatus = "Provisioning succeeded" },
            @{ DisplayStatus = "VM running" } 
        )
    }
    $MockNic = @{ Id = "mock-nic-id"; IpConfigurations = @( @{ PrivateIpAddress = "10.0.0.4"; PublicIpAddress = @{ Id = "mock-pip-id" } } ) }
    $MockPip = @{ Id = "mock-pip-id"; IpAddress = "20.1.2.3"; DnsSettings = @{ Fqdn = "$TestVmName.mockregion.cloudapp.azure.com" } }


    BeforeAll {
        . $FunctionUnderTestPath
    }
    
    AfterAll {
        # Cleanup
    }

    Context "Successful Deployments" {
        $CapturedTemplateParameters = $null
        $CapturedTemplateFile = $null
        $NewAzRgDeploymentCallCount = 0
        
        BeforeEach {
            $script:NewAzRgDeploymentCallCount = 0
            $script:CapturedTemplateParameters = $null
            $script:CapturedTemplateFile = $null
            $script:CurrentMockDeploymentOutput = $MockSuccessfulDeploymentOutput 
            $script:CurrentMockVMInstance = $MockVMInstance 

            Mock Get-EAFConfiguration { param($ConfigPath)
                if ($ConfigPath -like "Regions.Default.*") { return $TestLocation }
                return $null
            } -ModuleName New-EAFVM

            Mock Test-EAFResourceName { return $true } -ModuleName New-EAFVM
            Mock Test-EAFResourceGroupExists { return $true } -ModuleName New-EAFVM
            Mock Get-EAFDefaultTags { return $MockEAFDefaultTags } -ModuleName New-EAFVM
            Mock Get-EAFDefaultSKU { return $DefaultVmSize } -ModuleName New-EAFVM 
            Mock Invoke-WithRetry { param($ScriptBlock, $MaxRetryCount, $ActivityName) Invoke-Command -ScriptBlock $ScriptBlock } -ModuleName New-EAFVM
            Mock Write-EAFException { param($Exception, $ErrorCategory, $Throw) Write-Warning "Mock Write-EAFException: $($Exception.Message)"; if($Throw){ throw $Exception } } -ModuleName New-EAFVM
            Mock Test-EAFNetworkConfiguration { return $true } -ModuleName New-EAFVM
            
            Mock Get-Module { return $true } -ModuleName New-EAFVM
            Mock Get-AzResourceGroup { return @{ Location = $TestLocation } } -ModuleName New-EAFVM
            Mock Get-AzVM { return $null } -ModuleName New-EAFVM 
            Mock New-AzResourceGroupDeployment {
                param($ResourceGroupName, $Name, $TemplateFile, $TemplateParameterObject, $Verbose, $ErrorAction)
                $script:CapturedTemplateFile = $TemplateFile
                $script:CapturedTemplateParameters = $TemplateParameterObject
                $script:NewAzRgDeploymentCallCount++
                return $script:CurrentMockDeploymentOutput | ConvertTo-Json | ConvertFrom-Json 
            } -ModuleName New-EAFVM
            Mock Get-AzVirtualNetwork { 
                return @{ Name = $TestVnetName; Subnets = @( @{ Name = $TestSubnetName } ) }
            } -ModuleName New-EAFVM
            Mock Get-AzNetworkInterface { return $MockNic } -ModuleName New-EAFVM 
            Mock Get-AzPublicIpAddress { return $MockPip } -ModuleName New-EAFVM 

            Mock ShouldProcess { return $true }
        }

        # ... (previously added successful deployment tests are assumed here) ...
        # Minimal Windows, Minimal Linux, Location from Config, VmSize from Config, Custom VmSize, Custom DataDisks, VnetResourceGroupName

        It "Should correctly pass Managed Identity parameters (SystemAssigned)" {
            Mock Get-AzVM -ModuleName New-EAFVM -MockWith { return $script:CurrentMockVMInstance }
            $params = @{
                ResourceGroupName  = $TestResourceGroupName; VmName = $TestVmName; OsType = "Windows"
                AdminUsername      = $TestAdminUsername; AdminPassword = $TestAdminPassword
                VirtualNetworkName = $TestVnetName; SubnetName = $TestSubnetName; Department = $TestDepartment
                EnableManagedIdentity = $true; ManagedIdentityType = "SystemAssigned"
            }
            New-EAFVM @params
            $script:CapturedTemplateParameters['enableManagedIdentity'] | Should -Be $true
            $script:CapturedTemplateParameters['managedIdentityType'] | Should -Be "SystemAssigned"
        }

        It "Should correctly pass Managed Identity parameters (UserAssigned)" {
             $uaVM = $MockVMInstance.PSObject.Copy()
             $uaVM.Identity.Type = "UserAssigned" # Update mock for output
             Mock Get-AzVM -ModuleName New-EAFVM -MockWith { return $uaVM }

            $params = @{
                ResourceGroupName      = $TestResourceGroupName; VmName = $TestVmName; OsType = "Windows"
                AdminUsername          = $TestAdminUsername; AdminPassword = $TestAdminPassword
                VirtualNetworkName     = $TestVnetName; SubnetName = $TestSubnetName; Department = $TestDepartment
                EnableManagedIdentity  = $true; ManagedIdentityType = "UserAssigned"
                UserAssignedIdentityId = $TestUserAssignedIdentityId
            }
            New-EAFVM @params
            $script:CapturedTemplateParameters['enableManagedIdentity'] | Should -Be $true
            $script:CapturedTemplateParameters['managedIdentityType'] | Should -Be "UserAssigned"
            $script:CapturedTemplateParameters['userAssignedIdentities'] | Should -BeOfType ([hashtable])
            $script:CapturedTemplateParameters['userAssignedIdentities'].ContainsKey($TestUserAssignedIdentityId) | Should -Be $true
        }
        
        It "Should correctly pass Boot Diagnostics parameters" {
            Mock Get-AzVM -ModuleName New-EAFVM -MockWith { return $script:CurrentMockVMInstance }
            $diagStorageName = "diagstoragetestacct"
            $params = @{
                ResourceGroupName                = $TestResourceGroupName; VmName = $TestVmName; OsType = "Windows"
                AdminUsername                    = $TestAdminUsername; AdminPassword = $TestAdminPassword
                VirtualNetworkName               = $TestVnetName; SubnetName = $TestSubnetName; Department = $TestDepartment
                EnableBootDiagnostics            = $true
                BootDiagnosticsStorageAccountName = $diagStorageName
            }
            New-EAFVM @params
            $script:CapturedTemplateParameters['enableBootDiagnostics'] | Should -Be $true
            # The Bicep template's parameter for this is 'bootDiagnosticsStorageAccountName', but it's used by the template's 'diagnosticsStorageName' if empty.
            # The PowerShell parameter BootDiagnosticsStorageAccountName is used for 'existing' one.
            # The refactored vm.bicep now has 'bootDiagnosticsStorageAccountName' param which is what we pass.
            $script:CapturedTemplateParameters['bootDiagnosticsStorageAccountName'] | Should -Be $diagStorageName
        }
        
        # EnableBackup parameters are not in the repaired vm.bicep, so tests for them are omitted.
    }

    Context "Idempotency Checks" {
        $NewAzRgDeploymentCallCount = 0
        BeforeEach {
            $script:NewAzRgDeploymentCallCount = 0
            # Base mocks
            Mock Get-EAFConfiguration { return $TestLocation } -ModuleName New-EAFVM
            Mock Test-EAFResourceName { return $true } -ModuleName New-EAFVM
            Mock Test-EAFResourceGroupExists { return $true } -ModuleName New-EAFVM
            Mock Get-EAFDefaultTags { return $MockEAFDefaultTags } -ModuleName New-EAFVM
            Mock Get-EAFDefaultSKU { return $DefaultVmSize } -ModuleName New-EAFVM
            Mock Invoke-WithRetry { param($ScriptBlock) Invoke-Command -ScriptBlock $ScriptBlock } -ModuleName New-EAFVM
            Mock Write-EAFException { param($Exception, $Throw) if($Throw){ throw $Exception } } -ModuleName New-EAFVM
            Mock Get-Module { return $true } -ModuleName New-EAFVM
            Mock Get-AzResourceGroup { return @{ Location = $TestLocation } } -ModuleName New-EAFVM
            Mock New-AzResourceGroupDeployment { $script:NewAzRgDeploymentCallCount++; return $MockSuccessfulDeploymentOutput } -ModuleName New-EAFVM
            Mock Get-AzNetworkInterface { return $MockNic } -ModuleName New-EAFVM 
            Mock Get-AzPublicIpAddress { return $MockPip } -ModuleName New-EAFVM 
        }

        It "Should prompt user and NOT deploy if VM exists, -Force is not used, and user says No" {
            Mock Get-AzVM { return $MockVMInstance } -ModuleName New-EAFVM # VM Exists
            Mock ShouldProcess { return $false } # User says No
            
            $params = @{ ResourceGroupName = $TestResourceGroupName; VmName = $TestVmName; OsType = "Windows"; AdminUsername = $TestAdminUsername; AdminPassword = $TestAdminPassword; VirtualNetworkName = $TestVnetName; SubnetName = $TestSubnetName; Department = $TestDepartment }
            $result = New-EAFVM @params
            
            $script:NewAzRgDeploymentCallCount | Should -Be 0
            $result.Name | Should -Be $TestVmName # Should return the existing instance
        }

        It "Should proceed with deployment if VM exists and -Force is used" {
            Mock Get-AzVM { return $MockVMInstance } -ModuleName New-EAFVM # VM Exists
            Mock ShouldProcess { return $true } # ShouldProcess won't be called
            
            $params = @{ ResourceGroupName = $TestResourceGroupName; VmName = $TestVmName; OsType = "Windows"; AdminUsername = $TestAdminUsername; AdminPassword = $TestAdminPassword; VirtualNetworkName = $TestVnetName; SubnetName = $TestSubnetName; Department = $TestDepartment; Force = $true }
            New-EAFVM @params
            
            $script:NewAzRgDeploymentCallCount | Should -Be 1
        }
    }

    Context "Error Handling" {
        $WriteEAFExceptionCallCount = 0
        $LastEAFException = $null

        BeforeEach {
            $script:WriteEAFExceptionCallCount = 0
            $script:LastEAFException = $null
            # Base mocks
            Mock Get-EAFConfiguration { return $TestLocation } -ModuleName New-EAFVM
            Mock Test-EAFResourceName { return $true } -ModuleName New-EAFVM
            Mock Test-EAFResourceGroupExists { return $true } -ModuleName New-EAFVM
            Mock Get-EAFDefaultTags { return $MockEAFDefaultTags } -ModuleName New-EAFVM
            Mock Get-EAFDefaultSKU { return $DefaultVmSize } -ModuleName New-EAFVM
            Mock Invoke-WithRetry { param($ScriptBlock) Invoke-Command -ScriptBlock $ScriptBlock } -ModuleName New-EAFVM
            Mock Write-EAFException { 
                param($Exception, $ErrorCategory, $Throw) 
                $script:WriteEAFExceptionCallCount++
                $script:LastEAFException = $Exception
                if($Throw){ throw $Exception }
            } -ModuleName New-EAFVM
            Mock Get-Module { return $true } -ModuleName New-EAFVM
            Mock Get-AzResourceGroup { return @{ Location = $TestLocation } } -ModuleName New-EAFVM
            Mock Get-AzVM { return $null } -ModuleName New-EAFVM
            Mock New-AzResourceGroupDeployment { return $MockSuccessfulDeploymentOutput } -ModuleName New-EAFVM
            Mock ShouldProcess { return $true }
            Mock Test-Path { return $true } # Bicep template exists
            Mock Test-EAFNetworkConfiguration { return $true } -ModuleName New-EAFVM
            Mock Get-AzVirtualNetwork { return @{ Name = $TestVnetName; Subnets = @(@{ Name = $TestSubnetName }) } } -ModuleName New-EAFVM
        }

        It "Should throw EAFDependencyException if Az.Compute module is missing" {
            Mock Get-Module { param($Name) if($Name -eq 'Az.Compute') { return $null } else { return $true} } -ModuleName New-EAFVM
            { New-EAFVM -ResourceGroupName "any" -VmName "anyvm" -OsType "Windows" -AdminUsername "usr" -AdminPassword $TestAdminPassword -VirtualNetworkName "vnet" -SubnetName "snet" -Department "any" } | Should -Throw 
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.DependencyName | Should -Be "Az.Compute"
        }

        It "Should throw EAFDependencyException if Bicep template is missing" {
            Mock Test-Path { param($Path) if($Path -like "*vm.bicep") {return $false} else {return $true} } -ModuleName New-EAFVM
            { New-EAFVM -ResourceGroupName "any" -VmName "anyvm" -OsType "Windows" -AdminUsername "usr" -AdminPassword $TestAdminPassword -VirtualNetworkName "vnet" -SubnetName "snet" -Department "any" } | Should -Throw 
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.DependencyType | Should -Be "BicepTemplate"
        }

        It "Should throw EAFResourceValidationException if VM name is invalid" {
            Mock Test-EAFResourceName { return $false } -ModuleName New-EAFVM
            { New-EAFVM -ResourceGroupName "any" -VmName "invalid-vm-name!" -OsType "Windows" -AdminUsername "usr" -AdminPassword $TestAdminPassword -VirtualNetworkName "vnet" -SubnetName "snet" -Department "any" } | Should -Throw 
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.ResourceType | Should -Be "VirtualMachine"
        }
        
        It "Should throw if VNet/Subnet validation fails (mock Test-EAFNetworkConfiguration)" {
            Mock Test-EAFNetworkConfiguration { throw [EAFNetworkConfigurationException]::new("Mock VNet for VM not found", "VirtualMachine", "mockVNetVM", "VNetNotFound") } -ModuleName New-EAFVM
            { New-EAFVM -ResourceGroupName "any" -VmName "anyvm" -OsType "Windows" -AdminUsername "usr" -AdminPassword $TestAdminPassword -VirtualNetworkName "mockVNetVM" -SubnetName "mockSubnetVM" -Department "any" } | Should -Throw
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.ResourceType | Should -Be "VirtualMachine"
        }

        It "Should throw EAFParameterValidationException if UserAssignedIdentityId is missing when type is UserAssigned" {
            { New-EAFVM -ResourceGroupName "any" -VmName "anyvm" -OsType "Windows" -AdminUsername "usr" -AdminPassword $TestAdminPassword -VirtualNetworkName "vnet" -SubnetName "snet" -Department "any" -EnableManagedIdentity $true -ManagedIdentityType "UserAssigned" -UserAssignedIdentityId "" } | Should -Throw 
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.ParameterName | Should -Be "UserAssignedIdentityId"
        }
    }
}
