
resource "random_string" "asn_suffix" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}

locals {
  asn_blob_name = "GeoLite2-ASN-Blocks-IPv4.csv"
}

# Storage: serves the function runtime (AzureWebJobsStorage), the deployment zip
# and the data blob. Public access stays off; access is via SAS.
resource "azurerm_storage_account" "asn" {
  name                     = "stasn${local.location_short}${random_string.asn_suffix.result}"
  resource_group_name      = data.azurerm_resource_group.rg_log.name
  location                 = data.azurerm_resource_group.rg_log.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

resource "azurerm_storage_container" "asn_data" {
  name                  = "asn-data"
  storage_account_id    = azurerm_storage_account.asn.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "asn_deployments" {
  name                  = "deployments"
  storage_account_id    = azurerm_storage_account.asn.id
  container_access_type = "private"
}

# The provider uses Azure AD for blob data-plane operations (storage_use_azuread
# in provider.tf), so the CI/CD identity needs a data-plane role to write the
# deployment zip and seed blob below.
resource "azurerm_role_assignment" "asn_sa_ci_blob" {
  scope                = azurerm_storage_account.asn.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Seed the "last build seen" marker so the function's input binding always has a
# blob to read on the first run. The function overwrites its content each time it
# downloads, so ignore content drift here.
resource "azurerm_storage_blob" "asn_last_modified_seed" {
  name                   = ".maxmind-last-modified"
  storage_account_name   = azurerm_storage_account.asn.name
  storage_container_name = azurerm_storage_container.asn_data.name
  type                   = "Block"
  source_content         = ""

  depends_on = [azurerm_role_assignment.asn_sa_ci_blob]

  lifecycle {
    ignore_changes = [source_content, content_md5]
  }
}

# --- Key Vault holding the MaxMind license key -----------------------------
resource "azurerm_key_vault" "asn" {
  name                       = "kv-asn-${local.location_short}-${random_string.asn_suffix.result}"
  location                   = data.azurerm_resource_group.rg_log.location
  resource_group_name        = data.azurerm_resource_group.rg_log.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  tags                       = var.tags
}

# The CI service principal (the identity running terraform apply) needs data-plane
# rights to write the secret on an RBAC vault.
resource "azurerm_role_assignment" "asn_kv_ci_officer" {
  scope                = azurerm_key_vault.asn.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "maxmind" {
  name         = "maxmind-license-key"
  value        = var.maxmind_license_key
  key_vault_id = azurerm_key_vault.asn.id

  # Wait for the data-plane role to propagate before writing the secret.
  depends_on = [azurerm_role_assignment.asn_kv_ci_officer]
}

resource "azurerm_key_vault_secret" "maxmind_account" {
  name         = "maxmind-account-id"
  value        = var.maxmind_account_id
  key_vault_id = azurerm_key_vault.asn.id

  depends_on = [azurerm_role_assignment.asn_kv_ci_officer]
}

# The function's managed identity needs to read the secret (KV reference resolution).
resource "azurerm_role_assignment" "asn_kv_func_reader" {
  scope                = azurerm_key_vault.asn.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_windows_function_app.asn.identity[0].principal_id
}

# --- Function App ----------------------------------------------------------
resource "azurerm_service_plan" "asn" {
  name                = "asp-asn-${local.location_short}-001"
  resource_group_name = data.azurerm_resource_group.rg_log.name
  location            = data.azurerm_resource_group.rg_log.location
  os_type             = "Windows"
  sku_name            = "Y1"
  tags                = var.tags
}

# Zip the PowerShell function source at plan time (no build step needed).
data "archive_file" "asn_fetch" {
  type        = "zip"
  source_dir  = "${path.module}/../function_app/asn_fetch"
  output_path = "${path.module}/.build/asn_fetch.zip"
}

# Content hash in the name forces a new blob (and a new run-from-package URL,
# hence a redeploy) whenever the function source changes.
resource "azurerm_storage_blob" "asn_fetch_pkg" {
  name                   = "asn_fetch-${data.archive_file.asn_fetch.output_md5}.zip"
  storage_account_name   = azurerm_storage_account.asn.name
  storage_container_name = azurerm_storage_container.asn_deployments.name
  type                   = "Block"
  source                 = data.archive_file.asn_fetch.output_path
  content_md5            = data.archive_file.asn_fetch.output_md5

  depends_on = [azurerm_role_assignment.asn_sa_ci_blob]
}

# Read SAS for the deployment zip (WEBSITE_RUN_FROM_PACKAGE).
data "azurerm_storage_account_blob_container_sas" "asn_pkg" {
  connection_string = azurerm_storage_account.asn.primary_connection_string
  container_name    = azurerm_storage_container.asn_deployments.name
  https_only        = true
  start             = timestamp()
  expiry            = timeadd(timestamp(), "8760h") # 1 year

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = false
  }

  depends_on = [azurerm_storage_blob.asn_fetch_pkg]
}

# Read SAS for the data blob, consumed by externaldata() in the ft_asn_info function (law_queries.tf).
data "azurerm_storage_account_blob_container_sas" "asn_data_read" {
  connection_string = azurerm_storage_account.asn.primary_connection_string
  container_name    = azurerm_storage_container.asn_data.name
  https_only        = true
  start             = timestamp()
  expiry            = timeadd(timestamp(), "8760h") # 1 year

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = true
  }
}

locals {
  asn_pkg_url      = "${azurerm_storage_blob.asn_fetch_pkg.url}${data.azurerm_storage_account_blob_container_sas.asn_pkg.sas}"
  asn_blob_sas_url = "https://${azurerm_storage_account.asn.name}.blob.core.windows.net/${azurerm_storage_container.asn_data.name}/${local.asn_blob_name}${data.azurerm_storage_account_blob_container_sas.asn_data_read.sas}"
}

resource "azurerm_windows_function_app" "asn" {
  name                       = "func-asn-${local.location_short}-${random_string.asn_suffix.result}"
  resource_group_name        = data.azurerm_resource_group.rg_log.name
  location                   = data.azurerm_resource_group.rg_log.location
  service_plan_id            = azurerm_service_plan.asn.id
  storage_account_name       = azurerm_storage_account.asn.name
  storage_account_access_key = azurerm_storage_account.asn.primary_access_key
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
    "WEBSITE_RUN_FROM_PACKAGE" = local.asn_pkg_url
    "MAXMIND_ACCOUNT_ID"       = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.maxmind_account.versionless_id})"
    "MAXMIND_LICENSE_KEY"      = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.maxmind.versionless_id})"
    "AsnSchedule"              = var.asn_refresh_cron
  }
}