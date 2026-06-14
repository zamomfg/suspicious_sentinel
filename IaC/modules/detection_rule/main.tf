
locals {
  # Each known impacted-asset type maps to a fixed Graph identifier enum value.
  # The identifier dictates which column the query must project for the asset to
  # be bound (camelCase enum -> PascalCase column):
  #   impactedDeviceAsset        -> deviceId        -> DeviceId
  #   impactedUserAsset          -> accountObjectId -> AccountObjectId
  #   impactedMailboxAsset       -> accountUpn      -> AccountUpn
  #   impactedAzureResourceAsset -> azureResourceId -> ResourceUri (Azure resource entity)
  # For types not in this map, pass impacted_assets[].identifier explicitly.
  asset_identifiers = {
    impactedDeviceAsset        = "deviceId"
    impactedUserAsset          = "accountObjectId"
    impactedMailboxAsset       = "accountUpn"
    impactedAzureResourceAsset = "azureResourceId"
  }

  # Optional metadata header, rendered as KQL // comment lines.
  metadata = var.metadata == null ? "" : join("\n", concat(
    [
      "// Author: ${var.metadata.author}",
      "// Website: ${var.metadata.website}",
      "// References:",
    ],
    [for reference in var.metadata.references : "// - ${reference}"],
  ))

  # Map the convenient impacted_assets input onto the @odata.type-tagged objects
  # the Graph API expects. The identifier comes from the per-asset override when
  # given, otherwise the known map above.
  impacted_assets = [
    for asset in var.impacted_assets : {
      "@odata.type" = "#microsoft.graph.security.${asset.odata_type}"
      identifier    = coalesce(asset.identifier, lookup(local.asset_identifiers, asset.odata_type, null))
    }
  ]

  # Optionally strip KQL `//` line comments from the query. Two passes:
  #   1. whole-line comments — drop the entire line, including its newline, so
  #      no blank line is left behind ((?m) makes ^ match each line start);
  #   2. inline comments — drop the trailing `// ...` but keep the code.
  # trimspace tidies the edges.
  query_text = var.strip_comments ? trimspace(replace(
    replace(var.query_text, "/(?m)^[ \\t]*//.*\\n?/", ""),
    "/[ \\t]*//.*/",
    "",
  )) : (var.metadata == null ? var.query_text : "${local.metadata}\n${var.query_text}")

  # Build each response action: the @odata.type tag, an optional identifier,
  # and any action-specific settings merged in verbatim.
  response_actions = [
    for action in var.response_actions : merge(
      {
        "@odata.type" = "#microsoft.graph.security.${action.type}"
      },
      action.identifier == null ? {} : { identifier = action.identifier },
      action.settings,
    )
  ]
}

resource "msgraph_resource" "detection_rule" {
  url         = "security/rules/detectionRules"
  api_version = "beta"
  body = {
    displayName = var.display_name
    isEnabled   = var.is_enabled

    queryCondition = {
      queryText = local.query_text
    }

    schedule = {
      period = var.schedule_period
    }

    detectionAction = {
      organizationalScope = var.organizational_scope
      responseActions     = local.response_actions

      alertTemplate = {
        title              = var.alert_title
        description        = var.alert_description
        severity           = var.severity
        category           = var.category
        recommendedActions = var.recommended_actions
        mitreTechniques    = var.mitre_techniques
        impactedAssets     = local.impacted_assets
      }
    }
  }

  # Export server-assigned fields (export name => JMESPath into the response)
  # so they are available as outputs.
  response_export_values = {
    id                   = "id"
    detectorId           = "detectorId"
    createdDateTime      = "createdDateTime"
    lastModifiedDateTime = "lastModifiedDateTime"
  }
}
