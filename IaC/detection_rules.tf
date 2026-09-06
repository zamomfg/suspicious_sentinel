# Defender XDR custom detections (tenant-scoped, via the Microsoft Graph
# security/rules/detectionRules beta API). These are not bound to a workspace.

# Successful SSH logon to a Linux/Arc host from a public (non-RFC1918) source IP.
# Fires, for example, when someone reaches an Azure Arc-enabled server over SSH
# from Azure Cloud Shell (`az ssh arc`), whose egress is a public Azure IP.
# Single-table query so it is eligible for continuous (NRT) evaluation.
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
    | where isnotempty(RemoteIP) and not(ipv4_is_private(RemoteIP))
    | where RemoteIP != "127.0.0.1" and RemoteIP != "::1"
    | project Timestamp, ReportId, DeviceId, DeviceName, AccountName, AccountDomain, AccountSid, RemoteIP, LogonType, InitiatingProcessFileName
  KQL

  alert_title         = "SSH login to a Linux host from a public IP address"
  alert_description   = "A successful SSH logon to a Linux/Arc host came from a public source IP address."
  category            = "InitialAccess"
  recommended_actions = "Confirm the source IP and account are expected (e.g. Azure Cloud Shell / az ssh arc). If not, isolate the host and reset the account's credentials."

  mitre_tactics = [
    { tactic = "InitialAccess", techniques = ["T1078"] },
    { tactic = "LateralMovement", techniques = ["T1021.004"] },
  ]

  entity_mappings = {
    hosts    = [{ deviceIdColumn = "DeviceId", nameColumn = "DeviceName" }]
    accounts = [{ nameColumn = "AccountName", ntDomainColumn = "AccountDomain", sidColumn = "AccountSid" }]
    ips      = [{ addressColumn = "RemoteIP" }]
  }
}
