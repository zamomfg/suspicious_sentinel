
variable "storage_account" {
  type = object({
    name                      = string
    primary_connection_string = string
  })
}

variable "storage_container_name" {
  type = string
}

variable "content_file_path" {
  type    = string
  validation {
    condition     = var.content_file_path != ""
    error_message = "Module requires a file path"
  }
}

variable "numberOfLinesToSkip" {
  type    = number
  default = 0
}

variable "header" {
  type    = string
  default = ""
}

variable "content_type" {
  type    = string
  default = "csv"
  validation {
    condition     = contains(local.supported_file_types, var.content_type)
    error_message = "Content types that are supported: ${jsonencode(local.supported_file_types)}"
  }
}

locals {
  supported_file_types = tolist(["csv", "json"])
  filename = basename(var.content_file_path)

  sas_token_url = try("${azurerm_storage_blob.blob.url}${data.azurerm_storage_account_blob_container_sas.sas_token.sas}", null)

  file_content     = file("${var.content_file_path}")
  file_conent_hash = filemd5("${var.content_file_path}")
}

resource "azurerm_storage_blob" "blob" {

  name                   = local.filename
  storage_account_name   = var.storage_account.name
  storage_container_name = var.storage_container_name
  type                   = "Block"
  source_content         = local.file_content
  content_md5            = local.file_conent_hash

}

data "azurerm_storage_account_blob_container_sas" "sas_token" {

  container_name    = var.storage_container_name
  connection_string = var.storage_account.primary_connection_string
  https_only        = true
  start             = timestamp()
  expiry            = timeadd(timestamp(), "8760h") # 8760 hours = one year

  permissions {
    read   = true
    write  = false
    delete = false
    list   = true
    add    = false
    create = false
  }

  depends_on = [
    azurerm_storage_blob.blob
  ]
}

output "sas_token_url" {
  value = local.sas_token_url
}