
locals {
    law_map = {
    for idx, id in var.law_destinations_workspace_id : id => "log_law_${idx}"
  }
}

resource "azurerm_monitor_data_collection_rule" "dcr" {
  name = var.name
  resource_group_name = var.resource_group_name
  location = var.location
  tags = var.tags

  kind = var.kind
  data_collection_endpoint_id = var.data_collection_endpoint_id

  dynamic "destinations" {
    for_each = var.law_destinations_workspace_id
    content {
      log_analytics {
        name = local.law_map[destinations.value]
        workspace_resource_id = destinations.value
      }
    }
  }

  dynamic "data_flow" {
    for_each = var.data_flows
    content {
      destinations = [for id in data_flow.value.destinations : lookup(local.law_map, id, null)]
      streams      = data_flow.value.streams
      built_in_transform = try(data_flow.value.built_in_transform, null)
      output_stream      = try(data_flow.value.output_stream, null)
      transform_kql      = try(data_flow.value.transform_kql, null)
    }
  }

  dynamic "stream_declaration" {
    for_each = var.stream_declarations
    content {
      stream_name = stream_declaration.value.stream_name

      dynamic "column" {
        for_each = stream_declaration.value.column_schema
        content {
          name = column.value.name
          type = column.value.type
        }
      }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "dcr_diagnostics" {
  count = var.logging_workspace_id != null ? 1 : 0

  name = "${regex("[^/]+$", var.logging_workspace_id)}_all_logs"
  target_resource_id = azurerm_monitor_data_collection_rule.dcr.id

  log_analytics_workspace_id = var.logging_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

data "azapi_resource" "data_dcr" {
  type = "Microsoft.Insights/dataCollectionRules@2023-03-11"
  resource_id   = azurerm_monitor_data_collection_rule.dcr.id

  response_export_values = ["properties.immutableId"]
}


# TODO: need to check if dcra works with another dcr and vms or if the name clashing creates issues
# TODO: check compability with using dcra and dce at the same time
resource "azurerm_monitor_data_collection_rule_association" "dcra_virtual_machine" {
  count                 =  length(var.vm_association_ids)

  name                    = "dcra-${count.index}"
  target_resource_id      = var.vm_association_ids[count.index]
  data_collection_rule_id = azurerm_monitor_data_collection_rule.dcr.id
}