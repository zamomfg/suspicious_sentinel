
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

module "dcr_unifi" {
  source = "./modules/dcr"

  name                = "dcr-unifi-${local.location_short}-001"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = data.azurerm_resource_group.rg_log.location
  tags                = var.tags

  law_destinations_workspace_id = [azurerm_log_analytics_workspace.law.id]

  vm_association_ids = [ data.azurerm_arc_machine.home_lab_ama.id ]

  data_sources_syslog = [
    {
      name           = "source_unifi_syslog"
      facility_names = ["*"]
      log_levels     = ["*"]
      #   streams        = ["${local.custom_stream_prefix}${module.table_unifi_firewall.name}", "${local.custom_stream_prefix}${module.table_unifi.name}"]
      streams = ["Microsoft-Syslog"]
    }
  ]

  data_flows = [
    {
      streams       = ["Microsoft-Syslog"]
      destinations  = [azurerm_log_analytics_workspace.law.id]
      output_stream = "${local.custom_stream_prefix}${module.table_ubiquiti.name}"
        transform_kql = <<-EOT
          let EventData = Syslog
          | where HostName in ("Router-Ultra","U6LR")
          | extend M = SyslogMessage,
          EventVendor = 'Ubiquiti',
          EventTime = EventTime,
          Hostname = HostName
          | extend DvcType = iif(extract(@'[A-Fa-f0-9]{12},([A-Za-z0-9_-]+)-',1,M) != "",
          extract(@'[A-Fa-f0-9]{12},([A-Za-z0-9_-]+)-',1,M),
          iif(
          extract(@'\d+\:\d+\:\d+\s([A-Za-z0-9_-]+),[A-Fa-f0-9]{12}',1,M) != "",
          extract(@'\d+\:\d+\:\d+\s([A-Za-z0-9_-]+),[A-Fa-f0-9]{12}',1,M),
          iif(
          extract(@'([A-Za-z0-9_-]+),[A-Fa-f0-9]{12}',1,M) != "",
          extract(@'([A-Za-z0-9_-]+),[A-Fa-f0-9]{12}',1,M),
          ""
          )
          )
          )
          | extend DvcMacAddr = replace(@'(:)$',@'',replace(@'(\w{2})',@'\1:',extract(@'([A-Fa-f0-9]{12}),' ,1,M)))
          | extend FirmwareVersion = iif(extract(@'[A-Fa-f0-9]{12},v(.*?)\:',1,M)!="",extract(@'[A-Fa-f0-9]{12},v(.*?)\:',1,M),extract(@'[A-Fa-f0-9]{12},[A-Za-z-]+([\d\.\+]+)[\:\s]',1,M));
          let ub_dropbear_e =() {
          EventData
          | where M contains 'dropbear'
          | extend EventCategory = 'dropbear',
          EventMessage = extract(@' dropbear\[\d+\]\:\s(.*)',1,M),
          rcIpAddr = extract(@'from (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\:\d{1,5}',1,M)
          | extend SrcPortNumber = extract(@'from \d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\:(\d{1,5})',1,M)
          };
          let ub_hostapd_e =() {
          EventData
          | where M contains 'hostapd'
          | extend EventCategory = 'hostapd',
          WlanId = extract(@'hostapd:\s(\w+)',1,M),
          SrcType = extract(@':\s(\w+)\s[A-Fa-f0-9:]{17}',1,M),
          SrcMacAddr = extract(@':\s(\w+)\s([A-Fa-f0-9:]{17})',2,M),
          DstMacAddr = extract(@'addr=([a-fA-F0-9:]{17})',1,M),
          Service = extract(@'[A-Fa-f0-9:]{17}\s(.+):',2,M),
          EventMessage = extract(@'[A-Fa-f0-9:]{17}\s(.*):\s(.*)',2,M)
          };
          let ub_firewall_e =() {
          EventData
          | where M has "DESCR=" and M has "IN=" and M has "OUT=" and M has "MAC=" and M has "SRC=" and M has "DST=" and M has "LEN="
          | extend EventCategory = 'firewall',
          EventMessage = extract(@'DESCR="(.*?)"\s',1,M)
          | extend FlowId = extract(@'ID=(.*?)\s',1,M),
          DvcInboundInterface = extract(@'IN=(.*?)\s',1,M),
          DvcOutboundInterface = extract(@'OUT=(.*?)\s',1,M),
          DvcAction = case(EventMessage contains 'Block',"B",
          EventMessage contains 'Accept' or EventMessage contains 'Allow',"A",
          EventMessage contains 'Reject',"R",
          "Other")
          | extend NetworkRuleName = extract(@'\[([^\]]+)\]\s+DESCR=',1,M)
          | extend DstMacAddr = extract(@'MAC=([a-fA-F0-9:]{17}):',1,M)
          | extend SrcMacAddr = extract(@'MAC=[a-fA-F0-9:]{17}:([a-fA-F0-9:]{17})\s',1,M)
          | extend SrcIpAddr = extract(@'SRC=(.*?)\s',1,M)
          | extend SrcPortNumber = extract(@'SPT=(.*?)\s',1,M)
          | extend DstIpAddr = extract(@'DST=(.*?)\s',1,M)
          | extend DstPortNumber = extract(@'DPT=(.*?)\s',1,M)
          | extend NetworkBytes = extract(@'LEN=(.*?)\s',1,M)
          | extend Tos = extract(@'TOS=(.*?)\s',1,M)
          | extend Prec = extract(@'PREC=(.*?)\s',1,M)
          | extend Ttl = extract(@'TTL=(.*?)\s',1,M)
          | extend NetworkProtocol = extract(@'PROTO=(.*?)\s',1,M)
          | extend Window = extract(@'WINDOW=(.*?)\s',1,M)
          | extend Res = extract(@'RES=(.*?)\s',1,M)
          | extend Mark = extract(@'MARK=(.*?)\s',1,M)
          };
          let ub_dns_timeout_e =() {
          EventData
          | where M contains "DNS request timed out"
          | extend EventCategory = 'dnstimeout'
          | extend EventMessage = 'DNS request timed out'
          | extend SrcType = extract(@'\[(\w+):\s[a-fA-F0-9:]{17}\]',1,M)
          | extend DvcMacAddr = extract(@'\[\w+:\s([a-fA-F0-9:]{17})\]',1,M)
          | extend DnsQuery = extract(@'QUERY:(.*?)\]',1,M)
          | extend DnsServer = extract(@'DNS_SERVER\s?:(.*?)\]',1,M)
          };
          let ub_stahtd_e =() {
          EventData
          | where M contains 'stahtd'
          | extend EventCategory = extract(@'\"message_type\":\"(.*?)\"',1,M)
          | extend SrcDvcMacAddr = extract(@'\"mac\":\"(.*?)\"',1,M)
          | extend WlanId = extract(@'\"vap\":\"(.*?)\"',1,M)
          | extend AssocStatus = extract(@'\"assoc_status\":\"(.*?)\"',1,M)
          | extend EventResult = extract(@'\"event_type\":\"(.*?)\"',1,M)
          | extend EventMessage = extract(@'\}\s-\s(.*)',1,M)
          };
          let ub_EVT_AP_STA_ASSOC_TRACKER_DBG =() {
          EventData
          | where M contains 'EVT_AP_STA_ASSOC_TRACKER_DBG'
          | extend EventCategory = 'libubnt'
          | extend WlanId = extract(@'vap:\s(.*?)',1,M)
          | extend SrcMacAddr = extract(@'sta_mac:\s(.*?)',1,M)
          | extend EventResult = extract(@'event_type:\s(.*)',1,M)
          | extend EventMessage = 'Client failed to associate with an AP'
          };
          let ub_EVENT_STA_ =() {
          EventData
          | where M contains 'EVENT_STA_'
          | extend EventCategory = 'libubnt'
          | extend WlanId = extract(@'EVENT_STA_(JOIN|LEAVE|IP)\s(\w+):',2,M)
          | extend DvcAction = extract(@'EVENT_STA_(JOIN|LEAVE|IP)',1,M)
          | extend EventMessage = case(DvcAction == 'JOIN','Client joined AP',
          DvcAction == 'LEAVE','Client disconnected from AP',
          'Client IP info')
          | extend SrcMacAddr = extract(@':\s([A-Fa-f0-9:]{17})',1,M)
          | extend SrcIpAddr = extract(@'\/\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})',1,M)
          };
          let ub_syswrapper_e =() {
          EventData
          | where M contains 'syswrapper'
          | extend EventCategory = 'syswrapper'
          | extend EventMessage = extract(@'syswrapper:\s(.*)',1,M)
          };
          let ub_logread_e =() {
          EventData
          | where M contains 'logread'
          | extend EventCategory = 'logread'
          | extend DstIpAddr = extract(@'to\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})',1,M)
          | extend DstPortNumber = extract(@'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:(\d{1,5})',1,M)
          | extend EventMessage = extract(@'logread\[\d+\]:\s(.*)',1,M)
          };
          let ub_stamgr_e =() {
          EventData
          | where M contains'stamgr'
          | extend EventCategory = 'stamgr'
          | extend DstMacAddr = extract(@'\s([A-Fa-f0-9:]{17})',1,M)
          | extend WlanId = extract(@'\s[A-Fa-f0-9:]{17}\s(\S+)',1,M)
          | extend EventMessage = extract(@'stamgr:(.*?)\(',1,M)
          | extend EventResultDetails = extract(@'reason:(.*?)\)',1,M)
          };
          let ub_kernel_e =() {
          EventData
          | where M contains 'kernel'
          | where M contains 'FWLOG' or M contains 'FW LOG' or M contains 'set_ratelimit'
          | extend EventCategory = 'kernel'
          | extend EventMessage = case( M matches regex "kernel.*FW LOG",extract(@'FW LOG,\s*(.*)',1,M),M matches regex "kernel.*FWLOG",extract(@'FWLOG:\s*\[\d+\]\s*(.*)',1,M),M matches regex "kernel.*_set_ratelimit",extract(@'_set_ratelimit:\s*(.*)',1,M),
          "Check raw_message for details"
          )
          };
          let ub_dns_e =() {
          EventData
          | where M matches regex @'dnsmasq(-dhcp)?\[\d+\]:'
          | extend EventCategory = 'dnsmasq'
          | extend DstMacAddr = extract(@'MAC=([A-Fa-F0-9:]{17}):',1,M)
          | extend SrcMacAddr = extract(@'MAC=[A-Fa-F0-9:]{17}:([A-Fa-F0-9:]{17})\s',1,M)| extend DnsQuery = extract(@'dnsmasq(-dhcp)?\[\d+\]:\s(.*?)\[\w+\]|\s(\S+)\sfrom\s\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}',3,M)
          | extend SrcIpAddr = extract(@'dnsmasq(-dhcp)?\[\d+\]:\s(.*?)\[\w+\]|\s(.*?)from\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})',4,M)
          };
          let ub_mcad_e =() {
          EventData
          | where M contains 'mcad['
          | extend EventCategory = 'mcad'
          | extend EventMessage = extract(@'mcad\[\d+\]:\s(.*)',1,M)
          };
          let ub_unifi_mq_broker_e =() {
          EventData
          | where M contains 'unifi-mq-broker['
          | extend EventCategory = 'unifi-mq-broker'
          | extend EventMessage = extract(@'unifi-mq-broker\[\d+\]:\s(.*)',1,M)
          };
          let ub_ubios_udapi_server_e =() {
          EventData
          | where M contains 'ubios-udapi-server['
          | extend EventCategory = 'ubios-udapi-server'
          | extend EventMessage = extract(@'ubios-udapi-server\[\d+\]:\s(.*)',1,M)
          };
          let ub_vpn_e =() {
          EventData
          | where M contains "CEF:" and (M has "VPN Client Connected" or M has "VPN Client Disconnected")
          | extend EventCategory = case( M has "VPN Client Connected",'vpn_client_connected',M has "VPN Client Disconnected",'vpn_client_disconnected',
          'vpn_other')
          | extend EventMessage = extract(@'msg=([^\n]*)',1,M)
          | extend VpnUser = extract(@'suser=([^\s]+)',1,M)
          | extend VpnClientIp = extract(@'UNIFIclientIp=([^\s]+)',1,M)
          | extend VpnSourceIp = extract(@'src=([^\s]+)',1,M)
          | extend VpnName = extract(@'UNIFIvpnName=([^\n]+?)\sUNIFIvpnType=',1,M)
          | extend VpnType = extract(@'UNIFIvpnType=([^\s]+)',1,M)
          | extend VpnServerAddress = extract(@'UNIFIvpnServerAddress=([^\s]+)',1,M)
          | extend VpnSubnet = extract(@'UNIFIvpnSubnet=([^\s]+)',1,M)
          | extend VpnWan = extract(@'UNIFIwanId=([^\s]+)',1,M)
          | extend VpnUtcTime = extract(@'UNIFIutcTime=([^\s]+)',1,M)
          | extend VpnDuration = extract(@'UNIFIduration=([^\s]+\s[^\s]+)',1,M)
          | extend VpnUsageDown = extract(@'UNIFIusageDown=([^\s]+\s?MB|KB|B)',1,M)
          | extend VpnUsageUp = extract(@'UNIFIusageUp=([^\s]+\s?MB|KB|B)',1,M)
          };
          let ub_wifi_client_e =() {
          EventData
          | where M contains "CEF:" and ( M has "WiFi Client Connected" or M has "WiFi Client Roamed" or M has "WiFi Client Disconnected"
          )
          | extend EventCategory = case( M has "WiFi Client Connected",'wifi_client_connected',M has "WiFi Client Roamed",'wifi_client_roamed',M has "WiFi Client Disconnected",'wifi_client_disconnected','wifi_client_other')
          | extend EventMessage = extract(@'msg=([^\n]*)',1,M)
          | extend WifiClientAlias = extract(@'UNIFIclientAlias=([^\s]+)',1,M)
          | extend WifiClientHostname = extract(@'UNIFIclientHostname=([^\s]+)',1,M)
          | extend WifiClientIp = extract(@'UNIFIclientIp=([^\s]+)',1,M)
          | extend WifiClientMac = extract(@'UNIFIclientMac=([^\s]+)',1,M)
          | extend WifiChannel = extract(@'UNIFIwifiChannel=([^\s]+)',1,M)
          | extend WifiChannelWidth = extract(@'UNIFIwifiChannelWidth=([^\s]+)',1,M)
          | extend WifiName = extract(@'UNIFIwifiName=([^\n]+?)\sUNIFIwifiBand=',1,M)
          | extend WifiBand = extract(@'UNIFIwifiBand=([^\s]+)',1,M)
          | extend WifiAuthMethod = extract(@'UNIFIauthMethod=([^\s]+)',1,M)
          | extend WifiRssi = extract(@'UNIFIWiFiRssi=([^\s]+)',1,M)
          | extend WifiLastDeviceName = extract(@'UNIFIlastConnectedToDeviceName=([^\s]+)',1,M)
          | extend WifiLastDeviceIp = extract(@'UNIFIlastConnectedToDeviceIp=([^\s]+)',1,M)
          | extend WifiLastDeviceMac = extract(@'UNIFIlastConnectedToDeviceMac=([^\s]+)',1,M)
          | extend WifiLastDeviceModel = extract(@'UNIFIlastConnectedToDeviceModel=([^\s]+)',1,M)
          | extend WifiConnectedDeviceName = extract(@'UNIFIconnectedToDeviceName=([^\s]+)',1,M)
          | extend WifiConnectedDeviceIp = extract(@'UNIFIconnectedToDeviceIp=([^\s]+)',1,M)
          | extend WifiConnectedDeviceMac = extract(@'UNIFIconnectedToDeviceMac=([^\s]+)',1,M)
          | extend WifiConnectedDeviceModel = extract(@'UNIFIconnectedToDeviceModel=([^\s]+)',1,M)
          | extend WifiDuration = extract(@'UNIFIduration=([^\s]+\s[^\s]+)',1,M)
          | extend WifiUsageDown = extract(@'UNIFIusageDown=([^\s]+\s?MB|B)',1,M)
          | extend WifiUsageUp = extract(@'UNIFIusageUp=([^\s]+\s?MB|B)',1,M)
          | extend WifiNetworkName = extract(@'UNIFInetworkName=([^\s]+)',1,M)
          | extend WifiNetworkSubnet = extract(@'UNIFInetworkSubnet=([^\s]+)',1,M)
          | extend WifiNetworkVlan = extract(@'UNIFInetworkVlan=([^\s]+)',1,M)
          | extend WifiUtcTime = extract(@'UNIFIutcTime=([^\s]+)',1,M)
          | extend WifiLastConnectedToWiFiChannel = extract(@'UNIFIlastConnectedToWiFiChannel=([^\s]+)',1,M)
          | extend WifiLastConnectedToWiFiChannelWidth = extract(@'UNIFIlastConnectedToWiFiChannelWidth=([^\s]+)',1,M)
          | extend WifiLastConnectedToWiFiBand = extract(@'UNIFIlastConnectedToWiFiBand=([^\s]+)',1,M)
          | extend WifiLastConnectedToWiFiRssi = extract(@'UNIFIlastConnectedToWiFiRssi=([^\s]+)',1,M)
          };
          let ub_wevent_e =() {
          EventData
          | where M contains 'wevent['
          | extend EventCategory = 'wevent'
          | extend EventMessage = extract(@'wevent\[\d+\]:\s*(.*)',1,M)
          };
          let ub_wired_client_e =() {
          EventData
          | where M contains "CEF:" and ( M has "Wired Client Connected" or M has "Wired Client Disconnected" )
          | extend EventCategory = case( M has "Wired Client Connected",'wired_client_connected',M has "Wired Client Disconnected",'wired_client_disconnected','wired_client_other')
          | extend EventMessage = extract(@'msg=([^\n]*)',1,M)
          | extend WiredClientAlias = extract(@'UNIFIclientAlias=([^\n]+?)\sUNIFIclientHostname=',1,M)
          | extend WiredClientHostname = extract(@'UNIFIclientHostname=([^\s]+)',1,M)
          | extend WiredClientIp = extract(@'UNIFIclientIp=([^\s]+)',1,M)
          | extend WiredClientMac = extract(@'UNIFIclientMac=([^\s]+)',1,M)
          | extend WiredConnectedDeviceName = extract(@'UNIFIconnectedToDeviceName=([^\n]+?)\sUNIFIconnectedToDevicePort=',1,M)
          | extend WiredConnectedDevicePort = extract(@'UNIFIconnectedToDevicePort=([^\s]+)',1,M)
          | extend WiredConnectedDeviceIp = extract(@'UNIFIconnectedToDeviceIp=([^\s]+)',1,M)
          | extend WiredConnectedDeviceMac = extract(@'UNIFIconnectedToDeviceMac=([^\s]+)',1,M)
          | extend WiredLinkSpeed = extract(@'UNIFIlinkSpeed=([^\s]+)',1,M)
          | extend WiredDuration = extract(@'UNIFIduration=([^\s]+\s[^\s]+)',1,M)
          | extend WiredUsageDown = extract(@'UNIFIusageDown=([^\s]+\s?MB|B)',1,M)
          | extend WiredUsageUp = extract(@'UNIFIusageUp=([^\s]+\s?MB|B)',1,M)
          | extend WiredNetworkName = extract(@'UNIFInetworkName=([^\n]+?)\sUNIFInetworkSubnet=',1,M)
          | extend WiredNetworkSubnet = extract(@'UNIFInetworkSubnet=([^\s]+)',1,M)
          | extend WiredNetworkVlan = extract(@'UNIFInetworkVlan=([^\s]+)',1,M)
          | extend WiredUtcTime = extract(@'UNIFIutcTime=([^\s]+)',1,M)
          };
          let ub_earlyoom_e =() {
          EventData
          | where M contains 'earlyoom['
          | extend EventCategory = 'earlyoom'
          | extend EventMessage = extract(@'earlyoom\[\d+\]:\s*(.*)',1,M)
          };
          let ub_dpi_flow_stats_e =() {
          EventData
          | where M contains 'dpi-flow-stats['
          | extend EventCategory = 'dpi-flow-stats'
          | extend EventMessage = extract(@'dpi-flow-stats\[\d+\]:\s*(.*)',1,M)
          };
          let ub_coredns_e =() {
          EventData
          | where M contains 'coredns['
          | extend EventCategory = 'coredns'
          | extend EventMessage = extract(@'coredns\[\d+\]:\s*(\{.*\})',1,M)
          | extend DnsQuery = extract(@'"domain":"([^"]+)"',1,EventMessage)
          | extend SrcIpAddr = extract(@'"src_ip":"([^"]+)"',1,EventMessage)
          | extend SrcPortNumber = extract(@'"src_port":(\d+)',1,EventMessage)
          | extend DstIpAddr = extract(@'"dst_ip":"([^"]+)"',1,EventMessage)
          | extend DstPortNumber = extract(@'"dst_port":(\d+)',1,EventMessage)
          | extend NetworkProtocol = extract(@'"protocol":"([^"]+)"',1,EventMessage)
          | extend DstMacAddr = extract(@'"mac":"([^"]+)"',1,EventMessage)
          | extend SrcMacAddr = extract(@'"mac":"([^"]+)"',1,EventMessage)
          };
          union isfuzzy=true ub_dropbear_e,ub_hostapd_e,ub_firewall_e,ub_dns_timeout_e,ub_stahtd_e,ub_EVT_AP_STA_ASSOC_TRACKER_DBG,ub_EVENT_STA_,ub_syswrapper_e,ub_logread_e,ub_stamgr_e,ub_kernel_e,ub_dns_e,ub_mcad_e,ub_unifi_mq_broker_e,ub_ubios_udapi_server_e,ub_vpn_e,ub_wifi_client_e,ub_wevent_e,ub_wired_client_e,ub_earlyoom_e,ub_dpi_flow_stats_e,ub_coredns_e
          | project TimeGenerated,EventVendor,EventTime,Hostname,EventCategory,DvcType,DvcMacAddr,FirmwareVersion,EventMessage,WlanId,SrcType,Service,FlowId,DvcInboundInterface,DvcOutboundInterface,DvcAction,NetworkRuleName,SrcMacAddr,SrcIpAddr,SrcPortNumber,DstMacAddr,DstIpAddr,DstPortNumber,NetworkBytes,Tos,Prec,Ttl,NetworkProtocol,Window,Res,Mark,DnsQuery,DnsServer,SrcDvcMacAddr,AssocStatus,EventResult,EventResultDetails,Message=M,WifiClientAlias,WifiClientHostname,WifiClientIp,WifiClientMac,WifiChannel,WifiChannelWidth,WifiName,WifiBand,WifiAuthMethod,WifiRssi,WifiLastDeviceName,WifiLastDeviceIp,WifiLastDeviceMac,WifiLastDeviceModel,WifiConnectedDeviceName,WifiConnectedDeviceIp,WifiConnectedDeviceMac,WifiConnectedDeviceModel,WifiDuration,WifiUsageDown,WifiUsageUp,WifiNetworkName,WifiNetworkSubnet,WifiNetworkVlan,WifiUtcTime,WifiLastConnectedToWiFiChannel,WifiLastConnectedToWiFiChannelWidth,WifiLastConnectedToWiFiBand,WifiLastConnectedToWiFiRssi,WiredClientAlias,WiredClientHostname,WiredClientIp,WiredClientMac,WiredConnectedDeviceName,WiredConnectedDevicePort,WiredConnectedDeviceIp,WiredConnectedDeviceMac,WiredLinkSpeed,WiredDuration,WiredUsageDown,WiredUsageUp,WiredNetworkName,WiredNetworkSubnet,WiredNetworkVlan,WiredUtcTime,VpnUser,VpnClientIp,VpnSourceIp,VpnName,VpnType,VpnServerAddress,VpnSubnet,VpnWan,VpnUtcTime,VpnDuration,VpnUsageDown,VpnUsageUp
      EOT
    }
  ]

  stream_declarations = [
    {
      stream_name   = "${local.custom_stream_prefix}${module.table_ubiquiti.name}"
      column_schema = module.table_ubiquiti.column_schema
    }
  ]

  logging_workspace_id = azurerm_log_analytics_workspace.law.id
}