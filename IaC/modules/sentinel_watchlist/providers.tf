terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.3"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
  }
}
