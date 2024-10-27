

## Require P1 or P2 license to log signin logs. To log the other logs see the diagnostic settings
# resource "azurerm_sentinel_data_connector_azure_active_directory" "connector_azure_ad" {
#   name                       = "entra_id_connector"
#   log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
# }