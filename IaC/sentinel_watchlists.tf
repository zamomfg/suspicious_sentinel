
locals {
  watchlist_data_base_dir = "../watchlist_data/"
}

module "internal_hosts" {
  source = "./modules/sentinel_watchlist"

  name                       = "InternalHosts"
  display_name               = "Internal hosts"
  item_search_key            = "Host"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  encrypted_file_path        = "${local.watchlist_data_base_dir}test_hosts.csv"
}

module "vlans" {
  source = "./modules/sentinel_watchlist"

  name                       = "Vlans"
  display_name               = "VLANs / network segments"
  item_search_key            = "Subnet"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  encrypted_file_path        = "${local.watchlist_data_base_dir}vlans.csv"
}

moved {
  from = azurerm_sentinel_watchlist.internal_hosts
  to   = module.internal_hosts.azurerm_sentinel_watchlist.this
}
moved {
  from = azurerm_sentinel_watchlist_item.internal_hosts
  to   = module.internal_hosts.azurerm_sentinel_watchlist_item.this
}
moved {
  from = azurerm_sentinel_watchlist.vlans
  to   = module.vlans.azurerm_sentinel_watchlist.this
}
moved {
  from = azurerm_sentinel_watchlist_item.vlans
  to   = module.vlans.azurerm_sentinel_watchlist_item.this
}