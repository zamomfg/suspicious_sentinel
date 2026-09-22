# Defender XDR custom detections (tenant-scoped, via the Microsoft Graph
# security/rules/detectionRules beta API). These are not bound to a workspace.

# Successful SSH logon to a Linux/Arc host from a public (non-RFC1918) source IP.
# Fires, for example, when someone reaches an Azure Arc-enabled server over SSH
# from Azure Cloud Shell (`az ssh arc`), whose egress is a public Azure IP.
# Runs continuously (NRT). The NRT streaming engine can't compile the ipv4_*
# functions, so the public-IP check excludes RFC1918 / loopback / link-local
# ranges with plain string-prefix matches (incl. 172.16.0.0/12 as explicit
# per-/16 prefixes, since `matches regex` isn't guaranteed in the NRT engine).
module "detect_ssh_public_ip_login" {
  source = "./modules/detection_rule"

  rule_id            = "linux-ssh-login-from-public-ip"
  display_name       = "SSH login to a Linux host from a public IP address"
  description        = "A successful SSH logon to a Linux (incl. Azure Arc) host originated from a non-private source IP. Expected when connecting via Azure Cloud Shell / `az ssh arc`; otherwise may indicate remote access with valid credentials."
  severity           = "medium"
  schedule_frequency = "PT0S" # continuous / NRT

  query_text = <<-KQL
    DeviceLogonEvents
    | where ActionType == "LogonSuccess"
    | where InitiatingProcessFileName in~ ("sshd", "sshd-session")
    | where isnotempty(RemoteIP)
    | where not(RemoteIP startswith "10." or RemoteIP startswith "192.168."
        or RemoteIP startswith "172.16." or RemoteIP startswith "172.17." or RemoteIP startswith "172.18." or RemoteIP startswith "172.19."
        or RemoteIP startswith "172.20." or RemoteIP startswith "172.21." or RemoteIP startswith "172.22." or RemoteIP startswith "172.23."
        or RemoteIP startswith "172.24." or RemoteIP startswith "172.25." or RemoteIP startswith "172.26." or RemoteIP startswith "172.27."
        or RemoteIP startswith "172.28." or RemoteIP startswith "172.29." or RemoteIP startswith "172.30." or RemoteIP startswith "172.31."
        or RemoteIP startswith "127." or RemoteIP startswith "169.254."
        or RemoteIP == "::1" or RemoteIP startswith "fe80:" or RemoteIP startswith "fc" or RemoteIP startswith "fd")
    | project Timestamp, ReportId, DeviceId, DeviceName, AccountName, AccountDomain, AccountSid, RemoteIP, LogonType, InitiatingProcessFileName
  KQL

  alert_title         = "SSH login to a Linux host from a public IP address"
  alert_description   = "A successful SSH logon to a Linux/Arc host came from a public source IP address."
  category            = "InitialAccess"
  recommended_actions = "Confirm the source IP and account are expected (e.g. Azure Cloud Shell / az ssh arc). If not, isolate the host and reset the account's credentials."

  # The detectionRules API allows a single tactic. SSH from a public IP is
  # treated as Initial Access with valid credentials (T1078); the SSH-specific
  # T1021.004 (Lateral Movement) is noted here but can't be a second tactic.
  mitre_tactics = [
    { tactic = "InitialAccess", techniques = ["T1078"] },
  ]

  entity_mappings = {
    hosts    = [{ deviceIdColumn = "DeviceId", nameColumn = "DeviceName" }]
    accounts = [{ nameColumn = "AccountName", ntDomainColumn = "AccountDomain", sidColumn = "AccountSid" }]
    ips      = [{ addressColumn = "RemoteIP" }]
  }
}

# --- MikroTik firewall (ASimNetworkSessionLogs, reachable via the unified portal) ---
# Internal subnets come from the encrypted `Vlans` watchlist (never hardcoded, this
# repo is public). "SmartNet" below is only the segment's name; its CIDR is in the
# watchlist. The scan rules require an ephemeral source port (SrcPortNumber >= 1024)
# so server replies (e.g. DNS from src port 53) aren't mistaken for scans.

