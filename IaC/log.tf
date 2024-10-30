
resource "azurerm_resource_group" "rg_log" {
  name     = "rg-${var.app_name}-${local.location_short}-001"
  location = var.location
  tags     = var.tags
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${var.app_name}-${local.location_short}-001"
  location            = azurerm_resource_group.rg_log.location
  resource_group_name = azurerm_resource_group.rg_log.name
  tags                = var.tags

  sku               = "PerGB2018"
  retention_in_days = var.law_global_reteion_days

}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "sentinel" {
  workspace_id = azurerm_log_analytics_workspace.law.id
}

resource "azurerm_monitor_data_collection_endpoint" "dce_unifi_logs" {
  name                = "dce-unifi-${local.location_short}-001"
  resource_group_name = azurerm_resource_group.rg_log.name
  location            = azurerm_resource_group.rg_log.location
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
  location            = azurerm_resource_group.rg_log.location
  resource_group_name = azurerm_resource_group.rg_log.name
  tags                = var.tags

  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce_unifi_logs.id

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = local.law_dest_name
    }
  }

  data_sources {
    syslog {
      facility_names = ["*"]
      log_levels     = ["*"]
      name           = "datasource-syslog"
      streams        = ["Microsoft-Syslog"]
    }
  }

  data_flow {
    streams       = ["Microsoft-Syslog"]
    destinations  = [local.law_dest_name]
    output_stream = local.unifi_stream_name
    transform_kql = <<-EOT
                      source
                      | where SyslogMessage !startswith_cs "["
                      | project TimeGenerated, Computer, Message=SyslogMessage
      EOT
  }

  stream_declaration {
    stream_name = local.unifi_stream_name

    dynamic "column" {
      for_each = local.unifi_log_def
      content {
        name = column.value.name
        type = column.value.type
      }
    }
  }

  ###################################################

  data_flow {
    streams = [local.unifi_firewall_stream_name]
    # streams = ["Microsoft-Syslog"]
    destinations = [local.law_dest_name]
    output_stream = local.unifi_firewall_stream_name
    # transform_kql = <<-EOT
    #                source
    #                 | where Message startswith_cs "["
    #                 | project TimeGenerated, Message
    #                 | parse kind=relaxed Message with "[" Rule:string "]" _INTERFACE:string " MAC=" MAC:string " SRC=" SourceIP:string " DST=" DestIP:string " LEN=" Length " TOS=" TypeOfService:string " PREC=" Precedence:string " TTL=" TTL:int " ID=" ID:string " PROTO=" Protocol:string " " _REST
    #                 | parse kind=relaxed _REST with "SPT=" SourcePort:int " DPT=" DestPort:int " WINDOW=" WindowSize:int " RES=" Reserved:string " " Flags:string " URGP=" Urgent:int
    #                 | parse _INTERFACE with "IN=" InterfaceIn " OUT=" InterfaceOut
    #                 | project-away _INTERFACE, _REST
    #                 | extend Fragment = split(ID, " ", 1)[0]
    #                 | extend ID = split(ID, " ", 0)[0]
    #                 | project TimeGenerated, Rule, SourceIP, DestIP, SourcePort, DestPort, Protocol, Length, TTL, Flags, MAC, ID, WindowSize, TypeOfService, InterfaceIn, InterfaceOut, Precedence, Urgent, Reserved, Fragment, Message
    # EOT
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
      retentionInDays      = -1
      totalRetentionInDays = -1
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
      retentionInDays      = -1
      totalRetentionInDays = -1
    }
  }

  schema_validation_enabled = false # this flag is needed since the validation fails when using the log definitions in cloumns
  depends_on                = [azurerm_log_analytics_workspace.law]
}



# module "custom_logging" {
#   source = "./modules/terraform-logging-data-stream"

#   dcr_name            = "dcr-log-${local.location_short}-001"
#   location            = azurerm_resource_group.rg_log.location
#   resource_group_name = azurerm_resource_group.rg_log.name
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
