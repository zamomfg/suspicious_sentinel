output "id" {
  description = "The ID of the role definition."
  value       = msgraph_resource.role.id
}

output "assignment_ids" {
  description = "Role assignment IDs, keyed by assignment display_name."
  value       = { for k, a in msgraph_resource.assignment : k => a.id }
}
