locals {
  table_postifx = "_CL"

  # Columns present on every MikroTik table. Sourced from the CEF envelope
  # (header + dvchost/dvc/msg extension); Message is the raw SyslogMessage.
  mikrotik_common_columns = concat(
    [{ name = "TimeGenerated", type = "datetime" }],
    [for n in [
      "EventVendor", "EventProduct", "EventVersion", "Hostname", "DvcIpAddr",
      "EventCategory", "DeviceEventClassId", "EventSeverity", "EventMessage", "Message",
    ] : { name = n, type = "string" }]
  )

  # Category-specific columns per table (all string). Single source of truth:
  # module.mikrotik_tables builds each table schema from common + these, and the
  # dcr_mikrotik transform projection (log_dcr.tf) derives its category columns
  # from the same map. Every column here must be produced by the category's
  # `extends` in local.mikrotik_categories, which parse the CEF `msg` body.
  mikrotik_category_extra_columns = {
    Firewall = [for n in ["NetworkRuleName", "Chain", "DvcAction", "DvcInboundInterface", "DvcOutboundInterface", "ConnectionState", "SrcMacAddr", "NetworkProtocol", "SrcIpAddr", "SrcPortNumber", "DstIpAddr", "DstPortNumber", "NatInfo", "NetworkBytes"] : { name = n, type = "string" }]
    Dhcp     = [for n in ["DhcpServer", "DvcAction", "SrcIpAddr", "SrcMacAddr", "SrcHostname"] : { name = n, type = "string" }]
    System   = [for n in ["DvcAction", "User", "SrcIpAddr", "Service"] : { name = n, type = "string" }]
    Dns      = []
  }
}

# One tailored _CL table per MikroTik CEF topic. Driven by local.mikrotik_categories
# (log_dcr.tf); each table's schema is the common columns plus the category's
# entry in local.mikrotik_category_extra_columns above.
module "mikrotik_tables" {
  for_each = local.mikrotik_categories
  source   = "./modules/law_table"

  name             = "MikroTik${each.key}${local.table_postifx}"
  law_workspace_id = azurerm_log_analytics_workspace.law.id

  retention_in_days    = 90
  totalRetentionInDays = 90
  columns              = concat(local.mikrotik_common_columns, local.mikrotik_category_extra_columns[each.key])
}

# Tailscale output tables renames the raw API JSON into these PascalCase schemas.
module "tailscale_network_table" {
  source = "./modules/law_table"

  name             = "TailscaleNetworkLogs${local.table_postifx}"
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

  name             = "TailscaleAuditLogs${local.table_postifx}"
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
