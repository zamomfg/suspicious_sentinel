
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
