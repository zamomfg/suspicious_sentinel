
# module "ueba_essentials" {
#   source = "./modules/content_hub"

#   log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
#   api_version                = local.settings_api_version
#   content_id                 = "azuresentinel.azure-sentinel-solution-uebaessentials"
#   solution_version           = "3.0.6" # omit to track catalog latest; bump to update

#   install = {
#     workbooks       = true
#     hunting_queries = true
#   }
# }

module "azure_key_vault" {
  source = "./modules/content_hub"

  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  resource_group_name        = data.azurerm_resource_group.rg_log.name
  workspace_name             = azurerm_log_analytics_workspace.law.name
  location                   = data.azurerm_resource_group.rg_log.location
  content_id                 = "azuresentinel.azure-sentinel-solution-azurekeyvault"
  solution_version           = "3.0.2" # omit to track catalog latest; bump to update

  install = {
    analytics_rules = true
  }
}

# Ubiquiti UniFi. Disabled while the content_hub install is reworked to deploy
# packagedContent as an ARM template (fixes the portal "metadata.properties is
# undefined" error). Re-enable once the module is converted.
# module "ubiquiti_unifi" {
#   source = "./modules/content_hub"

#   log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
#   resource_group_name        = data.azurerm_resource_group.rg_log.name
#   workspace_name             = azurerm_log_analytics_workspace.law.name
#   location                   = data.azurerm_resource_group.rg_log.location
#   content_id                 = "azuresentinel.azure-sentinel-solution-ubiquitiunifi"
#   solution_version           = "3.0.4" # omit to track catalog latest; bump to update

#   install = {
#     workbooks       = true
#     hunting_queries = true
#     analytics_rules = true
#     parsers         = false # ours wins; see UbiquitiAuditEvent passthrough
#   }
# }
