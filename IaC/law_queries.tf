
locals {
  custom_query_prefix = "ct_"
  custom_func_prefix  = "ft_"
}

resource "azurerm_log_analytics_query_pack" "query_pack" {
  name                = "pack-queries-${local.location_short}-001"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = data.azurerm_resource_group.rg_log.location
  tags                = var.tags
}

# Aggregator parser for the Ubiquiti UniFi solution.
#
# We deliberately do NOT install the solution's own parser since we have set up parsing for the unifi events at transform time
resource "azurerm_log_analytics_saved_search" "ubiquiti_audit_event_aggregator" {
  name                       = "UbiquitiAuditEvent"
  function_alias             = "UbiquitiAuditEvent"
  display_name               = "Parser for UbiquitiAuditEvent"
  category                   = "Microsoft Sentinel Parser"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  query = "union isfuzzy=true ${join(", ", [for k in keys(local.unifi_categories) : module.unifi_tables[k].name])}"
}

resource "azurerm_log_analytics_query_pack_query" "dcr_metrics" {
  query_pack_id = azurerm_log_analytics_query_pack.query_pack.id
  display_name  = "${local.custom_query_prefix}dcr_mectrics"

  body = <<-EOT
    AzureMetrics
    | where TimeGenerated > ago(6h)
    | where ResourceId has "/DATACOLLECTIONRULES/"
    | where MetricName in ("LogsIngestionBytes","RowsReceived_Count","RowsDropped_Count","LogsTransformationErrors", "TransformationRuntime_DurationMs")
    | summarize Total = sum(Total) by MetricName, bin(TimeGenerated, 15m)
    | render timechart
  EOT
}

resource "azurerm_log_analytics_saved_search" "func_geolite_asn" {
  name           = "${local.custom_func_prefix}asn_info"
  function_alias = "${local.custom_func_prefix}asn_info"
  display_name   = "${local.custom_func_prefix}asn_info"

  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  category = "custom"
  query    = <<-EOT
                let ASN = externaldata(IpRange:string, ASN:string,ASNorg:string)
                [ 
                  h@"${local.asn_blob_sas_url}"
                ] with (format="csv", ignoreFirstRecord=true);
                ASN
  EOT
}

# resource "azurerm_log_analytics_saved_search" "func_local_ip_ranges" {
#   name                       = "${local.custom_func_prefix}local_ip_ranges"
#   function_alias             = "${local.custom_func_prefix}local_ip_ranges"
#   display_name               = "${local.custom_func_prefix}local_ip_ranges"

#   log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

#   category     = "custom"
#   query        = <<-EOT
#                 let LocalRanges = externaldata(Name:string, IpRange:string)
#                 [ 
#                   h@"${module.local_ip_ranges.sas_token_url}"
#                 ] with (format="csv", ignoreFirstRecord=true);
#                 LocalRanges
#   EOT
# }
