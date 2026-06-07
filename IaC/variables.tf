
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
