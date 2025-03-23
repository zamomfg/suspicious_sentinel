
locals {
  watchlist_data_base_dir = "../watchlist_data"
  # ip_asn_csv = csvdecode(file("${local.watchlist_data_base_dir}/GeoLite2-ASN-Blocks-IPv4.csv"))

  # tor_exit_nodes = toset(split("\n", data.http.tor_exit_nodes_data.response_body))

  # sub = "/subscription"
  # permission_storage_blob_data_contributor = "providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe"
}

resource "azurerm_storage_account" "watchlist_sa" {
  name                = "sasentinelwl${local.location_short}001"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = data.azurerm_resource_group.rg_log.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  blob_properties {
    cors_rule {
      allowed_headers    = [""]
      allowed_origins    = ["https://*.portal.azure.net"]
      allowed_methods    = ["GET", "OPTIONS"]
      exposed_headers    = [""]
      max_age_in_seconds = 0
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "watchlist_sa_container" {
  name                  = "watchlists"
  storage_account_name  = azurerm_storage_account.watchlist_sa.name
  container_access_type = "private"
}

output "role_id" {
  value = "${azurerm_storage_account.watchlist_sa.id}/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe"
}

resource "azurerm_role_assignment" "watchlist_role_assignment" {
  scope                = azurerm_storage_account.watchlist_sa.id
  # role_definition_id  = join("/", [local.sub, var.subscription_id, local.permission_storage_blob_data_contributor])
  role_definition_id   = trim("${azurerm_storage_account.watchlist_sa.id}/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe", "/")
  # role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.current_sp_id
}


# resource "azurerm_sentinel_watchlist" "watchlist_ip_asn" {
#   name                       = "IpASN-wl"
#   display_name               = "IpASN-wl"
#   log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
#   item_search_key            = "IPRange"
# }

# resource "azurerm_storage_blob" "watchlist_ip_asn_blob" {
#   name                   = "ans_ipv4_geoip.zip"
#   storage_account_name   = azurerm_storage_account.watchlist_sa.name
#   storage_container_name = azurerm_storage_container.watchlist_sa_container.name
#   type                   = "Block"
#   source_content         = file("${local.watchlist_data_base_dir}/GeoLite2-ASN-Blocks-IPv4.csv")
#   content_md5            = filemd5("${local.watchlist_data_base_dir}/GeoLite2-ASN-Blocks-IPv4.csv")
# }

# resource "azurerm_sentinel_watchlist" "watchlist_tor_exit_nodes" {
#   name                       = "TorExitNodes-wl"
#   display_name               = "TorExitNodes-wl"
#   log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
#   item_search_key            = "IPAddress"
# }

# resource "azurerm_sentinel_watchlist" "watchlist_ip_country" {
#   name                       = "IpCountry-wl"
#   display_name               = "IpCountry-wl"
#   log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
#   item_search_key            = "IPRange"
# }

# resource "azurerm_storage_blob" "watchlist_ip_country_blob" {
#   name                   = "country_ipv4_geoip.csv"
#   storage_account_name   = azurerm_storage_account.watchlist_sa.name
#   storage_container_name = azurerm_storage_container.watchlist_sa_container.name
#   type                   = "Block"
#   source_content         = file("${local.watchlist_data_base_dir}/geo_ip.csv")
#   content_md5            = filemd5("${local.watchlist_data_base_dir}/geo_ip.csv")

# }

# data "http" "tor_exit_nodes_data" {
#   # url = "https://raw.githubusercontent.com/alireza-rezaee/tor-nodes/main/latest.exits.csv"
#   url = "https://raw.githubusercontent.com/mmpx12/proxy-list/refs/heads/master/tor-exit-nodes.txt"
# }

# locals {
#   watch_list_tor_ips = <<-EOT
#                           ${azurerm_sentinel_watchlist.watchlist_tor_exit_nodes.item_search_key}
#                           ${data.http.tor_exit_nodes_data.response_body}"
#                           EOT
# }

# resource "azurerm_storage_blob" "watchlist_tor_ip_blob" {
#   name                   = "tor_ip_exit_nodes.txt"
#   storage_account_name   = azurerm_storage_account.watchlist_sa.name
#   storage_container_name = azurerm_storage_container.watchlist_sa_container.name
#   type                   = "Block"
#   source_content         = local.watch_list_tor_ips
#   content_md5            = md5(local.watch_list_tor_ips)
# }

# module "test_wl" {
#   source = "./modules/terraform-watchlist"

#   name = "test_wl"
#   log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
#   item_search_key            = "name"
#   storage_account = azurerm_storage_account.watchlist_sa
#   storage_container_name = azurerm_storage_container.watchlist_sa_container.name
#   watchlist_content_file_path = "../watchlist_data/test.csv"
#   use_storage_account = true

# }

# module "ip_asn_wl" {
#   source = "./modules/terraform-watchlist"

#   name = "ip_asn_wl"
#   log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
#   item_search_key            = "IPRange"
#   storage_account = azurerm_storage_account.watchlist_sa
#   storage_container_name = azurerm_storage_container.watchlist_sa_container.name
#   watchlist_content_file_path = "../watchlist_data/GeoLite2-ASN-Blocks-IPv4.csv"
#   use_storage_account = true

# }