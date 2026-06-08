data "sops_file" "this" {
  count       = var.encrypted ? 1 : 0
  source_file = var.file_path
  input_type  = "raw"
}

locals {
  rows = var.encrypted ? csvdecode(data.sops_file.this[0].raw) : csvdecode(file(var.file_path))
  # count must be non-sensitive; the encrypted branch's rows are sensitive.
  row_count = var.encrypted ? length(nonsensitive(local.rows)) : length(local.rows)
}

resource "azurerm_sentinel_watchlist" "this" {
  name                       = var.name
  display_name               = var.display_name
  log_analytics_workspace_id = var.log_analytics_workspace_id
  item_search_key            = var.item_search_key
}

# Items keyed by index; for encrypted sources the value is marked sensitive so
# it never leaks into the public CI plan output.
resource "azurerm_sentinel_watchlist_item" "this" {
  count        = local.row_count
  watchlist_id = azurerm_sentinel_watchlist.this.id
  properties   = var.encrypted ? sensitive(local.rows[count.index]) : local.rows[count.index]
}
