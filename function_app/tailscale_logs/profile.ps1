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

# Exchange the function's managed-identity OIDC token for a short-lived Tailscale
# API token via workload identity federation — no stored secret.
# https://tailscale.com/docs/features/workload-identity-federation
function Get-TailscaleAccessToken {
    param([string]$ClientId)
    if ([string]::IsNullOrWhiteSpace($ClientId)) { throw "TailscaleClientId is not set." }

    # The audience Tailscale expects is the API host plus the federated client id.
    $audience = "api.tailscale.com/$ClientId"

    # Mint an Entra OIDC JWT for this app's managed identity, scoped to that audience.
    $miUri = "$($env:IDENTITY_ENDPOINT)?resource=$([uri]::EscapeDataString($audience))&api-version=2019-08-01"
    $miResp = Invoke-RestMethod -Uri $miUri -Headers @{ "X-IDENTITY-HEADER" = $env:IDENTITY_HEADER } -Method Get

    # Trade the JWT for a Tailscale API token.
    $resp = Invoke-RestMethod -Uri "https://api.tailscale.com/api/v2/oauth/token-exchange" -Method Post -Body @{
        client_id = $ClientId
        jwt       = $miResp.access_token
    }
    return $resp.access_token
}

# Pull logs from a Tailscale API path using a bearer access token. Returns the
# `logs` array from the response.
function Get-TailscaleLogs {
    param(
        [string]$Tailnet,
        [string]$AccessToken,
        [string]$Path,
        [string]$Start,
        [string]$End
    )
    if ([string]::IsNullOrWhiteSpace($Tailnet)) { throw "TailscaleTailnet is not set." }
    if ([string]::IsNullOrWhiteSpace($AccessToken)) { throw "Tailscale access token is empty." }

    $uri  = "https://api.tailscale.com/api/v2/tailnet/$Tailnet/$Path" + "?start=$Start&end=$End"
    $resp = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $AccessToken" } -Method Get
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
