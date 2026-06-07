resource "random_string" "enc_suffix" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}

resource "azurerm_key_vault" "enc" {
  name                       = "kv-enc-${local.location_short}-${random_string.enc_suffix.result}"
  location                   = data.azurerm_resource_group.rg_log.location
  resource_group_name        = data.azurerm_resource_group.rg_log.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  tags                       = var.tags
}

resource "azurerm_role_assignment" "enc_ci_crypto" {
  scope                = azurerm_key_vault.enc.id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# SOPS encrypts/decrypts its data key against this key. Used to encrypt private
# watchlist CSVs committed to this public repo.
resource "azurerm_key_vault_key" "sops" {
  name         = "sops"
  key_vault_id = azurerm_key_vault.enc.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["decrypt", "encrypt", "wrapKey", "unwrapKey"]

  depends_on = [azurerm_role_assignment.enc_ci_crypto]
}

output "sops_key_url" {
  value       = azurerm_key_vault_key.sops.id
  description = "Key Vault key URL for SOPS (sops --encrypt --azure-kv <this>)."
}
