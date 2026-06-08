variable "name" {
  type        = string
  description = "Watchlist name/alias (used by _GetWatchlist)."
}

variable "display_name" {
  type        = string
  description = "Watchlist display name shown in the portal."
}

variable "item_search_key" {
  type        = string
  description = "CSV column used as the watchlist search key."
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Resource ID of the Sentinel-enabled Log Analytics workspace."
}

variable "encrypted_file_path" {
  type        = string
  description = "Path to the SOPS-encrypted CSV (binary mode), decrypted at plan/apply via the sops provider."
}
