output "id" {
  description = "The server-assigned ID of the detection rule."
  value       = try(msgraph_resource.detection_rule.output.id, null)
}

output "detector_id" {
  description = "The detector ID associated with the rule."
  value       = try(msgraph_resource.detection_rule.output.detectorId, null)
}

output "display_name" {
  description = "Display name of the detection rule."
  value       = var.display_name
}

output "output" {
  description = "All server-side values exported from the created detection rule."
  value       = try(msgraph_resource.detection_rule.output, null)
}
