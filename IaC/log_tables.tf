
locals {
  struct_declaration_path = "../log_struct_declaration/"
  table_postifx           = "_CL"
}

module "table_ubiquiti" {
  source = "./modules/law_table"

  name             = "Ubiquiti${local.table_postifx}"
  law_workspace_id = azurerm_log_analytics_workspace.law.id

  retention_in_days      = 90
  totalRetentionInDays   = 90
  table_struct_file_path = "${local.struct_declaration_path}/Ubiquiti_CL_struct.json"
}