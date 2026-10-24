
# NOTES:
# The detectionRules API allows a single tactic; only the first mitre_tactics entry is sent to Defender

# MITRE tactics and techniques: https://attack.mitre.org/techniques/enterprise/

module "detect_ssh_public_ip_login" {
  source = "./modules/detection_rule"

  rule_id     = "linux-ssh-login-from-public-ip"
  title       = "SSH login to a Linux host from a public IP address"
  description = "Detects a successful SSH logon to a Linux (incl. Azure Arc) host from a non-private source IP. Expected when connecting via Azure Cloud Shell / `az ssh arc`; otherwise may indicate remote access with valid credentials."
  status      = "experimental"
  author      = "zamomfg"
  date        = "2026-09-06"
  modified    = ""
  logsource   = { product = "linux", service = "sshd" }
  references = [
    "https://learn.microsoft.com/azure/azure-arc/servers/ssh-arc-overview",
  ]
  false_positives = [
    "Administrators connecting through Azure Cloud Shell / `az ssh arc`"
  ]
  severity = "medium"
  mitre_tactics = [
    { tactic = "InitialAccess", techniques = ["T1078"] },
    { tactic = "LateralMovement", techniques = ["T1021.004"] },
  ]

  recommended_actions = "Confirm the source IP and account are expected (e.g. Azure Cloud Shell / az ssh arc). If not, isolate the host and reset the account's credentials."

  schedule_frequency = "NRT"
  entity_mappings = {
    hosts    = [{ deviceIdColumn = "DeviceId", nameColumn = "DeviceName" }]
    accounts = [{ nameColumn = "AccountName", ntDomainColumn = "AccountDomain", sidColumn = "AccountSid" }]
    ips      = [{ addressColumn = "RemoteIP" }]
  }

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
}

module "detect_inbound_internet_accepted" {
  source = "./modules/detection_rule"

  rule_id     = "mikrotik-inbound-internet-accepted"
  title       = "Accepted inbound traffic from the internet (MikroTik)"
  description = "Detects a session from a public (non-RFC1918) IP address accepted by the perimeter firewall. Expected only for intentionally published services / port-forwards; otherwise review the source and destination."
  status      = "experimental"
  author      = "zamomfg"
  date        = "2026-09-22"
  modified    = ""
  logsource   = { category = "firewall", product = "mikrotik" }
  references  = []
  false_positives = [
    "Intentionally published services and port-forwards",
  ]
  severity      = "medium"
  mitre_tactics = [{ tactic = "InitialAccess", techniques = ["T1190"] }]

  recommended_actions = "Confirm the destination service is intentionally published. If not, tighten the firewall rule and investigate the source IP."

  schedule_frequency = "PT1H"
  entity_mappings = {
    ips = [{ addressColumn = "SrcIpAddr" }]
  }

  query_text = <<-KQL
    let InternalRanges = toscalar(_GetWatchlist('Vlans') | summarize make_set(Subnet));
    ASimNetworkSessionLogs
    | where DvcAction == "Allow"
    | where isnotempty(SrcIpAddr) and isnotempty(DstIpAddr)
    | where not(ipv4_is_private(SrcIpAddr))
    | summarize SessionCount = count(), DstPorts = make_set(DstPortNumber, 100), DstHosts = make_set(DstIpAddr, 100), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) by SrcIpAddr, SrcGeoCountry, SrcGeoCity
    | extend Timestamp = LastSeen
    | extend ReportId = tostring(hash(strcat(SrcIpAddr, tostring(LastSeen))))
  KQL
}

module "detect_smartnet_egress_accepted" {
  source = "./modules/detection_rule"

  rule_id     = "mikrotik-smartnet-egress-accepted"
  title       = "SmartNet: accepted traffic leaving the segment (MikroTik)"
  description = "Detects accepted traffic from a host in the SmartNet (IoT) segment to a destination outside SmartNet (another internal segment or the internet). IoT devices normally stay within their segment; egress can indicate misconfiguration or compromise."
  status      = "experimental"
  author      = "zamomfg"
  date        = "2026-09-22"
  modified    = ""
  logsource   = { category = "firewall", product = "mikrotik" }
  references  = []
  false_positives = [
    "IoT devices reaching their vendor cloud backend or firmware update servers",
  ]
  severity      = "medium"
  mitre_tactics = [{ tactic = "CommandAndControl", techniques = ["T1071"] }]

  recommended_actions = "Verify the SmartNet host should reach this destination. If not, restrict inter-segment/egress rules and inspect the device."

  schedule_frequency = "PT1H"
  entity_mappings = {
    ips = [{ addressColumn = "SrcIpAddr" }, { addressColumn = "DstIpAddr" }]
  }

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
}

