
locals {
  watchlist_data_base_dir = "../watchlist_data/"

  # Decrypted at plan/apply by the sops provider; sensitive, so items are keyed
  # by index (not hostname) to keep values out of the public CI plan output.
  internal_hosts = csvdecode(data.sops_file.internal_hosts.raw)
  vlans          = csvdecode(data.sops_file.vlans.raw)
}

data "sops_file" "internal_hosts" {
  source_file = "${local.watchlist_data_base_dir}test_hosts.csv"
  input_type  = "raw"
}

resource "azurerm_sentinel_watchlist" "internal_hosts" {
  name                       = "InternalHosts"
  display_name               = "Internal hosts"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  item_search_key            = "Host"
}

resource "azurerm_sentinel_watchlist_item" "internal_hosts" {
  count        = length(nonsensitive(local.internal_hosts))
  watchlist_id = azurerm_sentinel_watchlist.internal_hosts.id
  properties   = sensitive(local.internal_hosts[count.index])
}

data "sops_file" "vlans" {
  source_file = "${local.watchlist_data_base_dir}vlans.csv"
  input_type  = "raw"
}

resource "azurerm_sentinel_watchlist" "vlans" {
  name                       = "Vlans"
  display_name               = "VLANs / network segments"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  item_search_key            = "Subnet"
}

resource "azurerm_sentinel_watchlist_item" "vlans" {
  count        = length(nonsensitive(local.vlans))
  watchlist_id = azurerm_sentinel_watchlist.vlans.id
  properties   = sensitive(local.vlans[count.index])
}

# module "test_watchlist" {
#   source = "./modules/sentinel_watchlist"

#   name  = "Test watchlist module"
#   alias = "wl-test-watchlist-module"

#   log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
#   storage_account            = azurerm_storage_account.sa_watchlist
#   storage_container_name     = azurerm_storage_container.container_watchlist.name

#   file_name = "test_hosts.csv"
#   file_path = "${local.watchlist_data_base_dir}test_hosts.csv"

#   itemsSearchKey = "Host"

# }