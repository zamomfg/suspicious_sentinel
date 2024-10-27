
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
    request_headers = {
        hej = "hej"
    }

#   dynamic "request_headers" {
#     for_each        = var.watchlist_content_url_authorization_header == "" ? [] : [1]
#     Authorization = var.watchlist_content_url_authorization_header
#   }

}

resource "azurerm_storage_blob" "watchlist_blob" {
  name                   = var.name
  storage_account_name   = var.storage_account.name
  storage_container_name = var.storage_container_name
  type                   = "Block"
  source_content         = var.watchlist_content_file_path != "" ? file("${var.watchlist_content_file_path}") : "${data.http.url_data[0].response_body}"
  content_md5            = var.watchlist_content_file_path != "" ? filemd5("${var.watchlist_content_file_path}") : md5("${data.http.url_data[0].response_body}")

}

data "azurerm_storage_account_blob_container_sas" "sas_token" {
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
}

locals {
  sas_token_url = "${azurerm_storage_blob.watchlist_blob.url}${data.azurerm_storage_account_blob_container_sas.sas_token.sas}"
  sensitive     = true
}

resource "azurerm_sentinel_watchlist" "watchlist" {
  name                       = var.name
  display_name               = var.name
  log_analytics_workspace_id = var.log_analytics_workspace_id
  item_search_key            = var.item_search_key
}


# the SAS token cant be set via API right now -.- so this solution will not work automagicly
resource "azapi_resource" "watchlist_api" {
  type = "Microsoft.SecurityInsights/watchlists@2023-02-01-preview"
  name = var.name
  parent_id = var.log_analytics_workspace_id
  body = {
    properties = {
      contentType = "Text/Csv",


    #   description = "string"
      displayName = var.name
      watchlistAlias = var.name

      itemsSearchKey = var.item_search_key
      numberOfLinesToSkip = var.numberOfLinesToSkip

      provider = "Custom"

      rawContent = var.watchlist_content_file_path != "" ? "${file("${var.watchlist_content_file_path}")}" : local.sas_token_url
      sourceType = var.watchlist_content_file_path != "" ? "Local File" : "Remote Storage"

      rawContent = local.sas_token_url
      sourceType = "Remote Storage"



    }
  }
}
