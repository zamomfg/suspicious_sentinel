param($Timer)

$ErrorActionPreference = 'Stop'

$window = Get-TailscaleTimeWindow -Minutes ([int]$env:TailscaleLookbackMinutes)

$accessToken = Get-TailscaleAccessToken -ClientId $env:TailscaleClientId

$logs = Get-TailscaleLogs `
    -Tailnet     $env:TailscaleTailnet `
    -AccessToken $accessToken `
    -Path        "logging/configuration" `
    -Start       $window.Start `
    -End         $window.End

$records = foreach ($l in $logs) {
    [ordered]@{
        TimeGenerated = if ($l.eventTime) { $l.eventTime } else { $window.End }
        EventTime     = $l.eventTime
        EventGroupID  = [string]$l.eventGroupID
        Action        = [string]$l.action
        Actor         = $l.actor
        Target        = $l.target
        Origin        = [string]$l.origin
        EventType     = [string]$l.type
        Old           = $l.old
        New           = $l.new
    }
}

$count = Send-ToLogsIngestion `
    -DceUri         $env:LogsIngestionEndpoint `
    -DcrImmutableId $env:DcrImmutableId `
    -StreamName     $env:DcrAuditStreamName `
    -Records        @($records)

Write-Host "Ingested $count Tailscale audit-log record(s) [$($window.Start)..$($window.End)]"
