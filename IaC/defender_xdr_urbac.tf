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
