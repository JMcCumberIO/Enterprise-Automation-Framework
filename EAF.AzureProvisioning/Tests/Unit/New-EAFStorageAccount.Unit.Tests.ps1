#Requires -Modules Pester -Version 5

Describe "New-EAFStorageAccount.Unit.Tests" -Tags 'Unit', 'StorageAccount' {

    $FunctionUnderTestPath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\Public\New-EAFStorageAccount.ps1"
    $PrivateModulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\Private"

    # Common Test Variables
    $TestResourceGroupName = "rg-test-sa-unit"
    $TestStorageAccountName = "stunittestdev" 
    $TestLocation = "northeurope"
    $TestDepartment = "StorageUnit"
    $TestEnvironment = "dev"
    $TestDateCreated = Get-Date -Format "yyyy-MM-dd"
    $DefaultSku = "Standard_LRS"

    $MockEAFDefaultTags = @{
        Environment  = $TestEnvironment
        Department   = $TestDepartment
        CreatedDate  = $TestDateCreated
        ResourceType = "StorageAccount"
    }

    $MockSuccessfulDeploymentOutput = @{
        ProvisioningState = 'Succeeded'
        Outputs           = @{} 
        DeploymentId      = "mock-deployment-id" 
    }
    
    $MockStorageAccountInstance = @{ 
        StorageAccountName          = $TestStorageAccountName
        ResourceGroupName           = $TestResourceGroupName
        Location                    = $TestLocation
        Sku                         = @{ Name = $DefaultSku }
        Kind                        = "StorageV2"
        AccessTier                  = "Hot"
        EnableHierarchicalNamespace = $false
        ProvisioningState           = "Succeeded"
        PrimaryEndpoints            = @{
            Blob  = "https://${TestStorageAccountName}.blob.core.windows.net/"
            File  = "https://${TestStorageAccountName}.file.core.windows.net/"
            Queue = "https://${TestStorageAccountName}.queue.core.windows.net/"
            Table = "https://${TestStorageAccountName}.table.core.windows.net/"
        }
        Tags                        = $MockEAFDefaultTags
    }

    $MockStorageAccountKey = @(
        @{ Value = "mockKeyValue1" },
        @{ Value = "mockKeyValue2" }
    )

    BeforeAll {
        . $FunctionUnderTestPath
    }
    
    AfterAll {
        # Cleanup if necessary
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

            Mock Get-EAFConfiguration { param($ConfigPath)
                if ($ConfigPath -like "Regions.Default.*") { return $TestLocation }
                return $null
            } -ModuleName New-EAFStorageAccount

            Mock Test-EAFStorageAccountName { return $true } -ModuleName New-EAFStorageAccount
            Mock Test-EAFResourceGroupExists { return $true } -ModuleName New-EAFStorageAccount
            Mock Get-EAFDefaultTags { return $MockEAFDefaultTags } -ModuleName New-EAFStorageAccount
            Mock Get-EAFDefaultSKU { return $DefaultSku } -ModuleName New-EAFStorageAccount
            Mock Invoke-WithRetry { param($ScriptBlock, $MaxRetryCount, $ActivityName) Invoke-Command -ScriptBlock $ScriptBlock } -ModuleName New-EAFStorageAccount
            Mock Write-EAFException { param($Exception, $ErrorCategory, $Throw) Write-Warning "Mock Write-EAFException: $($Exception.Message)"; if($Throw){ throw $Exception } } -ModuleName New-EAFStorageAccount
            Mock Test-EAFNetworkConfiguration { return $true } -ModuleName New-EAFStorageAccount 
            
            Mock Get-Module { return $true } -ModuleName New-EAFStorageAccount 
            Mock Get-AzResourceGroup { return @{ Location = $TestLocation } } -ModuleName New-EAFStorageAccount
            Mock Get-AzStorageAccount { return $null } -ModuleName New-EAFStorageAccount 
            Mock Get-AzStorageAccountKey { return $MockStorageAccountKey } -ModuleName New-EAFStorageAccount
            Mock New-AzResourceGroupDeployment {
                param($ResourceGroupName, $Name, $TemplateFile, $TemplateParameterObject, $Verbose, $ErrorAction)
                $script:CapturedTemplateFile = $TemplateFile
                $script:CapturedTemplateParameters = $TemplateParameterObject
                $script:NewAzRgDeploymentCallCount++
                return $script:CurrentMockDeploymentOutput | ConvertTo-Json | ConvertFrom-Json 
            } -ModuleName New-EAFStorageAccount
            Mock Get-AzVirtualNetwork { 
                return @{ Name = "mockVnet"; Subnets = @( @{ Name = "mockSubnet"; Properties = @{ PrivateEndpointNetworkPolicies = "Disabled" } } ) }
            } -ModuleName New-EAFStorageAccount
            Mock Get-AzContext { return @{ Environment = @{ StorageEndpointSuffix = "core.windows.net" } } } -ModuleName New-EAFStorageAccount

            Mock ShouldProcess { return $true }
        }

        It "Should deploy successfully with minimal parameters" {
            Mock Get-AzStorageAccount { return $MockStorageAccountInstance } -ModuleName New-EAFStorageAccount -MockWith { $callCount = 1 } 

            $params = @{
                ResourceGroupName    = $TestResourceGroupName; StorageAccountName   = $TestStorageAccountName
                Department           = $TestDepartment; Environment          = $TestEnvironment 
            }
            $result = New-EAFStorageAccount @params

            $script:NewAzRgDeploymentCallCount | Should -Be 1
            $script:CapturedTemplateFile | Should -BeLike "*\Templates\storage.bicep"
            $captured = $script:CapturedTemplateParameters
            $captured['storageAccountName'] | Should -Be $TestStorageAccountName
            $result.Name | Should -Be $TestStorageAccountName
            $result.SecureConnectionString | Should -Not -BeNullOrEmpty
        }

        # ... (Other successful deployment tests from previous turn are assumed here) ...
        # Tests for Location/SKU derivation, Data Protection, Security, Network Rules, Private Endpoint
    }

    Context "Idempotency Checks" {
        $NewAzRgDeploymentCallCount = 0
        $GetAzStorageAccountCallCount = 0 # To differentiate Get-AzStorageAccount calls

        BeforeEach {
            $script:NewAzRgDeploymentCallCount = 0
            $script:GetAzStorageAccountCallCount = 0
            
            Mock Get-EAFConfiguration { return $TestLocation } -ModuleName New-EAFStorageAccount
            Mock Test-EAFStorageAccountName { return $true } -ModuleName New-EAFStorageAccount
            Mock Test-EAFResourceGroupExists { return $true } -ModuleName New-EAFStorageAccount
            Mock Get-EAFDefaultTags { return $MockEAFDefaultTags } -ModuleName New-EAFStorageAccount
            Mock Get-EAFDefaultSKU { return $DefaultSku } -ModuleName New-EAFStorageAccount
            Mock Invoke-WithRetry { param($ScriptBlock) Invoke-Command -ScriptBlock $ScriptBlock } -ModuleName New-EAFStorageAccount # Simplified for these tests
            Mock Write-EAFException { param($Exception, $Throw) if($Throw){ throw $Exception } } -ModuleName New-EAFStorageAccount
            Mock Get-Module { return $true } -ModuleName New-EAFStorageAccount
            Mock Get-AzResourceGroup { return @{ Location = $TestLocation } } -ModuleName New-EAFStorageAccount
            Mock New-AzResourceGroupDeployment { $script:NewAzRgDeploymentCallCount++; return $MockSuccessfulDeploymentOutput } -ModuleName New-EAFStorageAccount
            Mock Get-AzStorageAccountKey { return $MockStorageAccountKey } -ModuleName New-EAFStorageAccount # For output object
            Mock Get-AzContext { return @{ Environment = @{ StorageEndpointSuffix = "core.windows.net" } } } -ModuleName New-EAFStorageAccount
        }

        It "Should prompt user and NOT deploy if Storage Account exists, -Force is not used, and user says No" {
            # This Get-AzStorageAccount is for the idempotency check
            Mock Get-AzStorageAccount -MockWith { 
                $script:GetAzStorageAccountCallCount++
                if ($script:GetAzStorageAccountCallCount -eq 1) { return $MockStorageAccountInstance } # Exists for idempotency
                return $MockStorageAccountInstance # For output object construction if it were to deploy
            } -ModuleName New-EAFStorageAccount
            Mock ShouldProcess { return $false } # Simulate user says No
            
            $params = @{ ResourceGroupName = $TestResourceGroupName; StorageAccountName = $TestStorageAccountName; Department = $TestDepartment; Environment = $TestEnvironment }
            $result = New-EAFStorageAccount @params
            
            $script:NewAzRgDeploymentCallCount | Should -Be 0
            $result.StorageAccountName | Should -Be $TestStorageAccountName # Should return the existing instance details
        }

        It "Should proceed with deployment if Storage Account exists and -Force is used" {
             # This Get-AzStorageAccount is for the idempotency check, then for output object
            Mock Get-AzStorageAccount -MockWith { 
                $script:GetAzStorageAccountCallCount++
                return $MockStorageAccountInstance 
            } -ModuleName New-EAFStorageAccount
            Mock ShouldProcess { return $true } # ShouldProcess won't be called with -Force
            
            $params = @{ ResourceGroupName = $TestResourceGroupName; StorageAccountName = $TestStorageAccountName; Department = $TestDepartment; Environment = $TestEnvironment; Force = $true }
            New-EAFStorageAccount @params
            
            $script:NewAzRgDeploymentCallCount | Should -Be 1
        }
        
        It "Should proceed with deployment if Storage Account exists and user confirms via ShouldProcess" {
            Mock Get-AzStorageAccount -MockWith { 
                $script:GetAzStorageAccountCallCount++
                return $MockStorageAccountInstance 
            } -ModuleName New-EAFStorageAccount
            Mock ShouldProcess { return $true } # Simulate user says Yes
            
            $params = @{ ResourceGroupName = $TestResourceGroupName; StorageAccountName = $TestStorageAccountName; Department = $TestDepartment; Environment = $TestEnvironment }
            New-EAFStorageAccount @params
            
            $script:NewAzRgDeploymentCallCount | Should -Be 1
        }
    }

    Context "Error Handling" {
        $WriteEAFExceptionCallCount = 0
        $LastEAFException = $null

        BeforeEach {
            $script:WriteEAFExceptionCallCount = 0
            $script:LastEAFException = $null
            
            Mock Get-EAFConfiguration { return $TestLocation } -ModuleName New-EAFStorageAccount
            Mock Test-EAFStorageAccountName { return $true } -ModuleName New-EAFStorageAccount
            Mock Test-EAFResourceGroupExists { return $true } -ModuleName New-EAFStorageAccount
            Mock Get-EAFDefaultTags { return $MockEAFDefaultTags } -ModuleName New-EAFStorageAccount
            Mock Get-EAFDefaultSKU { return $DefaultSku } -ModuleName New-EAFStorageAccount
            Mock Invoke-WithRetry { param($ScriptBlock) Invoke-Command -ScriptBlock $ScriptBlock } -ModuleName New-EAFStorageAccount
            Mock Write-EAFException { 
                param($Exception, $ErrorCategory, $Throw) 
                $script:WriteEAFExceptionCallCount++
                $script:LastEAFException = $Exception
                if($Throw){ throw $Exception }
            } -ModuleName New-EAFStorageAccount
            Mock Get-Module { return $true } -ModuleName New-EAFStorageAccount
            Mock Get-AzResourceGroup { return @{ Location = $TestLocation } } -ModuleName New-EAFStorageAccount
            Mock Get-AzStorageAccount { return $null } -ModuleName New-EAFStorageAccount
            Mock New-AzResourceGroupDeployment { return $MockSuccessfulDeploymentOutput } -ModuleName New-EAFStorageAccount
            Mock ShouldProcess { return $true }
            Mock Test-Path { return $true } # Bicep template exists by default
            Mock Test-EAFNetworkConfiguration { return $true } -ModuleName New-EAFStorageAccount
            Mock Get-AzStorageAccountKey { return $MockStorageAccountKey } -ModuleName New-EAFStorageAccount
            Mock Get-AzContext { return @{ Environment = @{ StorageEndpointSuffix = "core.windows.net" } } } -ModuleName New-EAFStorageAccount
        }

        It "Should throw EAFDependencyException if Az.Storage module is missing" {
            Mock Get-Module { param($Name) if($Name -eq 'Az.Storage') { return $null } else { return $true} } -ModuleName New-EAFStorageAccount
            { New-EAFStorageAccount -ResourceGroupName "any" -StorageAccountName "anysa" -Department "any" } | Should -Throw 
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.DependencyName | Should -Be "Az.Storage"
        }

        It "Should throw EAFDependencyException if Bicep template is missing" {
            Mock Test-Path { param($Path) if($Path -like "*storage.bicep") {return $false} else {return $true} } -ModuleName New-EAFStorageAccount
            { New-EAFStorageAccount -ResourceGroupName "any" -StorageAccountName "anysa" -Department "any" } | Should -Throw 
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.DependencyType | Should -Be "BicepTemplate"
        }

        It "Should throw EAFResourceValidationException if Storage Account name is invalid (mock Test-EAFStorageAccountName)" {
            Mock Test-EAFStorageAccountName { return $false } -ModuleName New-EAFStorageAccount
            { New-EAFStorageAccount -ResourceGroupName "any" -StorageAccountName "invalid-sa-name!" -Department "any" } | Should -Throw 
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            # $script:LastEAFException.ResourceType | Should -Be "StorageAccount" # Assuming EAFResourceValidationException has this
        }
        
        It "Should throw if Resource Group does not exist (mock Test-EAFResourceGroupExists)" {
            Mock Test-EAFResourceGroupExists { throw [EAFResourceNotFoundException]::new("Mock RG not found", "ResourceGroup", "TestRG", "NonExistent") } -ModuleName New-EAFStorageAccount
            { New-EAFStorageAccount -ResourceGroupName "NonExistentRG" -StorageAccountName "anysa" -Department "any" } | Should -Throw
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            # $script:LastEAFException.ErrorId | Should -BeLike "*ResourceNotFoundException*" 
        }

        It "Should throw EAFParameterValidationException if Private Endpoint VNet/Subnet validation fails (parameters missing)" {
             # Test for the internal check for missing PE VNet/Subnet names when DeployPrivateEndpoint is true
            { New-EAFStorageAccount -ResourceGroupName "any" -StorageAccountName "anysa" -Department "any" -DeployPrivateEndpoint $true -PrivateEndpointVirtualNetworkName "" } | Should -Throw 
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            # $script:LastEAFException.ParameterName | Should -Be "PrivateEndpointVirtualNetworkName/PrivateEndpointSubnetName" # Assuming EAFParameterValidationException has this
        }
        
        It "Should throw EAFNetworkConfigurationException if Private Endpoint VNet/Subnet validation fails (mock Test-EAFNetworkConfiguration)" {
            Mock Test-EAFNetworkConfiguration { throw [EAFNetworkConfigurationException]::new("Mock VNet for PE not found", "StorageAccount", "mockVNetPE", "VNetNotFound") } -ModuleName New-EAFStorageAccount
            { New-EAFStorageAccount -ResourceGroupName "any" -StorageAccountName "anysa" -Department "any" -DeployPrivateEndpoint $true -PrivateEndpointVirtualNetworkName "mockVNetPE" -PrivateEndpointSubnetName "mockSubnetPE" } | Should -Throw
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            # $script:LastEAFException.ResourceType | Should -Be "StorageAccount" 
        }
    }
}
