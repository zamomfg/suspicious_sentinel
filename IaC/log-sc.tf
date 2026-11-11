# Second Sentinel instance in Sweden Central. Standalone workspace + Sentinel
# onboarding only (no data-plane: no DCR/DCE/tables/connectors). Deployed from
# the same state/apply as the primary. Reuses the existing rg-log-neu-01 RG (an
# RG's region is only metadata; the workspace itself is pinned to Sweden Central).
resource "azurerm_log_analytics_workspace" "law_sc" {
  name                = "law-${var.app_name}-sc-001"
  location            = "swedencentral"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  tags                = var.tags

  sku               = "PerGB2018"
  retention_in_days = var.law_global_reteion_days

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "sentinel_sc" {
  workspace_id = azurerm_log_analytics_workspace.law_sc.id
}

import {
  to = azapi_resource.ueba_sc
  id = "${azurerm_log_analytics_workspace.law_sc.id}/providers/Microsoft.SecurityInsights/settings/Ueba"
}

resource "azapi_resource" "ueba_sc" {
  type      = "Microsoft.SecurityInsights/settings@2025-10-01-preview"
  name      = "Ueba"
  parent_id = azurerm_log_analytics_workspace.law_sc.id
  body = {
    kind = "Ueba"
    properties = {
      dataSources = [
        "AuditLogs",
        "AzureActivity",
        "SecurityEvent",
        "SigninLogs",
        "AADManagedIdentitySignInLogs",
        "AADServicePrincipalSignInLogs",
        "DeviceLogonEvents",
        "CommonSecurityLog",
      ]
    }
  }

  schema_validation_enabled = false
  depends_on                = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel_sc]
}

import {
  to = azapi_resource.entity_analytics_sc
  id = "${azurerm_log_analytics_workspace.law_sc.id}/providers/Microsoft.SecurityInsights/settings/EntityAnalytics"
}

resource "azapi_resource" "entity_analytics_sc" {
  type      = "Microsoft.SecurityInsights/settings@2025-10-01-preview"
  name      = "EntityAnalytics"
  parent_id = azurerm_log_analytics_workspace.law_sc.id
  body = {
    kind       = "EntityAnalytics"
    properties = { entityProviders = ["AzureActiveDirectory"] }
  }

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel_sc]
}
