
locals {
  struct_declaration_path = "../log_struct_declaration/"
  table_postifx           = "_CL"

  # Columns present on every UniFi category table.
  unifi_common_columns = concat(
    [{ name = "TimeGenerated", type = "datetime" }],
    [for n in [
      "EventVendor", "EventTime", "Hostname", "EventCategory", "DvcType",
      "DvcMacAddr", "FirmwareVersion", "EventMessage", "Message",
    ] : { name = n, type = "string" }]
  )

  # Category-specific columns per table (all string). Single source of truth:
  # module.unifi_tables builds each table schema from common + these, and the
  # dcr_unifi transform projection (log_dcr.tf) derives its category columns
  # from the same map. Every column here must be produced by the category's
  # `extends` in local.unifi_categories.
  unifi_category_extra_columns = {
    Dropbear     = [for n in ["SrcIpAddr", "SrcPortNumber"] : { name = n, type = "string" }]
    Hostapd      = [for n in ["WlanId", "SrcType", "SrcMacAddr", "DstMacAddr", "Service"] : { name = n, type = "string" }]
    Firewall     = [for n in ["FlowId", "DvcInboundInterface", "DvcOutboundInterface", "DvcAction", "NetworkRuleName", "DstMacAddr", "SrcMacAddr", "SrcIpAddr", "SrcPortNumber", "DstIpAddr", "DstPortNumber", "NetworkBytes", "Tos", "Prec", "Ttl", "NetworkProtocol", "Window", "Res", "Mark"] : { name = n, type = "string" }]
    Stahtd       = [for n in ["SrcDvcMacAddr", "WlanId", "AssocStatus", "EventResult"] : { name = n, type = "string" }]
    AssocTracker = [for n in ["WlanId", "SrcMacAddr", "EventResult"] : { name = n, type = "string" }]
    StaEvent     = [for n in ["WlanId", "DvcAction", "SrcMacAddr", "SrcIpAddr"] : { name = n, type = "string" }]
    Logread      = [for n in ["DstIpAddr", "DstPortNumber"] : { name = n, type = "string" }]
    Stamgr       = [for n in ["DstMacAddr", "WlanId", "EventResultDetails"] : { name = n, type = "string" }]
    Vpn          = [for n in ["VpnUser", "VpnClientIp", "VpnSourceIp", "VpnName", "VpnType", "VpnServerAddress", "VpnSubnet", "VpnWan", "VpnUtcTime", "VpnDuration", "VpnUsageDown", "VpnUsageUp"] : { name = n, type = "string" }]
    WifiClient   = [for n in ["WifiClientAlias", "WifiClientHostname", "WifiClientIp", "WifiClientMac", "WifiChannel", "WifiChannelWidth", "WifiName", "WifiBand", "WifiAuthMethod", "WifiRssi", "WifiLastDeviceName", "WifiLastDeviceIp", "WifiLastDeviceMac", "WifiLastDeviceModel", "WifiConnectedDeviceName", "WifiConnectedDeviceIp", "WifiConnectedDeviceMac", "WifiConnectedDeviceModel", "WifiDuration", "WifiUsageDown", "WifiUsageUp", "WifiNetworkName", "WifiNetworkSubnet", "WifiNetworkVlan", "WifiUtcTime", "WifiLastConnectedToWiFiChannel", "WifiLastConnectedToWiFiChannelWidth", "WifiLastConnectedToWiFiBand", "WifiLastConnectedToWiFiRssi"] : { name = n, type = "string" }]
    WiredClient  = [for n in ["WiredClientAlias", "WiredClientHostname", "WiredClientIp", "WiredClientMac", "WiredConnectedDeviceName", "WiredConnectedDevicePort", "WiredConnectedDeviceIp", "WiredConnectedDeviceMac", "WiredLinkSpeed", "WiredDuration", "WiredUsageDown", "WiredUsageUp", "WiredNetworkName", "WiredNetworkSubnet", "WiredNetworkVlan", "WiredUtcTime"] : { name = n, type = "string" }]

    # Merged tables (multiple EventCategory values share one schema).
    System = []
    Dns    = [for n in ["SrcType", "DnsQuery", "DnsServer", "SrcIpAddr", "SrcPortNumber", "DstIpAddr", "DstPortNumber", "NetworkProtocol", "SrcMacAddr", "DstMacAddr"] : { name = n, type = "string" }]
  }
}

module "table_ubiquiti" {
  source = "./modules/law_table"

  name             = "Ubiquiti${local.table_postifx}"
  law_workspace_id = azurerm_log_analytics_workspace.law.id

  retention_in_days      = 90
  totalRetentionInDays   = 90
  table_struct_file_path = "${local.struct_declaration_path}/Ubiquiti_CL_struct.json"
}

# Tailscale network + configuration-audit logs, ingested by func-tailscale via
# the Logs Ingestion API (tailscale_logs.tf, dcr-tailscale in log_dcr.tf).
module "tailscale_table" {
  source = "./modules/law_table"

  name             = "TailscaleNetworkLogs_CL"
  law_workspace_id = azurerm_log_analytics_workspace.law.id

  retention_in_days    = 90
  totalRetentionInDays = 90

  columns = [
    { name = "TimeGenerated", type = "datetime" },
    { name = "NodeId", type = "string" },
    { name = "Start", type = "datetime" },
    { name = "End", type = "datetime" },
    { name = "Logged", type = "datetime" },
    { name = "VirtualTraffic", type = "dynamic" },
    { name = "PhysicalTraffic", type = "dynamic" },
    { name = "ExitTraffic", type = "dynamic" },
    { name = "SubnetTraffic", type = "dynamic" },
  ]
}

module "tailscale_audit_table" {
  source = "./modules/law_table"

  name             = "TailscaleAuditLogs_CL"
  law_workspace_id = azurerm_log_analytics_workspace.law.id

  retention_in_days    = 90
  totalRetentionInDays = 90

  columns = [
    { name = "TimeGenerated", type = "datetime" },
    { name = "EventTime", type = "datetime" },
    { name = "EventGroupID", type = "string" },
    { name = "Action", type = "string" },
    { name = "Actor", type = "dynamic" },
    { name = "Target", type = "dynamic" },
    { name = "Origin", type = "string" },
    { name = "EventType", type = "string" },
    { name = "Old", type = "dynamic" },
    { name = "New", type = "dynamic" },
  ]
}

# One tailored _CL table per UniFi log category. Driven by local.unifi_categories
# (log_dcr.tf); each table's schema is the common columns plus the category's
# entry in local.unifi_category_extra_columns above.
module "unifi_tables" {
  for_each = local.unifi_categories
  source   = "./modules/law_table"

  name             = "Ubiquiti${each.key}${local.table_postifx}"
  law_workspace_id = azurerm_log_analytics_workspace.law.id

  retention_in_days    = 90
  totalRetentionInDays = 90
  columns              = concat(local.unifi_common_columns, local.unifi_category_extra_columns[each.key])
}
