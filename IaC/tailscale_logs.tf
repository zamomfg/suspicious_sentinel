# Tailscale network-logs puller. A timer-triggered PowerShell function pulls the
# tailnet's network logs for the last interval and pushes them to a custom table
# via the Logs Ingestion API (DCE + DCR). The access token lives in Key Vault.

locals {
  tailscale_schedule            = "0 */${var.tailscale_log_interval_minutes} * * * *"
  tailscale_network_stream_name = "Custom-TailscaleNetworkLogs"
  tailscale_audit_stream_name   = "Custom-TailscaleAuditLogs"
}

# --- Storage (function runtime + deployment package) -----------------------
resource "azurerm_storage_account" "tailscale" {
  name                     = "sttailscale${local.location_short}001"
  resource_group_name      = data.azurerm_resource_group.rg_log.name
  location                 = data.azurerm_resource_group.rg_log.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

resource "azurerm_storage_container" "tailscale_deployments" {
  name                  = "deployments"
  storage_account_id    = azurerm_storage_account.tailscale.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "tailscale_sa_ci_blob" {
  scope                = azurerm_storage_account.tailscale.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

data "archive_file" "tailscale_logs" {
  type        = "zip"
  source_dir  = "${path.module}/../function_app/tailscale_logs"
  output_path = "${path.module}/.build/tailscale_logs.zip"
}

resource "azurerm_storage_blob" "tailscale_pkg" {
  name                   = "tailscale_logs-${data.archive_file.tailscale_logs.output_md5}.zip"
  storage_account_name   = azurerm_storage_account.tailscale.name
  storage_container_name = azurerm_storage_container.tailscale_deployments.name
  type                   = "Block"
  source                 = data.archive_file.tailscale_logs.output_path
  content_md5            = data.archive_file.tailscale_logs.output_md5

  depends_on = [azurerm_role_assignment.tailscale_sa_ci_blob]
}

data "azurerm_storage_account_blob_container_sas" "tailscale_pkg" {
  connection_string = azurerm_storage_account.tailscale.primary_connection_string
  container_name    = azurerm_storage_container.tailscale_deployments.name
  https_only        = true
  start             = local.sas_start
  expiry            = local.sas_expiry

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = false
  }

  depends_on = [azurerm_storage_blob.tailscale_pkg]
}

# --- Key Vault holding the Tailscale access token --------------------------
resource "azurerm_key_vault" "tailscale" {
  name                       = "kv-tailscale-${local.location_short}-001"
  location                   = data.azurerm_resource_group.rg_log.location
  resource_group_name        = data.azurerm_resource_group.rg_log.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  tags                       = var.tags
}

resource "azurerm_role_assignment" "tailscale_kv_ci_officer" {
  scope                = azurerm_key_vault.tailscale.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Seeded with a placeholder; set the real token out-of-band (drift ignored), so
# it never lands in Terraform state.
resource "azurerm_key_vault_secret" "tailscale_token" {
  name         = "tailscale-access-token"
  value        = "REPLACE_ME"
  key_vault_id = azurerm_key_vault.tailscale.id

  depends_on = [azurerm_role_assignment.tailscale_kv_ci_officer]

  lifecycle {
    ignore_changes = [value]
  }
}

# --- Function app ----------------------------------------------------------
resource "azurerm_service_plan" "tailscale" {
  name                = "asp-tailscale-${local.location_short}-001"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = data.azurerm_resource_group.rg_log.location
  os_type             = "Windows"
  sku_name            = "Y1"
  tags                = var.tags
}

resource "azurerm_application_insights" "tailscale" {
  name                = "appi-tailscale-${local.location_short}-001"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = data.azurerm_resource_group.rg_log.location
  workspace_id        = azurerm_log_analytics_workspace.law.id
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_windows_function_app" "tailscale" {
  name                       = "func-tailscale-${local.location_short}-001"
  resource_group_name        = data.azurerm_resource_group.rg_log.name
  location                   = data.azurerm_resource_group.rg_log.location
  service_plan_id            = azurerm_service_plan.tailscale.id
  storage_account_name       = azurerm_storage_account.tailscale.name
  storage_account_access_key = azurerm_storage_account.tailscale.primary_access_key
  tags                       = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      powershell_core_version = "7.4"
    }
  }

  app_settings = {
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.tailscale.connection_string
    "WEBSITE_RUN_FROM_PACKAGE"              = "${azurerm_storage_blob.tailscale_pkg.url}${data.azurerm_storage_account_blob_container_sas.tailscale_pkg.sas}"
    "TailscaleSchedule"                     = local.tailscale_schedule
    "TailscaleLookbackMinutes"              = tostring(var.tailscale_log_interval_minutes)
    "TailscaleTailnet"                      = var.tailscale_tailnet
    "TailscaleAccessToken"                  = sensitive("@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.tailscale_token.versionless_id})")
    "LogsIngestionEndpoint"                 = azurerm_monitor_data_collection_endpoint.tailscale.logs_ingestion_endpoint
    "DcrImmutableId"                        = module.tailscale_dcr.dcr_immutable_id
    "DcrNetworkStreamName"                  = local.tailscale_network_stream_name
    "DcrAuditStreamName"                    = local.tailscale_audit_stream_name
  }
}

# The function reads the access token from Key Vault...
resource "azurerm_role_assignment" "tailscale_kv_func_reader" {
  scope                = azurerm_key_vault.tailscale.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_windows_function_app.tailscale.identity[0].principal_id
}

# ...and publishes logs to the DCR.
resource "azurerm_role_assignment" "tailscale_dcr_publisher" {
  scope                = module.tailscale_dcr.data_collection_rule.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_windows_function_app.tailscale.identity[0].principal_id
}
