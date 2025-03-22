
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

  backend "azurerm" {
      use_oidc         = true
      use_azuread_auth = true
      key              = "log-terraform.tfstate"
  }
}

provider "azurerm" {
  resource_provider_registrations = "none"
  features {}
  subscription_id = var.subscription_id
}

provider "azapi" {
  subscription_id = var.subscription_id
}