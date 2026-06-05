
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
  content_id                 = "azuresentinel.azure-sentinel-solution-azurekeyvault"
  solution_version           = "3.0.2" # omit to track catalog latest; bump to update

  install = {
    analytics_rules = true
  }
}
