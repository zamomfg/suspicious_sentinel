
locals {
  custom_query_prefix = "ct_"
  custom_func_prefix  = "ft_" 
}

resource "azurerm_log_analytics_query_pack" "query_pack" {
    name                = "pack-queries-${local.location_short}-001"
    resource_group_name = data.azurerm_resource_group.rg_log.name
    location            = data.azurerm_resource_group.rg_log.location
    tags                = var.tags
}


# module "local_ip_ranges" {
#   source = "./modules/terraform-file-storage"

#   storage_account = azurerm_storage_account.watchlist_sa
#   storage_container_name = azurerm_storage_container.watchlist_sa_container.name
#   content_file_path = "../watchlist_data/local_ip_ranges.csv"
# }

# resource "azurerm_log_analytics_query_pack_query" "query_local_ip_ranges" {

#   query_pack_id = azurerm_log_analytics_query_pack.query_pack.id
#   display_name = "${local.custom_query_prefix}local_IP_network"

#   body = <<-EOT
#         let LocalRanges = externaldata(Name:string, IpRange:string)
#         [ 
#           h@"${module.local_ip_ranges.sas_token_url}"
#         ] with (format="csv", ignoreFirstRecord=true);
#         LocalRanges
#   EOT
# }

# resource "azurerm_log_analytics_saved_search" "func_local_ip_ranges" {
#   name                       = "${local.custom_func_prefix}local_ip_ranges"
#   function_alias             = "${local.custom_func_prefix}local_ip_ranges"
#   display_name               = "${local.custom_func_prefix}local_ip_ranges"

#   log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

#   category     = "custom"
#   query        = <<-EOT
#                 let LocalRanges = externaldata(Name:string, IpRange:string)
#                 [ 
#                   h@"${module.local_ip_ranges.sas_token_url}"
#                 ] with (format="csv", ignoreFirstRecord=true);
#                 LocalRanges
#   EOT
# }

# module "geolite_asn" {
#   source = "./modules/terraform-file-storage"

#   storage_account = azurerm_storage_account.watchlist_sa
#   storage_container_name = azurerm_storage_container.watchlist_sa_container.name
#   content_file_path = "../watchlist_data/GeoLite2-ASN-Blocks-IPv4.csv"
# }

# resource "azurerm_log_analytics_query_pack_query" "query_geolite_asn" {

#   query_pack_id = azurerm_log_analytics_query_pack.query_pack.id
#   display_name = "${local.custom_query_prefix}ASN_info"

#   body = <<-EOT
#         let ASN = externaldata(IpRange:string, ASN:string,ASNorg:string)
#         [ 
#           h@"${module.geolite_asn.sas_token_url}"
#         ] with (format="csv", ignoreFirstRecord=true);
#         ASN
#   EOT
# }

# resource "azurerm_log_analytics_saved_search" "func_geolite_asn" {
#   name                       = "${local.custom_func_prefix}asn_info"
#   function_alias             = "${local.custom_func_prefix}asn_info"
#   display_name               = "${local.custom_func_prefix}asn_info"

#   log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

#   category     = "custom"
#   query        = <<-EOT
#                 let ASN = externaldata(IpRange:string, ASN:string,ASNorg:string)
#                 [ 
#                   h@"${module.geolite_asn.sas_token_url}"
#                 ] with (format="csv", ignoreFirstRecord=true);
#                 ASN
#   EOT
# }