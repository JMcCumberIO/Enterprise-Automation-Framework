# Test Runner for EAF.AzureProvisioning Module
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("All", "Unit", "Integration")]
    [string]$TestType = "All",
    
    [Parameter(Mandatory = $false)]
    [string]$TestName = "*",
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowTestOutput,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipIntegrationTests,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\TestResults",

    [string]$IntegrationConfigPath = ".\Integration\test-config.json"
)

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Ensure Pester is installed
if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Host "Installing Pester module..."
    Install-Module -Name Pester -Force -SkipPublisherCheck
}

$pesterVersion = (Get-Module -Name Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
if ($pesterVersion -lt [Version]"5.0.0") {
    Write-Warning "Pester version 5.0.0 or higher is required. Current version: $pesterVersion"
    return
}

# Import required modules
Import-Module Pester
# Import-Module Az.KeyVault -ErrorAction SilentlyContinue

# Get test files based on type
$testFiles = @()
switch ($TestType) {
    "Unit" {
        $testFiles = Get-ChildItem -Path $PSScriptRoot -Filter "*Tests.ps1" |
            Where-Object { $_.DirectoryName -notlike "*\Integration" -and $_.Name -ne "Run-Tests.ps1" }
    }
    "Integration" {
        if (-not $SkipIntegrationTests) {
            $testFiles = Get-ChildItem -Path "$PSScriptRoot\Integration" -Filter "*Tests.ps1" | Where-Object { $_.Name -ne "Run-Tests.ps1" }
        }
    }
    "All" {
        $testFiles = Get-ChildItem -Path $PSScriptRoot -Filter "*Tests.ps1" -Recurse | Where-Object { $_.Name -ne "Run-Tests.ps1" }
        if ($SkipIntegrationTests) {
            $testFiles = $testFiles | Where-Object { $_.DirectoryName -notlike "*\Integration" }
        }
    }
}

# Ensure test files exist
if ($testFiles.Count -eq 0) {
    Write-Host "No test files found. Exiting..." -ForegroundColor Yellow
    return
}

# Configure Pester for all test files at once
$config = New-PesterConfiguration
$config.Run.Path = $testFiles | ForEach-Object { $_.FullName }
$config.Output.Verbosity = if ($ShowTestOutput) { 'Detailed' } else { 'Normal' }
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = Join-Path $OutputPath "TestResults.xml"

# Create test report structure
$testReport = @{
    StartTime = Get-Date
    EndTime = $null
    Duration = $null
    TotalTests = 0
    PassedTests = 0
    FailedTests = 0
    SkippedTests = 0
    TestFiles = @()
    FailedTestDetails = @()
}

Write-Host "`n========================================="
Write-Host "EAF Azure Provisioning Module Test Runner"
Write-Host "=========================================`n"
Write-Host "Test Type: $TestType"
Write-Host "Test Files Found: $($testFiles.Count)"
Write-Host "Output Path: $OutputPath`n"

# Run all tests at once
Write-Host "[DEBUG] Starting Invoke-Pester for $($testFiles.Count) files..."
$testRunStart = Get-Date
$result = Invoke-Pester -Configuration $config
$testRunEnd = Get-Date
Write-Host "[DEBUG] Invoke-Pester completed."

# Summarize results per file
foreach ($file in $testFiles) {
    $fileResult = $result.Tests | Where-Object { $_.Source -eq $file.FullName }
    $fileReport = @{
        FileName = $file.Name
        StartTime = $testRunStart
        EndTime = $testRunEnd
        Duration = $testRunEnd - $testRunStart
        TotalTests = ($fileResult | Measure-Object).Count
        PassedTests = ($fileResult | Where-Object { $_.Result -eq 'Passed' } | Measure-Object).Count
        FailedTests = ($fileResult | Where-Object { $_.Result -eq 'Failed' } | Measure-Object).Count
        SkippedTests = ($fileResult | Where-Object { $_.Result -eq 'Skipped' } | Measure-Object).Count
        FailedTestDetails = @()
    }
    foreach ($failed in ($fileResult | Where-Object { $_.Result -eq 'Failed' })) {
        $fileReport.FailedTestDetails += @{
            Name = $failed.Name
            ErrorMessage = $([System.Web.HttpUtility]::HtmlEncode($failed.ErrorRecord.Exception.Message))
            StackTrace = $([System.Web.HttpUtility]::HtmlEncode($failed.ErrorRecord.ScriptStackTrace))
        }
    }
    $testReport.TestFiles += $fileReport
    $testReport.TotalTests += $fileReport.TotalTests
    $testReport.PassedTests += $fileReport.PassedTests
    $testReport.FailedTests += $fileReport.FailedTests
    $testReport.SkippedTests += $fileReport.SkippedTests
}
$testReport.EndTime = $testRunEnd
$testReport.Duration = $testRunEnd - $testRunStart

# Generate HTML report
$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Test Results - EAF Azure Provisioning</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .summary { background-color: #f5f5f5; padding: 20px; margin-bottom: 20px; }
        .pass { color: green; }
        .fail { color: red; }
        .skip { color: orange; }
        .file-report { margin-bottom: 30px; }
        .failed-test { margin-left: 20px; margin-bottom: 10px; }
    </style>
</head>
<body>
    <h1>Test Results - EAF Azure Provisioning</h1>
    <div class="summary">
        <h2>Summary</h2>
        <p>Test Type: $TestType</p>
        <p>Duration: $($testReport.Duration.TotalSeconds) seconds</p>
        <p>Total Tests: $($testReport.TotalTests)</p>
        <p class="pass">Passed: $($testReport.PassedTests)</p>
        <p class="fail">Failed: $($testReport.FailedTests)</p>
        <p class="skip">Skipped: $($testReport.SkippedTests)</p>
    </div>
"@

foreach ($fileReport in $testReport.TestFiles) {
    $htmlReport += @"
    <div class="file-report">
        <h3>$($fileReport.FileName)</h3>
        <p>Duration: $($fileReport.Duration.TotalSeconds) seconds</p>
        <p>Total: $($fileReport.TotalTests) | Passed: $($fileReport.PassedTests) | Failed: $($fileReport.FailedTests) | Skipped: $($fileReport.SkippedTests)</p>
"@
    
    if ($fileReport.FailedTests.Count -gt 0) {
        $htmlReport += "<h4>Failed Tests:</h4>"
        foreach ($failed in $fileReport.FailedTestDetails) {
            $htmlReport += @"
            <div class="failed-test">
                <p><strong>$([System.Web.HttpUtility]::HtmlEncode($failed.Name))</strong></p>
                <p>$([System.Web.HttpUtility]::HtmlEncode($failed.ErrorMessage))</p>
                <pre>$([System.Web.HttpUtility]::HtmlEncode($failed.StackTrace))</pre>
            </div>
"@
        }
    }
    $htmlReport += "</div>"
}

$htmlReport += "</body></html>"

# Save HTML report
$htmlReport | Out-File (Join-Path $OutputPath "TestReport.html") -Force

# Display summary
Write-Host "`n==========================================="
Write-Host "Test Execution Summary"
Write-Host "===========================================`n"
Write-Host "Duration: $($testReport.Duration.TotalSeconds) seconds"
Write-Host "Total Tests: $($testReport.TotalTests)"
Write-Host "Passed Tests: $($testReport.PassedTests)" -ForegroundColor Green
Write-Host "Failed Tests: $($testReport.FailedTests)" -ForegroundColor Red
Write-Host "Skipped Tests: $($testReport.SkippedTests)" -ForegroundColor Yellow
Write-Host "`nDetailed report available at: $OutputPath\TestReport.html"

if ($testReport.FailedTests -gt 0) {
    exit 1
} elseif ($testReport.SkippedTests -gt 0) {
    exit 2
} else {
    exit 0
}
