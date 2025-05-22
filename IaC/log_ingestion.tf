
resource "azurerm_monitor_data_collection_endpoint" "dce_unifi_logs" {
  name                = "dce-unifi-${local.location_short}-001"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = data.azurerm_resource_group.rg_log.location
  tags                = var.tags
}

resource "azurerm_monitor_data_collection_rule_association" "dcra_unifi_logs" {
  name                    = "acra-unifi-${local.location_short}-001"
  target_resource_id      = data.azurerm_arc_machine.arc_log_machine.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.dcr_unifi_logs.id

  # lifecycle {
  #   replace_triggered_by = [azurerm_monitor_data_collection_rule.dcr_unifi_logs]
  # }
}

locals {
  log_struct_dir = "../log_struct_declaration/"
  law_dest_name  = "dest-law-log"

  unifi_table_name  = "UnifiLogs_CL"
  unifi_stream_name = "Custom-${local.unifi_table_name}"
  unifi_log_def     = jsondecode(file("${local.log_struct_dir}/unifi_struct.json"))

  unifi_firewall_table_name  = "UnifiFirewallLogs_CL"
  unifi_firewall_stream_name = "Custom-${local.unifi_firewall_table_name}"
  unifi_firewall_log_def     = jsondecode(file("${local.log_struct_dir}/unifi_firewall_struct.json"))
}

resource "azurerm_monitor_data_collection_rule" "dcr_unifi_logs" {
  name                = "dcr-unifi-${local.location_short}-001"
  location            = data.azurerm_resource_group.rg_log.location
  resource_group_name = data.azurerm_resource_group.rg_log.name
  tags                = var.tags

  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce_unifi_logs.id

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = local.law_dest_name
    }
  }


  ###################################################

  data_flow {
    streams       = [local.unifi_firewall_stream_name]
    destinations  = [local.law_dest_name]
    output_stream = local.unifi_firewall_stream_name
    transform_kql = <<-EOT
                  source
                  | where Message matches regex @"^\[\S+?\]IN="
                  | project TimeGenerated, Message
                  | parse kind=regex Message with @"\["  Rule: string "-" RuleNr: string "-" Action: string @"\]" _INTERFACE: string " MAC=" MAC: string " SRC=" SourceIP: string " DST=" DestIP: string " "
                  | parse _INTERFACE with "IN=" InterfaceIn " OUT=" InterfaceOut
                  | parse kind=regex Message with * " LEN=" Length: int " TOS=" TypeOfService: string " PREC=" Precedence: string " TTL=" TTL: int " ID=" ID: string " PROTO="
                  | parse kind=regex Message with * " SPT=" SourcePort: int " DPT=" DestPort: int " "
                  | parse kind=relaxed Message with * " WINDOW=" WindowSize: int " RES=" Reserved: string " " Flags: string " URGP=" Urgent: int
                  | extend Rule = strcat(Rule, "-", RuleNr)
                  | extend Action = case(
                      Action == "D", "Dropped",
                      Action == "R", "Rejected",
                      Action == "A", "Accepted",
                      "Unknown"
                  )
                  | extend Protocol = extract("PROTO=(.*?) ", 1, Message)
                  | extend Flags = strcat_delim(" ", Flags, split(ID, " ", 1)[0])
                  | extend ID = toint(split(ID, " ", 0)[0])
                  | extend AddidtionalData = iff(Protocol == "ICMP", 
                          tostring(
                              bag_pack(
                                  "ICMPCode", extract("CODE=(.*?) ", 1, Message),
                                  "ICMPID", extract(@"CODE=\d ID=(.*?) ", 1, Message),
                                  "ICMSequence", extract("SEQ=(.*?) ", 1, Message)
                              )
                          )
                      , "")
                  | extend SourceLocation = geo_location(SourceIP)
                  | extend DestLocation = geo_location(DestIP)
                  | project TimeGenerated, Action, Rule, SourceIP, DestIP, SourcePort, DestPort, Protocol, Length, TTL, Flags, SourceLocation, DestLocation, MAC, ID, WindowSize, TypeOfService, InterfaceIn, InterfaceOut, Precedence, Urgent, Reserved, AddidtionalData, Message
    EOT
  }
  
  stream_declaration {
    stream_name = local.unifi_firewall_stream_name

    dynamic "column" {
      for_each = local.unifi_firewall_log_def
      content {
        name = column.value.name
        type = column.value.type
      }
    }
  }


  # do we need to replace the DCR when updating the table? i have got issues when trying to update the table and not replacing the DCR
  # but that might have to do with somthing else
  # lifecycle {
  #     replace_triggered_by = [azapi_resource.law_table_unifi]
  # }

}

