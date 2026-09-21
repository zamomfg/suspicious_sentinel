# Raw-capture DCR (diagnostic only) — normally commented out.
# Lands every syslog line from the collector, untransformed, into the built-in
# Syslog table so the raw on-wire message format can be inspected. Uncomment,
# apply, look at the Syslog table, then comment it out and apply again. The
# MikroTik DCR is the real pipeline and deliberately filters everything else out.
# module "dcr_rawcapture" {
#   source = "./modules/dcr"

#   name                = "dcr-rawcap-${local.primary_location_short}-001"
#   resource_group_name = data.azurerm_resource_group.rg_log.name
#   location            = local.primary_location
#   tags                = var.tags

#   law_destinations_workspace_id = [azurerm_log_analytics_workspace.law_sc.id]
#   vm_association_ids            = [data.azurerm_arc_machine.home_lab_ama.id]

#   data_sources_syslog = [
#     {
#       name           = "source_rawcapture_syslog"
#       facility_names = ["*"]
#       log_levels     = ["*"]
#       streams        = ["Microsoft-Syslog"]
#     }
#   ]

#   data_flows = [
#     {
#       streams      = ["Microsoft-Syslog"]
#       destinations = [azurerm_log_analytics_workspace.law_sc.id]
#     }
#   ]
# }
