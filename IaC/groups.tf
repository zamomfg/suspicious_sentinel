resource "msgraph_resource" "group_urbac_organization_management" {
  url = "groups"
  body = {
    displayName     = "sg-urbac-organization-management"
    description     = "Members get the Defender unified RBAC Organization Management role."
    mailEnabled     = false
    mailNickname    = "sg-urbac-organization-management"
    securityEnabled = true
    "owners@odata.bind" = [
      "https://graph.microsoft.com/v1.0/servicePrincipals/${data.azurerm_client_config.current.object_id}",
    ]
  }
}
