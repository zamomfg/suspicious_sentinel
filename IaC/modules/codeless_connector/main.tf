# Microsoft Sentinel codeless connector (CCF). Creates the connector's gallery UI
# (dataConnectorDefinition) and one RestApiPoller dataConnector per poller, directly
# via azapi — no ARM solution template, no Content Hub install step. The DCE, DCR and
# output tables the pollers bind to are created by the caller and referenced through
# each poller's dcrConfig.

locals {
  api_version = "2025-09-01"
}

resource "azapi_resource" "definition" {
  type      = "Microsoft.SecurityInsights/dataConnectorDefinitions@${local.api_version}"
  name      = var.definition_name
  parent_id = var.workspace_id

  body = {
    kind = "Customizable"
    properties = {
      connectorUiConfig = var.connector_ui_config
    }
  }

  schema_validation_enabled = false
}

resource "azapi_resource" "metadata" {
  type      = "Microsoft.SecurityInsights/metadata@${local.api_version}"
  name      = "DataConnector-${var.definition_name}"
  parent_id = var.workspace_id

  body = {
    properties = {
      parentId  = azapi_resource.definition.id
      contentId = var.definition_name
      kind      = "DataConnector"
      version   = "1.0.0"
      source    = { kind = "LocalWorkspace", name = var.definition_name }
      author    = { name = var.author }
      support   = { name = var.support_name, tier = var.support_tier }
    }
  }

  schema_validation_enabled = false
}

resource "azapi_resource" "poller" {
  for_each = var.pollers

  type      = "Microsoft.SecurityInsights/dataConnectors@${local.api_version}"
  name      = each.key
  parent_id = var.workspace_id

  body = {
    kind       = "RestApiPoller"
    properties = each.value.properties
  }

  sensitive_body = {
    properties = each.value.sensitive_properties
  }

  sensitive_body_version = each.value.sensitive_body_version

  schema_validation_enabled = false

  depends_on = [azapi_resource.definition]
}
