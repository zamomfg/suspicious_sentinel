
locals {
  custom_stream_prefix = "Custom-"
}

# module "dcr_workspace" {
#   source = "./modules/dcr"

#   name                = "dcr-workspace-${local.location_short}-001"
#   resource_group_name = azurerm_resource_group.rg_log.name
#   location            = azurerm_resource_group.rg_log.location
#   tags                = var.tags

#   law_destinations_workspace_id = [azurerm_log_analytics_workspace.law.id]
#   kind                          = "WorkspaceTransforms"

#   data_flows = []

#   stream_declarations = []

#   logging_workspace_id = azurerm_log_analytics_workspace.law.id
# }

# ---------------------------------------------------------------------------
# Ubiquiti UniFi: per-category split.
#
# DCR transformations run per-record and cannot use `union`, tabular `let`
# functions, or a named-table source — only `source`. So instead of one flow
# that unions 22 categories into Ubiquiti_CL, each UniFi log category gets its
# own data flow -> custom stream -> tailored _CL table, each with a small,
# legal single-pipeline transform. The UbiquitiAuditEvent function
# (law_queries.tf) unions these tables back together for the solution content.
#
# The per-category tables live in log_tables.tf (module.unifi_tables); their
# schemas come from local.unifi_category_extra_columns there, which is also the
# single source of truth the transform projection below uses for category columns.
# ---------------------------------------------------------------------------
locals {
  # Projection of the common columns (Message is the raw SyslogMessage).
  unifi_common_projection = "TimeGenerated,EventVendor,EventTime,Hostname,EventCategory,DvcType,DvcMacAddr,FirmwareVersion,EventMessage,Message"

  unifi_source = <<-KQL
    source
    | where HostName in ("Router-Ultra","U6LR")
    | extend Message = SyslogMessage
  KQL

  # Shared extends producing the common columns. Runs after the category filter
  # and before the category-specific extends. EventCategory/EventMessage get
  # empty defaults so the common projection always succeeds even for categories
  # that don't set them (e.g. dnsmasq).
  unifi_common_extends = <<-KQL
    | extend EventVendor = 'Ubiquiti', EventTime = tostring(EventTime), Hostname = HostName, EventCategory = '', EventMessage = ''
    | extend DvcType = iif(extract(@'[A-Fa-f0-9]{12},([A-Za-z0-9_-]+)-',1,Message) != "", extract(@'[A-Fa-f0-9]{12},([A-Za-z0-9_-]+)-',1,Message), iif(extract(@'\d+\:\d+\:\d+\s([A-Za-z0-9_-]+),[A-Fa-f0-9]{12}',1,Message) != "", extract(@'\d+\:\d+\:\d+\s([A-Za-z0-9_-]+),[A-Fa-f0-9]{12}',1,Message), iif(extract(@'([A-Za-z0-9_-]+),[A-Fa-f0-9]{12}',1,Message) != "", extract(@'([A-Za-z0-9_-]+),[A-Fa-f0-9]{12}',1,Message), "")))
    | extend DvcMacAddr = replace(@'(:)$',@'',replace(@'(\w{2})',@'\1:',extract(@'([A-Fa-f0-9]{12}),' ,1,Message)))
    | extend FirmwareVersion = iif(extract(@'[A-Fa-f0-9]{12},v(.*?)\:',1,Message)!="",extract(@'[A-Fa-f0-9]{12},v(.*?)\:',1,Message),extract(@'[A-Fa-f0-9]{12},[A-Za-z-]+([\d\.\+]+)[\:\s]',1,Message))
  KQL

  # Category-specific projection columns, taken from the same source the tables
  # use (local.unifi_category_extra_columns in log_tables.tf).
  unifi_category_columns = {
    for k, cols in local.unifi_category_extra_columns : k => [for c in cols : c.name]
  }

  # One entry per UniFi log category. The table schema (and thus the projection)
  # lives in the matching struct file; here we only hold the KQL: the `filter`
  # that selects the category and the `extends` that populate its columns. Every
  # column in a category's struct file must be produced by its `extends`.
  unifi_categories = {
    Dropbear = {
      filter  = "| where Message contains 'dropbear'"
      extends = <<-KQL
        | extend EventCategory = 'dropbear', EventMessage = extract(@' dropbear\[\d+\]\:\s(.*)',1,Message), SrcIpAddr = extract(@'from (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\:\d{1,5}',1,Message)
        | extend SrcPortNumber = extract(@'from \d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\:(\d{1,5})',1,Message)
      KQL
    }

    Hostapd = {
      filter  = "| where Message contains 'hostapd'"
      extends = <<-KQL
        | extend EventCategory = 'hostapd', WlanId = extract(@'hostapd:\s(\w+)',1,Message), SrcType = extract(@':\s(\w+)\s[A-Fa-f0-9:]{17}',1,Message), SrcMacAddr = extract(@':\s(\w+)\s([A-Fa-f0-9:]{17})',2,Message), DstMacAddr = extract(@'addr=([a-fA-F0-9:]{17})',1,Message), Service = extract(@'[A-Fa-f0-9:]{17}\s(.+):',2,Message), EventMessage = extract(@'[A-Fa-f0-9:]{17}\s(.*):\s(.*)',2,Message)
      KQL
    }

    Firewall = {
      filter  = "| where Message has \"DESCR=\" and Message has \"IN=\" and Message has \"OUT=\" and Message has \"MAC=\" and Message has \"SRC=\" and Message has \"DST=\" and Message has \"LEN=\""
      extends = <<-KQL
        | extend EventCategory = 'firewall', EventMessage = extract(@'DESCR="(.*?)"\s',1,Message)
        | extend FlowId = extract(@'ID=(.*?)\s',1,Message), DvcInboundInterface = extract(@'IN=(.*?)\s',1,Message), DvcOutboundInterface = extract(@'OUT=(.*?)\s',1,Message), DvcAction = case(EventMessage contains 'Block',"B", EventMessage contains 'Accept' or EventMessage contains 'Allow',"A", EventMessage contains 'Reject',"R", "Other")
        | extend NetworkRuleName = extract(@'\[([^\]]+)\]\s+DESCR=',1,Message)
        | extend DstMacAddr = extract(@'MAC=([a-fA-F0-9:]{17}):',1,Message)
        | extend SrcMacAddr = extract(@'MAC=[a-fA-F0-9:]{17}:([a-fA-F0-9:]{17})\s',1,Message)
        | extend SrcIpAddr = extract(@'SRC=(.*?)\s',1,Message)
        | extend SrcPortNumber = extract(@'SPT=(.*?)\s',1,Message)
        | extend DstIpAddr = extract(@'DST=(.*?)\s',1,Message)
        | extend DstPortNumber = extract(@'DPT=(.*?)\s',1,Message)
        | extend NetworkBytes = extract(@'LEN=(.*?)\s',1,Message)
        | extend Tos = extract(@'TOS=(.*?)\s',1,Message)
        | extend Prec = extract(@'PREC=(.*?)\s',1,Message)
        | extend Ttl = extract(@'TTL=(.*?)\s',1,Message)
        | extend NetworkProtocol = extract(@'PROTO=(.*?)\s',1,Message)
        | extend Window = extract(@'WINDOW=(.*?)\s',1,Message)
        | extend Res = extract(@'RES=(.*?)\s',1,Message)
        | extend Mark = extract(@'MARK=(.*?)\s',1,Message)
      KQL
    }

    DnsTimeout = {
      filter  = "| where Message contains \"DNS request timed out\""
      extends = <<-KQL
        | extend EventCategory = 'dnstimeout'
        | extend EventMessage = 'DNS request timed out'
        | extend SrcType = extract(@'\[(\w+):\s[a-fA-F0-9:]{17}\]',1,Message)
        | extend DvcMacAddr = extract(@'\[\w+:\s([a-fA-F0-9:]{17})\]',1,Message)
        | extend DnsQuery = extract(@'QUERY:(.*?)\]',1,Message)
        | extend DnsServer = extract(@'DNS_SERVER\s?:(.*?)\]',1,Message)
      KQL
    }

    Stahtd = {
      filter  = "| where Message contains 'stahtd'"
      extends = <<-KQL
        | extend EventCategory = extract(@'\"message_type\":\"(.*?)\"',1,Message)
        | extend SrcDvcMacAddr = extract(@'\"mac\":\"(.*?)\"',1,Message)
        | extend WlanId = extract(@'\"vap\":\"(.*?)\"',1,Message)
        | extend AssocStatus = extract(@'\"assoc_status\":\"(.*?)\"',1,Message)
        | extend EventResult = extract(@'\"event_type\":\"(.*?)\"',1,Message)
        | extend EventMessage = extract(@'\}\s-\s(.*)',1,Message)
      KQL
    }

    AssocTracker = {
      filter  = "| where Message contains 'EVT_AP_STA_ASSOC_TRACKER_DBG'"
      extends = <<-KQL
        | extend EventCategory = 'libubnt'
        | extend WlanId = extract(@'vap:\s(.*?)',1,Message)
        | extend SrcMacAddr = extract(@'sta_mac:\s(.*?)',1,Message)
        | extend EventResult = extract(@'event_type:\s(.*)',1,Message)
        | extend EventMessage = 'Client failed to associate with an AP'
      KQL
    }

    StaEvent = {
      filter  = "| where Message contains 'EVENT_STA_'"
      extends = <<-KQL
        | extend EventCategory = 'libubnt'
        | extend WlanId = extract(@'EVENT_STA_(JOIN|LEAVE|IP)\s(\w+):',2,Message)
        | extend DvcAction = extract(@'EVENT_STA_(JOIN|LEAVE|IP)',1,Message)
        | extend EventMessage = case(DvcAction == 'JOIN','Client joined AP', DvcAction == 'LEAVE','Client disconnected from AP', 'Client IP info')
        | extend SrcMacAddr = extract(@':\s([A-Fa-f0-9:]{17})',1,Message)
        | extend SrcIpAddr = extract(@'\/\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})',1,Message)
      KQL
    }

    Syswrapper = {
      filter  = "| where Message contains 'syswrapper'"
      extends = <<-KQL
        | extend EventCategory = 'syswrapper'
        | extend EventMessage = extract(@'syswrapper:\s(.*)',1,Message)
      KQL
    }

    Logread = {
      filter  = "| where Message contains 'logread'"
      extends = <<-KQL
        | extend EventCategory = 'logread'
        | extend DstIpAddr = extract(@'to\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})',1,Message)
        | extend DstPortNumber = extract(@'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:(\d{1,5})',1,Message)
        | extend EventMessage = extract(@'logread\[\d+\]:\s(.*)',1,Message)
      KQL
    }

    Stamgr = {
      filter  = "| where Message contains 'stamgr'"
      extends = <<-KQL
        | extend EventCategory = 'stamgr'
        | extend DstMacAddr = extract(@'\s([A-Fa-f0-9:]{17})',1,Message)
        | extend WlanId = extract(@'\s[A-Fa-f0-9:]{17}\s(\S+)',1,Message)
        | extend EventMessage = extract(@'stamgr:(.*?)\(',1,Message)
        | extend EventResultDetails = extract(@'reason:(.*?)\)',1,Message)
      KQL
    }

    Kernel = {
      filter  = <<-KQL
        | where Message contains 'kernel'
        | where Message contains 'FWLOG' or Message contains 'FW LOG' or Message contains 'set_ratelimit'
      KQL
      extends = <<-KQL
        | extend EventCategory = 'kernel'
        | extend EventMessage = case( Message matches regex "kernel.*FW LOG",extract(@'FW LOG,\s*(.*)',1,Message),Message matches regex "kernel.*FWLOG",extract(@'FWLOG:\s*\[\d+\]\s*(.*)',1,Message),Message matches regex "kernel.*_set_ratelimit",extract(@'_set_ratelimit:\s*(.*)',1,Message), "Check raw_message for details")
      KQL
    }

    Dnsmasq = {
      filter  = "| where Message matches regex @'dnsmasq(-dhcp)?\\[\\d+\\]:'"
      extends = <<-KQL
        | extend EventCategory = 'dnsmasq'
        | extend DstMacAddr = extract(@'MAC=([A-Fa-F0-9:]{17}):',1,Message)
        | extend SrcMacAddr = extract(@'MAC=[A-Fa-F0-9:]{17}:([A-Fa-F0-9:]{17})\s',1,Message)
        | extend DnsQuery = extract(@'dnsmasq(-dhcp)?\[\d+\]:\s(.*?)\[\w+\]|\s(\S+)\sfrom\s\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}',3,Message)
        | extend SrcIpAddr = extract(@'dnsmasq(-dhcp)?\[\d+\]:\s(.*?)\[\w+\]|\s(.*?)from\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})',4,Message)
      KQL
    }

    Mcad = {
      filter  = "| where Message contains 'mcad['"
      extends = <<-KQL
        | extend EventCategory = 'mcad'
        | extend EventMessage = extract(@'mcad\[\d+\]:\s(.*)',1,Message)
      KQL
    }

    UnifiMqBroker = {
      filter  = "| where Message contains 'unifi-mq-broker['"
      extends = <<-KQL
        | extend EventCategory = 'unifi-mq-broker'
        | extend EventMessage = extract(@'unifi-mq-broker\[\d+\]:\s(.*)',1,Message)
      KQL
    }

    UbiosUdapiServer = {
      filter  = "| where Message contains 'ubios-udapi-server['"
      extends = <<-KQL
        | extend EventCategory = 'ubios-udapi-server'
        | extend EventMessage = extract(@'ubios-udapi-server\[\d+\]:\s(.*)',1,Message)
      KQL
    }

    Vpn = {
      filter  = "| where Message contains \"CEF:\" and (Message has \"VPN Client Connected\" or Message has \"VPN Client Disconnected\")"
      extends = <<-KQL
        | extend EventCategory = case( Message has "VPN Client Connected",'vpn_client_connected',Message has "VPN Client Disconnected",'vpn_client_disconnected', 'vpn_other')
        | extend EventMessage = extract(@'msg=([^\n]*)',1,Message)
        | extend VpnUser = extract(@'suser=([^\s]+)',1,Message)
        | extend VpnClientIp = extract(@'UNIFIclientIp=([^\s]+)',1,Message)
        | extend VpnSourceIp = extract(@'src=([^\s]+)',1,Message)
        | extend VpnName = extract(@'UNIFIvpnName=([^\n]+?)\sUNIFIvpnType=',1,Message)
        | extend VpnType = extract(@'UNIFIvpnType=([^\s]+)',1,Message)
        | extend VpnServerAddress = extract(@'UNIFIvpnServerAddress=([^\s]+)',1,Message)
        | extend VpnSubnet = extract(@'UNIFIvpnSubnet=([^\s]+)',1,Message)
        | extend VpnWan = extract(@'UNIFIwanId=([^\s]+)',1,Message)
        | extend VpnUtcTime = extract(@'UNIFIutcTime=([^\s]+)',1,Message)
        | extend VpnDuration = extract(@'UNIFIduration=([^\s]+\s[^\s]+)',1,Message)
        | extend VpnUsageDown = extract(@'UNIFIusageDown=([^\s]+\s?MB|KB|B)',1,Message)
        | extend VpnUsageUp = extract(@'UNIFIusageUp=([^\s]+\s?MB|KB|B)',1,Message)
      KQL
    }

    WifiClient = {
      filter  = "| where Message contains \"CEF:\" and ( Message has \"WiFi Client Connected\" or Message has \"WiFi Client Roamed\" or Message has \"WiFi Client Disconnected\" )"
      extends = <<-KQL
        | extend EventCategory = case( Message has "WiFi Client Connected",'wifi_client_connected',Message has "WiFi Client Roamed",'wifi_client_roamed',Message has "WiFi Client Disconnected",'wifi_client_disconnected','wifi_client_other')
        | extend EventMessage = extract(@'msg=([^\n]*)',1,Message)
        | extend WifiClientAlias = extract(@'UNIFIclientAlias=([^\s]+)',1,Message)
        | extend WifiClientHostname = extract(@'UNIFIclientHostname=([^\s]+)',1,Message)
        | extend WifiClientIp = extract(@'UNIFIclientIp=([^\s]+)',1,Message)
        | extend WifiClientMac = extract(@'UNIFIclientMac=([^\s]+)',1,Message)
        | extend WifiChannel = extract(@'UNIFIwifiChannel=([^\s]+)',1,Message)
        | extend WifiChannelWidth = extract(@'UNIFIwifiChannelWidth=([^\s]+)',1,Message)
        | extend WifiName = extract(@'UNIFIwifiName=([^\n]+?)\sUNIFIwifiBand=',1,Message)
        | extend WifiBand = extract(@'UNIFIwifiBand=([^\s]+)',1,Message)
        | extend WifiAuthMethod = extract(@'UNIFIauthMethod=([^\s]+)',1,Message)
        | extend WifiRssi = extract(@'UNIFIWiFiRssi=([^\s]+)',1,Message)
        | extend WifiLastDeviceName = extract(@'UNIFIlastConnectedToDeviceName=([^\s]+)',1,Message)
        | extend WifiLastDeviceIp = extract(@'UNIFIlastConnectedToDeviceIp=([^\s]+)',1,Message)
        | extend WifiLastDeviceMac = extract(@'UNIFIlastConnectedToDeviceMac=([^\s]+)',1,Message)
        | extend WifiLastDeviceModel = extract(@'UNIFIlastConnectedToDeviceModel=([^\s]+)',1,Message)
        | extend WifiConnectedDeviceName = extract(@'UNIFIconnectedToDeviceName=([^\s]+)',1,Message)
        | extend WifiConnectedDeviceIp = extract(@'UNIFIconnectedToDeviceIp=([^\s]+)',1,Message)
        | extend WifiConnectedDeviceMac = extract(@'UNIFIconnectedToDeviceMac=([^\s]+)',1,Message)
        | extend WifiConnectedDeviceModel = extract(@'UNIFIconnectedToDeviceModel=([^\s]+)',1,Message)
        | extend WifiDuration = extract(@'UNIFIduration=([^\s]+\s[^\s]+)',1,Message)
        | extend WifiUsageDown = extract(@'UNIFIusageDown=([^\s]+\s?MB|B)',1,Message)
        | extend WifiUsageUp = extract(@'UNIFIusageUp=([^\s]+\s?MB|B)',1,Message)
        | extend WifiNetworkName = extract(@'UNIFInetworkName=([^\s]+)',1,Message)
        | extend WifiNetworkSubnet = extract(@'UNIFInetworkSubnet=([^\s]+)',1,Message)
        | extend WifiNetworkVlan = extract(@'UNIFInetworkVlan=([^\s]+)',1,Message)
        | extend WifiUtcTime = extract(@'UNIFIutcTime=([^\s]+)',1,Message)
        | extend WifiLastConnectedToWiFiChannel = extract(@'UNIFIlastConnectedToWiFiChannel=([^\s]+)',1,Message)
        | extend WifiLastConnectedToWiFiChannelWidth = extract(@'UNIFIlastConnectedToWiFiChannelWidth=([^\s]+)',1,Message)
        | extend WifiLastConnectedToWiFiBand = extract(@'UNIFIlastConnectedToWiFiBand=([^\s]+)',1,Message)
        | extend WifiLastConnectedToWiFiRssi = extract(@'UNIFIlastConnectedToWiFiRssi=([^\s]+)',1,Message)
      KQL
    }

    Wevent = {
      filter  = "| where Message contains 'wevent['"
      extends = <<-KQL
        | extend EventCategory = 'wevent'
        | extend EventMessage = extract(@'wevent\[\d+\]:\s*(.*)',1,Message)
      KQL
    }

    WiredClient = {
      filter  = "| where Message contains \"CEF:\" and ( Message has \"Wired Client Connected\" or Message has \"Wired Client Disconnected\" )"
      extends = <<-KQL
        | extend EventCategory = case( Message has "Wired Client Connected",'wired_client_connected',Message has "Wired Client Disconnected",'wired_client_disconnected','wired_client_other')
        | extend EventMessage = extract(@'msg=([^\n]*)',1,Message)
        | extend WiredClientAlias = extract(@'UNIFIclientAlias=([^\n]+?)\sUNIFIclientHostname=',1,Message)
        | extend WiredClientHostname = extract(@'UNIFIclientHostname=([^\s]+)',1,Message)
        | extend WiredClientIp = extract(@'UNIFIclientIp=([^\s]+)',1,Message)
        | extend WiredClientMac = extract(@'UNIFIclientMac=([^\s]+)',1,Message)
        | extend WiredConnectedDeviceName = extract(@'UNIFIconnectedToDeviceName=([^\n]+?)\sUNIFIconnectedToDevicePort=',1,Message)
        | extend WiredConnectedDevicePort = extract(@'UNIFIconnectedToDevicePort=([^\s]+)',1,Message)
        | extend WiredConnectedDeviceIp = extract(@'UNIFIconnectedToDeviceIp=([^\s]+)',1,Message)
        | extend WiredConnectedDeviceMac = extract(@'UNIFIconnectedToDeviceMac=([^\s]+)',1,Message)
        | extend WiredLinkSpeed = extract(@'UNIFIlinkSpeed=([^\s]+)',1,Message)
        | extend WiredDuration = extract(@'UNIFIduration=([^\s]+\s[^\s]+)',1,Message)
        | extend WiredUsageDown = extract(@'UNIFIusageDown=([^\s]+\s?MB|B)',1,Message)
        | extend WiredUsageUp = extract(@'UNIFIusageUp=([^\s]+\s?MB|B)',1,Message)
        | extend WiredNetworkName = extract(@'UNIFInetworkName=([^\n]+?)\sUNIFInetworkSubnet=',1,Message)
        | extend WiredNetworkSubnet = extract(@'UNIFInetworkSubnet=([^\s]+)',1,Message)
        | extend WiredNetworkVlan = extract(@'UNIFInetworkVlan=([^\s]+)',1,Message)
        | extend WiredUtcTime = extract(@'UNIFIutcTime=([^\s]+)',1,Message)
      KQL
    }

    Earlyoom = {
      filter  = "| where Message contains 'earlyoom['"
      extends = <<-KQL
        | extend EventCategory = 'earlyoom'
        | extend EventMessage = extract(@'earlyoom\[\d+\]:\s*(.*)',1,Message)
      KQL
    }

    DpiFlowStats = {
      filter  = "| where Message contains 'dpi-flow-stats['"
      extends = <<-KQL
        | extend EventCategory = 'dpi-flow-stats'
        | extend EventMessage = extract(@'dpi-flow-stats\[\d+\]:\s*(.*)',1,Message)
      KQL
    }

    Coredns = {
      filter  = "| where Message contains 'coredns['"
      extends = <<-KQL
        | extend EventCategory = 'coredns'
        | extend EventMessage = extract(@'coredns\[\d+\]:\s*(\{.*\})',1,Message)
        | extend DnsQuery = extract(@'"domain":"([^"]+)"',1,EventMessage)
        | extend SrcIpAddr = extract(@'"src_ip":"([^"]+)"',1,EventMessage)
        | extend SrcPortNumber = extract(@'"src_port":(\d+)',1,EventMessage)
        | extend DstIpAddr = extract(@'"dst_ip":"([^"]+)"',1,EventMessage)
        | extend DstPortNumber = extract(@'"dst_port":(\d+)',1,EventMessage)
        | extend NetworkProtocol = extract(@'"protocol":"([^"]+)"',1,EventMessage)
        | extend DstMacAddr = extract(@'"mac":"([^"]+)"',1,EventMessage)
        | extend SrcMacAddr = extract(@'"mac":"([^"]+)"',1,EventMessage)
      KQL
    }
  }
}

