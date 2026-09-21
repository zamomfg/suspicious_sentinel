# MikroTik RouterOS native syslog -> Sentinel.
# RouterOS emits native topic-prefixed syslog (e.g. "firewall,info <body>"), not
# CEF. Firewall and DHCP are normalized into the ASIM tables
# (ASimNetworkSessionLogs / ASimDhcpEventLogs); System and DNS stay in tailored
# custom tables. Every flow starts from the same source identification: the
# "topic,severity " message shape, which also keeps out any other source added
# to this collector later.
locals {
  mikrotik_source_where = "| where Message matches regex @'^[a-z][a-z0-9-]*(?:,[a-z][a-z0-9-]*)+ '"

  # Regex matching an RFC1918 / loopback / link-local IPv4 prefix. Used to skip
  # geo_location() (an external, per-row lookup) for internal addresses that have
  # no public geolocation anyway.
  mikrotik_private_ip_regex = "^(?:10\\.|127\\.|169\\.254\\.|192\\.168\\.|172\\.(?:1[6-9]|2[0-9]|3[01])\\.)"

  # firewall,info block traffic between VLANs for: in:vlan-server out:vlan-server, connection-state:new src-mac DA:.., proto UDP, 192.168.5.8:53->192.168.5.21:1817, len 425
  mikrotik_firewall_asim_kql = <<-KQL
    source
    | extend Message = SyslogMessage
    ${local.mikrotik_source_where}
    | extend CefName = extract(@'^(\S+)\s', 1, Message)
    | where CefName startswith 'firewall'
    | extend EventMessage = extract(@'^\S+\s+(.*)$', 1, Message)
    | extend TopicSeverity = tostring(split(CefName, ',')[1])
    | extend NetworkRuleName = extract(@'^(.*?)\s+in:', 1, EventMessage)
    | extend DvcInboundInterface = extract(@'\bin:(.*?)\s+out:', 1, EventMessage)
    | extend DvcOutboundInterface = extract(@'\bout:([^,]*)', 1, EventMessage)
    | extend SrcMacAddr = extract(@'src-mac ([0-9a-fA-F:]{17})', 1, EventMessage)
    | extend NetworkProtocol = extract(@'proto ([A-Za-z0-9]+)', 1, EventMessage)
    | extend SrcIpAddr = extract(@',\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(?::\d+)?->', 1, EventMessage)
    | extend SrcPortNumber = extract(@'\s\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:(\d+)->', 1, EventMessage)
    | extend DstIpAddr = extract(@'->(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})', 1, EventMessage)
    | extend DstPortNumber = extract(@'->\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:(\d+)', 1, EventMessage)
    | extend NetworkBytes = extract(@'\blen (\d+)', 1, EventMessage)
    | extend DvcAction = case(NetworkRuleName has 'drop' or NetworkRuleName has 'block' or NetworkRuleName has 'deny' or NetworkRuleName contains 'no access', 'Deny', NetworkRuleName has 'reject', 'Reset', NetworkRuleName has 'accept' or NetworkRuleName has 'allow' or NetworkRuleName has 'pass', 'Allow', '')
    | extend SrcGeo = iif(isempty(SrcIpAddr) or isnotempty(extract(@'${local.mikrotik_private_ip_regex}', 0, SrcIpAddr)), parse_json('{}'), geo_location(SrcIpAddr))
    | extend DstGeo = iif(isempty(DstIpAddr) or isnotempty(extract(@'${local.mikrotik_private_ip_regex}', 0, DstIpAddr)), parse_json('{}'), geo_location(DstIpAddr))
    | project
        TimeGenerated,
        EventStartTime = TimeGenerated,
        EventEndTime = TimeGenerated,
        EventCount = toint(1),
        EventType = 'NetworkSession',
        EventResult = case(DvcAction == 'Allow', 'Success', DvcAction == '', 'NA', 'Failure'),
        EventProduct = 'RouterOS',
        EventVendor = 'MikroTik',
        EventSchemaVersion = '0.2.6',
        EventSeverity = case(TopicSeverity has 'crit' or TopicSeverity has 'error', 'High', TopicSeverity has 'warn', 'Medium', 'Informational'),
        EventMessage,
        Dvc = HostName,
        DvcHostname = HostName,
        DvcAction,
        DvcInboundInterface,
        DvcOutboundInterface,
        NetworkRuleName,
        NetworkProtocol,
        SrcIpAddr,
        SrcPortNumber = toint(SrcPortNumber),
        DstIpAddr,
        DstPortNumber = toint(DstPortNumber),
        SrcMacAddr,
        NetworkBytes = tolong(NetworkBytes),
        SrcGeoCountry = tostring(SrcGeo.Country),
        SrcGeoRegion = tostring(SrcGeo.State),
        SrcGeoCity = tostring(SrcGeo.City),
        SrcGeoLatitude = toreal(SrcGeo.Latitude),
        SrcGeoLongitude = toreal(SrcGeo.Longitude),
        DstGeoCountry = tostring(DstGeo.Country),
        DstGeoRegion = tostring(DstGeo.State),
        DstGeoCity = tostring(DstGeo.City),
        DstGeoLatitude = toreal(DstGeo.Latitude),
        DstGeoLongitude = toreal(DstGeo.Longitude)
  KQL

  # dhcp,info defconf assigned 192.168.88.37 for B0:E4:5C:27:EF:F2 Samsung
  mikrotik_dhcp_asim_kql = <<-KQL
    source
    | extend Message = SyslogMessage
    ${local.mikrotik_source_where}
    | extend CefName = extract(@'^(\S+)\s', 1, Message)
    | where CefName startswith 'dhcp'
    | extend EventMessage = extract(@'^\S+\s+(.*)$', 1, Message)
    | where EventMessage contains 'assigned'
    | extend TopicSeverity = tostring(split(CefName, ',')[1])
    | extend RawAction = extract(@'\b((?:de)?assigned)\b', 1, EventMessage)
    | extend SrcIpAddr = extract(@'(?:de)?assigned (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})', 1, EventMessage)
    | extend SrcMacAddr = extract(@'for ([0-9A-Fa-f:]{17})', 1, EventMessage)
    | extend SrcHostname = extract(@'for [0-9A-Fa-f:]{17}\s+(.+)$', 1, EventMessage)
    | extend SrcGeo = iif(isempty(SrcIpAddr) or isnotempty(extract(@'${local.mikrotik_private_ip_regex}', 0, SrcIpAddr)), parse_json('{}'), geo_location(SrcIpAddr))
    | project
        TimeGenerated,
        EventStartTime = TimeGenerated,
        EventEndTime = TimeGenerated,
        EventCount = toint(1),
        EventType = iif(RawAction == 'deassigned', 'Release', 'Assign'),
        EventResult = 'Success',
        EventProduct = 'RouterOS',
        EventVendor = 'MikroTik',
        EventSchema = 'Dhcp',
        EventSchemaVersion = '0.1.0',
        EventSeverity = case(TopicSeverity has 'crit' or TopicSeverity has 'error', 'High', TopicSeverity has 'warn', 'Medium', 'Informational'),
        EventMessage,
        DvcAction = iif(RawAction == 'deassigned', 'Release', 'Assign'),
        Dvc = HostName,
        DvcHostname = HostName,
        SrcIpAddr,
        SrcMacAddr,
        SrcHostname,
        SrcGeoCountry = tostring(SrcGeo.Country),
        SrcGeoRegion = tostring(SrcGeo.State),
        SrcGeoCity = tostring(SrcGeo.City),
        SrcGeoLatitude = toreal(SrcGeo.Latitude),
        SrcGeoLongitude = toreal(SrcGeo.Longitude)
  KQL

  # Common projection for the still-custom System/DNS tables (Message is raw).
  mikrotik_common_projection = "TimeGenerated,EventVendor,EventProduct,EventVersion,Hostname,DvcIpAddr,EventCategory,DeviceEventClassId,EventSeverity,EventMessage,Message"

  mikrotik_source = <<-KQL
    source
    | extend Message = SyslogMessage
    ${local.mikrotik_source_where}
  KQL

  mikrotik_common_extends = <<-KQL
    | extend EventVendor = 'MikroTik'
    | extend EventProduct = ''
    | extend EventVersion = ''
    | extend DeviceEventClassId = ''
    | extend CefName = extract(@'^(\S+)\s', 1, Message)
    | extend EventMessage = extract(@'^\S+\s+(.*)$', 1, Message)
    | extend Hostname = HostName
    | extend DvcIpAddr = HostIP
    | extend EventCategory = tostring(split(CefName, ',')[0])
    | extend EventSeverity = tostring(split(CefName, ',')[1])
  KQL

  mikrotik_category_columns = {
    for k, cols in local.mikrotik_category_extra_columns : k => [for c in cols : c.name]
  }

  # Custom-table topics (System/DNS). `filter` selects the topic; `extends` parses
  # the topic's fields out of EventMessage. Firewall and DHCP are handled above as
  # ASIM flows and are intentionally not in this map.
  mikrotik_categories = {
    # system,info,account user admin logged in from 10.1.101.212 via winbox
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

  data_flows = concat(
    [
      {
        streams       = ["Microsoft-Syslog"]
        destinations  = [azurerm_log_analytics_workspace.law_sc.id]
        output_stream = "Microsoft-ASimNetworkSessionLogs"
        transform_kql = trimspace(local.mikrotik_firewall_asim_kql)
      },
      {
        streams       = ["Microsoft-Syslog"]
        destinations  = [azurerm_log_analytics_workspace.law_sc.id]
        output_stream = "Microsoft-ASimDhcpEventLogs"
        transform_kql = trimspace(local.mikrotik_dhcp_asim_kql)
      },
    ],
    [
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
  )

  stream_declarations = [
    for k, c in local.mikrotik_categories : {
      stream_name   = "${local.custom_stream_prefix}${module.mikrotik_tables[k].name}"
      column_schema = module.mikrotik_tables[k].column_schema
    }
  ]

  logging_workspace_id = azurerm_log_analytics_workspace.law_sc.id
}
