locals {
  assignments = {
    for a in var.assignments : a.display_name => merge(a, {
      app_scope_ids = concat(
        [for s in a.data_sources : s == "AllExistingAndFutureDataSources" ? "/" : s],
        [for c in a.data_collections : c == "AllExistingAndFutureWorkspaces" ? "/Workspaces" : "/Workspaces/${c}"],
      )
    })
  }
}

resource "msgraph_resource" "role" {
  url         = "roleManagement/defender/roleDefinitions"
  api_version = "beta"
  body = merge(
    {
      displayName = var.display_name
      rolePermissions = [
        { allowedResourceActions = var.permissions }
      ]
    },
    var.description == null ? {} : { description = var.description },
  )
}

resource "msgraph_resource" "assignment" {
  for_each = local.assignments

  url         = "roleManagement/defender/roleAssignments"
  api_version = "beta"
  body = {
    "@odata.type"     = "#microsoft.graph.unifiedRoleAssignmentMultiple"
    displayName       = each.key
    roleDefinitionId  = msgraph_resource.role.id
    principalIds      = each.value.principal_ids
    directoryScopeIds = ["/"]
    appScopeIds       = each.value.app_scope_ids
  }
}
