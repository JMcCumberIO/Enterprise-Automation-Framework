#Requires -Modules Pester -Version 5
#Requires -Modules Az.Accounts, Az.Resources, Az.Websites, Az.ApplicationInsights # Key Az Modules for these tests

<#
    .SYNOPSIS
        True Integration Tests for New-EAFAppService.ps1.
    .DESCRIPTION
        These tests deploy actual Azure resources to validate the New-EAFAppService cmdlet.
        They will incur Azure costs and take time to run.
        Ensure you are logged into an appropriate Azure account before running.
    .NOTES
        Test Naming Convention: New-EAFAppService.Integration.Tests.ps1
        Requires EAF.AzureProvisioning module to be available.
#>

# Ensure the module is imported. Adjust path as necessary if running from a different location.
# This assumes the test is run from a context where module auto-loading or explicit import has handled EAF.AzureProvisioning.
# For explicit import if needed:
# Import-Module (Join-Path $PSScriptRoot '..\..\EAF.AzureProvisioning.psd1') -Force

Describe "New-EAFAppService True Integration Tests" -Tags 'Integration', 'AppService', 'AzureLive' {

    # Test Configuration - Azure Connection and Resource Naming
    # Ensure you are logged into Azure: Connect-AzAccount
    # Select appropriate subscription if necessary: Set-AzContext -SubscriptionId "your-subscription-id"

    $timestamp = Get-Date -Format 'yyyyMMddHHmmssfff'
    $uniqueId = $timestamp.Substring($timestamp.Length - 8) # Shorter unique ID for some resource names

    # Variables for resources
    $baseName = "eafintappsvc${uniqueId}" # Base for uniqueness
    $resourceGroupName = "rg-${baseName}"
    $location = "uksouth" # Or a location from Get-AzLocation | Select-Object -First 1 -ExpandProperty Location

    $appServiceName = "app-${baseName}"
    $appServicePlanName = "asp-${baseName}"
    # App Insights and Log Analytics names are often derived within the Bicep/cmdlet,
    # but we might need to predict them for Get- cmdlets if not returned by New-EAFAppService.
    # For now, we'll rely on the output of New-EAFAppService or construct them if needed.

    $commonTestParams = @{
        ResourceGroupName = $resourceGroupName
        AppServiceName    = $appServiceName
        Location          = $location
        Department        = "IntegrationTest"
        Environment       = "dev" # Keep environment consistent for naming/tagging
        # Other common parameters can be added here
    }

    BeforeAll {
        Write-Host "INFO: Starting BeforeAll - Ensuring Azure connection and creating Resource Group..."
        
        # Ensure Azure Connection (conceptual - actual login should be pre-requisite)
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (-not $context) {
            throw "Azure login required. Please run Connect-AzAccount."
        }
        Write-Host "INFO: Connected to Azure subscription '$($context.Subscription.Name)' ($($context.Subscription.Id))"

        Write-Host "INFO: Creating unique Resource Group: $resourceGroupName in $location"
        New-AzResourceGroup -Name $resourceGroupName -Location $location -Force -ErrorAction Stop | Out-Null
        Write-Host "INFO: Resource Group $resourceGroupName created."
    }

    AfterAll {
        Write-Host "INFO: Starting AfterAll - Cleaning up Resource Group: $resourceGroupName"
        # Consider adding a delay or loop to wait for job completion if necessary
        Remove-AzResourceGroup -Name $resourceGroupName -Force -AsJob -ErrorAction SilentlyContinue
        Write-Host "INFO: Resource Group $resourceGroupName deletion initiated as a background job."
        Write-Host "WARN: Monitor Azure to ensure the resource group '$resourceGroupName' is deleted to avoid orphaned resources and costs."
    }

    Context "Basic App Service Deployment" {
        It "Should deploy a basic App Service with correct properties and tags" {
            $currentAppServiceName = "${appServiceName}-basic"
            $basicTestParams = @{
                AppServiceName = $currentAppServiceName
                SkuName        = "B1" # Smallest practical SKU for testing
                RuntimeStack   = "dotnet"
                RuntimeVersion = "6.0" # A common, stable runtime
            } + $commonTestParams # Merge with common parameters

            Write-Host "INFO: Deploying basic App Service '$currentAppServiceName'..."
            $appServiceOutput = New-EAFAppService @basicTestParams -ErrorAction Stop
            
            $appServiceOutput | Should -Not -BeNull
            $appServiceOutput.Name | Should -Be $currentAppServiceName
            $appServiceOutput.ResourceGroupName | Should -Be $resourceGroupName
            $appServiceOutput.Location | Should -Be $location
            $appServiceOutput.URL | Should -Not -BeNullOrEmpty

            # Retrieve and validate deployed resources
            $deployedApp = Get-AzWebApp -ResourceGroupName $resourceGroupName -Name $currentAppServiceName -ErrorAction SilentlyContinue
            $deployedApp | Should -Not -BeNull "App Service '$currentAppServiceName' was not found after deployment."
            $deployedApp.Name | Should -Be $currentAppServiceName
            $deployedApp.Location | Should -Be $location
            $deployedApp.SiteConfig.NetFrameworkVersion | Should -Match "v6.0" # Or specific check for runtime
            $deployedApp.HttpsOnly | Should -Be $true # Default in EAF
            $deployedApp.SiteConfig.MinTlsVersion | Should -Be "1.2" # Default in EAF

            $deployedPlanName = $deployedApp.ServerFarmId.Split('/')[-1]
            $deployedPlan = Get-AzAppServicePlan -ResourceGroupName $resourceGroupName -Name $deployedPlanName -ErrorAction SilentlyContinue
            $deployedPlan | Should -Not -BeNull "App Service Plan '$deployedPlanName' was not found."
            $deployedPlan.Sku.Name | Should -Be "B1"
            $deployedPlan.Sku.Tier | Should -Be "Basic" # Tier corresponding to B1

            # Verify App Insights (assuming name is predictable or in output)
            # $appInsightsName = $appServiceOutput.AppInsightsName # If output object contains it
            # If not, construct as Bicep does: "${currentAppServiceName}-insights"
            $expectedAppInsightsName = "${currentAppServiceName}-insights" 
            $appInsights = Get-AzApplicationInsights -ResourceGroupName $resourceGroupName -Name $expectedAppInsightsName -ErrorAction SilentlyContinue
            $appInsights | Should -Not -BeNull "Application Insights instance '$expectedAppInsightsName' not found."
            $appInsights.ApplicationType | Should -Be "web"

            # Verify Tags
            $eafTags = @{
                Environment  = $commonTestParams.Environment
                Department   = $commonTestParams.Department
                ResourceType = "AppService" 
                # CreatedDate can vary slightly, so might not be exact to check here unless captured precisely
            }
            $deployedApp.Tags.Keys | Should -Contain ($eafTags.Keys | ForEach-Object { $_ })
            $deployedApp.Tags['Environment'] | Should -Be $commonTestParams.Environment
            $deployedApp.Tags['Department'] | Should -Be $commonTestParams.Department

            $deployedPlan.Tags.Keys | Should -Contain ($eafTags.Keys | ForEach-Object { $_ })
            $deployedPlan.Tags['Environment'] | Should -Be $commonTestParams.Environment
        }
    }

    Context "App Service with Deployment Slots" {
        It "Should deploy an App Service with a staging slot" {
            # Define parameters including EnableDeploymentSlots = $true, DeploymentSlotNames = @('staging')
            # $slotTestParams = @{ ... } + $commonTestParams
            # $slotTestParams.AppServiceName = "${appServiceName}-slots"
            # $slotTestParams.EnableDeploymentSlots = $true
            # $slotTestParams.DeploymentSlotNames = @('staging')
            
            # Write-Host "INFO: Deploying App Service with slots '$($slotTestParams.AppServiceName)'..."
            # $slotAppOutput = New-EAFAppService @slotTestParams -ErrorAction Stop
            
            # $slotAppOutput | Should -Not -BeNull
            # $slotAppOutput.DeploymentSlotsEnabled | Should -Be $true
            # $slotAppOutput.DeploymentSlots | Should -Contain 'staging'

            # $deployedSlot = Get-AzWebAppSlot -ResourceGroupName $resourceGroupName -Name $slotTestParams.AppServiceName -Slot 'staging' -ErrorAction SilentlyContinue
            # $deployedSlot | Should -Not -BeNull "Staging slot was not found."
            # $deployedSlot.Name | Should -Be 'staging' # The slot name part
            
            Write-Host "TODO: Test for App Service with Deployment Slots needs to be fully implemented."
            Skip "Test for App Service with Deployment Slots not yet fully implemented."
        }
    }

    Context "App Service - Container Deployment" {
        It "Should deploy an App Service from a public container image" {
            # Define parameters for container deployment
            # $containerTestParams = @{ ... } + $commonTestParams
            # $containerTestParams.AppServiceName = "${appServiceName}-container"
            # $containerTestParams.EnableContainerDeployment = $true
            # $containerTestParams.RuntimeStack = '' # Bicep might need this empty or specific value for containers
            # $containerTestParams.ContainerImageAndTag = "mcr.microsoft.com/azuredocs/aci-helloworld:latest" 
            # # No ContainerRegistryServer, Username, Password for public Docker Hub / MCR images usually

            # Write-Host "INFO: Deploying App Service from container '$($containerTestParams.AppServiceName)'..."
            # $containerAppOutput = New-EAFAppService @containerTestParams -ErrorAction Stop

            # $containerAppOutput | Should -Not -BeNull
            # $containerAppOutput.ContainerDeploymentEnabled | Should -Be $true

            # $deployedContainerApp = Get-AzWebApp -ResourceGroupName $resourceGroupName -Name $containerTestParams.AppServiceName
            # $deployedContainerApp.SiteConfig.LinuxFxVersion | Should -Match "DOCKER\|mcr.microsoft.com/azuredocs/aci-helloworld:latest"
            # $deployedContainerApp.Kind | Should -Match "linux" # Container apps are usually Linux

            Write-Host "TODO: Test for App Service with Container Deployment needs to be fully implemented."
            Skip "Test for App Service with Container Deployment not yet fully implemented."
        }
    }

    # --- Placeholder for Further Tests ---
    # Context "App Service with AutoScale" { ... }
    # Context "App Service with Backups" { ... }
    # Context "App Service with Different Runtimes (Node, Python, etc.)" { ... }
    # Context "App Service with Custom Domain and SSL" { ... }
    # Context "App Service Network Integration (VNet, Private Endpoint)" { ... }

    # Note on Error Handling:
    # Individual 'It' blocks use '-ErrorAction Stop' on the 'New-EAFAppService' cmdlet.
    # Pester will catch any terminating errors from this, failing the specific test.
    # The 'AfterAll' block for resource group cleanup is designed to run even if tests within 'Context' blocks fail.
}
