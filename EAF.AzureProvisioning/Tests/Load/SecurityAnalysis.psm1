        # Generate report based on format
        $reportPath = Join-Path $OutputPath "SecurityAnalysis-$(Get-Date -Format 'yyyyMMdd-HHmmss').$Format"
        
        switch ($Format) {
            "HTML" {
                $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Analysis Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .section { margin: 20px 0; padding: 10px; background-color: #f5f5f5; }
        .critical { color: #d9534f; }
        .high { color: #f0ad4e; }
        .medium { color: #ffd700; }
        .low { color: #5bc0de; }
        .chart { margin: 20px 0; height: 300px; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
</head>
<body>
    <h1>Security Analysis Report</h1>
    <div class="section">
        <h2>Summary</h2>
        <p>Generated: $($report.GeneratedAt)</p>
        <p>Total Certificates Analyzed: $($report.Certificates.Total)</p>
        <p>Total Protocol Analyses: $($report.Protocols.Total)</p>
        <p>Total Vulnerabilities: $($report.Vulnerabilities.Total)</p>
        <p>MITM Attempts Detected: $($report.MITM.Detected)</p>
    </div>
    
    <div class="section">
        <h2>Vulnerability Distribution</h2>
        <div id="vulnerabilityChart" class="chart"></div>
        <table>
            <tr><th>Severity</th><th>Count</th></tr>
            $(foreach ($severity in $report.Vulnerabilities.BySeverity.GetEnumerator()) {
                "<tr><td class='$($severity.Key.ToLower())'>$($severity.Key)</td><td>$($severity.Value)</td></tr>"
            })
        </table>
    </div>
    
    $(if ($report.MITM.Incidents.Count -gt 0) {
    @"
    <div class="section">
        <h2>MITM Detection</h2>
        <table>
            <tr>
                <th>Timestamp</th>
                <th>Host</th>
                <th>Expected Thumbprint</th>
                <th>Received Thumbprint</th>
            </tr>
            $(foreach ($incident in $report.MITM.Incidents) {
                "<tr>
                    <td>$($incident.Timestamp)</td>
                    <td>$($incident.HostName)</td>
                    <td>$($incident.ExpectedThumbprint)</td>
                    <td>$($incident.ReceivedThumbprint)</td>
                </tr>"
            })
        </table>
    </div>
"@
    })
    
    $(if ($report.Protocols.Downgrades.Count -gt 0) {
    @"
    <div class="section">
        <h2>Protocol Downgrades</h2>
        <table>
            <tr>
                <th>Timestamp</th>
                <th>Host</th>
                <th>Expected Protocol</th>
                <th>Negotiated Protocol</th>
            </tr>
            $(foreach ($downgrade in $report.Protocols.Downgrades) {
                "<tr>
                    <td>$($downgrade.Timestamp)</td>
                    <td>$($downgrade.HostName)</td>
                    <td>$($downgrade.ExpectedProtocol)</td>
                    <td>$($downgrade.NegotiatedProtocol)</td>
                </tr>"
            })
        </table>
    </div>
"@
    })
    
    <script>
        var vulnerabilityData = [{
            type: 'pie',
            labels: $(ConvertTo-Json @($report.Vulnerabilities.BySeverity.Keys)),
            values: $(ConvertTo-Json @($report.Vulnerabilities.BySeverity.Values)),
            marker: {
                colors: ['#d9534f', '#f0ad4e', '#ffd700', '#5bc0de']
            }
        }];
        
        Plotly.newPlot('vulnerabilityChart', vulnerabilityData);
    </script>
</body>
</html>
"@
                $htmlReport | Out-File -FilePath $reportPath -Force
            }
            "JSON" {
                $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Force
            }
            "CSV" {
                # Export vulnerabilities
                $vulnData = $script:SecurityAnalysis.VulnerabilityStore.Values | ForEach-Object {
                    [PSCustomObject]@{
                        Timestamp = $_.Timestamp
                        Type = $_.Type
                        Severity = $_.Severity
                        Description = $_.Description
                    }
                }
                $vulnData | Export-Csv -Path $reportPath -NoTypeInformation -Force
            }
        }
        
        Write-Verbose "Security analysis report generated: $reportPath"
        return $reportPath
    }
    catch {
        Write-Error "Failed to generate security analysis report: $_"
        return $null
    }
}

function Stop-SecurityAnalysis {
    [CmdletBinding()]
    param()
    
    try {
        # Generate final report
        $reportPath = Get-SecurityAnalysisReport
        
        # Clear stores
        $script:SecurityAnalysis.CertificateStore.Clear()
        $script:SecurityAnalysis.ProtocolStore.Clear()
        $script:SecurityAnalysis.VulnerabilityStore.Clear()
        
        if ($script:SecurityAnalysis.MITMDetection) {
            $script:SecurityAnalysis.MITMDetection.KnownCertificates.Clear()
            $script:SecurityAnalysis.MITMDetection.Violations.Clear()
        }
        
        if ($script:SecurityAnalysis.ProtocolDowngrade) {
            $script:SecurityAnalysis.ProtocolDowngrade.Violations.Clear()
        }
        
        Write-Verbose "Security analysis stopped. Final report: $reportPath"
        return $true
    }
    catch {
        Write-Error "Failed to stop security analysis: $_"
        return $false
    }
}

# Helper function to calculate risk score
function Get-SecurityRiskScore {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [hashtable]$Weights = @{
            Critical = 10
            High = 7
            Medium = 4
            Low = 1
            MITM = 10
            ProtocolDowngrade = 5
            CertificateIssue = 3
        }
    )
    
    try {
        $riskScore = 0
        
        # Calculate vulnerability score
        $script:SecurityAnalysis.VulnerabilityStore.Values | ForEach-Object {
            $riskScore += $Weights[$_.Severity]
        }
        
        # Add MITM detection score
        if ($script:SecurityAnalysis.MITMDetection.Enabled) {
            $riskScore += $script:SecurityAnalysis.MITMDetection.Violations.Count * $Weights.MITM
        }
        
        # Add protocol downgrade score
        if ($script:SecurityAnalysis.ProtocolDowngrade.Enabled) {
            $riskScore += $script:SecurityAnalysis.ProtocolDowngrade.Violations.Count * $Weights.ProtocolDowngrade
        }
        
        # Calculate final risk category
        $riskCategory = switch ($riskScore) {
            { $_ -gt 50 } { "Critical" }
            { $_ -gt 30 } { "High" }
            { $_ -gt 15 } { "Medium" }
            default { "Low" }
        }
        
        return @{
            Score = $riskScore
            Category = $riskCategory
            Details = @{
                VulnerabilityCount = $script:SecurityAnalysis.VulnerabilityStore.Count
                MITMCount = $script:SecurityAnalysis.MITMDetection.Violations.Count
                ProtocolDowngradeCount = $script:SecurityAnalysis.ProtocolDowngrade.Violations.Count
            }
        }
    }
    catch {
        Write-Error "Failed to calculate security risk score: $_"
        return $null
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Start-SecurityAnalysis',
    'Add-CertificateAnalysis',
    'Add-ProtocolAnalysis',
    'Add-VulnerabilityAnalysis',
    'Get-SecurityAnalysisReport',
    'Stop-SecurityAnalysis',
    'Get-SecurityRiskScore'
)
