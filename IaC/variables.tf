
variable "subscription_id" {
  type = string
}

variable "location" {
  type = string
}

variable "app_name" {
  type = string
}

variable "law_global_reteion_days" {
  type = number
}

variable "tags" {
  type = map(string)
}

variable "current_sp_id" {
  type        = string
  description = "The id of the service principal running the cd/ci pipeline"
}

variable "maxmind_account_id" {
  type        = string
  sensitive   = true
  description = "MaxMind account ID, used with the license key (HTTP Basic auth) to download GeoLite2. Supplied via TF_VAR_maxmind_account_id (GitHub Actions secret); stored in Key Vault and surfaced to the function as a KV reference."
}

variable "maxmind_license_key" {
  type        = string
  sensitive   = true
  description = "MaxMind license key used to download the GeoLite2-ASN database. Supplied via TF_VAR_maxmind_license_key (GitHub Actions secret); stored in Key Vault, never set directly on the function app."
}

variable "asn_refresh_cron" {
  type        = string
  default     = "0 0 3 * * *"
  description = "NCRONTAB schedule for the ASN feed refresh (default: daily at 03:00 UTC)."
}

variable "tailscale_tailnet" {
  type        = string
  sensitive   = true
  description = "Tailscale tailnet (org) to pull network logs from, e.g. example.com. Supplied via TF_VAR_tailscale_tailnet (GitHub Actions secret); identifying, so kept out of the repo."
}

variable "tailscale_client_id" {
  type        = string
  sensitive   = true
  description = "Tailscale OAuth client id (client-credentials) used by the codeless connector. Supplied via TF_VAR_tailscale_client_id (GitHub Actions secret)."
}

variable "tailscale_client_secret" {
  type        = string
  sensitive   = true
  description = "Tailscale OAuth client secret used by the codeless connector. Supplied via TF_VAR_tailscale_client_secret (GitHub Actions secret)."
}

variable "tailscale_log_interval_minutes" {
  type        = number
  default     = 5
  description = "Minutes between Tailscale network-log pulls; also the query window size (start = now - interval, end = now)."
}

variable "security_insights_object_id" {
  type        = string
  sensitive   = true
  description = "Object ID of the 'Azure Security Insights' service principal in this tenant. Granted Microsoft Sentinel Automation Contributor on rg-log so automation rules can run the playbook. Supplied via TF_VAR_security_insights_object_id (GitHub Actions secret)."
}

locals {
  location_short = lookup(
    {
      westeurope         = "weu"
      northeurope        = "neu"
      eastus             = "eus"
      eastus2            = "eus2"
      westus             = "wus"
      westus2            = "wus2"
      westus3            = "wus3"
      centralus          = "cus"
      southcentralus     = "scus"
      northcentralus     = "ncus"
      uksouth            = "uks"
      ukwest             = "ukw"
      francecentral      = "frc"
      germanywestcentral = "gwc"
      switzerlandnorth   = "chn"
      norwayeast         = "noe"
      swedencentral      = "sec"
      australiaeast      = "aue"
      southeastasia      = "sea"
      eastasia           = "ea"
      japaneast          = "jpe"
      centralindia       = "cin"
      canadacentral      = "cac"
      brazilsouth        = "brs"
    },
    var.location,
    "null"
  )
}
