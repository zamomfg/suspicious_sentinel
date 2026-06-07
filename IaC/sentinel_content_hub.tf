
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

# Ubiquiti UniFi. parsers = false keeps the solution's UbiquitiAuditEvent parser
# out — our own aggregator function (law_queries.tf) over the per-category tables
# owns that alias.
module "ubiquiti_unifi" {
  source = "./modules/content_hub"

  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  resource_group_name        = data.azurerm_resource_group.rg_log.name
  workspace_name             = azurerm_log_analytics_workspace.law.name
  location                   = data.azurerm_resource_group.rg_log.location
  content_id                 = "azuresentinel.azure-sentinel-solution-ubiquitiunifi"
  solution_version           = "3.0.4" # omit to track catalog latest; bump to update

  install = {
    workbooks       = true
    hunting_queries = true
    analytics_rules = true
    parsers         = false # ours wins; see UbiquitiAuditEvent aggregator
  }
}

module "soc_handbook" {
  source = "./modules/content_hub"

  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  resource_group_name        = data.azurerm_resource_group.rg_log.name
  workspace_name             = azurerm_log_analytics_workspace.law.name
  location                   = data.azurerm_resource_group.rg_log.location
  content_id                 = "microsoftsentinelcommunity.azure-sentinel-solution-sochandbook"
  solution_version           = "3.0.6"

  install = {
    workbooks = true
  }
}

module "soc_process_framework" {
  source = "./modules/content_hub"

  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  resource_group_name        = data.azurerm_resource_group.rg_log.name
  workspace_name             = azurerm_log_analytics_workspace.law.name
  location                   = data.azurerm_resource_group.rg_log.location
  content_id                 = "azuresentinel.azure-sentinel-solution-socprocessframework"
  solution_version           = "3.0.2"

  install = {
    workbooks = true
  }
}
