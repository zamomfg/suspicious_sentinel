data "sops_file" "this" {
  source_file = var.encrypted_file_path
  input_type  = "raw"
}

locals {
  rows = csvdecode(data.sops_file.this.raw)
}

resource "azurerm_sentinel_watchlist" "this" {
  name                       = var.name
  display_name               = var.display_name
  log_analytics_workspace_id = var.log_analytics_workspace_id
  item_search_key            = var.item_search_key
}

# Decrypted rows are sensitive; key items by index (not value) so nothing leaks
# into the public CI plan output.
resource "azurerm_sentinel_watchlist_item" "this" {
  count        = length(nonsensitive(local.rows))
  watchlist_id = azurerm_sentinel_watchlist.this.id
  properties   = sensitive(local.rows[count.index])
}
