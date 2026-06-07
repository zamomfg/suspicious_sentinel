param($Timer, $lastModifiedState)

$ErrorActionPreference = 'Stop'

# MaxMind downloads use HTTP Basic auth (account ID : license key). The license
# key is injected via a Key Vault reference (resolved by the function's managed
# identity); the account ID is a plain, non-secret app setting.
$accountId  = $env:MAXMIND_ACCOUNT_ID
$licenseKey = $env:MAXMIND_LICENSE_KEY
if ([string]::IsNullOrWhiteSpace($accountId)) {
    throw "MAXMIND_ACCOUNT_ID app setting is not set."
}
if ([string]::IsNullOrWhiteSpace($licenseKey)) {
    throw "MAXMIND_LICENSE_KEY app setting is not set."
}

$editionId = 'GeoLite2-ASN-CSV'
$url = "https://download.maxmind.com/geoip/databases/$editionId/download?suffix=zip"

$basic   = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${accountId}:${licenseKey}"))
$headers = @{ Authorization = "Basic $basic" }

# Check whether the database has changed before downloading. Per MaxMind's
# guidance, a HEAD request exposes the build date via the Last-Modified header
# and does NOT count against the daily download limit. We compare it to the
# value persisted from the previous run (.maxmind-last-modified state blob).
# (Auth is sent on the first hop; Invoke-WebRequest drops it on the signed
# redirect, which is the desired behaviour.)
$currentBuild = ''
try {
    $head = Invoke-WebRequest -Uri $url -Method Head -Headers $headers -MaximumRedirection 5 -UseBasicParsing
    $currentBuild = [string]($head.Headers['Last-Modified'] | Select-Object -First 1).Trim()
}
catch {
    Write-Host "HEAD check failed ($($_.Exception.Message)); proceeding with download."
}

$previousBuild = if ($null -ne $lastModifiedState) { ([string]$lastModifiedState).Trim() } else { '' }

if ($currentBuild -ne '' -and $currentBuild -eq $previousBuild) {
    Write-Host "GeoLite2-ASN unchanged (Last-Modified: $currentBuild); skipping download."
    return
}

Write-Host "GeoLite2-ASN changed (was '$previousBuild', now '$currentBuild'); downloading..."

$tempZip = Join-Path $env:TEMP ("geolite2-asn-{0}.zip" -f ([guid]::NewGuid()))
Invoke-WebRequest -Uri $url -Headers $headers -MaximumRedirection 5 -OutFile $tempZip -UseBasicParsing

# GeoLite2-ASN-CSV is a zip containing GeoLite2-ASN-Blocks-IPv4.csv (and IPv6 +
# a COPYRIGHT/LICENSE) under a dated folder. Extract the IPv4 blocks file as-is;
# MaxMind already emits a headered, properly quoted CSV, so no transform needed.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($tempZip)
try {
    $entry = $zip.Entries | Where-Object { $_.FullName -like '*GeoLite2-ASN-Blocks-IPv4.csv' } | Select-Object -First 1
    if ($null -eq $entry) {
        throw "GeoLite2-ASN-Blocks-IPv4.csv not found in the downloaded archive."
    }
    $reader = New-Object System.IO.StreamReader($entry.Open())
    try {
        $csv = $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }
}
finally {
    $zip.Dispose()
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
}

Push-OutputBinding -Name outputBlob -Value $csv
# Persist the build date so the next run can skip an unchanged database.
Push-OutputBinding -Name lastModifiedStateOut -Value $currentBuild

Write-Host "ASN dataset updated (build '$currentBuild')."
