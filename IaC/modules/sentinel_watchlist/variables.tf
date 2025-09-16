
variable "name" {
  type = string
}

variable "alias" {
  type = string
}

variable "description" {
  type = string
  default = ""
}

variable "watchlist_provider" {
  type = string
  default = ""
}

variable "itemsSearchKey" {
  type = string
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "storage_account" {
  type = object({
    name = string
    primary_connection_string = string
  })
}

variable "storage_container_name" {
  type = string
}

variable "file_name" {
  type = string
}

variable "file_path" {
  type = string
}