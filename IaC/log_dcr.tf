
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

# Ubiquiti UniFi: per-category split.
# Logic is from the official parser but split up to different tables https://github.com/Azure/Azure-Sentinel/blob/master/Solutions/Ubiquiti%20UniFi/Parsers/UbiquitiAuditEvent.yaml
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
        | extend EventCategory = 'hostapd', WlanId = extract(@'hostapd:\s(\w+)',1,Message), SrcType = extract(@':\s(\w+)\s[A-Fa-f0-9:]{17}',1,Message), SrcMacAddr = extract(@':\s(\w+)\s([A-Fa-f0-9:]{17})',2,Message), DstMacAddr = extract(@'addr=([a-fA-F0-9:]{17})',1,Message), EventMessage = extract(@'[A-Fa-f0-9:]{17}\s(.*):\s(.*)',2,Message)
        // Regex fix vs the official UbiquitiAuditEvent parser: it extracts capture group 2 from a single-group regex (always empty); group 1 actually returns the service.
        | extend Service = extract(@'[A-Fa-f0-9:]{17}\s(.+):',1,Message)
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

    # DNS events from three sources (dnstimeout, dnsmasq, coredns) share one
    # table; EventCategory distinguishes them and each field is extracted per
    # subtype. coredns fields come from the parsed JSON in EventMessage.
    Dns = {
      filter  = "| where Message contains \"DNS request timed out\" or Message matches regex @'dnsmasq(-dhcp)?\\[\\d+\\]:' or Message contains 'coredns['"
      extends = <<-KQL
        | extend EventCategory = case(Message contains "DNS request timed out", 'dnstimeout', Message matches regex @'dnsmasq(-dhcp)?\[\d+\]:', 'dnsmasq', Message contains 'coredns[', 'coredns', '')
        | extend EventMessage = case(EventCategory == 'dnstimeout', 'DNS request timed out', EventCategory == 'coredns', extract(@'coredns\[\d+\]:\s*(\{.*\})',1,Message), '')
        | extend DvcMacAddr = iif(EventCategory == 'dnstimeout', extract(@'\[\w+:\s([a-fA-F0-9:]{17})\]',1,Message), DvcMacAddr)
        | extend SrcType = iif(EventCategory == 'dnstimeout', extract(@'\[(\w+):\s[a-fA-F0-9:]{17}\]',1,Message), '')
        | extend DnsQuery = case(EventCategory == 'dnstimeout', extract(@'QUERY:(.*?)\]',1,Message), EventCategory == 'dnsmasq', extract(@'dnsmasq(-dhcp)?\[\d+\]:\s(.*?)\[\w+\]|\s(\S+)\sfrom\s\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}',3,Message), EventCategory == 'coredns', extract(@'"domain":"([^"]+)"',1,EventMessage), '')
        | extend DnsServer = iif(EventCategory == 'dnstimeout', extract(@'DNS_SERVER\s?:(.*?)\]',1,Message), '')
        | extend SrcIpAddr = case(EventCategory == 'dnsmasq', extract(@'dnsmasq(-dhcp)?\[\d+\]:\s(.*?)\[\w+\]|\s(.*?)from\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})',4,Message), EventCategory == 'coredns', extract(@'"src_ip":"([^"]+)"',1,EventMessage), '')
        | extend SrcPortNumber = iif(EventCategory == 'coredns', extract(@'"src_port":(\d+)',1,EventMessage), '')
        | extend DstIpAddr = iif(EventCategory == 'coredns', extract(@'"dst_ip":"([^"]+)"',1,EventMessage), '')
        | extend DstPortNumber = iif(EventCategory == 'coredns', extract(@'"dst_port":(\d+)',1,EventMessage), '')
        | extend NetworkProtocol = iif(EventCategory == 'coredns', extract(@'"protocol":"([^"]+)"',1,EventMessage), '')
        | extend SrcMacAddr = case(EventCategory == 'dnsmasq', extract(@'MAC=[a-fA-F0-9:]{17}:([a-fA-F0-9:]{17})\s',1,Message), EventCategory == 'coredns', extract(@'"mac":"([^"]+)"',1,EventMessage), '')
        | extend DstMacAddr = case(EventCategory == 'dnsmasq', extract(@'MAC=([a-fA-F0-9:]{17}):',1,Message), EventCategory == 'coredns', extract(@'"mac":"([^"]+)"',1,EventMessage), '')
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

    # Low-value system/noise processes that carry no fields beyond EventMessage
    # all share one table; EventCategory distinguishes the source process.
    System = {
      filter  = <<-KQL
        | where Message contains 'syswrapper' or (Message contains 'kernel' and (Message contains 'FWLOG' or Message contains 'FW LOG' or Message contains 'set_ratelimit')) or Message contains 'mcad[' or Message contains 'unifi-mq-broker[' or Message contains 'ubios-udapi-server[' or Message contains 'wevent[' or Message contains 'earlyoom[' or Message contains 'dpi-flow-stats['
      KQL
      extends = <<-KQL
        | extend EventCategory = case(Message contains 'syswrapper', 'syswrapper', Message contains 'kernel', 'kernel', Message contains 'mcad[', 'mcad', Message contains 'unifi-mq-broker[', 'unifi-mq-broker', Message contains 'ubios-udapi-server[', 'ubios-udapi-server', Message contains 'wevent[', 'wevent', Message contains 'earlyoom[', 'earlyoom', Message contains 'dpi-flow-stats[', 'dpi-flow-stats', '')
        | extend EventMessage = case(EventCategory == 'syswrapper', extract(@'syswrapper:\s(.*)',1,Message), EventCategory == 'kernel', case(Message matches regex "kernel.*FW LOG",extract(@'FW LOG,\s*(.*)',1,Message),Message matches regex "kernel.*FWLOG",extract(@'FWLOG:\s*\[\d+\]\s*(.*)',1,Message),Message matches regex "kernel.*_set_ratelimit",extract(@'_set_ratelimit:\s*(.*)',1,Message),"Check raw_message for details"), EventCategory == 'mcad', extract(@'mcad\[\d+\]:\s(.*)',1,Message), EventCategory == 'unifi-mq-broker', extract(@'unifi-mq-broker\[\d+\]:\s(.*)',1,Message), EventCategory == 'ubios-udapi-server', extract(@'ubios-udapi-server\[\d+\]:\s(.*)',1,Message), EventCategory == 'wevent', extract(@'wevent\[\d+\]:\s*(.*)',1,Message), EventCategory == 'earlyoom', extract(@'earlyoom\[\d+\]:\s*(.*)',1,Message), EventCategory == 'dpi-flow-stats', extract(@'dpi-flow-stats\[\d+\]:\s*(.*)',1,Message), '')
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

# Tailscale DCR + data flows now created by the Sentinel codeless connector (CCF)
# ARM template (SentinelCCF/TailScale/mainTemplate.json) when you click Connect; the
# DCE it binds to lives in log_dce.tf. Kept commented for reference.
/*
module "tailscale_dcr" {
  source = "./modules/dcr"

  name                = "dcr-tailscale-${local.location_short}-001"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = data.azurerm_resource_group.rg_log.location
  tags                = var.tags

  data_collection_endpoint_id   = azurerm_monitor_data_collection_endpoint.tailscale.id
  law_destinations_workspace_id = [azurerm_log_analytics_workspace.law.id]
  data_sources_syslog           = []
  logging_workspace_id          = azurerm_log_analytics_workspace.law.id

  stream_declarations = [
    {
      stream_name   = local.tailscale_network_stream_name
      column_schema = module.tailscale_table.column_schema
    },
    {
      stream_name   = local.tailscale_audit_stream_name
      column_schema = module.tailscale_audit_table.column_schema
    },
  ]

  data_flows = [
    {
      streams       = [local.tailscale_network_stream_name]
      destinations  = [azurerm_log_analytics_workspace.law.id]
      transform_kql = "source"
      output_stream = "Custom-TailscaleNetworkLogs_CL"
    },
    {
      streams       = [local.tailscale_audit_stream_name]
      destinations  = [azurerm_log_analytics_workspace.law.id]
      transform_kql = "source"
      output_stream = "Custom-TailscaleAuditLogs_CL"
    },
  ]
}
*/
