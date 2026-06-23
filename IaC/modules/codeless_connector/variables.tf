variable "workspace_id" {
  type        = string
  description = "Resource ID of the Log Analytics workspace; parent for the Sentinel data connector resources."
}

variable "definition_name" {
  type        = string
  description = "Name/id of the dataConnectorDefinition. Pollers reference it via connectorDefinitionName."
}

variable "author" {
  type        = string
  default     = "Community"
  description = "Author name shown in the connector's content metadata."
}

variable "support_name" {
  type        = string
  default     = "Community"
  description = "Support name shown in the connector's content metadata."
}

variable "support_tier" {
  type        = string
  default     = "Community"
  description = "Support tier shown as 'Supported by' on the connector page (Microsoft | Partner | Community)."
}

variable "connector_ui_config" {
  description = <<-EOT
    connectorUiConfig rendered as the connector's page in the Sentinel gallery.
    Field names/types follow the Sentinel REST API CustomizableConnectorUiConfig
    model, where no sub-field is marked required:
    https://learn.microsoft.com/rest/api/securityinsights/data-connector-definitions/create-or-update
  EOT

  type = object({
    title                            = optional(string)
    publisher                        = optional(string)
    descriptionMarkdown              = optional(string)
    id                               = optional(string)
    logo                             = optional(string)
    graphQueriesTableName            = optional(string)
    isConnectivityCriteriasMatchSome = optional(bool)

    graphQueries = optional(list(object({
      metricName = optional(string)
      legend     = optional(string)
      baseQuery  = optional(string)
    })))

    sampleQueries = optional(list(object({
      description = optional(string)
      query       = optional(string)
    })))

    dataTypes = optional(list(object({
      name                  = optional(string)
      lastDataReceivedQuery = optional(string)
    })))

    connectivityCriteria = optional(list(object({
      type  = optional(string)
      value = optional(list(string))
    })))

    availability = optional(object({
      status    = optional(number)
      isPreview = optional(bool)
    }))

    permissions = optional(object({
      resourceProvider = optional(list(object({
        provider               = optional(string)
        providerDisplayName    = optional(string)
        permissionsDisplayText = optional(string)
        scope                  = optional(string)
        requiredPermissions = optional(object({
          action = optional(bool)
          delete = optional(bool)
          read   = optional(bool)
          write  = optional(bool)
        }))
      })))
      customs = optional(list(object({
        name        = optional(string)
        description = optional(string)
      })))
      licenses = optional(list(string))
      tenant   = optional(list(string))
    }))

    instructionSteps = optional(list(object({
      title       = optional(string)
      description = optional(string)
      innerSteps  = optional(any)
      instructions = optional(list(object({
        type       = optional(string)
        parameters = optional(any)
      })))
    })))
  })
}

variable "pollers" {
  description = <<-EOT
    RestApiPoller connections, keyed by Azure resource name. `properties` is the
    dataConnector body; `sensitive_properties` is deep-merged in via azapi
    `sensitive_body` so secrets (e.g. clientSecret) stay out of Terraform state.
    Required/optional follow the Sentinel REST API model (data-connectors,
    RestApiPoller), which is the authoritative contract for the azapi body:
    https://learn.microsoft.com/rest/api/securityinsights/data-connectors/create-or-update
  EOT

  type = map(object({
    # Per the REST API, only auth, connectorDefinitionName and request are
    # required; every sub-field of request/response/dcrConfig/auth is optional.
    properties = object({
      auth                    = any # CcpAuthConfig union (OAuth2/Basic/APIKey/JWT/...)
      connectorDefinitionName = string

      request = object({
        apiEndpoint                    = optional(string)
        httpMethod                     = optional(string)
        queryWindowInMin               = optional(number)
        rateLimitQPS                   = optional(number)
        retryCount                     = optional(number)
        timeoutInSeconds               = optional(number)
        queryTimeFormat                = optional(string)
        isPostPayloadJson              = optional(bool)
        headers                        = optional(map(string))
        queryParameters                = optional(any)
        queryParametersTemplate        = optional(string)
        startTimeAttributeName         = optional(string)
        endTimeAttributeName           = optional(string)
        queryTimeIntervalAttributeName = optional(string)
        queryTimeIntervalPrepend       = optional(string)
        queryTimeIntervalDelimiter     = optional(string)
      })

      response = optional(object({
        eventsJsonPaths               = optional(list(string))
        format                        = optional(string)
        successStatusJsonPath         = optional(string)
        successStatusValue            = optional(string)
        isGzipCompressed              = optional(bool)
        compressionAlgo               = optional(string)
        csvDelimiter                  = optional(string)
        hasCsvBoundary                = optional(bool)
        hasCsvHeader                  = optional(bool)
        csvEscape                     = optional(string)
        convertChildPropertiesToArray = optional(bool)
      }))

      dcrConfig = optional(object({
        dataCollectionEndpoint        = optional(string)
        dataCollectionRuleImmutableId = optional(string)
        streamName                    = optional(string)
      }))

      paging          = optional(any) # RestApiPollerRequestPagingConfig (polymorphic)
      dataType        = optional(string)
      isActive        = optional(bool)
      addOnAttributes = optional(map(string))
    })

    sensitive_properties = optional(any, {})
  }))
}
