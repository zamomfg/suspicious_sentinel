
variable "name" {
  type = string
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "item_search_key" {
  type = string
}

variable "storage_account" {
  type = object({
    name                      = string
    primary_connection_string = string
  })
}

variable "storage_container_name" {
  type = string
}

variable "watchlist_content_file_path" {
  type    = string
  default = ""
  validation {
    condition     = var.watchlist_content_url != "" || var.watchlist_content_file_path != ""
    error_message = "Module requires either a file path or a file url"
  }
}

variable "use_storage_account" {
  type    = bool
  default = false
}

variable "watchlist_content_url" {
  type    = string
  default = ""
  #   validation {
  #     condition     = var.watchlist_content_url == "" || var.watchlist_content_file_path == ""
  #     error_message = "Cant set both file path and file url"
  #   }
}

variable "watchlist_content_url_authorization_header" {
  type    = string
  default = ""
  #   validation {
  #     condition     =  var.watchlist_content_url_authorization_header == "" && var.watchlist_content_url != ""
  #     error_message = "Cant set Authorization header without using file url"
  #   }
}

variable "numberOfLinesToSkip" {
  type    = number
  default = 0
}

variable "header" {
  type    = string
  default = ""
}


locals {
  supported_file_types = tolist(["csv"])
}

variable "watchlist_content_type" {
  type    = string
  default = "csv"
  validation {
    condition     = contains(local.supported_file_types, var.watchlist_content_type)
    error_message = "Content types that are supported: ${jsonencode(local.supported_file_types)}"
  }
}


data "http" "url_data" {
  count = var.watchlist_content_url == "" ? 0 : 1

  url = var.watchlist_content_url

  #   dynamic "request_headers" {
  #     for_each        = var.watchlist_content_url_authorization_header == "" ? [] : [1]
  #     Authorization = var.watchlist_content_url_authorization_header
  #   }

}

locals {
  file_content     = var.watchlist_content_file_path != "" ? file("${var.watchlist_content_file_path}") : "${data.http.url_data[0].response_body}"
  file_conent_hash = var.watchlist_content_file_path != "" ? filemd5("${var.watchlist_content_file_path}") : md5("${data.http.url_data[0].response_body}")
}

resource "azurerm_storage_blob" "watchlist_blob" {
  count = var.use_storage_account == true ? 1 : 0

  name                   = var.name
  storage_account_name   = var.storage_account.name
  storage_container_name = var.storage_container_name
  type                   = "Block"
  source_content         = local.file_content
  content_md5            = local.file_conent_hash

}

data "azurerm_storage_account_blob_container_sas" "sas_token" {
  count = var.use_storage_account == true ? 1 : 0

  container_name    = var.storage_container_name
  connection_string = var.storage_account.primary_connection_string
  https_only        = true
  start             = timestamp()
  expiry            = timeadd(timestamp(), "8760h") # 8760 hours = one year

  permissions {
    read   = true
    write  = true
    delete = true
    list   = true
    add    = true
    create = true
  }

  depends_on = [
    azurerm_storage_blob.watchlist_blob
  ]
}

locals {
  sas_token_url = try("${azurerm_storage_blob.watchlist_blob[0].url}${data.azurerm_storage_account_blob_container_sas.sas_token[0].sas}", null)
  sensitive     = true
}

resource "azurerm_sentinel_watchlist" "watchlist" {
  name                       = var.name
  display_name               = var.name
  log_analytics_workspace_id = var.log_analytics_workspace_id
  item_search_key            = var.item_search_key
}

locals {
  watchlist_data_csv = csvdecode(local.file_content)

}

resource "azurerm_sentinel_watchlist_item" "watchlist_item" {
  count = length(local.watchlist_data_csv)

  watchlist_id = azurerm_sentinel_watchlist.watchlist.id

  properties = local.watchlist_data_csv[count.index]

}

# the SAS token cant be set via API right now -.- so this solution will not work automagicly
# resource "azapi_resource" "watchlist_api" {
#   type      = "Microsoft.SecurityInsights/watchlists@2023-02-01-preview"
#   name      = var.name
#   parent_id = var.log_analytics_workspace_id
#   body = {
#     properties = {
#       contentType = "Text/Csv",


#       #   description = "string"
#       displayName    = var.name
#       watchlistAlias = var.name

#       itemsSearchKey      = var.item_search_key
#       numberOfLinesToSkip = var.numberOfLinesToSkip

#       provider = "Custom"

#       rawContent = var.use_storage_account == true ? local.file_content : "" 
#       sourceType = var.use_storage_account == true ? "Local File" : "Remote Storage"

#     }
#   }
# }