# Accepted inbound session whose source is a public (internet) address.
module "detect_inbound_internet_accepted" {
  source = "./modules/detection_rule"

  rule_id            = "mikrotik-inbound-internet-accepted"
  display_name       = "Accepted inbound traffic from the internet (MikroTik)"
  description        = "The firewall accepted a session sourced from a public (non-RFC1918) IP address. Expected only for intentionally published services / port-forwards; otherwise review the source and destination."
  severity           = "medium"
  schedule_frequency = "PT1H"

  query_text = <<-KQL
    let InternalRanges = toscalar(_GetWatchlist('Vlans') | summarize make_set(Subnet));
    ASimNetworkSessionLogs
    | where DvcAction == "Allow"
    | where isnotempty(SrcIpAddr) and isnotempty(DstIpAddr)
    | where not(ipv4_is_private(SrcIpAddr))
    | summarize SessionCount = count(), DstPorts = make_set(DstPortNumber, 50), DstHosts = make_set(DstIpAddr, 50), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) by SrcIpAddr, SrcGeoCountry, SrcGeoCity
    | extend Timestamp = LastSeen
    | extend ReportId = tostring(hash(strcat(SrcIpAddr, tostring(LastSeen))))
  KQL

  alert_title         = "Accepted inbound traffic from the internet"
  alert_description   = "A session from a public source IP was accepted by the perimeter firewall."
  category            = "InitialAccess"
  recommended_actions = "Confirm the destination service is intentionally published. If not, tighten the firewall rule and investigate the source IP."
  mitre_tactics       = [{ tactic = "InitialAccess", techniques = ["T1190"] }]

  entity_mappings = {
    ips = [{ addressColumn = "SrcIpAddr" }]
  }
}

# SmartNet (IoT) device with accepted traffic leaving its own segment.
module "detect_smartnet_egress_accepted" {
  source = "./modules/detection_rule"

  rule_id            = "mikrotik-smartnet-egress-accepted"
  display_name       = "SmartNet: accepted traffic leaving the segment (MikroTik)"
  description        = "A host in the SmartNet (IoT) segment had traffic accepted to a destination outside SmartNet (another internal segment or the internet). IoT devices normally stay within their segment; egress can indicate misconfiguration or compromise."
  severity           = "medium"
  schedule_frequency = "PT1H"

  query_text = <<-KQL
    let SmartNet = toscalar(_GetWatchlist('Vlans') | where NetworkName == "SmartNet" | summarize make_set(Subnet));
    let InternalRanges = toscalar(_GetWatchlist('Vlans') | summarize make_set(Subnet));
    ASimNetworkSessionLogs
    | where DvcAction == "Allow"
    | where isnotempty(SrcIpAddr) and isnotempty(DstIpAddr)
    | where ipv4_is_in_any_range(SrcIpAddr, SmartNet)
    | where not(ipv4_is_in_any_range(DstIpAddr, SmartNet))
    | extend DestinationScope = iif(ipv4_is_in_any_range(DstIpAddr, InternalRanges), "internal-other-segment", "external-internet")
    | summarize SessionCount = count(), DstPorts = make_set(DstPortNumber, 50), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) by SrcIpAddr, DstIpAddr, DestinationScope, NetworkProtocol
    | extend Timestamp = LastSeen
    | extend ReportId = tostring(hash(strcat(SrcIpAddr, DstIpAddr, tostring(LastSeen))))
  KQL

  alert_title         = "SmartNet traffic left the segment"
  alert_description   = "An IoT (SmartNet) host had accepted traffic to a destination outside its segment."
  category            = "CommandAndControl"
  recommended_actions = "Verify the SmartNet host should reach this destination. If not, restrict inter-segment/egress rules and inspect the device."
  mitre_tactics       = [{ tactic = "CommandAndControl", techniques = ["T1071"] }]

  entity_mappings = {
    ips = [{ addressColumn = "SrcIpAddr" }, { addressColumn = "DstIpAddr" }]
  }
}

