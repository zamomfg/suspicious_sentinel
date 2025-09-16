
locals {
  custom_stream_prefix = "Custom-"
}

# module "dcr_workspace" {
#   source = "./modules/dcr"

#   name                = "dcr-workspace-${local.location_short}-01"
#   resource_group_name = azurerm_resource_group.rg_log.name
#   location            = azurerm_resource_group.rg_log.location
#   tags                = var.tags

#   law_destinations_workspace_id = [azurerm_log_analytics_workspace.law.id]
#   kind                          = "WorkspaceTransforms"

#   data_flows = []

#   stream_declarations = []

#   logging_workspace_id = azurerm_log_analytics_workspace.law.id
# }

module "dcr_unifi" {
  source = "./modules/dcr"

  name                = "dcr-unifi-${local.location_short}-001"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = data.azurerm_resource_group.rg_log.location
  tags                = var.tags

  law_destinations_workspace_id = [azurerm_log_analytics_workspace.law.id]

  data_flows = [
    {
      streams       = ["Microsoft-Syslog"]
      destinations  = [azurerm_log_analytics_workspace.law.id]
      output_stream = "${local.custom_stream_prefix}${module.table_unifi.name}"
    #   transform_kql = <<-EOT
    #               source
    #               | where Message matches regex @"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2})(.*)? \[\S+?\] DESCR"
    #               | project TimeGenerated, Message
    #               | parse kind=regex Message with * " " HostName @" \["  Rule: string "-" Action: string "-" RuleNr: string @"\] DESCR=" Description:string " IN=" InterfaceIn: string " OUT=" InterfaceOut " MAC=" MAC: string " SRC=" SourceIP: string " DST=" DestIP: string " "                  | parse _INTERFACE with "IN=" InterfaceIn " OUT=" InterfaceOut
    #               | parse kind=regex Message with * " LEN=" Length: int " TOS=" TypeOfService: string " PREC=" Precedence: string " TTL=" TTL: int " ID=" ID: string " PROTO="
    #               | parse kind=regex Message with * " SPT=" SourcePort: int " DPT=" DestPort: int " "
    #               | parse kind=relaxed Message with * " WINDOW=" WindowSize: int " RES=" Reserved: string " " Flags: string " URGP=" Urgent: int
    #               | extend Rule = strcat(Rule, "-", RuleNr)
    #               | extend Action = case(
    #                   Action == "D", "Dropped",
    #                   Action == "R", "Rejected",
    #                   Action == "A", "Accepted",
    #                   "Unknown"
    #               )
    #               | extend Protocol = extract("PROTO=(.*?) ", 1, Message)
    #               | extend Flags = strcat_delim(" ", Flags, split(ID, " ", 1)[0])
    #               | extend ID = toint(split(ID, " ", 0)[0])
    #               | extend AddidtionalData = iff(Protocol == "ICMP", 
    #                       tostring(
    #                           bag_pack(
    #                               "ICMPCode", extract("CODE=(.*?) ", 1, Message),
    #                               "ICMPID", extract(@"CODE=\d ID=(.*?) ", 1, Message),
    #                               "ICMSequence", extract("SEQ=(.*?) ", 1, Message)
    #                           )
    #                       )
    #                   , "")
    #               | extend SourceLocation = geo_location(SourceIP)
    #               | extend DestLocation = geo_location(DestIP)
    #               | project TimeGenerated, Action, Rule, SourceIP, DestIP, SourcePort, DestPort, Protocol, Length, TTL, Flags, SourceLocation, DestLocation, MAC, ID, WindowSize, TypeOfService, InterfaceIn, InterfaceOut, Precedence, Urgent, Reserved, AddidtionalData, Message
    # EOT
    }
  ]

  stream_declarations = [
    {
      stream_name   = "${local.custom_stream_prefix}${module.table_unifi_firewall.name}"
      column_schema = module.table_unifi_firewall.column_schema
    },
    {
      stream_name   = "${local.custom_stream_prefix}${module.table_unifi.name}"
      column_schema = module.table_unifi.column_schema
    }
  ]

  logging_workspace_id = azurerm_log_analytics_workspace.law.id
  vm_association_ids = [data.azurerm_arc_machine.arc_log_machine]
}
