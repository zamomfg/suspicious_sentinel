# MikroTik RouterOS syslog -> Sentinel.
# RouterOS sends either its default format ("firewall,info <body>") or CEF
# ("CEF:0|MikroTik|<model>|<ver>|<id>|firewall,info|<sev>|dvchost=.. dvc=.. msg=<body>");
# mikrotik_message rewrites CEF to the default shape so all parsing below is shared.
# Firewall and DHCP are normalized into the ASIM tables
# (ASimNetworkSessionLogs / ASimDhcpEventLogs); System and DNS stay in tailored
# custom tables. Every flow starts from the same source identification: the
# "topic,severity " message shape, which also keeps out any other source added
# to this collector later.
locals {
  mikrotik_message = "| extend Message = iif(SyslogMessage contains 'CEF:0|MikroTik|', strcat(extract(@'CEF:\\d+(?:\\|[^|]*){4}\\|([^|]*)\\|', 1, SyslogMessage), ' ', replace(@'\\\\=', '=', extract(@'\\bmsg=(.*?)\\s*$', 1, SyslogMessage))), SyslogMessage)"

  mikrotik_source_where = "| where Message matches regex @'^[a-z][a-z0-9-]*(?:,[a-z][a-z0-9-]*)+ '"

  # Regex matching an RFC1918 / loopback / link-local IPv4 prefix. Used to skip
  # geo_location() (an external, per-row lookup) for internal addresses that have
  # no public geolocation anyway.
  mikrotik_private_ip_regex = "^(?:10\\.|127\\.|169\\.254\\.|192\\.168\\.|172\\.(?:1[6-9]|2[0-9]|3[01])\\.)"

  # RouterOS never logs the action, so home_net prefixes each line with A/D/R/L (accept/drop/reject/log).
  mikrotik_firewall_asim_kql = <<-KQL
    source
    ${local.mikrotik_message}
    ${local.mikrotik_source_where}
    | extend CefName = extract(@'^(\S+)\s', 1, Message)
    | where CefName startswith 'firewall'
    | extend EventMessage = extract(@'^\S+\s+(.*)$', 1, Message)
    | extend TopicSeverity = tostring(split(CefName, ',')[1])
    | extend RulePrefix = replace(@'^message repeated \d+ times: \[ ', '', extract(@'^(.*?)\s+in:', 1, EventMessage))
    | extend ActionLetter = extract(@'^([ADRL]) ', 1, RulePrefix)
    | extend NetworkRuleName = iif(isnotempty(ActionLetter), substring(RulePrefix, 2), RulePrefix)
    | extend DvcInboundInterface = extract(@'\bin:(.*?)\s+out:', 1, EventMessage)
    | extend DvcOutboundInterface = extract(@'\bout:([^,]*)', 1, EventMessage)
    | extend SrcMacAddr = extract(@'src-mac ([0-9a-fA-F:]{17})', 1, EventMessage)
    | extend NetworkProtocol = extract(@'proto ([A-Za-z0-9]+)', 1, EventMessage)
    | extend SrcIpAddr = extract(@',\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(?::\d+)?->', 1, EventMessage)
    | extend SrcPortNumber = extract(@'\s\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:(\d+)->', 1, EventMessage)
    | extend DstIpAddr = extract(@'->(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})', 1, EventMessage)
    | extend DstPortNumber = extract(@'->\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:(\d+)', 1, EventMessage)
    | extend NetworkBytes = extract(@'\blen (\d+)', 1, EventMessage)
    | extend DvcAction = case(ActionLetter == 'A', 'Allow', ActionLetter == 'D', 'Deny', ActionLetter == 'R', 'Reset', ActionLetter == 'L', '', NetworkRuleName has 'drop' or NetworkRuleName has 'block' or NetworkRuleName has 'deny' or NetworkRuleName contains 'no access', 'Deny', NetworkRuleName has 'reject', 'Reset', NetworkRuleName has 'accept' or NetworkRuleName has 'allow' or NetworkRuleName has 'pass', 'Allow', '')
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
    ${local.mikrotik_message}
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
    ${local.mikrotik_message}
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

locals {
  # Output streams + transforms used by the Fluent Bit DCR (log_dcr_fluent_bit.tf)
  # for its Custom-MikroTikSyslog stream.
  mikrotik_flows = concat(
    [
      {
        output_stream = "Microsoft-ASimNetworkSessionLogs"
        transform_kql = trimspace(local.mikrotik_firewall_asim_kql)
      },
      {
        output_stream = "Microsoft-ASimDhcpEventLogs"
        transform_kql = trimspace(local.mikrotik_dhcp_asim_kql)
      },
    ],
    [
      for k, c in local.mikrotik_categories : {
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

  mikrotik_table_stream_declarations = [
    for k, c in local.mikrotik_categories : {
      stream_name   = "${local.custom_stream_prefix}${module.mikrotik_tables[k].name}"
      column_schema = module.mikrotik_tables[k].column_schema
    }
  ]
}
