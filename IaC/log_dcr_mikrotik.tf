# MikroTik RouterOS: per-topic split of CEF syslog.
# RouterOS 7.18+ emits CEF over syslog. The CEF header carries the envelope
# (vendor, product/model, version, signature id, topic list, severity) and the
# extension carries dvchost/dvc plus the original message text in `msg=`.
# RouterOS does NOT expand per-topic fields into CEF keys, so the actual firewall/
# dhcp/system fields still live in `msg=` and are regex-parsed here per topic.
locals {
  # Projection of the common columns (Message is the raw SyslogMessage).
  mikrotik_common_projection = "TimeGenerated,EventVendor,EventProduct,EventVersion,Hostname,DvcIpAddr,EventCategory,DeviceEventClassId,EventSeverity,EventMessage,Message"

  # Identify MikroTik by the CEF vendor header rather than a hostname, so this
  # works regardless of what the router is named.
  mikrotik_source = <<-KQL
    source
    | extend Message = SyslogMessage
    | where Message startswith "CEF:0|MikroTik|"
  KQL

  # Shared extends producing the common columns. Parses the CEF header (fields
  # split by `|`) and the extension (dvchost/dvc/msg). EventCategory is the first
  # topic in the CEF Name field (e.g. "firewall,info" -> "firewall").
  mikrotik_common_extends = <<-KQL
    | extend EventVendor = 'MikroTik'
    | extend EventProduct = extract(@'^CEF:\d+\|[^|]*\|([^|]*)\|', 1, Message)
    | extend EventVersion = extract(@'^CEF:\d+\|[^|]*\|[^|]*\|([^|]*)\|', 1, Message)
    | extend DeviceEventClassId = extract(@'^CEF:\d+\|[^|]*\|[^|]*\|[^|]*\|([^|]*)\|', 1, Message)
    | extend CefName = extract(@'^CEF:\d+\|[^|]*\|[^|]*\|[^|]*\|[^|]*\|([^|]*)\|', 1, Message)
    | extend EventSeverity = extract(@'^CEF:\d+\|[^|]*\|[^|]*\|[^|]*\|[^|]*\|[^|]*\|([^|]*)\|', 1, Message)
    | extend CefExtension = extract(@'^CEF:\d+(?:\|[^|]*){6}\|(.*)$', 1, Message)
    | extend Hostname = extract(@'dvchost=(\S+)', 1, CefExtension)
    | extend Hostname = iif(Hostname == '', HostName, Hostname)
    | extend DvcIpAddr = extract(@'dvc=(\S+)', 1, CefExtension)
    | extend EventMessage = extract(@'msg=(.*)$', 1, CefExtension)
    | extend EventCategory = tostring(split(CefName, ',')[0])
  KQL

  # Category-specific projection columns, taken from the same source the tables
  # use (local.mikrotik_category_extra_columns in log_tables.tf).
  mikrotik_category_columns = {
    for k, cols in local.mikrotik_category_extra_columns : k => [for c in cols : c.name]
  }

  # One entry per MikroTik CEF topic. `filter` selects the topic from the CEF
  # Name field; `extends` parses the topic's fields out of EventMessage (the CEF
  # `msg` body). Every column in a category's schema must be produced here.
  mikrotik_categories = {
    # firewall,info forward: in:ether1 out:bridge, src-mac aa:.., proto UDP, 1.2.3.4:53722->192.168.85.12:62181, NAT ..., len 78
    Firewall = {
      filter  = "| where CefName startswith 'firewall'"
      extends = <<-KQL
        | extend Chain = extract(@'\b(input|output|forward|prerouting|postrouting|srcnat|dstnat)\:', 1, EventMessage)
        | extend NetworkRuleName = trim(@'\s+', extract(@'^(.*?)\b(?:input|output|forward|prerouting|postrouting|srcnat|dstnat)\:', 1, EventMessage))
        | extend DvcInboundInterface = extract(@'\bin:(.*?)\s+out:', 1, EventMessage)
        | extend DvcOutboundInterface = extract(@'\bout:([^,]*)', 1, EventMessage)
        | extend ConnectionState = extract(@'connection-state:(\S+)', 1, EventMessage)
        | extend SrcMacAddr = extract(@'src-mac ([0-9a-fA-F:]{17})', 1, EventMessage)
        | extend NetworkProtocol = extract(@'proto ([A-Za-z0-9]+)', 1, EventMessage)
        | extend SrcIpAddr = extract(@',\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(?::\d+)?->', 1, EventMessage)
        | extend SrcPortNumber = extract(@'\s\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:(\d+)->', 1, EventMessage)
        | extend DstIpAddr = extract(@'->(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})', 1, EventMessage)
        | extend DstPortNumber = extract(@'->\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:(\d+)', 1, EventMessage)
        | extend NatInfo = extract(@'NAT (.*?),\s*len', 1, EventMessage)
        | extend NetworkBytes = extract(@'\blen (\d+)', 1, EventMessage)
        | extend DvcAction = case(NetworkRuleName has 'drop' or NetworkRuleName has 'block', 'B', NetworkRuleName has 'accept' or NetworkRuleName has 'allow', 'A', NetworkRuleName has 'reject', 'R', 'Other')
      KQL
    }

    # dhcp,info defconf assigned 192.168.88.37 for B0:E4:5C:27:EF:F2 Samsung
    Dhcp = {
      filter  = "| where CefName startswith 'dhcp'"
      extends = <<-KQL
        | extend DvcAction = extract(@'\b((?:de)?assigned)\b', 1, EventMessage)
        | extend DhcpServer = extract(@'^(\S+)\s+(?:de)?assigned', 1, EventMessage)
        | extend SrcIpAddr = extract(@'(?:de)?assigned (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})', 1, EventMessage)
        | extend SrcMacAddr = extract(@'for ([0-9A-Fa-f:]{17})', 1, EventMessage)
        | extend SrcHostname = extract(@'for [0-9A-Fa-f:]{17}\s+(.+)$', 1, EventMessage)
      KQL
    }

    # system,info,account user admin logged in from 10.1.101.212 via winbox
    # system,error,critical login failure for user admin from 192.168.33.2 via web
    System = {
      filter  = "| where CefName startswith 'system'"
      extends = <<-KQL
        | extend DvcAction = case(EventMessage has 'logged in', 'login', EventMessage has 'logged out', 'logout', EventMessage has 'login failure', 'login_failure', 'other')
        | extend User = extract(@'user (\S+) logged', 1, EventMessage)
        | extend User = iif(User == '', extract(@'login failure for user (\S+) from', 1, EventMessage), User)
        | extend SrcIpAddr = extract(@'from (\S+?) via', 1, EventMessage)
        | extend Service = extract(@'via (\S+)', 1, EventMessage)
      KQL
    }

    # dns topic in RouterOS is sparse (cache/errors); keep the raw msg only.
    Dns = {
      filter  = "| where CefName startswith 'dns'"
      extends = ""
    }
  }
}

