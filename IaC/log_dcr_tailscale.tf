# Input streams carry the raw API wire schema (camelCase, incl. reserved `type`); the transform renames it into the tables. Names stay distinct from the Custom-<table>_CL output streams so source binds to these columns.
locals {
  tailscale_audit_stream   = "${local.custom_stream_prefix}TailscaleAuditLogs"
  tailscale_network_stream = "${local.custom_stream_prefix}TailscaleNetworkLogs"

  tailscale_audit_input_stream_columns = [
    { name = "eventTime", type = "string" },
    { name = "eventGroupID", type = "string" },
    { name = "action", type = "string" },
    { name = "actor", type = "dynamic" },
    { name = "target", type = "dynamic" },
    { name = "origin", type = "string" },
    { name = "type", type = "string" },
    { name = "old", type = "dynamic" },
    { name = "new", type = "dynamic" },
  ]

  tailscale_network_input_stream_columns = [
    { name = "nodeId", type = "string" },
    { name = "start", type = "string" },
    { name = "end", type = "string" },
    { name = "logged", type = "string" },
    { name = "virtualTraffic", type = "dynamic" },
    { name = "physicalTraffic", type = "dynamic" },
    { name = "exitTraffic", type = "dynamic" },
    { name = "subnetTraffic", type = "dynamic" },
  ]
}

module "tailscale_dcr" {
  source = "./modules/dcr"

  name                = "dcr-tailscale-${local.primary_location_short}-001"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = local.primary_location
  tags                = var.tags

  data_collection_endpoint_id   = azurerm_monitor_data_collection_endpoint.tailscale.id
  law_destinations_workspace_id = [azurerm_log_analytics_workspace.law_sc.id]
  data_sources_syslog           = []
  logging_workspace_id          = azurerm_log_analytics_workspace.law_sc.id

  stream_declarations = [
    {
      stream_name   = local.tailscale_network_stream
      column_schema = local.tailscale_network_input_stream_columns
    },
    {
      stream_name   = local.tailscale_audit_stream
      column_schema = local.tailscale_audit_input_stream_columns
    },
  ]

  data_flows = [
    {
      streams       = [local.tailscale_network_stream]
      destinations  = [azurerm_log_analytics_workspace.law_sc.id]
      output_stream = "${local.custom_stream_prefix}${module.tailscale_network_table.name}"
      transform_kql = <<-KQL
        source
        | project
            TimeGenerated   = todatetime(logged),
            NodeId          = tostring(nodeId),
            Start           = todatetime(start),
            End             = todatetime(end),
            Logged          = todatetime(logged),
            VirtualTraffic  = virtualTraffic,
            PhysicalTraffic = physicalTraffic,
            ExitTraffic     = exitTraffic,
            SubnetTraffic   = subnetTraffic
      KQL
    },
    {
      streams       = [local.tailscale_audit_stream]
      destinations  = [azurerm_log_analytics_workspace.law_sc.id]
      output_stream = "${local.custom_stream_prefix}${module.tailscale_audit_table.name}"
      transform_kql = <<-KQL
        source
        | project
            TimeGenerated = todatetime(eventTime),
            EventTime     = todatetime(eventTime),
            EventGroupID  = tostring(eventGroupID),
            Action        = tostring(action),
            Actor         = actor,
            Target        = target,
            Origin        = tostring(origin),
            EventType     = tostring(type),
            Old           = old,
            New           = new
      KQL
    },
  ]

  depends_on = [module.tailscale_network_table, module.tailscale_audit_table]
}
