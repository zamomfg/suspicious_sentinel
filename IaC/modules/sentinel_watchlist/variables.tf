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

variable "file_path" {
  type        = string
  description = "Path to the watchlist CSV. SOPS-encrypted (binary mode) when encrypted = true, plaintext otherwise."
}

variable "encrypted" {
  type        = bool
  default     = false
  description = "When true, file_path is a SOPS-encrypted CSV: decrypted via the sops provider and the item values are marked sensitive."
}
