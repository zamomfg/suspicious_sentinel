
output "id" {
  value = azapi_resource.summary_rule.id
}

output "destination_table" {
  value = var.destination_table
}
