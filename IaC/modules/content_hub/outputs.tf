
output "solution_id" {
  description = "Resource ID of the installed solution (contentPackages)."
  value       = azapi_resource.solution.id
}

output "solution" {
  description = "Key catalog metadata for the installed solution."
  value = {
    content_id        = local.package.contentId
    display_name      = local.package.displayName
    version           = local.solution_version
    latest_in_catalog = local.package.version
  }
}

output "installed_templates" {
  description = "Map of deployed content items, keyed by contentId, with kind and display name."
  value = {
    for cid, t in local.templates : cid => {
      kind         = t.contentKind
      display_name = t.displayName
      version      = t.version
    }
  }
}
