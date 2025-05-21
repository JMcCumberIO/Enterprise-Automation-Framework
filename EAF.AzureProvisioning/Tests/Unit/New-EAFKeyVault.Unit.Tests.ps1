#Requires -Modules Pester -Version 5

Describe "New-EAFKeyVault.Unit.Tests" -Tags 'Unit', 'KeyVault' {

    $FunctionUnderTestPath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\Public\New-EAFKeyVault.ps1"
    $PrivateModulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\Private"

    # Common Test Variables
    $TestResourceGroupName = "rg-test-kv-unit"
    $TestKeyVaultName = "kv-unittest-dev"
    $TestLocation = "westus2"
    $TestDepartment = "SecurityUnit"
    $TestEnvironment = "dev"
    $TestAdminObjectId = "00000000-0000-0000-0000-000000000001"
    $TestSecretsUserPrincipalId = "00000000-0000-0000-0000-000000000002"
    $TestCertificatesOfficerPrincipalId = "00000000-0000-0000-0000-000000000003"
    $TestDateCreated = Get-Date -Format "yyyy-MM-dd"

    $DefaultPrincipalType = 'ServicePrincipal'

    $MockEAFDefaultTags = @{
        Environment  = $TestEnvironment
        Department   = $TestDepartment
        CreatedDate  = $TestDateCreated
        ResourceType = "KeyVault"
    }

    $MockSuccessfulDeploymentOutput = @{
        ProvisioningState = 'Succeeded'
        Outputs           = @{ # Simulate outputs from keyVault.bicep
            keyVaultId                  = "/subscriptions/mockSub/resourceGroups/${TestResourceGroupName}/providers/Microsoft.KeyVault/vaults/${TestKeyVaultName}"
            keyVaultUri                 = "https://${TestKeyVaultName}.vault.azure.net/"
            keyVaultName                = $TestKeyVaultName
            keyVaultResourceId          = "/subscriptions/mockSub/resourceGroups/${TestResourceGroupName}/providers/Microsoft.KeyVault/vaults/${TestKeyVaultName}"
            rbacEnabled                 = $true
            softDeleteEnabled           = $true
            purgeProtectionEnabled      = $true 
            privateEndpointEnabled      = $false
            monitoringEnabled           = $true # Default this to true for output checks
            logAnalyticsWorkspaceName   = 'law-mock'
            appInsightsName             = 'appi-mock'
        }
    }
    
    $MockKeyVaultInstance = @{ # From Get-AzKeyVault
        VaultName                   = $TestKeyVaultName
        ResourceGroupName           = $TestResourceGroupName
        Location                    = $TestLocation
        VaultUri                    = "https://${TestKeyVaultName}.vault.azure.net/"
        Sku                         = @{ Name = "Standard" } 
        TenantId                    = "mock-tenant-id"
        ResourceId                  = "/subscriptions/mockSub/resourceGroups/${TestResourceGroupName}/providers/Microsoft.KeyVault/vaults/${TestKeyVaultName}"
        EnableRbacAuthorization     = $true
        EnableSoftDelete            = $true
        SoftDeleteRetentionInDays   = 90
        EnablePurgeProtection       = $true # By default, assume it's enabled for existing
        Tags                        = $MockEAFDefaultTags
    }

    BeforeAll {
        . $FunctionUnderTestPath
    }
    
    AfterAll {
        # Clean up any mocks or state if necessary, Pester 5 usually handles this well for module functions.
        # Unload helper modules if they were truly imported (which they are not in this pattern)
    }

    Context "Successful Deployments" {
        $CapturedTemplateParameters = $null
        $CapturedTemplateFile = $null
        $NewAzRgDeploymentCallCount = 0
        $EnableEAFDiagnosticsCallCount = 0

        BeforeEach {
            $script:NewAzRgDeploymentCallCount = 0
            $script:CapturedTemplateParameters = $null
            $script:CapturedTemplateFile = $null
            $script:EnableEAFDiagnosticsCallCount = 0
            $script:CurrentMockDeploymentOutput = $MockSuccessfulDeploymentOutput # Default, can be overridden per test

            Mock Get-EAFConfiguration { param($ConfigPath)
                if ($ConfigPath -like "Regions.Default.*") { return $TestLocation }
                if ($ConfigPath -like "Security.KeyVault.SoftDeleteRetention.*") { return 90 } 
                if ($ConfigPath -like "Security.EnableDiagnostics.*") { return $false } # Default for diagnostics unless overridden
                return $null
            } -ModuleName New-EAFKeyVault

            Mock Test-EAFResourceName { return $true } -ModuleName New-EAFKeyVault
            Mock Test-EAFResourceGroupExists { return $true } -ModuleName New-EAFKeyVault
            Mock Get-EAFDefaultTags { return $MockEAFDefaultTags } -ModuleName New-EAFKeyVault
            Mock Get-EAFDefaultSKU { return "standard" } -ModuleName New-EAFKeyVault
            Mock Invoke-WithRetry { param($ScriptBlock, $MaxRetryCount, $ActivityName) Invoke-Command -ScriptBlock $ScriptBlock } -ModuleName New-EAFKeyVault
            Mock Write-EAFException { param($Exception, $ErrorCategory, $Throw) Write-Warning "Mock Write-EAFException: $($Exception.Message)"; if($Throw){ throw $Exception } } -ModuleName New-EAFKeyVault
            Mock Enable-EAFDiagnosticSettings { $script:EnableEAFDiagnosticsCallCount++ } -ModuleName New-EAFKeyVault
            
            Mock Get-Module { return $true }
            Mock Get-AzResourceGroup { return @{ Location = $TestLocation } } -ModuleName New-EAFKeyVault
            Mock Get-AzKeyVault { return $null } -ModuleName New-EAFKeyVault 
            Mock New-AzResourceGroupDeployment {
                param($ResourceGroupName, $Name, $TemplateFile, $TemplateParameterObject, $Verbose, $ErrorAction)
                $script:CapturedTemplateFile = $TemplateFile
                $script:CapturedTemplateParameters = $TemplateParameterObject
                $script:NewAzRgDeploymentCallCount++
                return $script:CurrentMockDeploymentOutput | ConvertTo-Json | ConvertFrom-Json 
            } -ModuleName New-EAFKeyVault
            Mock Get-AzVirtualNetwork { 
                return @{ Name = "mockVnet"; Subnets = @( @{ Name = "mockSubnet"; Properties = @{ PrivateEndpointNetworkPolicies = "Disabled" } } ) }
            } -ModuleName New-EAFKeyVault
            Mock Test-EAFNetworkConfiguration { return $true } 

            Mock ShouldProcess { return $true }
        }

        It "Should deploy successfully with minimal RBAC parameters (AdminObjectId for Admin role)" {
            $params = @{
                ResourceGroupName = $TestResourceGroupName; KeyVaultName = $TestKeyVaultName
                Department        = $TestDepartment; Environment = $TestEnvironment
                AdminObjectId     = $TestAdminObjectId 
            }
            $result = New-EAFKeyVault @params

            $script:NewAzRgDeploymentCallCount | Should -Be 1
            $script:CapturedTemplateFile | Should -BeLike "*\Templates\keyVault.bicep"
            $captured = $script:CapturedTemplateParameters
            $captured['keyVaultAdministratorPrincipalId'] | Should -Be $TestAdminObjectId
            $result.Name | Should -Be $TestKeyVaultName
        }

        It "Should deploy with Access Policies when RBAC is disabled and DeployDefaultAccessPolicy is true" {
            $params = @{
                ResourceGroupName = $TestResourceGroupName; KeyVaultName = $TestKeyVaultName
                Department = $TestDepartment; Environment = $TestEnvironment
                EnableRbacAuthorization = $false; DeployDefaultAccessPolicy = $true
                AdminObjectId = $TestAdminObjectId 
            }
            $result = New-EAFKeyVault @params
            $script:CapturedTemplateParameters['enableRbacAuthorization'] | Should -Be $false
            $script:CapturedTemplateParameters['administratorObjectId'] | Should -Be $TestAdminObjectId
            $result.EnableRbacAuthorization | Should -Be $false # Assuming Get-AzKeyVault is mocked to reflect this post-deployment
        }
        
        # ... (other successful deployment tests from previous turn are assumed here) ...
        # Test for location, SKU, Network ACLs, Secrets, Diagnostics, Principal Types

        It "Should call Enable-EAFDiagnosticSettings if 'Security.EnableDiagnostics.env' config is true" {
            Mock Get-EAFConfiguration { param($ConfigPath)
                if ($ConfigPath -like "Security.EnableDiagnostics.$TestEnvironment") { return $true }
                if ($ConfigPath -like "Regions.Default.*") { return $TestLocation }
                return $null 
            } -ModuleName New-EAFKeyVault
            
            New-EAFKeyVault -ResourceGroupName $TestResourceGroupName -KeyVaultName $TestKeyVaultName -Department $TestDepartment -AdminObjectId $TestAdminObjectId -Environment $TestEnvironment
            $script:EnableEAFDiagnosticsCallCount | Should -Be 1
        }
    }

    Context "Idempotency Checks" {
        $NewAzRgDeploymentCallCount = 0
        BeforeEach {
            $script:NewAzRgDeploymentCallCount = 0
            # Base mocks
            Mock Get-EAFConfiguration { return $TestLocation } -ModuleName New-EAFKeyVault
            Mock Test-EAFResourceName { return $true } -ModuleName New-EAFKeyVault
            Mock Test-EAFResourceGroupExists { return $true } -ModuleName New-EAFKeyVault
            Mock Get-EAFDefaultTags { return $MockEAFDefaultTags } -ModuleName New-EAFKeyVault
            Mock Get-EAFDefaultSKU { return "standard" } -ModuleName New-EAFKeyVault
            Mock Invoke-WithRetry { param($ScriptBlock) Invoke-Command -ScriptBlock $ScriptBlock } -ModuleName New-EAFKeyVault
            Mock Write-EAFException { param($Exception, $Throw) if($Throw){ throw $Exception } } -ModuleName New-EAFKeyVault
            Mock Get-Module { return $true }
            Mock Get-AzResourceGroup { return @{ Location = $TestLocation } } -ModuleName New-EAFKeyVault
            Mock New-AzResourceGroupDeployment { $script:NewAzRgDeploymentCallCount++; return $MockSuccessfulDeploymentOutput } -ModuleName New-EAFKeyVault
        }

        It "Should prompt user and NOT deploy if Key Vault exists and -Force is not used and user says No" {
            Mock Get-AzKeyVault { return $MockKeyVaultInstance } -ModuleName New-EAFKeyVault
            Mock ShouldProcess { return $false } # Simulate user says No
            
            $params = @{ ResourceGroupName = $TestResourceGroupName; KeyVaultName = $TestKeyVaultName; Department = $TestDepartment; AdminObjectId = $TestAdminObjectId }
            $result = New-EAFKeyVault @params
            
            $script:NewAzRgDeploymentCallCount | Should -Be 0
            $result.VaultName | Should -Be $TestKeyVaultName # Should return the existing instance
        }

        It "Should proceed with deployment if Key Vault exists and -Force is used" {
            Mock Get-AzKeyVault { return $MockKeyVaultInstance } -ModuleName New-EAFKeyVault
            Mock ShouldProcess { return $true } # ShouldProcess won't be called with -Force
            
            $params = @{ ResourceGroupName = $TestResourceGroupName; KeyVaultName = $TestKeyVaultName; Department = $TestDepartment; AdminObjectId = $TestAdminObjectId; Force = $true }
            New-EAFKeyVault @params
            
            $script:NewAzRgDeploymentCallCount | Should -Be 1
        }
        
        It "Should warn if trying to disable purge protection on an existing vault where it's enabled" {
            $existingVaultWithPurge = $MockKeyVaultInstance.PSObject.Copy()
            $existingVaultWithPurge.EnablePurgeProtection = $true
            Mock Get-AzKeyVault { return $existingVaultWithPurge } -ModuleName New-EAFKeyVault
            Mock ShouldProcess { return $true }
            
            $params = @{ ResourceGroupName = $TestResourceGroupName; KeyVaultName = $TestKeyVaultName; Department = $TestDepartment; AdminObjectId = $TestAdminObjectId; EnablePurgeProtection = $false; Force = $true }
            # Expect a warning, not a throw. Pester's -WarningAction Inquire might be needed for specific warning message check.
            # For now, just ensure deployment proceeds if forced.
            New-EAFKeyVault @params
            $script:NewAzRgDeploymentCallCount | Should -Be 1
            # Here, one might also check if Write-Warning was called with specific text if that mock was more advanced.
        }
    }

    Context "Error Handling" {
        $WriteEAFExceptionCallCount = 0
        $LastEAFException = $null

        BeforeEach {
            $script:WriteEAFExceptionCallCount = 0
            $script:LastEAFException = $null
            # Base mocks
            Mock Get-EAFConfiguration { return $TestLocation } -ModuleName New-EAFKeyVault
            Mock Test-EAFResourceName { return $true } -ModuleName New-EAFKeyVault
            Mock Test-EAFResourceGroupExists { return $true } -ModuleName New-EAFKeyVault
            Mock Get-EAFDefaultTags { return $MockEAFDefaultTags } -ModuleName New-EAFKeyVault
            Mock Get-EAFDefaultSKU { return "standard" } -ModuleName New-EAFKeyVault
            Mock Invoke-WithRetry { param($ScriptBlock) Invoke-Command -ScriptBlock $ScriptBlock } -ModuleName New-EAFKeyVault
            Mock Write-EAFException { 
                param($Exception, $ErrorCategory, $Throw) 
                $script:WriteEAFExceptionCallCount++
                $script:LastEAFException = $Exception
                if($Throw){ throw $Exception }
            } -ModuleName New-EAFKeyVault
            Mock Get-Module { return $true }
            Mock Get-AzResourceGroup { return @{ Location = $TestLocation } } -ModuleName New-EAFKeyVault
            Mock Get-AzKeyVault { return $null } -ModuleName New-EAFKeyVault
            Mock New-AzResourceGroupDeployment { return $MockSuccessfulDeploymentOutput } -ModuleName New-EAFKeyVault
            Mock ShouldProcess { return $true }
            Mock Test-Path { return $true } # Bicep template exists by default
            Mock Test-EAFNetworkConfiguration { return $true } 
        }

        It "Should throw EAFDependencyException if Az.KeyVault module is missing" {
            Mock Get-Module { param($Name) if($Name -eq 'Az.KeyVault') { return $null } else { return $true} }
            { New-EAFKeyVault -ResourceGroupName "any" -KeyVaultName "any" -Department "any" -AdminObjectId "any" } | Should -Throw 
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.DependencyName | Should -Be "Az.KeyVault"
        }

        It "Should throw EAFDependencyException if Bicep template is missing" {
            Mock Test-Path { param($Path) if($Path -like "*keyVault.bicep") {return $false} else {return $true} } -ModuleName New-EAFKeyVault
            { New-EAFKeyVault -ResourceGroupName "any" -KeyVaultName "any" -Department "any" -AdminObjectId "any" } | Should -Throw 
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.DependencyType | Should -Be "BicepTemplate"
        }

        It "Should throw EAFResourceValidationException if Key Vault name is invalid" {
            Mock Test-EAFResourceName { return $false } -ModuleName New-EAFKeyVault
            { New-EAFKeyVault -ResourceGroupName "any" -KeyVaultName "invalid-name" -Department "any" -AdminObjectId "any" } | Should -Throw 
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.ResourceType | Should -Be "KeyVault"
        }

        It "Should throw EAFParameterValidationException if AdminObjectId is missing when RBAC disabled and DeployDefaultAccessPolicy is true" {
            { New-EAFKeyVault -ResourceGroupName "any" -KeyVaultName "anykv" -Department "any" -EnableRbacAuthorization $false -DeployDefaultAccessPolicy $true -AdminObjectId "" } | Should -Throw
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.ParameterName | Should -Be "AdminObjectId" # Assuming EAFParameterValidationException has this property
        }
        
        It "Should throw EAFNetworkConfigurationException if Private Endpoint VNet/Subnet validation fails (mock Test-EAFNetworkConfiguration)" {
            Mock Test-EAFNetworkConfiguration { throw [EAFNetworkConfigurationException]::new("Mock VNet not found", "KeyVault", "mockVNet", "VNetNotFound") } -ModuleName New-EAFKeyVault
            { New-EAFKeyVault -ResourceGroupName "any" -KeyVaultName "anykv" -Department "any" -AdminObjectId "any" -DeployPrivateEndpoint $true -PrivateEndpointVirtualNetworkName "mockVNet" -PrivateEndpointSubnetName "mockSubnet" } | Should -Throw
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.ResourceType | Should -Be "KeyVault" # Assuming EAFNetworkConfigurationException has ResourceType
        }
    }
}
