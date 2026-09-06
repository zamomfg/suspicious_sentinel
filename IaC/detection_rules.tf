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
