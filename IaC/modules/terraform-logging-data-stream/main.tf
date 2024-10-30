

variable "dcr_name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = map()
}

variable "workspace_resource_id" {
  type = string
}

variable "data_flows" {
  type = list(object({
    input_stream  = list(string)
    output_stream = list(string)
    transform_kql = string
  }))
}

variable "data_streams" {
  type = list(object({
    table_name                         = string
    log_structure_definition_file_path = string
  }))

  validation {
    condition = endswith(var.data_streams.table_name, "_CL") == false
    error_message = "Custom tables need to end with _CL"
  }
}

locals {
  law_dest_name = "dest-law-log"

  table_name_suffix  = "_CL"
  stream_name_prefix = "Custom-"
}

resource "azurerm_monitor_data_collection_rule" "dcr_unifi_logs" {
  name                = var.dcr_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce_unifi_logs.id

  destinations {
    log_analytics {
      workspace_resource_id = var.workspace_resource_id
      name                  = local.law_dest_name
    }
  }

  dynamic "data_flow" {
    for_each = var.data_flows
    content {
      streams       = data_flow.value.input_stream
      destinations  = [local.law_dest_name]
      output_stream = data_flow.value.output_stream
      transform_kql = data_flow.value.transform_kql
    }
  }

  dynamic "stream_declaration" {
    for_each = var.data_streams

    content {
      stream_name = "${stream_name_prefix}${stream_declaration.value.table_name}"

      dynamic "column" {
        for_each = jsondecode(file("${stream_declaration.value.log_structure_definition_file_path}"))

        content {
          name = column.value.name
          type = column.value.type
        }
      }
    }
  }
}

resource "azapi_resource" "law_table" {
    count = lengt(var.data_streams)


  name      = var.data_streams[count.index].table_name
  parent_id = var.workspace_resource_id
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  body = {
    properties = {
      schema = {
        name    = var.data_streams[count.index].table_name
        columns = jsondecode(file("${var.data_streams[count.index].log_structure_definition_file_path}"))
      }
      retentionInDays      = -1
      totalRetentionInDays = -1
    }
  }

  schema_validation_enabled = false # this flag is needed since the validation fails when using the log definitions in cloumns
  depends_on                = [var.workspace_resource_id]
}
