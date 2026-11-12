
locals {
  interval_minutes = {
    "20m" = 20
    "30m" = 30
    "1h"  = 60
    "2h"  = 120
    "3h"  = 180
    "6h"  = 360
    "12h" = 720
    "24h" = 1440
    "1d"  = 1440
  }

  rule_definition = {
    for k, v in {
      query            = var.query
      destinationTable = var.destination_table
      binSize          = local.interval_minutes[var.interval]
      binDelay         = var.delay
      binStartTime     = var.start_time
    } : k => v if v != null
  }
}

resource "azapi_resource" "summary_rule" {
  name      = var.name
  parent_id = var.law_workspace_id
  type      = "Microsoft.OperationalInsights/workspaces/summaryLogs@2025-07-01"

  body = {
    properties = {
      ruleType       = "User"
      displayName    = var.display_name
      ruleDefinition = local.rule_definition
    }
  }
}
