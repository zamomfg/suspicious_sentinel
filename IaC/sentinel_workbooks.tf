
resource "azurerm_application_insights_workbook" "asr" {
  name                = uuidv5("url", "suspicious-sentinel/workbooks/attack-surface-reduction")
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = local.primary_location
  display_name        = "Attack Surface Reduction Dashboard"
  category            = "sentinel"
  source_id           = lower(azurerm_log_analytics_workspace.law_sc.id)
  data_json           = file("${path.module}/../workbooks/AttackSurfaceReduction.json")
  tags                = var.tags
}

resource "azurerm_application_insights_workbook" "data_ingestion" {
  name                = uuidv5("url", "suspicious-sentinel/workbooks/data-ingestion-monitor")
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = local.primary_location
  display_name        = "Data Ingestion Monitor"
  category            = "sentinel"
  source_id           = lower(azurerm_log_analytics_workspace.law_sc.id)
  data_json           = file("${path.module}/../workbooks/DataIngestionMonitor.json")
  tags                = var.tags
}
