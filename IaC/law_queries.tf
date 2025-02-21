
resource "azurerm_log_analytics_query_pack" "query_pack" {
    name                = "pack-queries-${local.location_short}-001"
    resource_group_name = azurerm_resource_group.rg_log.name
    location            = azurerm_resource_group.rg_log.location
}


module "local_ip_ranges" {
  source = "./modules/terraform-file-storage"

  storage_account = azurerm_storage_account.watchlist_sa
  storage_container_name = azurerm_storage_container.watchlist_sa_container.name
  content_file_path = "../watchlist_data/local_ip_ranges.csv"
}

resource "azurerm_log_analytics_query_pack_query" "query_local_ip_ranges" {

  query_pack_id = azurerm_log_analytics_query_pack.query_pack.id
  display_name = "local_IP_network"

  body = <<-EOT
        let LocalRanges = externaldata(Name:string, IpRange:string)
        [ 
            h@"(${module.local_ip_ranges.sas_token_url}"
        ] with (format="csv");
  EOT
}

# locals {
#   query_path = "../queries/"
#   files = fileset(local.query_path, "*.kql")
# }

# resource "azurerm_log_analytics_query_pack_query" "query" {
#   for_each = local.files

#   query_pack_id = azurerm_log_analytics_query_pack.query_pack.id
#   display_name = each.value

#   body = file("${local.query_path}/${each.value}")
# }