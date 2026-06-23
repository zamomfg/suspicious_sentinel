# Tailscale logs via a Sentinel codeless connector (CCF). Two RestApiPoller
# connectors pull configuration-audit and network-flow logs over OAuth2
# client-credentials and land them in TailscaleAuditLogs_CL / TailscaleNetworkLogs_CL
# (log_tables.tf) through dcr-tailscale (log_dcr.tf), bound to the DCE in log_dce.tf.

locals {
  # Shared OAuth2 client-credentials block (secret supplied via sensitive_properties).
  tailscale_oauth = {
    type                 = "OAuth2"
    grantType            = "client_credentials"
    ClientId             = var.tailscale_client_id
    TokenEndpoint        = "https://api.tailscale.com/api/v2/oauth/token"
    tokenEndpointHeaders = { "Content-Type" = "application/x-www-form-urlencoded" }
  }

  tailscale_request_base = {
    httpMethod             = "GET"
    rateLimitQPS           = 5
    queryWindowInMin       = 5
    retryCount             = 3
    timeoutInSeconds       = 60
    headers                = { Accept = "application/json" }
    queryTimeFormat        = "yyyy-MM-ddTHH:mm:ssZ"
    startTimeAttributeName = "start"
    endTimeAttributeName   = "end"
  }

  tailscale_connector_ui_config = {
    id                    = "TailscaleCCPDefinition"
    title                 = "Tailscale Logging"
    publisher             = "Tailscale"
    logo                  = file("${path.module}/../SentinelCCF/TailScale/tailscale-logo.svg")
    descriptionMarkdown   = "The [Tailscale](https://tailscale.com/) Logging data connector ingests configuration audit logs and network flow logs from the [Tailscale API](https://tailscale.com/api) into Microsoft Sentinel, authenticating with an OAuth 2.0 client-credentials client."
    graphQueriesTableName = "TailscaleAuditLogs_CL"

    graphQueries = [
      {
        metricName = "Total configuration audit logs received"
        legend     = "Tailscale configuration audit logs"
        baseQuery  = "TailscaleAuditLogs_CL"
      },
      {
        metricName = "Total network flow logs received"
        legend     = "Tailscale network flow logs"
        baseQuery  = "TailscaleNetworkLogs_CL"
      },
    ]

    sampleQueries = [
      {
        description = "Get a sample of Tailscale configuration audit logs"
        query       = "TailscaleAuditLogs_CL\n | take 10"
      },
      {
        description = "Get a sample of Tailscale network flow logs"
        query       = "TailscaleNetworkLogs_CL\n | take 10"
      },
    ]

    dataTypes = [
      {
        name                  = "TailscaleAuditLogs_CL"
        lastDataReceivedQuery = "TailscaleAuditLogs_CL\n | summarize Time = max(TimeGenerated)\n | where isnotempty(Time)"
      },
      {
        name                  = "TailscaleNetworkLogs_CL"
        lastDataReceivedQuery = "TailscaleNetworkLogs_CL\n | summarize Time = max(TimeGenerated)\n | where isnotempty(Time)"
      },
    ]

    availability = {
      status    = 1
      isPreview = false
    }

    connectivityCriteria = [
      {
        type = "HasDataConnectors"
      },
    ]

    permissions = {
      resourceProvider = [
        {
          provider               = "Microsoft.OperationalInsights/workspaces"
          permissionsDisplayText = "Read and Write permissions are required."
          providerDisplayName    = "Workspace"
          scope                  = "Workspace"
          requiredPermissions = {
            action = false
            write  = true
            read   = true
            delete = true
          }
        },
      ]
      customs = [
        {
          name        = "Tailscale API access"
          description = "An OAuth client created in the Tailscale admin console with the `logs:configuration:read` and `logs:network:read` scopes is required."
        },
      ]
    }

    instructionSteps = [
      {
        title       = "Connect Tailscale to Microsoft Sentinel"
        description = "1) In the Tailscale admin console, go to **Settings > OAuth clients** and select **Generate OAuth client**. \n 2) Grant the client the **`logs:configuration:read`** and **`logs:network:read`** scopes, then generate it. \n 3) Copy the **Client ID** and **Client Secret** before leaving the page and store them securely — the secret is shown only once. \n 4) Below, enter your **Tailnet** (the organization name shown in the admin console, e.g. `example.com`, or `-` for the default tailnet), then provide the **Client ID** and **Client Secret** and select **Connect**."
        instructions = [
          {
            type = "Textbox"
            parameters = {
              label       = "Tailnet"
              placeholder = "example.com"
              type        = "text"
              name        = "tailnet"
              required    = true
            }
          },
          {
            type = "OAuthForm"
            parameters = {
              clientIdLabel         = "Client ID"
              clientSecretLabel     = "Client Secret"
              connectButtonLabel    = "Connect"
              disconnectButtonLabel = "Disconnect"
              showRedirectUri       = false
              sendRedirectUri       = false
            }
          },
        ]
      },
    ]
  }
}

module "tailscale_connector" {
  source = "./modules/codeless_connector"

  workspace_id        = azurerm_log_analytics_workspace.law.id
  definition_name     = "TailscaleCCPDefinition"
  connector_ui_config = local.tailscale_connector_ui_config

  author       = "Zamomfg"
  support_name = "Community"
  support_tier = "Community"

  pollers = {
    TailscaleAuditDataConnector = {
      properties = {
        connectorDefinitionName = "TailscaleCCPDefinition"
        dataType                = module.tailscale_audit_table.name
        dcrConfig = {
          dataCollectionEndpoint        = azurerm_monitor_data_collection_endpoint.tailscale.logs_ingestion_endpoint
          dataCollectionRuleImmutableId = module.tailscale_dcr.dcr_immutable_id
          streamName                    = local.tailscale_audit_stream
        }
        auth = merge(local.tailscale_oauth, { scope = "logs:configuration:read" })
        request = merge(local.tailscale_request_base, {
          apiEndpoint = "https://api.tailscale.com/api/v2/tailnet/${var.tailscale_tailnet}/logging/configuration"
        })
        response = { eventsJsonPaths = ["$.logs"], format = "json" }
      }
      sensitive_properties = {
        auth = { ClientSecret = var.tailscale_client_secret }
      }
    }

    TailscaleNetworkDataConnector = {
      properties = {
        connectorDefinitionName = "TailscaleCCPDefinition"
        dataType                = module.tailscale_network_table.name
        dcrConfig = {
          dataCollectionEndpoint        = azurerm_monitor_data_collection_endpoint.tailscale.logs_ingestion_endpoint
          dataCollectionRuleImmutableId = module.tailscale_dcr.dcr_immutable_id
          streamName                    = local.tailscale_network_stream
        }
        auth = merge(local.tailscale_oauth, { scope = "logs:network:read" })
        request = merge(local.tailscale_request_base, {
          apiEndpoint = "https://api.tailscale.com/api/v2/tailnet/${var.tailscale_tailnet}/network-logs"
        })
        response = { eventsJsonPaths = ["$.logs"], format = "json" }
      }
      sensitive_properties = {
        auth = { ClientSecret = var.tailscale_client_secret }
      }
    }
  }
}
