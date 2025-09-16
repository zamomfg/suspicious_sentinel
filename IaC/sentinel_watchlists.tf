
locals {
  watchlist_data_base_dir = "../watchlist_data"
}

resource "random_string" "rand" {
  length  = 3
  upper   = false
  lower   = true
  numeric = true
  special = false
}

resource "azurerm_storage_account" "sa_watchlist" {
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = var.location

  name = "stwawl${local.location_short}${random_string.rand.result}"

  account_tier             = "Standard"
  account_replication_type = "LRS"

  https_traffic_only_enabled    = true
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = true

  shared_access_key_enabled       = true
  default_to_oauth_authentication = true
}

resource "azurerm_storage_container" "container_watchlist" {
  name                  = "watchlists"
  storage_account_id    = azurerm_storage_account.sa_watchlist.id
  container_access_type = "private"
}

# module "test_watchlist" {
#   source = "./modules/sentinel_watchlist"

#   name = "Test watchlist module"
#   alias = "wl-test-watchlist-module"
  
#   log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
#   storage_account = azurerm_storage_account.sa_watchlist
#   storage_container_name = azurerm_storage_container.container_watchlist.name

#   file_name = "test_hosts.csv"
#   file_path = "${local.watchlist_data_base_dir}test_hosts.csv"

#   itemsSearchKey = "Host"

# }