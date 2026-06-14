# Microsoft Graph application permissions requested on the CI app registration,
# so they can be admin-consented ("approved") in the Entra portal. Required to
# deploy the Defender XDR custom detection rules in detection_rules.tf.

data "azuread_service_principal" "msgraph" {
  client_id = "00000003-0000-0000-c000-000000000000"
}

data "azuread_application" "ci" {
  client_id = var.current_sp_id
}

# CustomDetection.ReadWrite.All — create/manage custom detection rules via Graph.
# ThreatHunting.Read.All     — run advanced hunting queries (e.g. rule testing).
resource "azuread_application_api_access" "ci_graph" {
  application_id = data.azuread_application.ci.id
  api_client_id  = data.azuread_service_principal.msgraph.client_id
  role_ids = [
    data.azuread_service_principal.msgraph.app_role_ids["CustomDetection.ReadWrite.All"],
    data.azuread_service_principal.msgraph.app_role_ids["ThreatHunting.Read.All"],
  ]
}