module "dcr_mikrotik" {
  source = "./modules/dcr"

  name                = "dcr-mikrotik-${local.primary_location_short}-001"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = local.primary_location
  tags                = var.tags

  law_destinations_workspace_id = [azurerm_log_analytics_workspace.law_sc.id]

  vm_association_ids = [data.azurerm_arc_machine.home_lab_ama.id]

  data_sources_syslog = [
    {
      name           = "source_mikrotik_syslog"
      facility_names = ["*"]
      log_levels     = ["*"]
      streams        = ["Microsoft-Syslog"]
    }
  ]

  data_flows = [
    for k, c in local.mikrotik_categories : {
      streams       = ["Microsoft-Syslog"]
      destinations  = [azurerm_log_analytics_workspace.law_sc.id]
      output_stream = "${local.custom_stream_prefix}${module.mikrotik_tables[k].name}"
      transform_kql = join("\n", compact([
        trimspace(local.mikrotik_source),
        trimspace(local.mikrotik_common_extends),
        trimspace(c.filter),
        trimspace(c.extends),
        "| project ${local.mikrotik_common_projection}${length(local.mikrotik_category_columns[k]) > 0 ? ",${join(",", local.mikrotik_category_columns[k])}" : ""}",
      ]))
    }
  ]

  stream_declarations = [
    for k, c in local.mikrotik_categories : {
      stream_name   = "${local.custom_stream_prefix}${module.mikrotik_tables[k].name}"
      column_schema = module.mikrotik_tables[k].column_schema
    }
  ]

  logging_workspace_id = azurerm_log_analytics_workspace.law_sc.id
}
