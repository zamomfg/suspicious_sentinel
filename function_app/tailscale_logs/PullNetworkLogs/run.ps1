param($Timer)

$ErrorActionPreference = 'Stop'

$window = Get-TailscaleTimeWindow -Minutes ([int]$env:TailscaleLookbackMinutes)

$logs = Get-TailscaleLogs `
    -Tailnet $env:TailscaleTailnet `
    -Token   $env:TailscaleAccessToken `
    -Path    "network-logs" `
    -Start   $window.Start `
    -End     $window.End

$records = foreach ($l in $logs) {
    [ordered]@{
        TimeGenerated   = if ($l.logged) { $l.logged } else { $window.End }
        NodeId          = [string]$l.nodeId
        Start           = $l.start
        End             = $l.end
        Logged          = $l.logged
        VirtualTraffic  = $l.virtualTraffic
        PhysicalTraffic = $l.physicalTraffic
        ExitTraffic     = $l.exitTraffic
        SubnetTraffic   = $l.subnetTraffic
    }
}

$count = Send-ToLogsIngestion `
    -DceUri         $env:LogsIngestionEndpoint `
    -DcrImmutableId $env:DcrImmutableId `
    -StreamName     $env:DcrNetworkStreamName `
    -Records        @($records)

Write-Host "Ingested $count Tailscale network-log record(s) [$($window.Start)..$($window.End)]"
