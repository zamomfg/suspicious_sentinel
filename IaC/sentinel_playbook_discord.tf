
# Sentinel -> Discord notification playbook.
# Automation rules run this Logic App on incident create and update. The playbook creates
# one Discord forum post per incident (storing the thread id + alert count as incident
# labels) and adds a comment to that post when new alerts join the incident. The webhook
# URL is read from Key Vault via the playbook's managed identity. The webhook MUST belong
# to a Discord forum/media channel (forum posts require thread_name).

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

# --- Key Vault managed connection (managed-identity auth) ------------------
resource "azapi_resource" "keyvault_connection" {
  type      = "Microsoft.Web/connections@2016-06-01"
  name      = azurerm_key_vault.soc.name
  location  = data.azurerm_resource_group.rg_log.location
  parent_id = data.azurerm_resource_group.rg_log.id
  tags      = var.tags

  schema_validation_enabled = false

  body = {
    properties = {
      displayName        = "keyvault"
      parameterValueType = "Alternative"
      alternativeParameterValues = {
        vaultName = azurerm_key_vault.soc.name
      }
      api = {
        id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Web/locations/${data.azurerm_resource_group.rg_log.location}/managedApis/keyvault"
      }
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
            type = "ApiConnection"
            inputs = {
              host = {
                connection = {
                  name = "@parameters('$connections')['keyvault']['connectionId']"
                }
              }
              method = "get"
              path   = "/secrets/@{encodeURIComponent('discord-webhook-url')}/value"
            }
            runtimeConfiguration = {
              secureData = {
                properties = ["outputs"]
              }
            }
          }
          Find_thread_label = {
            type     = "Query"
            runAfter = { Get_webhook_url = ["Succeeded"] }
            inputs = {
              from  = "@coalesce(triggerBody()?['object']?['properties']?['labels'], json('[]'))"
              where = "@startsWith(item()?['labelName'], 'discord-thread:')"
            }
          }
          Route_incident = {
            type     = "If"
            runAfter = { Find_thread_label = ["Succeeded"] }
            expression = {
              and = [
                {
                  greater = ["@length(body('Find_thread_label'))", 0]
                }
              ]
            }
            # Thread already exists -> comment, but only when new alerts joined.
            actions = {
              Find_count_labels = {
                type = "Query"
                inputs = {
                  from  = "@coalesce(triggerBody()?['object']?['properties']?['labels'], json('[]'))"
                  where = "@startsWith(item()?['labelName'], 'discord-count:')"
                }
              }
              Select_counts = {
                type     = "Select"
                runAfter = { Find_count_labels = ["Succeeded"] }
                inputs = {
                  from   = "@body('Find_count_labels')"
                  select = "@int(last(split(item()?['labelName'], ':')))"
                }
              }
              Check_new_alerts = {
                type     = "If"
                runAfter = { Select_counts = ["Succeeded"] }
                expression = {
                  and = [
                    {
                      greater = [
                        "@coalesce(triggerBody()?['object']?['properties']?['additionalData']?['alertsCount'], 0)",
                        "@if(empty(body('Select_counts')), 0, max(body('Select_counts')))"
                      ]
                    }
                  ]
                }
                actions = {
                  Comment_on_post = {
                    type = "Http"
                    inputs = {
                      method = "POST"
                      uri    = "@{body('Get_webhook_url')?['value']}?thread_id=@{last(split(first(body('Find_thread_label'))?['labelName'], ':'))}"
                      headers = {
                        "Content-Type" = "application/json"
                      }
                      body = {
                        embeds = [
                          {
                            title       = "New alert(s) — incident now has @{coalesce(triggerBody()?['object']?['properties']?['additionalData']?['alertsCount'], 0)} alert(s)"
                            description = "Status: @{triggerBody()?['object']?['properties']?['status']} · Severity: @{triggerBody()?['object']?['properties']?['severity']}"
                            url         = "@{triggerBody()?['object']?['properties']?['incidentUrl']}"
                            color       = 15844367
                            timestamp   = "@{triggerBody()?['object']?['properties']?['lastModifiedTimeUtc']}"
                            fields = [
                              {
                                name   = "Products"
                                value  = "@{if(empty(triggerBody()?['object']?['properties']?['additionalData']?['alertProductNames']), 'N/A', join(triggerBody()?['object']?['properties']?['additionalData']?['alertProductNames'], ', '))}"
                                inline = true
                              },
                              {
                                name   = "Tactics"
                                value  = "@{if(empty(triggerBody()?['object']?['properties']?['additionalData']?['tactics']), 'None', join(triggerBody()?['object']?['properties']?['additionalData']?['tactics'], ', '))}"
                                inline = true
                              }
                            ]
                          }
                        ]
                      }
                    }
                  }
                  Update_count_label = {
                    type     = "ApiConnection"
                    runAfter = { Comment_on_post = ["Succeeded"] }
                    inputs = {
                      host = {
                        connection = {
                          name = "@parameters('$connections')['azuresentinel']['connectionId']"
                        }
                      }
                      method = "put"
                      path   = "/Incidents"
                      body = {
                        incidentArmId = "@triggerBody()?['object']?['id']"
                        tagsToAdd = {
                          TagsToAdd = [
                            {
                              Tag = "discord-count:@{coalesce(triggerBody()?['object']?['properties']?['additionalData']?['alertsCount'], 0)}"
                            }
                          ]
                        }
                      }
                    }
                  }
                }
              }
            }
            # First time for this incident -> create the forum post and store its thread id.
            else = {
              actions = {
                Create_forum_post = {
                  type = "Http"
                  inputs = {
                    method = "POST"
                    uri    = "@{body('Get_webhook_url')?['value']}?wait=true"
                    headers = {
                      "Content-Type" = "application/json"
                    }
                    body = {
                      username    = "Microsoft Sentinel"
                      thread_name = "Incident #@{triggerBody()?['object']?['properties']?['incidentNumber']}: @{triggerBody()?['object']?['properties']?['title']}"
                      content     = "🚨 **Incident #@{triggerBody()?['object']?['properties']?['incidentNumber']}: @{triggerBody()?['object']?['properties']?['title']}**"
                      embeds = [
                        {
                          title       = "@{triggerBody()?['object']?['properties']?['title']}"
                          description = "@{triggerBody()?['object']?['properties']?['description']}"
                          url         = "@{triggerBody()?['object']?['properties']?['incidentUrl']}"
                          color       = 15158332
                          timestamp   = "@{triggerBody()?['object']?['properties']?['createdTimeUtc']}"
                          footer = {
                            text = "@{triggerBody()?['object']?['properties']?['providerName']} · Incident #@{triggerBody()?['object']?['properties']?['incidentNumber']}"
                          }
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
                            },
                            {
                              name   = "Owner"
                              value  = "@{coalesce(triggerBody()?['object']?['properties']?['owner']?['assignedTo'], 'Unassigned')}"
                              inline = true
                            },
                            {
                              name   = "Alerts"
                              value  = "@{coalesce(triggerBody()?['object']?['properties']?['additionalData']?['alertsCount'], 0)}"
                              inline = true
                            },
                            {
                              name   = "Tactics"
                              value  = "@{if(empty(triggerBody()?['object']?['properties']?['additionalData']?['tactics']), 'None', join(triggerBody()?['object']?['properties']?['additionalData']?['tactics'], ', '))}"
                              inline = true
                            },
                            {
                              name   = "Products"
                              value  = "@{if(empty(triggerBody()?['object']?['properties']?['additionalData']?['alertProductNames']), 'N/A', join(triggerBody()?['object']?['properties']?['additionalData']?['alertProductNames'], ', '))}"
                              inline = true
                            }
                          ]
                        }
                      ]
                    }
                  }
                }
                Store_thread_label = {
                  type     = "ApiConnection"
                  runAfter = { Create_forum_post = ["Succeeded"] }
                  inputs = {
                    host = {
                      connection = {
                        name = "@parameters('$connections')['azuresentinel']['connectionId']"
                      }
                    }
                    method = "put"
                    path   = "/Incidents"
                    body = {
                      incidentArmId = "@triggerBody()?['object']?['id']"
                      tagsToAdd = {
                        TagsToAdd = [
                          {
                            Tag = "discord-thread:@{body('Create_forum_post')?['channel_id']}"
                          },
                          {
                            Tag = "discord-count:@{coalesce(triggerBody()?['object']?['properties']?['additionalData']?['alertsCount'], 0)}"
                          }
                        ]
                      }
                    }
                  }
                }
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
            keyvault = {
              connectionId   = azapi_resource.keyvault_connection.id
              connectionName = "keyvault"
              id             = "/subscriptions/${var.subscription_id}/providers/Microsoft.Web/locations/${data.azurerm_resource_group.rg_log.location}/managedApis/keyvault"
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

# Playbook identity reads the webhook secret from Key Vault.
resource "azurerm_role_assignment" "playbook_kv_reader" {
  scope                = azurerm_key_vault.soc.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.playbook.principal_id
}

# Playbook identity writes the thread-id / alert-count labels back onto the incident.
resource "azurerm_role_assignment" "playbook_sentinel_responder" {
  scope                = data.azurerm_resource_group.rg_log.id
  role_definition_name = "Microsoft Sentinel Responder"
  principal_id         = azurerm_user_assigned_identity.playbook.principal_id
}

# Grant Microsoft Sentinel's service principal permission to run playbooks in rg-log,
# so the automation rule can invoke this playbook. Equivalent to the portal's
# "Manage playbook permissions". Gated on the object id being supplied.
resource "azurerm_role_assignment" "sentinel_run_playbook" {
  scope                = data.azurerm_resource_group.rg_log.id
  role_definition_name = "Microsoft Sentinel Automation Contributor"
  principal_id         = var.security_insights_object_id
}

# --- Automation rules: run the playbook on incident create and update ------
# Requires the grant above (or the equivalent portal grant) to already exist, else
# creation fails with "Missing required permissions for Microsoft Sentinel".
# The playbook branches on the discord-thread label, so create -> new forum post and
# update -> comment (when new alerts joined).
resource "random_uuid" "discord_automation_created" {}
resource "random_uuid" "discord_automation_updated" {}

resource "azurerm_sentinel_automation_rule" "discord_incident_created" {
  name                       = random_uuid.discord_automation_created.result
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  display_name               = "Discord: forum post on new incidents"
  order                      = 1
  triggers_on                = "Incidents"
  triggers_when              = "Created"

  action_playbook {
    logic_app_id = azapi_resource.discord_playbook.id
    order        = 1
    tenant_id    = data.azurerm_client_config.current.tenant_id
  }

  depends_on = [
    azurerm_sentinel_log_analytics_workspace_onboarding.sentinel,
    azurerm_role_assignment.sentinel_run_playbook,
  ]
}

resource "azurerm_sentinel_automation_rule" "discord_incident_updated" {
  name                       = random_uuid.discord_automation_updated.result
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  display_name               = "Discord: comment on incident updates"
  order                      = 2
  triggers_on                = "Incidents"
  triggers_when              = "Updated"

  # Update-trigger rules must declare a change condition; fire only when alerts are added.
  condition_json = jsonencode([
    {
      conditionType = "PropertyArrayChanged"
      conditionProperties = {
        arrayType  = "Alerts"
        changeType = "Added"
      }
    }
  ])

  action_playbook {
    logic_app_id = azapi_resource.discord_playbook.id
    order        = 1
    tenant_id    = data.azurerm_client_config.current.tenant_id
  }

  depends_on = [
    azurerm_sentinel_log_analytics_workspace_onboarding.sentinel,
    azurerm_role_assignment.sentinel_run_playbook,
  ]
}
