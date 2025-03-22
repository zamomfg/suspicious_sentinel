
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
  type = string
  description = "The id of the service principal running the cd/ci pipeline"
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
