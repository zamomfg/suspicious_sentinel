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

resource "msgraph_resource" "group_urbac_defender_operator" {
  url = "groups"
  body = {
    displayName     = "sg-urbac-defender-operator"
    description     = "Members get the Defender unified RBAC Defender Operator role."
    mailEnabled     = false
    mailNickname    = "sg-urbac-defender-operator"
    securityEnabled = true
    "owners@odata.bind" = [
      "https://graph.microsoft.com/v1.0/servicePrincipals/${data.azurerm_client_config.current.object_id}",
    ]
  }
}

resource "msgraph_resource" "group_urbac_defender_admin" {
  url = "groups"
  body = {
    displayName     = "sg-urbac-defender-admin"
    description     = "Members get the Defender unified RBAC Defender Admin role."
    mailEnabled     = false
    mailNickname    = "sg-urbac-defender-admin"
    securityEnabled = true
    "owners@odata.bind" = [
      "https://graph.microsoft.com/v1.0/servicePrincipals/${data.azurerm_client_config.current.object_id}",
    ]
  }
}
