
output "data_collection_rule" {
  value = azurerm_monitor_data_collection_rule.dcr
}

output "dcr_immutable_id" {
  value = data.azapi_resource.data_dcr.output.properties.immutableId
}