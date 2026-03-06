
locals {
  struct_declaration_path = "../log_struct_declaration/"
  table_postifx           = "_CL"
}

module "table_unifi_firewall" {
  source = "./modules/law_table"

  name             = "UnifiFirewallLogs${local.table_postifx}"
  law_workspace_id = azurerm_log_analytics_workspace.law.id

  retention_in_days      = 90
  totalRetentionInDays   = 90
  table_struct_file_path = "${local.struct_declaration_path}/unifi_firewall_struct.json"
}

module "table_unifi" {
  source = "./modules/law_table"

  name             = "UnifiLogs${local.table_postifx}"
  law_workspace_id = azurerm_log_analytics_workspace.law.id

  retention_in_days      = 90
  totalRetentionInDays   = 90
  table_struct_file_path = "${local.struct_declaration_path}/unifi_struct.json"
}