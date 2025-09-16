
resource "azurerm_storage_blob" "blob_watchlist" {
  name                   = var.file_name
  storage_account_name   = var.storage_account.name
  storage_container_name = var.storage_container_name
  type                   = "Block"
  source_content         = file(var.file_path)
}

data "azurerm_storage_account_sas" "sas_watchlist" {
  connection_string = var.storage_account.primary_connection_string
  https_only        = true

  start  = timeadd(timestamp(), "-5m")
  expiry = timeadd(timestamp(), "720h") # hours = 30 days

  resource_types {
    service   = false
    container = false
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  permissions {
    read    = true
    write   = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
    delete  = false
    tag     = false
    filter  = false
  }
}

locals {
  sas_url = "${azurerm_storage_blob.blob_watchlist.url}${data.azurerm_storage_account_sas.sas_watchlist.sas}"
}

resource "azapi_resource" "wl_test" {
  type      = "Microsoft.SecurityInsights/watchlists@2022-01-01-preview"
  name      = var.alias
  parent_id = var.log_analytics_workspace_id

  body = {
    properties = {
      displayName         = var.name
      description         = var.description
      itemsSearchKey      = var.itemsSearchKey
      provider            = var.watchlist_provider
      sourceType          = "AzureStorage"
      source              = azurerm_storage_blob.blob_watchlist.name
      contentType         = "text/csv"
      numberOfLinesToSkip = 0
      sasUri              = local.sas_url
    }
  }
}
