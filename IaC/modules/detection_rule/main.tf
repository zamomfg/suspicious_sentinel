locals {
  sigma_tags = concat(
    flatten([
      for t in var.mitre_tactics : concat(
        ["attack.${lower(replace(t.tactic, "/([a-z])([A-Z])/", "$${1}_$${2}"))}"],
        [for technique in t.techniques : "attack.${lower(technique)}"],
      )
    ]),
    var.tags,
  )

  # SigmaHQ-ordered metadata header rendered as KQL `//` comment lines.
  metadata_header = join("\n", concat(
    [
      "// Title: ${var.title}",
      "// Id: ${var.rule_id}",
      "// Status: ${var.status}",
      "// Description: ${replace(trimspace(var.description), "\n", "\n// ")}",
    ],
    length(var.references) > 0 ? concat(["// References:"], [for r in var.references : "//   - ${r}"]) : [],
    [
      "// Author: ${var.author}",
      "// Date: ${var.date}",
    ],
    var.modified == "" ? [] : ["// Modified: ${var.modified}"],
    length(local.sigma_tags) > 0 ? ["// Tags: ${join(", ", local.sigma_tags)}"] : [],
    ["// Logsource:"],
    [for k in ["category", "product", "service"] : "//   ${k}: ${var.logsource[k]}" if var.logsource[k] != null],
    ["// False Positives:"],
    [for fp in var.false_positives : "//   - ${fp}"],
    ["// Level: ${var.severity}"],
  ))

  # Optionally strip KQL `//` line comments (whole-line then inline); otherwise
  # prepend the metadata header.
  query_text = var.strip_comments ? trimspace(replace(
    replace(var.query_text, "/(?m)^[ \\t]*//.*\\n?/", ""),
    "/[ \\t]*//.*/",
    "",
  )) : "${local.metadata_header}\n\n${var.query_text}"

  # The detectionRules API accepts a single tactic, so only the first one is sent;
  # the rest still appear as Sigma tags in the header.
  defender_tactics = [
    for t in slice(var.mitre_tactics, 0, min(1, length(var.mitre_tactics))) : {
      tactic     = t.tactic
      techniques = [for technique in t.techniques : { technique = technique }]
    }
  ]

  category = var.category != null ? var.category : try(var.mitre_tactics[0].tactic, null)

  alert_template = merge(
    {
      title       = var.title
      description = var.description
      severity    = var.severity
    },
    local.category != null ? { category = local.category } : {},
    var.recommended_actions != null ? { recommendedActions = var.recommended_actions } : {},
    length(local.defender_tactics) > 0 ? { tactics = local.defender_tactics } : {},
    var.entity_mappings != null ? { entityMappings = var.entity_mappings } : {},
  )

  # detection_action_extra carries the volatile parts of detectionAction verbatim
  # (e.g. automatedActions, organizationalScope) so the module stays correct as
  # the beta schema evolves.
  detection_action = merge(
    { alertTemplate = local.alert_template },
    var.detection_action_extra,
  )

  schedule_frequency = var.schedule_frequency == "NRT" ? "PT0S" : var.schedule_frequency

  body = {
    id              = var.rule_id
    displayName     = var.title
    description     = var.description
    status          = var.is_enabled ? "enabled" : "disabled"
    queryCondition  = { queryText = local.query_text }
    schedule        = { frequency = local.schedule_frequency }
    detectionAction = local.detection_action
  }
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
