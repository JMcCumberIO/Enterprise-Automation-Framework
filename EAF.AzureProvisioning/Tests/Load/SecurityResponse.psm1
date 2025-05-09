</html>
"@
                $htmlDashboard | Out-File -FilePath $dashboardPath -Force
            }
            "JSON" {
                $dashboard | ConvertTo-Json -Depth 10 | Out-File -FilePath $dashboardPath -Force
            }
        }
        
        Write-Verbose "Security dashboard generated: $dashboardPath"
        return $dashboardPath
    }
    catch {
        Write-Error "Failed to generate security dashboard: $_"
        return $null
    }
}

# Helper functions for remediation actions
function Block-Connection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Details,
        
        [Parameter(Mandatory = $true)]
        [TimeSpan]$Duration
    )
    
    try {
        $result = @{
            Action = "Block"
            Target = $Details.HostName
            StartTime = Get-Date
            EndTime = (Get-Date) + $Duration
            Status = "Success"
        }
        
        # Add to blocked connections list
        $script:ResponseStore.BlockedConnections = @{}
        $script:ResponseStore.BlockedConnections[$Details.HostName] = $result
        
        return $result
    }
    catch {
        return @{
            Action = "Block"
            Target = $Details.HostName
            Error = $_.Exception.Message
            Status = "Failed"
        }
    }
}

function Retry-SecureConnection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Details,
        
        [Parameter(Mandatory = $true)]
        [int]$MaxRetries
    )
    
    try {
        $result = @{
            Action = "Retry"
            Target = $Details.HostName
            Attempts = 0
            Status = "Pending"
        }
        
        for ($i = 1; $i -le $MaxRetries; $i++) {
            $result.Attempts = $i
            
            # Force TLS 1.2/1.3
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
            
            # Attempt connection
            try {
                $webRequest = [Net.HttpWebRequest]::Create("https://$($Details.HostName)")
                $webRequest.GetResponse().Close()
                $result.Status = "Success"
                break
            }
            catch {
                if ($i -eq $MaxRetries) {
                    $result.Status = "Failed"
                    $result.Error = $_.Exception.Message
                }
                Start-Sleep -Seconds (2 * $i) # Exponential backoff
            }
        }
        
        return $result
    }
    catch {
        return @{
            Action = "Retry"
            Target = $Details.HostName
            Error = $_.Exception.Message
            Status = "Failed"
        }
    }
}

function Revoke-Certificate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Details
    )
    
    try {
        $result = @{
            Action = "Revoke"
            Target = $Details.Certificate.Thumbprint
            Status = "Success"
        }
        
        # Add to revoked certificates list
        $script:ResponseStore.RevokedCertificates = @{}
        $script:ResponseStore.RevokedCertificates[$Details.Certificate.Thumbprint] = @{
            Certificate = $Details.Certificate
            RevokedAt = Get-Date
            Reason = "SecurityResponse"
        }
        
        return $result
    }
    catch {
        return @{
            Action = "Revoke"
            Target = $Details.Certificate.Thumbprint
            Error = $_.Exception.Message
            Status = "Failed"
        }
    }
}

function Start-AnomalyMonitoring {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Details,
        
        [Parameter(Mandatory = $true)]
        [int]$Threshold
    )
    
    try {
        $result = @{
            Action = "Monitor"
            Target = $Details.HostName
            StartTime = Get-Date
            Threshold = $Threshold
            Status = "Success"
            Metrics = @{
                BaselineRequests = 0
                AnomalousRequests = 0
                AnomalyPercentage = 0
            }
        }
        
        # Initialize monitoring
        $script:ResponseStore.AnomalyMonitoring = @{}
        $script:ResponseStore.AnomalyMonitoring[$Details.HostName] = $result
        
        return $result
    }
    catch {
        return @{
            Action = "Monitor"
            Target = $Details.HostName
            Error = $_.Exception.Message
            Status = "Failed"
        }
    }
}

function Stop-SecurityResponse {
    [CmdletBinding()]
    param()
    
    try {
        # Generate final dashboard
        $dashboardPath = Get-SecurityDashboard
        
        # Clear response stores
        $script:ResponseStore.Incidents.Clear()
        $script:ResponseStore.Responses.Clear()
        $script:ResponseStore.Policies.Clear()
        $script:ResponseStore.Alerts.Clear()
        
        if ($script:ResponseStore.AutoRemediation) {
            $script:ResponseStore.AutoRemediation.Actions.Clear()
            $script:ResponseStore.AutoRemediation.Results.Clear()
        }
        
        if ($script:ResponseStore.AlertNotification) {
            $script:ResponseStore.AlertNotification.Queue.Clear()
            $script:ResponseStore.AlertNotification.History.Clear()
        }
        
        Write-Verbose "Security response stopped. Final dashboard: $dashboardPath"
        return $true
    }
    catch {
        Write-Error "Failed to stop security response: $_"
        return $false
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Start-SecurityResponse',
    'Add-SecurityIncident',
    'Start-SecurityRemediation',
    'Add-SecurityAlert',
    'Get-SecurityDashboard',
    'Stop-SecurityResponse'
)
