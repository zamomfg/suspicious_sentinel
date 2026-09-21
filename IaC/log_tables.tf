locals {
  table_postifx = "_CL"

  # Columns present on every custom MikroTik table (System/DNS). Sourced from the
  # native RouterOS topic header; Message is the raw SyslogMessage.
  mikrotik_common_columns = concat(
    [{ name = "TimeGenerated", type = "datetime" }],
    [for n in [
      "EventVendor", "EventProduct", "EventVersion", "Hostname", "DvcIpAddr",
      "EventCategory", "DeviceEventClassId", "EventSeverity", "EventMessage", "Message",
    ] : { name = n, type = "string" }]
  )

  # Category-specific columns per still-custom table (all string). Single source
  # of truth: module.mikrotik_tables builds each table schema from common + these,
  # and the System/DNS transform projections (log_dcr_mikrotik.tf) derive their
  # category columns from the same map. Firewall and DHCP are normalized into the
  # ASIM tables instead and have no custom table here.
  mikrotik_category_extra_columns = {
    System = [for n in ["DvcAction", "User", "SrcIpAddr", "Service"] : { name = n, type = "string" }]
    Dns    = []
  }
}

# One tailored _CL table per still-custom MikroTik topic (System/DNS). Driven by
# local.mikrotik_categories (log_dcr_mikrotik.tf); each table's schema is the
# common columns plus the category's entry in local.mikrotik_category_extra_columns.
module "mikrotik_tables" {
  for_each = local.mikrotik_categories
  source   = "./modules/law_table"

  name             = "MikroTik${each.key}${local.table_postifx}"
  law_workspace_id = azurerm_log_analytics_workspace.law_sc.id

  retention_in_days    = 90
  totalRetentionInDays = 90
  columns              = concat(local.mikrotik_common_columns, local.mikrotik_category_extra_columns[each.key])
}

# Tailscale output tables renames the raw API JSON into these PascalCase schemas.
module "tailscale_network_table" {
  source = "./modules/law_table"

  name             = "TailscaleNetworkLogs${local.table_postifx}"
  law_workspace_id = azurerm_log_analytics_workspace.law_sc.id

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
  law_workspace_id = azurerm_log_analytics_workspace.law_sc.id

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
