
resource "azurerm_application_insights_workbook" "asr" {
  name                = uuidv5("url", "suspicious-sentinel/workbooks/attack-surface-reduction")
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = data.azurerm_resource_group.rg_log.location
  display_name        = "Attack Surface Reduction Dashboard"
  category            = "sentinel"
  source_id           = lower(azurerm_log_analytics_workspace.law.id)
  data_json           = file("${path.module}/../workbooks/AttackSurfaceReduction.json")
  tags                = var.tags
}
