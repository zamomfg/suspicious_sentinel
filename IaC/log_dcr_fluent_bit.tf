# Generic Logs Ingestion API DCR for the Fluent Bit receiver in home_lab
# (apps/fluent-bit). Each log source gets its own input stream (Fluent Bit
# output `table_name` = stream name without the Custom- prefix) and data flows.
locals {
  fluent_bit_mikrotik_stream = "${local.custom_stream_prefix}MikroTikSyslog"

  fluent_bit_input_streams = [
    {
      stream_name = local.fluent_bit_mikrotik_stream
      column_schema = [
        { name = "TimeGenerated", type = "datetime" },
        { name = "HostName", type = "string" },
        { name = "HostIP", type = "string" },
        { name = "SyslogMessage", type = "string" },
      ]
    },
  ]

  fluent_bit_data_flows = [
    for f in local.mikrotik_flows : merge(f, {
      streams      = [local.fluent_bit_mikrotik_stream]
      destinations = [azurerm_log_analytics_workspace.law_sc.id]
    })
  ]
}

module "dcr_fluent_bit" {
  source = "./modules/dcr"

  name                = "dcr-fluentbit-${local.primary_location_short}-001"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = local.primary_location
  tags                = var.tags

  law_destinations_workspace_id = [azurerm_log_analytics_workspace.law_sc.id]
  data_collection_endpoint_id   = azurerm_monitor_data_collection_endpoint.fluent_bit.id
  data_sources_syslog           = []

  data_flows          = local.fluent_bit_data_flows
  stream_declarations = concat(local.fluent_bit_input_streams, local.mikrotik_table_stream_declarations)

  logging_workspace_id = azurerm_log_analytics_workspace.law_sc.id
}
