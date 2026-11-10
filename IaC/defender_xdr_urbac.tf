import {
  to = msgraph_resource.urbac_sentinel_contributor
  id = "/roleManagement/defender/roleDefinitions/3c6daca9-d903-4153-9397-deaa31211d91?api-version=beta"
}

resource "msgraph_resource" "urbac_sentinel_contributor" {
  url         = "roleManagement/defender/roleDefinitions"
  api_version = "beta"
  body = {
    displayName = "URBAC Sentinel Contributor"
    description = "Full access to manage Microsoft Sentinel"
    rolePermissions = [
      {
        allowedResourceActions = [
          "microsoft.xdr/secops/securitydata/basics/read",
          "microsoft.xdr/secops/securitydata/alerts/manage",
          "microsoft.xdr/secops/securitydata/response/manage",
          "microsoft.xdr/configuration/security/detectiontuning/manage",
        ]
      }
    ]
  }

  # Updating a role with Sentinel permissions needs URBAC manage rights on the Workspaces data collection.
  lifecycle {
    ignore_changes = [body]
  }
}

import {
  to = msgraph_resource.urbac_organization_management
  id = "/roleManagement/defender/roleDefinitions/e9fa37ec-efb7-49fc-b37c-47a95ef1471f?api-version=beta"
}

resource "msgraph_resource" "urbac_organization_management" {
  url         = "roleManagement/defender/roleDefinitions"
  api_version = "beta"
  body = {
    displayName = "Organization Management"
    description = "This role was imported based on mapping for Exchange Online permissions. Members of this management role group have permissions to manage Exchange objects and their properties in the Exchange organization. Members can also delegate role groups and management roles in the organization. This role group shouldn't be deleted."
    rolePermissions = [
      {
        allowedResourceActions = [
          "microsoft.xdr/configuration/security/core/manage",
          "microsoft.xdr/configuration/security/detectiontuning/manage",
          "microsoft.xdr/configuration/system/manage",
          "microsoft.xdr/configuration/security/core/read",
        ]
      }
    ]
  }
}

import {
  to = msgraph_resource.urbac_view_only_organization_management
  id = "/roleManagement/defender/roleDefinitions/56af8797-1a07-4bcd-81d2-96acd84603b8?api-version=beta"
}

resource "msgraph_resource" "urbac_view_only_organization_management" {
  url         = "roleManagement/defender/roleDefinitions"
  api_version = "beta"
  body = {
    displayName = "View-Only Organization Management"
    description = "This role was imported based on mapping for Exchange Online permissions. Members of this management role group can view recipient and configuration objects and their properties in the Exchange organization."
    rolePermissions = [
      {
        allowedResourceActions = [
          "microsoft.xdr/configuration/security/core/read",
          "microsoft.xdr/configuration/system/read",
        ]
      }
    ]
  }
}

import {
  to = msgraph_resource.urbac_defender_operator
  id = "/roleManagement/defender/roleDefinitions/e03885b9-f04c-4828-8077-c90da939bcd7?api-version=beta"
}

resource "msgraph_resource" "urbac_defender_operator" {
  url         = "roleManagement/defender/roleDefinitions"
  api_version = "beta"
  body = {
    displayName = "Defender Operator"
    rolePermissions = [
      {
        allowedResourceActions = [
          "microsoft.xdr/secops/securitydata/alerts/manage",
          "microsoft.xdr/secops/securitydata/response/manage",
          "microsoft.xdr/secops/securitydata/liveresponse-basic/manage",
          "microsoft.xdr/secops/securitydata/liveresponse-advanced/manage",
          "microsoft.xdr/secops/securitydata/filecollection/manage",
          "microsoft.xdr/secops/securitydata/emailquarantine/manage",
          "microsoft.xdr/secops/securitydata/copilot/read",
          "microsoft.xdr/secops/securitydata/workbooks/read",
          "microsoft.xdr/secops/securitydata/contenthub/read",
          "microsoft.xdr/secops/securitydata/automation/rules/read",
          "microsoft.xdr/secops/securitydata/automation/playbooks/read",
          "microsoft.xdr/secops/securitydata/automation/integrations/read",
          "microsoft.xdr/secops/securitydata/automation/actions-hard/manage",
          "microsoft.xdr/secops/securitydata/automation/approve-hard/manage",
          "microsoft.xdr/securityposture/*/read",
          "microsoft.xdr/configuration/security/core/read",
          "microsoft.xdr/configuration/system/read",
        ]
      }
    ]
  }

  # Updating a role with Sentinel permissions needs URBAC manage rights on the Workspaces data collection.
  lifecycle {
    ignore_changes = [body]
  }
}

import {
  to = msgraph_resource.urbac_defender_admin
  id = "/roleManagement/defender/roleDefinitions/0c473ea4-797a-4da9-bc16-dd3c3c7d91ac?api-version=beta"
}

resource "msgraph_resource" "urbac_defender_admin" {
  url         = "roleManagement/defender/roleDefinitions"
  api_version = "beta"
  body = {
    displayName = "Defender Admin"
    rolePermissions = [
      {
        allowedResourceActions = [
          "microsoft.xdr/secops/*/manage",
          "microsoft.xdr/securityposture/*/manage",
          "microsoft.xdr/configuration/*/manage",
          "microsoft.xdr/dataops/*/manage",
        ]
      }
    ]
  }

  # Updating a role with Sentinel permissions needs URBAC manage rights on the Workspaces data collection.
  lifecycle {
    ignore_changes = [body]
  }
}

resource "msgraph_resource" "urbac_organization_management_assignment" {
  url         = "roleManagement/defender/roleAssignments"
  api_version = "beta"
  body = {
    "@odata.type"     = "#microsoft.graph.unifiedRoleAssignmentMultiple"
    displayName       = "Organization Management - sg-urbac-organization-management"
    roleDefinitionId  = msgraph_resource.urbac_organization_management.id
    principalIds      = [msgraph_resource.group_urbac_organization_management.id]
    directoryScopeIds = ["/"]
    appScopeIds       = ["Mdo"]
  }
}
