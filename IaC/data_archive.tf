
resource "azurerm_storage_account" "archive_storage" {
  name                     = "sa${var.app_name}${local.location_short}001"
  resource_group_name      = data.azurerm_resource_group.rg_log.name
  location                 = data.azurerm_resource_group.rg_log.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  local_user_enabled              = false

  is_hns_enabled = true
  account_kind   = "StorageV2"

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  tags = var.tags
}

resource "azurerm_role_assignment" "pipeline_permissions_archive_storage" {
  scope                = azurerm_storage_account.archive_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.current_sp_id
}

# resource "azurerm_storage_data_lake_gen2_filesystem" "archive_storage_filesystem" {
#   name               = "dlsfs-${var.app_name}-${local.location_short}-001"
#   storage_account_id = azurerm_storage_account.archive_storage.id
# }