module "dcr_unifi" {
  source = "./modules/dcr"

  name                = "dcr-unifi-${local.location_short}-001"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = data.azurerm_resource_group.rg_log.location
  tags                = var.tags

  law_destinations_workspace_id = [azurerm_log_analytics_workspace.law.id]

  vm_association_ids = [data.azurerm_arc_machine.home_lab_ama.id]

  data_sources_syslog = [
    {
      name           = "source_unifi_syslog"
      facility_names = ["*"]
      log_levels     = ["*"]
      streams        = ["Microsoft-Syslog"]
    }
  ]

  # One data flow per category: same Microsoft-Syslog input, category-specific
  # transform, routed to that category's custom stream / table.
  data_flows = [
    for k, c in local.unifi_categories : {
      streams       = ["Microsoft-Syslog"]
      destinations  = [azurerm_log_analytics_workspace.law.id]
      output_stream = "${local.custom_stream_prefix}${module.unifi_tables[k].name}"
      transform_kql = join("\n", [
        trimspace(local.unifi_source),
        trimspace(c.filter),
        trimspace(local.unifi_common_extends),
        trimspace(c.extends),
        "| project ${local.unifi_common_projection}${length(local.unifi_category_columns[k]) > 0 ? ",${join(",", local.unifi_category_columns[k])}" : ""}",
      ])
    }
  ]

  stream_declarations = [
    for k, c in local.unifi_categories : {
      stream_name   = "${local.custom_stream_prefix}${module.unifi_tables[k].name}"
      column_schema = module.unifi_tables[k].column_schema
    }
  ]

  logging_workspace_id = azurerm_log_analytics_workspace.law.id
}
