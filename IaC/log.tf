
locals {
  settings_api_version = "2025-06-01"
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${var.app_name}-${local.location_short}-001"
  location            = data.azurerm_resource_group.rg_log.location
  resource_group_name = data.azurerm_resource_group.rg_log.name
  tags                = var.tags

  sku               = "PerGB2018"
  retention_in_days = var.law_global_reteion_days

  # data_collection_rule_id = data.azurerm_monitor_data_collection_rule.workspace_dcr.id

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "sentinel" {
  workspace_id = azurerm_log_analytics_workspace.law.id
}

# resource "azapi_resource" "anomalies" {
#   type      = "Microsoft.SecurityInsights/settings@${local.settings_api_version}"
#   name      = "Anomalies"
#   parent_id = azurerm_log_analytics_workspace.law.id
#   body      = { kind = "Anomalies", properties = { isEnabled = true } }

#   schema_validation_enabled = false
# }

# resource "azapi_resource" "entity_analytics" {
#   type      = "Microsoft.SecurityInsights/settings@${local.settings_api_version}"
#   name      = "EntityAnalytics"
#   parent_id = azurerm_log_analytics_workspace.law.id
#   body      = { kind = "EntityAnalytics", properties = { entityProviders = ["AzureActiveDirectory"] } }

#   schema_validation_enabled = false
# }

# # resource "azapi_resource" "eyes_on" {
# #   type      = "Microsoft.SecurityInsights/settings@${local.settings_api_version}"
# #   name      = "EyesOn"
# #   parent_id = azurerm_log_analytics_workspace.law.id
# #   body      = { kind = "EyesOn", properties = { isEnabled = true } }
# # }

resource "azapi_resource" "ueba" {
  type      = "Microsoft.SecurityInsights/settings@${local.settings_api_version}"
  name      = "Ueba"
  parent_id = azurerm_log_analytics_workspace.law.id
  body = {
    kind       = "Ueba"
    properties = { dataSources = ["AuditLogs", "AzureActivity", "SecurityEvent", "SigninLogs"] }
  }

  schema_validation_enabled = false
}