
resource "azurerm_storage_account" "archive_storage" {
  name                     = "dls-${var.app_name}-${local.location_short}-001"
  resource_group_name      = data.azurerm_resource_group.rg_log.name
  location                 = data.azurerm_resource_group.rg_log.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  is_hns_enabled = true
  account_kind = "StorageV2"

  tags = var.tags
}

resource "azurerm_storage_data_lake_gen2_filesystem" "archive_storage_filesystem" {
  name               = "dlsfs-${var.app_name}-${local.location_short}-001"
  storage_account_id = azurerm_storage_account.archive_storage.id
}