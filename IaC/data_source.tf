
data "azurerm_arc_machine" "arc_log_machine" {
  name = "log.server.local"
  resource_group_name = "rg-arc-prod-sc"
}