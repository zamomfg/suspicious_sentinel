# Data collection endpoint for the Tailscale codeless connector (CCF). The
# connector's DCR — created by SentinelCCF/TailScale/mainTemplate.json when you
# click Connect — binds to this DCE, passed in by name from sentinel_content_hub.tf.
resource "azurerm_monitor_data_collection_endpoint" "tailscale" {
  name                = "dce-tailscale-${local.location_short}-001"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = data.azurerm_resource_group.rg_log.location
  tags                = var.tags
}
