
locals {
  custom_stream_prefix = "Custom-"
}

# module "dcr_workspace" {
#   source = "./modules/dcr"

#   name                = "dcr-workspace-${local.location_short}-001"
#   resource_group_name = azurerm_resource_group.rg_log.name
#   location            = azurerm_resource_group.rg_log.location
#   tags                = var.tags

#   law_destinations_workspace_id = [azurerm_log_analytics_workspace.law_sc.id]
#   kind                          = "WorkspaceTransforms"

#   data_flows = []

#   stream_declarations = []

#   logging_workspace_id = azurerm_log_analytics_workspace.law_sc.id
# }
