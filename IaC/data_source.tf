
data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "rg_log" {
  name = "rg-log-neu-01"
}

data "azurerm_arc_machine" "home_lab_ama" {
  resource_group_name = "rg-arc-prod-sc"
  name                = "ubuntu-ama"
}

# data "azurerm_monitor_data_collection_rule" "workspace_dcr" {
#   name = "dcr-workspace-sc-001"
#   resource_group_name = "rg-log-sc-001"
# }
