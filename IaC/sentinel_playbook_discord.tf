
# Sentinel -> Discord notification playbook.
# An automation rule runs this Logic App on every incident; the playbook reads the
# Discord webhook URL from Key Vault (via its managed identity) and posts the incident.

# Dedicated identity the playbook runs as — used for both the Sentinel connection
# and the Key Vault read. User-assigned so its roles exist before the playbook runs.
resource "azurerm_user_assigned_identity" "playbook" {
  name                = "id-soc-discord-${local.location_short}-001"
  location            = data.azurerm_resource_group.rg_log.location
  resource_group_name = data.azurerm_resource_group.rg_log.name
  tags                = var.tags
}

# --- Key Vault holding the Discord webhook URL -----------------------------
resource "azurerm_key_vault" "soc" {
  name                       = "kv-soc-${local.location_short}-001"
  location                   = data.azurerm_resource_group.rg_log.location
  resource_group_name        = data.azurerm_resource_group.rg_log.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  tags                       = var.tags
}

resource "azurerm_role_assignment" "soc_kv_ci_officer" {
  scope                = azurerm_key_vault.soc.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "discord_webhook" {
  name         = "discord-webhook-url"
  value        = "REPLACE_ME"
  key_vault_id = azurerm_key_vault.soc.id

  depends_on = [azurerm_role_assignment.soc_kv_ci_officer]

  lifecycle {
    ignore_changes = [value]
  }
}

# --- Microsoft Sentinel managed connection (managed-identity auth) ---------
resource "azapi_resource" "sentinel_connection" {
  type      = "Microsoft.Web/connections@2016-06-01"
  name      = "azuresentinel-soc-${local.location_short}-001"
  location  = data.azurerm_resource_group.rg_log.location
  parent_id = data.azurerm_resource_group.rg_log.id
  tags      = var.tags

  schema_validation_enabled = false

  body = {
    properties = {
      displayName = "azuresentinel"
      api = {
        id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Web/locations/${data.azurerm_resource_group.rg_log.location}/managedApis/azuresentinel"
      }
      parameterValueType = "Alternative"
    }
  }
}

# --- Playbook (Logic App) ---------------------------------------------------
resource "azapi_resource" "discord_playbook" {
  type      = "Microsoft.Logic/workflows@2019-05-01"
  name      = "logic-soc-discord-${local.location_short}-001"
  location  = data.azurerm_resource_group.rg_log.location
  parent_id = data.azurerm_resource_group.rg_log.id
  tags      = var.tags

  schema_validation_enabled = false

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.playbook.id]
  }

  body = {
    properties = {
      state = "Enabled"
      definition = {
        "$schema"      = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
        contentVersion = "1.0.0.0"
        parameters = {
          "$connections" = {
            type         = "Object"
            defaultValue = {}
          }
        }
        triggers = {
          Microsoft_Sentinel_incident = {
            type = "ApiConnectionWebhook"
            inputs = {
              body = {
                callback_url = "@{listCallbackUrl()}"
              }
              host = {
                connection = {
                  name = "@parameters('$connections')['azuresentinel']['connectionId']"
                }
              }
              path = "/incident-creation"
            }
          }
        }
        actions = {
          Get_webhook_url = {
            type = "Http"
            inputs = {
              method = "GET"
              uri    = "${azurerm_key_vault.soc.vault_uri}secrets/discord-webhook-url?api-version=7.4"
              authentication = {
                type     = "ManagedServiceIdentity"
                identity = azurerm_user_assigned_identity.playbook.id
                audience = "https://vault.azure.net"
              }
            }
            runtimeConfiguration = {
              secureData = {
                properties = ["outputs"]
              }
            }
          }
          Post_to_Discord = {
            type     = "Http"
            runAfter = { Get_webhook_url = ["Succeeded"] }
            inputs = {
              method = "POST"
              uri    = "@{body('Get_webhook_url')['value']}"
              headers = {
                "Content-Type" = "application/json"
              }
              body = {
                username = "Microsoft Sentinel"
                content  = "🚨 **@{triggerBody()?['object']?['properties']?['title']}**"
                embeds = [
                  {
                    title       = "@{triggerBody()?['object']?['properties']?['title']}"
                    description = "@{triggerBody()?['object']?['properties']?['description']}"
                    url         = "@{triggerBody()?['object']?['properties']?['incidentUrl']}"
                    color       = 15158332
                    fields = [
                      {
                        name   = "Severity"
                        value  = "@{triggerBody()?['object']?['properties']?['severity']}"
                        inline = true
                      },
                      {
                        name   = "Status"
                        value  = "@{triggerBody()?['object']?['properties']?['status']}"
                        inline = true
                      }
                    ]
                  }
                ]
              }
            }
          }
        }
      }
      parameters = {
        "$connections" = {
          value = {
            azuresentinel = {
              connectionId   = azapi_resource.sentinel_connection.id
              connectionName = "azuresentinel"
              id             = "/subscriptions/${var.subscription_id}/providers/Microsoft.Web/locations/${data.azurerm_resource_group.rg_log.location}/managedApis/azuresentinel"
              connectionProperties = {
                authentication = {
                  type     = "ManagedServiceIdentity"
                  identity = azurerm_user_assigned_identity.playbook.id
                }
              }
            }
          }
        }
      }
    }
  }
}

# Playbook identity reads the webhook secret...
resource "azurerm_role_assignment" "playbook_kv_reader" {
  scope                = azurerm_key_vault.soc.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.playbook.principal_id
}

# ...and needs Sentinel access for the incident-trigger connection.
resource "azurerm_role_assignment" "playbook_sentinel_responder" {
  scope                = data.azurerm_resource_group.rg_log.id
  role_definition_name = "Microsoft Sentinel Responder"
  principal_id         = azurerm_user_assigned_identity.playbook.principal_id
}

# Lets Sentinel automation rules run the playbook. Optional: only created when the
# Azure Security Insights SP object id is supplied; otherwise grant via the portal.
resource "azurerm_role_assignment" "sentinel_run_playbook" {
  count                = coalesce(var.sentinel_automation_sp_object_id, "") == "" ? 0 : 1
  scope                = data.azurerm_resource_group.rg_log.id
  role_definition_name = "Microsoft Sentinel Automation Contributor"
  principal_id         = var.sentinel_automation_sp_object_id
}

# --- Automation rule: run the playbook on every incident -------------------
resource "random_uuid" "discord_automation" {}

resource "azurerm_sentinel_automation_rule" "discord_all_incidents" {
  name                       = random_uuid.discord_automation.result
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  display_name               = "Notify Discord on all incidents"
  order                      = 1
  triggers_on                = "Incidents"
  triggers_when              = "Created"

  action_playbook {
    logic_app_id = azapi_resource.discord_playbook.id
    order        = 1
    tenant_id    = data.azurerm_client_config.current.tenant_id
  }

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel]
}
