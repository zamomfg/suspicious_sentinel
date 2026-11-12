module "summary_outbound_network_sessions" {
  source = "./modules/summary_rule"

  name             = "outbound-network-sessions"
  law_workspace_id = azurerm_log_analytics_workspace.law_sc.id
  display_name     = "Outbound network sessions (IPv4/IPv6, allowed and blocked)"

  destination_table = module.network_session_outbound_summary_table.name
  interval          = "1h"

  # NetworkDirection isn't populated, and IPv6 LAN hosts use global addresses, so egress interface defines outbound.
  query = <<-KQL
    ASimNetworkSessionLogs
    | where DvcOutboundInterface in ("sfp1", "wg-proton")
    | extend IpVersion = iif(DstIpAddr has ":", "IPv6", "IPv4")
    | summarize
        SessionCount = count(),
        NetworkBytes = sum(NetworkBytes),
        FirstSeen = min(TimeGenerated),
        LastSeen = max(TimeGenerated)
        by SrcIpAddr, DstIpAddr, DstPortNumber, NetworkProtocol, IpVersion, DvcAction, EventResult, DvcOutboundInterface, DstGeoCountry
  KQL
}
