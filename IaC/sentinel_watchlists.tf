
locals {
  watchlist_data_base_dir = "../watchlist_data/"
}

module "internal_hosts" {
  source = "./modules/sentinel_watchlist"

  name                       = "InternalHosts"
  display_name               = "Internal hosts"
  item_search_key            = "Host"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  file_path                  = "${local.watchlist_data_base_dir}test_hosts.csv"
  encrypted                  = true
}

module "vlans" {
  source = "./modules/sentinel_watchlist"

  name                       = "Vlans"
  display_name               = "VLANs / network segments"
  item_search_key            = "Subnet"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  file_path                  = "${local.watchlist_data_base_dir}vlans.csv"
  encrypted                  = true
}