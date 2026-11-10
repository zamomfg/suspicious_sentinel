terraform {
  required_version = ">= 1.5.0"

  required_providers {
    msgraph = {
      source  = "microsoft/msgraph"
      version = ">= 0.1.0"
    }
  }
}
