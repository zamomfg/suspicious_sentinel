output "definition_id" {
  value = azapi_resource.definition.id
}

output "poller_ids" {
  value = { for k, p in azapi_resource.poller : k => p.id }
}
