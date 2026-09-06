locals {
  # Optional metadata header rendered as KQL `//` comment lines.
  metadata = var.metadata == null ? "" : trimspace(join("\n", concat(
    ["// Author: ${var.metadata.author}"],
    var.metadata.website == null ? [] : ["// Website: ${var.metadata.website}"],
    length(var.metadata.references) > 0 ? concat(["// References:"], [for r in var.metadata.references : "// - ${r}"]) : [],
  )))

  # Optionally strip KQL `//` line comments (whole-line then inline); otherwise
  # prepend the metadata header when one is supplied.
  query_text = var.strip_comments ? trimspace(replace(
    replace(var.query_text, "/(?m)^[ \\t]*//.*\\n?/", ""),
    "/[ \\t]*//.*/",
    "",
  )) : (var.metadata == null ? var.query_text : "${local.metadata}\n${var.query_text}")

  # mitre_tactics -> the API's tactics[] shape ({ tactic, techniques:[{technique}] }).
  tactics = [
    for t in var.mitre_tactics : {
      tactic     = t.tactic
      techniques = [for technique in t.techniques : { technique = technique }]
    }
  ]

  alert_template = merge(
    {
      title       = coalesce(var.alert_title, var.display_name)
      description = var.alert_description
      severity    = var.severity
    },
    var.category != null ? { category = var.category } : {},
    var.recommended_actions != null ? { recommendedActions = var.recommended_actions } : {},
    length(local.tactics) > 0 ? { tactics = local.tactics } : {},
    var.entity_mappings != null ? { entityMappings = var.entity_mappings } : {},
  )

  # detection_action_extra carries the volatile parts of detectionAction verbatim
  # (e.g. automatedActions, organizationalScope) so the module stays correct as
  # the beta schema evolves.
  detection_action = merge(
    { alertTemplate = local.alert_template },
    var.detection_action_extra,
  )

  body = merge(
    {
      id              = var.rule_id
      displayName     = var.display_name
      status          = var.is_enabled ? "enabled" : "disabled"
      queryCondition  = { queryText = local.query_text }
      schedule        = { frequency = var.schedule_frequency }
      detectionAction = local.detection_action
    },
    var.description != null ? { description = var.description } : {},
  )
}

resource "msgraph_resource" "detection_rule" {
  url         = "security/rules/detectionRules"
  api_version = "beta"
  body        = local.body

  # export name => JMESPath into the response
  response_export_values = {
    id                   = "id"
    status               = "status"
    createdDateTime      = "createdDateTime"
    lastModifiedDateTime = "lastModifiedDateTime"
  }
}
