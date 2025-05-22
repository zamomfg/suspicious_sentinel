
# resource "azurerm_resource_group" "rg_log" {
#   name     = "rg-${var.app_name}-${local.location_short}-001"
#   location = var.location
#   tags     = var.tags
# }

resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${var.app_name}-${local.location_short}-001"
  location            = data.azurerm_resource_group.rg_log.location
  resource_group_name = data.azurerm_resource_group.rg_log.name
  tags                = var.tags

  sku               = "PerGB2018"
  retention_in_days = var.law_global_reteion_days

  # data_collection_rule_id = azurerm_monitor_data_collection_rule.workspace_dcr.id
  data_collection_rule_id = data.azurerm_monitor_data_collection_rule.workspace_dcr.id

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "sentinel" {
  workspace_id = azurerm_log_analytics_workspace.law.id
}