#Requires -Modules Pester -Version 5

Describe "New-EAFAppService.Unit.Tests" -Tags 'Unit', 'AppService' {
    
    # Path to the function to test and private modules
    $FunctionUnderTestPath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\Public\New-EAFAppService.ps1"
    $PrivateModulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\Private"

    # Common variables for tests
    $TestResourceGroupName = "rg-test-appservice-unit"
    $TestAppServiceName = "app-unittest-dev"
    $TestLocation = "uksouth"
    $TestDepartment = "TestDept"
    $TestEnvironment = "dev"
    $TestAppServicePlanName = "$TestAppServiceName-plan"
    $TestSkuName = "S1" # Default SKU for many tests
    $TestRuntimeStack = "dotnet" # Default Runtime
    $TestRuntimeVersion = "6.0"  # Default Runtime Version
    $TestDateCreated = Get-Date -Format "yyyy-MM-dd"
    $TestBackupSasTokenExpiryPeriod = 'P1Y' # Default for the new parameter

    $MockEAFDefaultTags = @{
        Environment = $TestEnvironment
        Department  = $TestDepartment
        CreatedDate = $TestDateCreated
        ResourceType = "AppService"
    }

    # Define a more complete mock output, especially for parameters that have outputs
    $MockSuccessfulDeploymentOutput = @{
        ProvisioningState = 'Succeeded'
        Outputs           = @{
            appInsightsInstrumentationKey = 'mock-appinsights-key'
            appServiceUrl                 = "http://${TestAppServiceName}.azurewebsites.net"
            appServiceId                  = "/subscriptions/mockSub/resourceGroups/${TestResourceGroupName}/providers/Microsoft.Web/sites/${TestAppServiceName}"
            appServicePrincipalId         = "mock-principal-id"
            deploymentSlotsEnabled        = $false # Default, will be overridden in tests
            deploymentSlots               = @()    # Default
            deploymentSlotsUrls           = @()    # Default
            autoScalingEnabled            = $false # Default
            containerDeploymentEnabled    = $false # Default
            customDomainEnabled           = $false # Default
            backupEnabled                 = $false # Default
        }
    }
    $MockAppServiceInstance = @{
        Name = $TestAppServiceName
        ResourceGroupName = $TestResourceGroupName
        Location = $TestLocation
        ServerFarmId = "/subscriptions/mockSub/resourceGroups/${TestResourceGroupName}/providers/Microsoft.Web/serverfarms/${TestAppServicePlanName}"
        HttpsOnly = $true
        State = "Running"
        # Add other properties as needed by the function's output construction
    }


    BeforeAll {
        . $FunctionUnderTestPath
        
        $helperModuleFiles = @(
            "exceptions.psm1", "retry-logic.psm1", "validation-helpers.psm1",
            "configuration-helpers.psm1", "monitoring-helpers.psm1"
        )
        # Mocking functions from these conceptual modules will be done in BeforeEach/It blocks
    }

    Context "Successful Deployments" {
        $CapturedTemplateParameters = $null
        $CapturedTemplateFile = $null
        $NewAzRgDeploymentCallCount = 0

        BeforeEach {
            $script:NewAzRgDeploymentCallCount = 0
            $script:CapturedTemplateParameters = $null
            $script:CapturedTemplateFile = $null

            Mock Get-EAFConfiguration { param($ConfigPath) 
                if ($ConfigPath -like "Regions.Default.*") { return $TestLocation }
                return $null # Default for other configs
            } -ModuleName New-EAFAppService
            Mock Test-EAFResourceName { return $true } -ModuleName New-EAFAppService
            Mock Test-EAFResourceGroupExists { return $true } -ModuleName New-EAFAppService
            Mock Get-EAFDefaultTags { return $MockEAFDefaultTags } -ModuleName New-EAFAppService
            Mock Get-EAFDefaultSKU { return $TestSkuName } -ModuleName New-EAFAppService
            Mock Invoke-WithRetry { param($ScriptBlock, $MaxRetryCount, $ActivityName) Invoke-Command -ScriptBlock $ScriptBlock } -ModuleName New-EAFAppService
            Mock Write-EAFException { param($Exception, $ErrorCategory, $Throw) Write-Warning "Mock Write-EAFException: $($Exception.Message)"; if($Throw){ throw $Exception } } -ModuleName New-EAFAppService
            
            Mock Get-Module { return $true } 
            Mock Get-AzResourceGroup { return @{ Location = $TestLocation } } -ModuleName New-EAFAppService
            Mock Get-AzWebApp { return $null } -ModuleName New-EAFAppService
            Mock New-AzResourceGroupDeployment {
                param($ResourceGroupName, $Name, $TemplateFile, $TemplateParameterObject, $Verbose, $ErrorAction)
                $script:CapturedTemplateFile = $TemplateFile
                $script:CapturedTemplateParameters = $TemplateParameterObject
                $script:NewAzRgDeploymentCallCount++
                # Return a copy of the mock output to avoid modification issues if tests alter it
                return $script:CurrentMockDeploymentOutput | ConvertTo-Json | ConvertFrom-Json 
            } -ModuleName New-EAFAppService
            Mock Get-AzStorageAccount { 
                return @{ Name = "mockbackupstorage"; ResourceGroupName = $TestResourceGroupName } 
            } -ModuleName New-EAFAppService

            Mock ShouldProcess { return $true } 
            $script:CurrentMockDeploymentOutput = $MockSuccessfulDeploymentOutput # Default mock output
        }

        It "Should deploy successfully with minimal mandatory parameters" {
            $params = @{
                ResourceGroupName = $TestResourceGroupName
                AppServiceName    = $TestAppServiceName
                Department        = $TestDepartment
                Environment       = $TestEnvironment
            }
            $result = New-EAFAppService @params

            $script:NewAzRgDeploymentCallCount | Should -Be 1
            $script:CapturedTemplateFile | Should -BeLike "*\Templates\appService.bicep"
            $script:CapturedTemplateParameters['appServiceName'] | Should -Be $TestAppServiceName
            $script:CapturedTemplateParameters['location'] | Should -Be $TestLocation
            $script:CapturedTemplateParameters['skuName'] | Should -Be $TestSkuName
            $result.Name | Should -Be $TestAppServiceName
        }

        It "Should use Location from Get-EAFConfiguration if -Location is not provided and config returns a value" {
            Mock Get-EAFConfiguration { param($ConfigPath) if ($ConfigPath -like "Regions.Default.*") { return "eastus" } } -ModuleName New-EAFAppService
            New-EAFAppService -ResourceGroupName $TestResourceGroupName -AppServiceName $TestAppServiceName -Department $TestDepartment -Environment $TestEnvironment
            $script:CapturedTemplateParameters['location'] | Should -Be "eastus"
        }

        It "Should use SkuName from Get-EAFDefaultSKU if -SkuName is not provided (or is default S1) and config returns a value" {
            Mock Get-EAFDefaultSKU { return "P1v2" } -ModuleName New-EAFAppService
             New-EAFAppService -ResourceGroupName $TestResourceGroupName -AppServiceName $TestAppServiceName -Department $TestDepartment -Environment $TestEnvironment
            $script:CapturedTemplateParameters['skuName'] | Should -Be "P1v2"
        }
        
        It "Should correctly pass SkuName if specified and not default S1" {
            New-EAFAppService -ResourceGroupName $TestResourceGroupName -AppServiceName $TestAppServiceName -Department $TestDepartment -Environment $TestEnvironment -SkuName "B1"
            $script:CapturedTemplateParameters['skuName'] | Should -Be "B1"
        }

        It "Should correctly pass Backup parameters including SasTokenExpiryPeriod" {
            $script:CurrentMockDeploymentOutput = $MockSuccessfulDeploymentOutput.PSObject.Copy()
            $script:CurrentMockDeploymentOutput.Outputs.backupEnabled = $true

            $backupParams = @{
                ResourceGroupName          = $TestResourceGroupName
                AppServiceName             = $TestAppServiceName
                Department                 = $TestDepartment
                Environment                = $TestEnvironment
                EnableBackup               = $true
                BackupStorageAccountName   = "backupstorageacct"
                BackupStorageContainerName = "mybackupcontainer"
                BackupSchedule             = "0 1 * * *" 
                BackupRetentionPeriodDays  = 60
                BackupSasTokenExpiryPeriod = "P60D"
            }
            New-EAFAppService @backupParams

            $script:CapturedTemplateParameters['enableBackup'] | Should -Be $true
            $script:CapturedTemplateParameters['backupStorageAccountName'] | Should -Be "backupstorageacct"
            $script:CapturedTemplateParameters['backupSasTokenExpiryPeriod'] | Should -Be "P60D"
        }

        It "Should correctly pass Container Deployment parameters" {
            $script:CurrentMockDeploymentOutput = $MockSuccessfulDeploymentOutput.PSObject.Copy()
            $script:CurrentMockDeploymentOutput.Outputs.containerDeploymentEnabled = $true
            $containerPassword = ConvertTo-SecureString "TestPassword123!" -AsPlainText -Force
            $containerParams = @{
                ResourceGroupName           = $TestResourceGroupName
                AppServiceName              = $TestAppServiceName
                Department                  = $TestDepartment
                Environment                 = $TestEnvironment
                EnableContainerDeployment   = $true
                ContainerRegistryServer     = "myacr.azurecr.io"
                ContainerRegistryUsername   = "acruser"
                ContainerRegistryPassword   = $containerPassword
                ContainerImageAndTag        = "myimage:latest"
            }
            New-EAFAppService @containerParams

            $script:CapturedTemplateParameters['enableContainerDeployment'] | Should -Be $true
            $script:CapturedTemplateParameters['containerRegistryServer'] | Should -Be "myacr.azurecr.io"
            $script:CapturedTemplateParameters['containerRegistryPassword'] | Should -Be "TestPassword123!" 
        }

        It "Should enable Deployment Slots correctly" {
            $script:CurrentMockDeploymentOutput = $MockSuccessfulDeploymentOutput.PSObject.Copy()
            $script:CurrentMockDeploymentOutput.Outputs.deploymentSlotsEnabled = $true
            $script:CurrentMockDeploymentOutput.Outputs.deploymentSlots = @("staging", "dev")
            $script:CurrentMockDeploymentOutput.Outputs.deploymentSlotsUrls = @("http://slot1-url", "http://slot2-url")


            $slotParams = @{
                ResourceGroupName     = $TestResourceGroupName
                AppServiceName        = $TestAppServiceName
                Department            = $TestDepartment
                Environment           = $TestEnvironment
                EnableDeploymentSlots = $true
                DeploymentSlotsCount  = 2
                DeploymentSlotNames   = @("staging", "dev")
                EnableAutoSwap        = $true # Requires 'staging' slot
            }
            New-EAFAppService @slotParams

            $script:CapturedTemplateParameters['enableDeploymentSlots'] | Should -Be $true
            $script:CapturedTemplateParameters['deploymentSlotsCount'] | Should -Be 2
            $script:CapturedTemplateParameters['deploymentSlotNames'] | Should -BeOfType ([string[]]) | Should -BeExactly @("staging", "dev")
            $script:CapturedTemplateParameters['enableAutoSwap'] | Should -Be $true
        }

        It "Should enable Auto-Scale correctly" {
            $script:CurrentMockDeploymentOutput = $MockSuccessfulDeploymentOutput.PSObject.Copy()
            $script:CurrentMockDeploymentOutput.Outputs.autoScalingEnabled = $true

            $autoScaleParams = @{
                ResourceGroupName             = $TestResourceGroupName
                AppServiceName                = $TestAppServiceName
                Department                    = $TestDepartment
                Environment                   = $TestEnvironment
                EnableAutoScale               = $true
                AutoScaleMinInstanceCount     = 2
                AutoScaleMaxInstanceCount     = 6
                AutoScaleDefaultInstanceCount = 3
                CpuPercentageScaleOut         = 75
                CpuPercentageScaleIn          = 25
            }
            New-EAFAppService @autoScaleParams

            $script:CapturedTemplateParameters['enableAutoScale'] | Should -Be $true
            $script:CapturedTemplateParameters['autoScaleMinInstanceCount'] | Should -Be 2
            $script:CapturedTemplateParameters['autoScaleMaxInstanceCount'] | Should -Be 6
        }

        It "Should enable Custom Domain correctly" {
            $script:CurrentMockDeploymentOutput = $MockSuccessfulDeploymentOutput.PSObject.Copy()
            $script:CurrentMockDeploymentOutput.Outputs.customDomainEnabled = $true

            $customDomainParams = @{
                ResourceGroupName        = $TestResourceGroupName
                AppServiceName           = $TestAppServiceName
                Department               = $TestDepartment
                Environment              = $TestEnvironment
                EnableCustomDomain       = $true
                CustomDomainName         = "www.testdomain.com"
                EnableSslBinding         = $true
                SslCertificateThumbprint = "TESTTHUMBPRINT123"
            }
            New-EAFAppService @customDomainParams

            $script:CapturedTemplateParameters['enableCustomDomain'] | Should -Be $true
            $script:CapturedTemplateParameters['customDomainName'] | Should -Be "www.testdomain.com"
            $script:CapturedTemplateParameters['sslCertificateThumbprint'] | Should -Be "TESTTHUMBPRINT123"
        }
    }

    Context "Idempotency Checks" {
        $CapturedTemplateParameters = $null
        $NewAzRgDeploymentCallCount = 0

        BeforeEach {
            $script:NewAzRgDeploymentCallCount = 0
            $script:CapturedTemplateParameters = $null
            # Base mocks, Get-AzWebApp will be overridden
            Mock Get-EAFConfiguration { param($ConfigPath) if ($ConfigPath -like "Regions.Default.*") { return $TestLocation } } -ModuleName New-EAFAppService
            Mock Test-EAFResourceName { return $true } -ModuleName New-EAFAppService
            Mock Test-EAFResourceGroupExists { return $true } -ModuleName New-EAFAppService
            Mock Get-EAFDefaultTags { return $MockEAFDefaultTags } -ModuleName New-EAFAppService
            Mock Get-EAFDefaultSKU { return $TestSkuName } -ModuleName New-EAFAppService
            Mock Invoke-WithRetry { param($ScriptBlock, $MaxRetryCount, $ActivityName) Invoke-Command -ScriptBlock $ScriptBlock } -ModuleName New-EAFAppService
            Mock Write-EAFException { param($Exception, $ErrorCategory, $Throw) Write-Warning "Mock Write-EAFException: $($Exception.Message)"; if($Throw){ throw $Exception } } -ModuleName New-EAFAppService
            Mock Get-Module { return $true }
            Mock Get-AzResourceGroup { return @{ Location = $TestLocation } } -ModuleName New-EAFAppService
            Mock New-AzResourceGroupDeployment { $script:NewAzRgDeploymentCallCount++; return $MockSuccessfulDeploymentOutput } -ModuleName New-EAFAppService
            $script:CurrentMockDeploymentOutput = $MockSuccessfulDeploymentOutput 
        }

        It "Should prompt user and NOT deploy if App Service exists and -Force is not used and user says No" {
            Mock Get-AzWebApp { return $MockAppServiceInstance } -ModuleName New-EAFAppService
            Mock ShouldProcess { Write-Host "Mock ShouldProcess called"; return $false } # Simulate user says No
            
            $params = @{
                ResourceGroupName = $TestResourceGroupName
                AppServiceName    = $TestAppServiceName
                Department        = $TestDepartment
                Environment       = $TestEnvironment
            }
            $result = New-EAFAppService @params
            
            $script:NewAzRgDeploymentCallCount | Should -Be 0
            $result.Name | Should -Be $TestAppServiceName # Should return the existing instance
        }

        It "Should proceed with deployment if App Service exists and -Force is used" {
            Mock Get-AzWebApp { return $MockAppServiceInstance } -ModuleName New-EAFAppService
            Mock ShouldProcess { return $true } # ShouldProcess won't be called if -Force is true, but set for safety
            
            $params = @{
                ResourceGroupName = $TestResourceGroupName
                AppServiceName    = $TestAppServiceName
                Department        = $TestDepartment
                Environment       = $TestEnvironment
                Force             = $true
            }
            New-EAFAppService @params
            
            $script:NewAzRgDeploymentCallCount | Should -Be 1
        }

        It "Should proceed with deployment if App Service exists and user confirms via ShouldProcess" {
            Mock Get-AzWebApp { return $MockAppServiceInstance } -ModuleName New-EAFAppService
            Mock ShouldProcess { Write-Host "Mock ShouldProcess called, returning true"; return $true } # Simulate user says Yes
            
            $params = @{
                ResourceGroupName = $TestResourceGroupName
                AppServiceName    = $TestAppServiceName
                Department        = $TestDepartment
                Environment       = $TestEnvironment
            }
            New-EAFAppService @params
            
            $script:NewAzRgDeploymentCallCount | Should -Be 1
        }
    }

    Context "Error Handling" {
        $WriteEAFExceptionCallCount = 0
        $LastEAFException = $null

        BeforeEach {
            $script:WriteEAFExceptionCallCount = 0
            $script:LastEAFException = $null
            # Base mocks, specific mocks will be overridden per test
            Mock Get-EAFConfiguration { return $TestLocation } -ModuleName New-EAFAppService
            Mock Test-EAFResourceName { return $true } -ModuleName New-EAFAppService
            Mock Test-EAFResourceGroupExists { return $true } -ModuleName New-EAFAppService
            Mock Get-EAFDefaultTags { return $MockEAFDefaultTags } -ModuleName New-EAFAppService
            Mock Get-EAFDefaultSKU { return $TestSkuName } -ModuleName New-EAFAppService
            Mock Invoke-WithRetry { param($ScriptBlock) Invoke-Command -ScriptBlock $ScriptBlock } -ModuleName New-EAFAppService
            Mock Write-EAFException { 
                param($Exception, $ErrorCategory, $Throw) 
                $script:WriteEAFExceptionCallCount++
                $script:LastEAFException = $Exception
                Write-Warning "Mock Write-EAFException: $($Exception.Message)"
                if($Throw){ throw $Exception }
            } -ModuleName New-EAFAppService
            Mock Get-Module { return $true }
            Mock Get-AzResourceGroup { return @{ Location = $TestLocation } } -ModuleName New-EAFAppService
            Mock Get-AzWebApp { return $null } -ModuleName New-EAFAppService
            Mock New-AzResourceGroupDeployment { return $MockSuccessfulDeploymentOutput } -ModuleName New-EAFAppService
            Mock ShouldProcess { return $true }
            Mock Test-Path { return $true } # Assume Bicep template path exists by default
            Mock Get-AzStorageAccount { return @{ Name = "mockbackupstorage"} } -ModuleName New-EAFAppService
        }

        It "Should throw EAFDependencyException if Az.Websites module is missing" {
            Mock Get-Module { param($Name) if($Name -eq 'Az.Websites') { return $null } else { return $true} }
            { New-EAFAppService -ResourceGroupName "any" -AppServiceName "any" -Department "any" } | Should -Throw #-ExceptionType ([EAFDependencyException]) # Pester 5 specific type assertion
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.DependencyName | Should -Be "Az.Websites"
        }

        It "Should throw EAFDependencyException if Bicep template is missing" {
            Mock Test-Path { param($Path) if($Path -like "*appService.bicep") {return $false} else {return $true} } -ModuleName New-EAFAppService
            { New-EAFAppService -ResourceGroupName "any" -AppServiceName "any" -Department "any" } | Should -Throw
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.DependencyType | Should -Be "BicepTemplate"
        }

        It "Should throw EAFResourceValidationException if App Service name is invalid" {
            Mock Test-EAFResourceName { return $false } -ModuleName New-EAFAppService
            { New-EAFAppService -ResourceGroupName "any" -AppServiceName "invalid-name" -Department "any" } | Should -Throw
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.ResourceType | Should -Be "AppService"
        }

        It "Should throw if Resource Group does not exist (via Test-EAFResourceGroupExists)" {
            Mock Test-EAFResourceGroupExists { throw [EAFResourceNotFoundException]::new("Mock RG not found", "ResourceGroup", "TestRG", "NonExistent") } -ModuleName New-EAFAppService
            { New-EAFAppService -ResourceGroupName "NonExistentRG" -AppServiceName "any" -Department "any" } | Should -Throw
            $script:WriteEAFExceptionCallCount | Should -BeGreaterThan 0
            $script:LastEAFException.ErrorId | Should -BeLike "*ResourceNotFoundException*" # Check ErrorId or type
        }
        
        It "Should throw if EnableContainerDeployment is true and ContainerRegistryServer is missing" {
            { New-EAFAppService -ResourceGroupName "any" -AppServiceName "any" -Department "any" -EnableContainerDeployment $true -ContainerRegistryServer "" } | Should -Throw "ContainerRegistryServer is required when EnableContainerDeployment is true."
            # No need to check Write-EAFException here as it's a direct throw from the function
        }

        It "Should throw if EnableBackup is true and BackupStorageAccountName is missing" {
            { New-EAFAppService -ResourceGroupName "any" -AppServiceName "any" -Department "any" -EnableBackup $true -BackupStorageAccountName "" } | Should -Throw "BackupStorageAccountName is required when EnableBackup is true."
        }

        It "Should throw (or warn and proceed depending on exact logic) if BackupStorageAccountName for backup does not exist" {
            Mock Get-AzStorageAccount { param($ResourceGroupName, $Name) return $null } -ModuleName New-EAFAppService
            # The function currently Write-Warning. If it should throw, the test needs to reflect that.
            # For now, we'll just ensure it's called. A more robust test would check for the warning.
            New-EAFAppService -ResourceGroupName "any" -AppServiceName "any" -Department "any" -EnableBackup $true -BackupStorageAccountName "nonexiststorage"
            # To assert a warning: In Pester 5, you might need to use -WarningAction Inquire then check $WarningPreference
            # This test might need adjustment based on desired behavior (throw vs. warn).
            # For now, ensuring no UNEXPECTED throw is the primary goal.
            # If it's meant to throw, the above { } | Should -Throw would be used.
        }
    }
}
