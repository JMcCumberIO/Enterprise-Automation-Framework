#Requires -Version 7.0

# EAF.AzureProvisioning module loader
# Enhanced module loading with detailed function validation and explicit exports

Write-Verbose "=== Starting EAF.AzureProvisioning module initialization ==="
Write-Verbose ("Module root path: " + $PSScriptRoot)

# Initialize collections to track functions
$script:PublicFunctions = @()
$script:PrivateFunctions = @()
$script:FailedImports = @()

# Define paths
$PublicFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "Public"
$PrivateFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "Private"

Write-Verbose ("Public folder path: " + $PublicFolderPath)
Write-Verbose ("Private folder path: " + $PrivateFolderPath)

# Helper function to import PS1 files
function Import-PSFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Type
    )
    
    try {
        Write-Verbose ("  Importing " + $Type + " function from: " + $FilePath)
        . $FilePath
        
        # Extract the function name from the file name
        $functionName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        
        # Verify the function was actually loaded
        $functionLoaded = Get-Command -Name $functionName -ErrorAction SilentlyContinue
        
        if ($functionLoaded) {
            Write-Verbose ("  Successfully loaded function: " + $functionName)
            return $functionName
        } else {
            Write-Warning ("  Function " + $functionName + " not found after dot-sourcing file. Check file content.")
            $script:FailedImports += ("Function " + $functionName + " not loaded from " + $FilePath)
            return $null
        }
    }
    catch {
        Write-Error ("  Failed to import " + $Type + " function " + $FilePath + ". Error: " + ${_}.Exception.Message)
        $script:FailedImports += ("Error loading " + $FilePath + ": " + ${_}.Exception.Message)
        return $null
    }
}

# 1. Load public functions
Write-Verbose "Searching for public functions..."
if (Test-Path -Path $PublicFolderPath) {
    $publicFiles = Get-ChildItem -Path $PublicFolderPath -Filter "*.ps1" -File
    Write-Verbose ("Found " + $publicFiles.Count + " public function files")
    
    foreach ($file in $publicFiles) {
        $functionName = Import-PSFile -FilePath $file.FullName -Type "Public"
        if ($functionName) {
            $script:PublicFunctions += $functionName
        }
    }
} else {
    Write-Warning "Public directory not found at: $PublicFolderPath"
}

# 2. Load private functions
Write-Verbose "Searching for private functions..."
if (Test-Path -Path $PrivateFolderPath) {
    $privateFiles = Get-ChildItem -Path $PrivateFolderPath -Filter "*.ps1" -File
    Write-Verbose ("Found " + $privateFiles.Count + " private function files")
    
    foreach ($file in $privateFiles) {
        $functionName = Import-PSFile -FilePath $file.FullName -Type "Private"
        if ($functionName) {
            $script:PrivateFunctions += $functionName
        }
    }
} else {
    Write-Verbose "Private directory not found or is empty: $PrivateFolderPath"
}

# 3. Explicitly export public functions
Write-Verbose ("Exporting " + $script:PublicFunctions.Count + " public functions...")

foreach ($function in $script:PublicFunctions) {
    Write-Verbose ("Exporting function: " + $function)
    try {
        Export-ModuleMember -Function $function -ErrorAction Stop
        Write-Verbose ("Successfully exported: " + $function)
    }
    catch {
        Write-Error ("Failed to export function " + $function + ". Error: " + ${_}.Exception.Message)
    }
}

# 4. Module import summary
if ($script:FailedImports.Count -gt 0) {
    Write-Warning ("Module loaded with " + $script:FailedImports.Count + " import failures.")
    foreach ($failure in $script:FailedImports) {
        Write-Warning ("  " + $failure)
    }
}

Write-Verbose "=== Module initialization complete ==="
Write-Verbose ("Public functions loaded: " + $script:PublicFunctions.Count + " - " + ($script:PublicFunctions -join ', '))
$privateFunctionsStr = if ($script:PrivateFunctions.Count -gt 0) { $script:PrivateFunctions -join ', ' } else { 'None' }
Write-Verbose ("Private functions loaded: " + $script:PrivateFunctions.Count + " - " + $privateFunctionsStr)

# Clean up helper function to avoid polluting the global namespace
Remove-Item -Path Function:\Import-PSFile -ErrorAction SilentlyContinue
