# Azure Functions profile — runs once per cold start. No Az modules are used.
# Shared helpers for the Tailscale pull-and-ingest functions live here.

function Get-TailscaleTimeWindow {
    param([int]$Minutes)
    if ($Minutes -le 0) { $Minutes = 5 }
    $end   = [DateTime]::UtcNow
    $start = $end.AddMinutes(-$Minutes)
    [pscustomobject]@{
        Start = $start.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        End   = $end.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
}

# Pull logs from a Tailscale API path. Auth is HTTP Basic with the access token
# as the username and an empty password (the curl `-u "$TOKEN:"` form). Returns
# the `logs` array from the response.
function Get-TailscaleLogs {
    param(
        [string]$Tailnet,
        [string]$Token,
        [string]$Path,
        [string]$Start,
        [string]$End
    )
    if ([string]::IsNullOrWhiteSpace($Tailnet)) { throw "TailscaleTailnet is not set." }
    if ([string]::IsNullOrWhiteSpace($Token)) { throw "TailscaleAccessToken is not set." }

    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${Token}:"))
    $uri   = "https://api.tailscale.com/api/v2/tailnet/$Tailnet/$Path" + "?start=$Start&end=$End"
    $resp  = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Basic $basic" } -Method Get
    return @($resp.logs)
}

# Push records to a Log Analytics custom table via the Logs Ingestion API, using
# the function's managed identity for the Entra token. Returns the count sent.
function Send-ToLogsIngestion {
    param(
        [string]$DceUri,
        [string]$DcrImmutableId,
        [string]$StreamName,
        [object[]]$Records
    )
    if (-not $Records -or $Records.Count -eq 0) { return 0 }
    foreach ($v in @($DceUri, $DcrImmutableId, $StreamName)) {
        if ([string]::IsNullOrWhiteSpace($v)) { throw "DCE/DCR ingestion settings are not fully configured." }
    }

    $miUri  = "$($env:IDENTITY_ENDPOINT)?resource=https://monitor.azure.com&api-version=2019-08-01"
    $miResp = Invoke-RestMethod -Uri $miUri -Headers @{ "X-IDENTITY-HEADER" = $env:IDENTITY_HEADER } -Method Get

    $ingestUri = "$DceUri/dataCollectionRules/$DcrImmutableId/streams/$StreamName" + "?api-version=2023-01-01"
    $body      = ConvertTo-Json -InputObject @($Records) -Depth 20 -Compress

    Invoke-RestMethod -Uri $ingestUri -Method Post -Body $body -Headers @{
        Authorization  = "Bearer $($miResp.access_token)"
        "Content-Type" = "application/json"
    } | Out-Null

    return $Records.Count
}
