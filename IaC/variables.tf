
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

locals {
  location_short = lookup(
    {
      swedencentral = "sc",
      westeurope    = "weu"
    },
    var.location,
    "null"
  )
}
