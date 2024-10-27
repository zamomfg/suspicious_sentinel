

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.3"
    }
    azapi = {
      source = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}