resource "azurerm_monitor_diagnostic_setting" "dcr_unifi_logs_diagnostics" {
  name = "${azurerm_log_analytics_workspace.law.name}_logging_audit_metric"
  target_resource_id = azurerm_monitor_data_collection_rule.dcr_unifi_logs.id

  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

############################
############################

resource "azapi_resource" "law_table_unifi" {
  name      = local.unifi_table_name
  parent_id = azurerm_log_analytics_workspace.law.id
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  body = {
    properties = {
      schema = {
        name    = local.unifi_table_name
        columns = local.unifi_log_def
      }
      retentionInDays      = var.law_global_reteion_days
      totalRetentionInDays = var.law_global_reteion_days
    }
  }

  schema_validation_enabled = false # this flag is needed since the validation fails when using the log definitions in cloumns
  depends_on                = [azurerm_log_analytics_workspace.law]
}

resource "azapi_resource" "law_table_unifi_firewall" {
  name      = local.unifi_firewall_table_name
  parent_id = azurerm_log_analytics_workspace.law.id
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  body = {
    properties = {
      schema = {
        name    = local.unifi_firewall_table_name
        columns = local.unifi_firewall_log_def
      }
      retentionInDays      = var.law_global_reteion_days
      totalRetentionInDays = var.law_global_reteion_days
    }
  }

  schema_validation_enabled = false # this flag is needed since the validation fails when using the log definitions in cloumns
  depends_on                = [azurerm_log_analytics_workspace.law]
}

resource "azurerm_monitor_data_collection_rule" "graph_activity_dcr" {
  name                = "dcr-graphactivity-${local.location_short}-001"
  location            = data.azurerm_resource_group.rg_log.location
  resource_group_name = data.azurerm_resource_group.rg_log.name
  tags                = var.tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = local.law_dest_name
    }
  }

  data_flow {
    streams       = ["Microsoft-Table-MicrosoftGraphActivityLogs"]
    destinations  = [local.law_dest_name]
    transform_kql = <<-EOT
                  source
                  | where ServicePrincipalId != "57a2c1e0-6ad0-4b82-9bc5-608f503c3894"
    EOT
  }
}

resource "azurerm_monitor_diagnostic_setting" "graph_activity_dcr_diagnostics" {
  name = "${azurerm_log_analytics_workspace.law.name}_logging_audit_metric"
  target_resource_id = azurerm_monitor_data_collection_rule.graph_activity_dcr.id

  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_data_collection_rule" "workspace_dcr" {
  name                = "dcr-workspace-${local.location_short}-001"
  location            = data.azurerm_resource_group.rg_log.location
  resource_group_name = data.azurerm_resource_group.rg_log.name
  tags                = var.tags

  kind = "WorkspaceTransforms"

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = local.law_dest_name
    }
  }

  data_flow {
    streams       = ["Microsoft-Table-MicrosoftGraphActivityLogs"]
    destinations  = [local.law_dest_name]
    transform_kql = <<-EOT
                  source
                  | where ServicePrincipalId != "57a2c1e0-6ad0-4b82-9bc5-608f503c3894"
    EOT
  }
}

resource "azurerm_monitor_diagnostic_setting" "workspace_dcr_diagnostics" {
  name = "${azurerm_log_analytics_workspace.law.name}_logging_audit_metric"
  target_resource_id = azurerm_monitor_data_collection_rule.workspace_dcr.id

  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}


# module "custom_logging" {
#   source = "./modules/terraform-logging-data-stream"

#   dcr_name            = "dcr-log-${local.location_short}-001"
#   location            = data.azurerm_resource_group.rg_log.location
#   resource_group_name = data.azurerm_resource_group.rg_log.name
#   workspace_resource_id = azurerm_log_analytics_workspace.law.id
#   tags                = var.tags
#   # data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce_unifi_logs.id 

#   data_streams = [
#     {
#       table_name = "UnifiLogs_CL"
#       log_structure_definition_file_path = local.unifi_firewall_log_def
#     }
#   ]

#   data_flows = [ 
#     {

#     }
#     ]

# }