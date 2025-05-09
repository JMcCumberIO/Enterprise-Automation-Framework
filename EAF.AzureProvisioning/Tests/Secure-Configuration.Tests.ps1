# Unit Tests for Secure Configuration Module

Describe "Secure Configuration Tests" {
    BeforeAll {
        # Import required modules
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\Private\secure-configuration-helpers.psm1"
        Import-Module -Name $modulePath -Force
        
        # Define test variables
        $script:testConfigPath = "Test.SecureConfiguration"
        $script:testPassword = "Test$ecureP@ssw0rd!"
        $script:testSecureString = ConvertTo-SecureString -String $script:testPassword -AsPlainText -Force
    }
    
    AfterAll {
        # Clean up any test data
        Get-ChildItem -Path "Variable:script:*" | Remove-Variable -Scope Script
        
        # Remove the module
        Remove-Module -Name "secure-configuration-helpers" -ErrorAction SilentlyContinue
    }
    
    Context "Memory-based secure storage" {
        BeforeEach {
            # Store a test configuration
            Set-EAFSecureConfiguration -ConfigPath $script:testConfigPath -SecureValue $script:testSecureString -Force
        }
        
        AfterEach {
            # Remove test configuration
            Remove-EAFSecureConfiguration -ConfigPath $script:testConfigPath
        }
        
        It "Should store secure values in memory" {
            # Act
            $result = Test-EAFSecureConfiguration -ConfigPath $script:testConfigPath
            
            # Assert
            $result | Should -BeTrue
        }
        
        It "Should retrieve secure values correctly" {
            # Act
            $retrieved = Get-EAFSecureConfiguration -ConfigPath $script:testConfigPath
            $plaintext = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($retrieved)
            )
            
            # Assert
            $plaintext | Should -Be $script:testPassword
        }
        
        It "Should retrieve secure values as plaintext when requested" {
            # Act
            $plaintext = Get-EAFSecureConfiguration -ConfigPath $script:testConfigPath -AsPlainText
            
            # Assert
            $plaintext | Should -Be $script:testPassword
        }
        
        It "Should not store the actual plaintext value" {
            # Arrange & Act
            $storeRef = Get-Variable -Name "script:SecureConfigStore" -ValueOnly
            $storedObj = $storeRef[$script:testConfigPath]
            
            # Assert
            $storedObj.Type | Should -Be "Memory"
            $storedObj | Should -Not -BeNullOrEmpty
            $storedObj.PSObject.Properties.Name | Should -Contain "Value"
            $storedObj.Value | Should -Not -Be $script:testPassword
        }
        
        It "Should remove secure values when requested" {
            # Act
            $removeResult = Remove-EAFSecureConfiguration -ConfigPath $script:testConfigPath
            $existsResult = Test-EAFSecureConfiguration -ConfigPath $script:testConfigPath
            
            # Assert
            $removeResult | Should -BeTrue
            $existsResult | Should -BeFalse
        }
    }
    
    Context "Error handling" {
        It "Should return false when testing non-existent configuration" {
            # Act
            $result = Test-EAFSecureConfiguration -ConfigPath "NonExistent.Configuration"
            
            # Assert
            $result | Should -BeFalse
        }
        
        It "Should throw when getting non-existent configuration" {
            # Act & Assert
            { Get-EAFSecureConfiguration -ConfigPath "NonExistent.Configuration" } | Should -Throw
        }
        
        It "Should return false when removing non-existent configuration" {
            # Act
            $result = Remove-EAFSecureConfiguration -ConfigPath "NonExistent.Configuration"
            
            # Assert
            $result | Should -BeFalse
        }
        
        It "Should validate inputs properly" {
            # Arrange
            $emptyPath = ""
            $nullSecure = $null
            
            # Act & Assert
            { Set-EAFSecureConfiguration -ConfigPath $emptyPath -SecureValue $script:testSecureString } | Should -Throw
            { Set-EAFSecureConfiguration -ConfigPath $script:testConfigPath -SecureValue $nullSecure } | Should -Throw
        }
    }
    
    Context "Security features" {
        BeforeEach {
            Set-EAFSecureConfiguration -ConfigPath $script:testConfigPath -SecureValue $script:testSecureString -Force
        }
        
        AfterEach {
            Remove-EAFSecureConfiguration -ConfigPath $script:testConfigPath
        }
        
        It "Should not expose secure values in typical PowerShell output" {
            # Act
            $configStore = Get-Variable -Name "script:SecureConfigStore" -ValueOnly
            $configValue = $configStore[$script:testConfigPath]
            $configOutput = $configValue | Format-List | Out-String
            
            # Assert
            $configOutput | Should -Not -Match $script:testPassword
        }
        
        It "Should use a copy of the secure string" {
            # Act
            $retrieved = Get-EAFSecureConfiguration -ConfigPath $script:testConfigPath
            
            # Assert
            $retrieved | Should -Not -Be $script:testSecureString # Different objects
            [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($retrieved)) | 
                Should -Be $script:testPassword # But same content
        }
    }
}

AFSecureConfiguration -ConfigPath "" `
                -SecureValue $script:testSecureString } | Should -Throw

            { Set-EAFSecureConfiguration -ConfigPath $script:testConfigPath `
                -SecureValue $null } | Should -Throw
        }

        It "Should handle operation timeouts" {
            # Arrange - Mock Set-AzKeyVaultSecret to simulate timeout
            Mock Set-AzKeyVaultSecret -ModuleName "Az.KeyVault.Mocks" {
                Start-Sleep -Seconds 5
                throw "Operation timed out"
            }

            # Act & Assert
            { Set-EAFSecureConfiguration -ConfigPath $script:testConfigPath `
                -SecureValue $script:testSecureString `
                -KeyVaultName $script:testKeyVaultName } | Should -Throw
        }

        It "Should handle concurrent access" {
            # Arrange
            $jobs = 1..3 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($Path, $Value, $VaultName)
                    Set-EAFSecureConfiguration -ConfigPath $Path -SecureValue $Value -KeyVaultName $VaultName
                } -ArgumentList $script:testConfigPath, $script:testSecureString, $script:testKeyVaultName
            }

            # Act & Assert
            { $jobs | Wait-Job | Receive-Job } | Should -Not -Throw
        }
    }
}
