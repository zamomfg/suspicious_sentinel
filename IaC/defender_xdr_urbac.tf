# module "urbac_sentinel_contributor" {
#   source = "./modules/defender_urbac_role"
#
#   display_name = "URBAC Sentinel Contributor"
#   description  = "Full access to manage Microsoft Sentinel"
#   permissions = [
#     "microsoft.xdr/secops/securitydata/basics/read",
#     "microsoft.xdr/secops/securitydata/alerts/manage",
#     "microsoft.xdr/secops/securitydata/response/manage",
#     "microsoft.xdr/configuration/security/detectiontuning/manage",
#   ]
# }

removed {
  from = module.urbac_sentinel_contributor

  lifecycle {
    destroy = false
  }
}

module "urbac_organization_management" {
  source = "./modules/defender_urbac_role"

  display_name = "Organization Management"
  description  = "This role was imported based on mapping for Exchange Online permissions. Members of this management role group have permissions to manage Exchange objects and their properties in the Exchange organization. Members can also delegate role groups and management roles in the organization. This role group shouldn't be deleted."
  permissions = [
    "microsoft.xdr/configuration/security/core/manage",
    "microsoft.xdr/configuration/security/detectiontuning/manage",
    "microsoft.xdr/configuration/system/manage",
    "microsoft.xdr/configuration/security/core/read",
  ]

  assignments = [
    {
      display_name  = "Organization Management - sg-urbac-organization-management"
      principal_ids = [msgraph_resource.group_urbac_organization_management.id]
      data_sources  = ["Mdo"]
    },
  ]
}

module "urbac_view_only_organization_management" {
  source = "./modules/defender_urbac_role"

  display_name = "View-Only Organization Management"
  description  = "This role was imported based on mapping for Exchange Online permissions. Members of this management role group can view recipient and configuration objects and their properties in the Exchange organization."
  permissions = [
    "microsoft.xdr/configuration/security/core/read",
    "microsoft.xdr/configuration/system/read",
  ]
}

module "urbac_defender_operator" {
  source = "./modules/defender_urbac_role"

  display_name = "Defender Operator"
  permissions = [
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

  # assignments = [
  #   {
  #     display_name     = "Defender Operator - sg-urbac-defender-operator"
  #     principal_ids    = [msgraph_resource.group_urbac_defender_operator.id]
  #     data_sources     = ["AllExistingAndFutureDataSources"]
  #     data_collections = ["AllExistingAndFutureWorkspaces"]
  #   },
  # ]
}

module "urbac_defender_admin" {
  source = "./modules/defender_urbac_role"

  display_name = "Defender Admin"
  permissions = [
    "microsoft.xdr/secops/*/manage",
    "microsoft.xdr/securityposture/*/manage",
    "microsoft.xdr/configuration/*/manage",
    "microsoft.xdr/dataops/*/manage",
  ]

  # assignments = [
  #   {
  #     display_name     = "Defender Admin - sg-urbac-defender-admin"
  #     principal_ids    = [msgraph_resource.group_urbac_defender_admin.id]
  #     data_sources     = ["AllExistingAndFutureDataSources"]
  #     data_collections = ["AllExistingAndFutureWorkspaces"]
  #   },
  # ]
}

moved {
  from = msgraph_resource.urbac_organization_management
  to   = module.urbac_organization_management.msgraph_resource.role
}

moved {
  from = msgraph_resource.urbac_view_only_organization_management
  to   = module.urbac_view_only_organization_management.msgraph_resource.role
}
