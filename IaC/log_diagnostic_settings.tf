

# This setting cannot be set via service principal. It needs Azure CLI authentication
resource "azurerm_monitor_aad_diagnostic_setting" "azure_ad_diagnostic_settings" {
  name                       = "entra_id_diagnostics"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id


  enabled_log {
    category = "AuditLogs"
    retention_policy {
      enabled = false
    }
  }

  enabled_log {
    category = "SignInLogs"
    retention_policy {
      enabled = false
    }
  }

  enabled_log {
    category = "NonInteractiveUserSignInLogs"
    retention_policy {
      enabled = false
    }
  }

  enabled_log {
    category = "ServicePrincipalSignInLogs"
    retention_policy {
      enabled = false
    }
  }

  enabled_log {
    category = "ManagedIdentitySignInLogs"
    retention_policy {
      enabled = false
    }
  }

  enabled_log {
    category = "ProvisioningLogs"
    retention_policy {
      enabled = false
    }
  }

  enabled_log {
    category = "RiskyUsers"
    retention_policy {
      enabled = false
    }
  }

  enabled_log {
    category = "UserRiskEvents"
    retention_policy {
      enabled = false
    }
  }

  enabled_log {
    category = "NetworkAccessTrafficLogs"
    retention_policy {
      enabled = false
    }
  }

  enabled_log {
    category = "RiskyServicePrincipals"
    retention_policy {
      enabled = false
    }
  }

  enabled_log {
    category = "ServicePrincipalRiskEvents"
    retention_policy {
      enabled = false
    }
  }

  enabled_log {
    category = "EnrichedOffice365AuditLogs"
    retention_policy {
      enabled = false
    }
  }

  enabled_log {
    category = "MicrosoftGraphActivityLogs"
    retention_policy {
      enabled = false
    }
  }

  enabled_log {
    category = "RemoteNetworkHealthLogs"
    retention_policy {
      enabled = false
    }
  }

  enabled_log {
    category = "NetworkAccessAlerts"
    retention_policy {
      enabled = false
    }
  }
}



# AuditLogs
# SignInLogs
# NonInteractiveUserSignInLogs
# ServicePrincipalSignInLogs
# ManagedIdentitySignInLogs
# ProvisioningLogs
# ADFSSignInLogs
# RiskyUsers
# UserRiskEvents
# NetworkAccessTrafficLogs
# RiskyServicePrincipals
# ServicePrincipalRiskEvents
# EnrichedOffice365AuditLogs
# MicrosoftGraphActivityLogs
# RemoteNetworkHealthLogs
# NetworkAccessAlerts
