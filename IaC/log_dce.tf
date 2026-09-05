
resource "azurerm_monitor_data_collection_endpoint" "tailscale" {
  name                = "dce-tailscale-${local.primary_location_short}-001"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = local.primary_location
  tags                = var.tags
}