# Horizontal scan: one internal source reaching many internal hosts on the same port.
module "detect_internal_scan_horizontal" {
  source = "./modules/detection_rule"

  rule_id            = "mikrotik-internal-scan-horizontal"
  display_name       = "Internal horizontal scan (one source, many hosts, same port) (MikroTik)"
  description        = "An internal host contacted many distinct internal hosts on the same destination port within an hour - a horizontal (service) sweep looking for a specific service across the network."
  severity           = "medium"
  schedule_frequency = "PT1H"

  query_text = <<-KQL
    let InternalRanges = toscalar(_GetWatchlist('Vlans') | summarize make_set(Subnet));
    ASimNetworkSessionLogs
    | where isnotempty(SrcIpAddr) and isnotempty(DstIpAddr) and DstPortNumber > 0 and SrcPortNumber >= 1024
    | where ipv4_is_in_any_range(SrcIpAddr, InternalRanges) and ipv4_is_in_any_range(DstIpAddr, InternalRanges)
    | summarize DistinctHosts = dcount(DstIpAddr), TargetHosts = make_set(DstIpAddr, 100), Attempts = count(), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) by SrcIpAddr, DstPortNumber, NetworkProtocol
    | where DistinctHosts >= 20
    | extend Timestamp = LastSeen
    | extend ReportId = tostring(hash(strcat(SrcIpAddr, tostring(DstPortNumber), tostring(LastSeen))))
  KQL

  alert_title         = "Internal horizontal scan detected"
  alert_description   = "An internal host contacted many internal hosts on the same port, consistent with a horizontal service sweep."
  category            = "Discovery"
  recommended_actions = "Identify the source host and whether it is an authorized scanner (e.g. vulnerability management). If not, isolate and investigate."
  mitre_tactics       = [{ tactic = "Discovery", techniques = ["T1046"] }]

  entity_mappings = {
    ips = [{ addressColumn = "SrcIpAddr" }]
  }
}

# Vertical scan: one internal source hitting many ports on a single internal host.
module "detect_internal_scan_vertical" {
  source = "./modules/detection_rule"

  rule_id            = "mikrotik-internal-scan-vertical"
  display_name       = "Internal vertical scan (one source, many ports, single host) (MikroTik)"
  description        = "An internal host contacted many distinct ports on a single internal host within an hour - a vertical port scan enumerating services on one target."
  severity           = "medium"
  schedule_frequency = "PT1H"

  query_text = <<-KQL
    let InternalRanges = toscalar(_GetWatchlist('Vlans') | summarize make_set(Subnet));
    ASimNetworkSessionLogs
    | where isnotempty(SrcIpAddr) and isnotempty(DstIpAddr) and DstPortNumber > 0 and SrcPortNumber >= 1024
    | where ipv4_is_in_any_range(SrcIpAddr, InternalRanges) and ipv4_is_in_any_range(DstIpAddr, InternalRanges)
    | summarize DistinctPorts = dcount(DstPortNumber), TargetPorts = make_set(DstPortNumber, 100), Attempts = count(), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) by SrcIpAddr, DstIpAddr, NetworkProtocol
    | where DistinctPorts >= 20
    | extend Timestamp = LastSeen
    | extend ReportId = tostring(hash(strcat(SrcIpAddr, DstIpAddr, tostring(LastSeen))))
  KQL

  alert_title         = "Internal vertical scan detected"
  alert_description   = "An internal host contacted many ports on a single internal host, consistent with a vertical port scan."
  category            = "Discovery"
  recommended_actions = "Identify the source host and whether it is an authorized scanner. If not, isolate the source and inspect the target host."
  mitre_tactics       = [{ tactic = "Discovery", techniques = ["T1046"] }]

  entity_mappings = {
    ips = [{ addressColumn = "SrcIpAddr" }, { addressColumn = "DstIpAddr" }]
  }
}