# Horizontal scan: one internal source reaching many internal hosts on the same port.
module "detect_internal_scan_horizontal" {
  source = "./modules/detection_rule"

  rule_id     = "mikrotik-internal-scan-horizontal"
  title       = "Internal horizontal scan (one source, many hosts, same port) (MikroTik)"
  description = "Detects an internal host contacting many distinct internal hosts on the same destination port within an hour - a horizontal (service) sweep looking for a specific service across the network."
  status      = "experimental"
  author      = "zamomfg"
  date        = "2026-09-22"
  modified    = ""
  logsource   = { category = "firewall", product = "mikrotik" }
  references  = []
  false_positives = [
    "Authorized vulnerability scanners or network discovery tools"
  ]
  severity      = "medium"
  mitre_tactics = [{ tactic = "Discovery", techniques = ["T1046"] }]

  recommended_actions = "Identify the source host and whether it is an authorized scanner (e.g. vulnerability management). If not, isolate and investigate."

  schedule_frequency = "PT1H"
  entity_mappings = {
    ips = [{ addressColumn = "SrcIpAddr" }]
  }

  query_text = <<-KQL
    let NrHostsThreshold = 20;
    let HostWatchlist = materialize(
        _GetWatchlist("InternalHosts")
        | where MAC != ""
        | project Host, MAC, IP
    );
    let InternalRanges = toscalar(_GetWatchlist('Vlans') | summarize make_set(Subnet));
    ASimNetworkSessionLogs
    | where ipv4_is_private(SrcIpAddr) and ipv4_is_private(DstIpAddr)
    | summarize DistinctHosts = dcount(DstIpAddr), TargetHosts = make_set(DstIpAddr, 100), Attempts = count(), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) by SrcIpAddr, DstPortNumber, NetworkProtocol
    | where DistinctHosts >= NrHostsThreshold
    | extend Timestamp = LastSeen
    | join kind=leftouter (HostWatchlist | project SrcHost = Host, IP, MAC) on $left.SrcIpAddr == $right.IP
    | project-away IP, MAC
    | project-reorder Timestamp, SrcIpAddr, SrcHost, NetworkProtocol, DistinctHosts, Attempts, DstPortNumber, FirstSeen, LastSeen
  KQL
}

# Vertical scan: one internal source hitting many ports on a single internal host.
module "detect_internal_scan_vertical" {
  source = "./modules/detection_rule"

  rule_id     = "mikrotik-internal-scan-vertical"
  title       = "Internal vertical scan (one source, many ports, single host) (MikroTik)"
  description = "Detects an internal host contacting many distinct ports on a single internal host within an hour - a vertical port scan enumerating services on one target."
  status      = "experimental"
  author      = "zamomfg"
  date        = "2026-09-22"
  modified    = ""
  logsource   = { category = "firewall", product = "mikrotik" }
  references  = []
  false_positives = [
    "Authorized vulnerability scanners"
  ]
  severity      = "medium"
  mitre_tactics = [{ tactic = "Discovery", techniques = ["T1046"] }]

  recommended_actions = "Identify the source host and whether it is an authorized scanner. If not, isolate the source and inspect the target host."

  schedule_frequency = "PT1H"
  entity_mappings = {
    ips = [{ addressColumn = "SrcIpAddr" }, { addressColumn = "DstIpAddr" }]
  }

  query_text = <<-KQL
    let NrPortsThreshold = 20;
    let HostWatchlist = materialize(
        _GetWatchlist("InternalHosts")
        | where MAC != ""
        | project Host, MAC, IP
    );
    let InternalRanges = toscalar(_GetWatchlist('Vlans') | summarize make_set(Subnet));
    ASimNetworkSessionLogs
    | where ipv4_is_private(SrcIpAddr) and ipv4_is_private(DstIpAddr)
    | sort by DstPortNumber desc
    | summarize DistinctPorts = dcount(DstPortNumber), TargetPorts = make_set(DstPortNumber, 1000), Attempts = count(), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) by SrcIpAddr, SrcMacAddr, DstIpAddr, DstMacAddr, NetworkProtocol
    | where DistinctPorts >= NrPortsThreshold
    | extend Timestamp = LastSeen
    | join kind=leftouter (HostWatchlist | project DstHost = Host, IP, MAC) on $left.DstIpAddr == $right.IP
    | join kind=leftouter (HostWatchlist | project SrcHost = Host, IP, MAC) on $left.SrcIpAddr == $right.IP
    | project-away IP, IP1, MAC, MAC1
    | project-reorder Timestamp, SrcIpAddr, SrcHost, DstIpAddr, DstHost, NetworkProtocol, DistinctPorts, Attempts, TargetPorts, FirstSeen, LastSeen
  KQL
}
