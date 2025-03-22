
data "azurerm_resource_group" "rg_log" {
  name = "rg-log-sc-001"
}

data "azurerm_arc_machine" "arc_log_machine" {
  name = "log.server.local"
  resource_group_name = "rg-arc-prod-sc"
}

data "azurerm_monitor_data_collection_rule" "workspace_dcr" {
  name = "dcr-workspace-sc-001"
  resource_group_name = "rg-log-sc-001"
}