
# resource "azurerm_sentinel_alert_rule_scheduled" "log_source_volume_drop" {
#   name                       = "log-source-volume-drop-${local.location_short}-001"
#   log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
#   display_name               = "Log source ingestion drop anomaly (per table)"
#   description                = "Fires per table when a completed 30-minute bin in the last hour is an anomalous drop (>=20% below the table's learned 14-day baseline)."
#   severity                   = "Medium"
#   tactics                    = ["DefenseEvasion"]

#   enabled         = true
#   query_frequency = "PT1H"
#   query_period    = "P14D"

#   trigger_operator  = "GreaterThan"
#   trigger_threshold = 0

#   event_grouping {
#     aggregation_method = "AlertPerResult"
#   }

#   query = <<-QUERY
#     let endBin = bin(now(), 30m);
#     let weeklyPeriod = 24 * 14;
#     Usage
#     | where TimeGenerated >= ago(14d)
#     | make-series Volume = sum(Quantity) default = 0.0 on TimeGenerated from endBin - 14d to endBin step 30m by DataType
#     | extend (flag, score, baseline) = series_decompose_anomalies(Volume, 1.5, weeklyPeriod, "linefit")
#     | mv-expand TimeGenerated to typeof(datetime), Volume to typeof(real), flag to typeof(long), score to typeof(real), baseline to typeof(real)
#     | where TimeGenerated >= endBin - 1h and TimeGenerated < endBin
#     | where flag == -1
#     | extend baseline = max_of(baseline, 0.0)
#     | where baseline > 0
#     | extend DeviationPercent = round((Volume - baseline) / baseline * 100, 1)
#     | where DeviationPercent <= -20
#     | project BinTime = TimeGenerated, DataType, ExpectedMB = round(baseline, 2), ActualMB = round(Volume, 2), DeviationPercent, AnomalyScore = round(score, 2)
#     | order by DeviationPercent asc
#   QUERY
# }

# resource "azurerm_sentinel_alert_rule_scheduled" "log_source_volume_spike" {
#   name                       = "log-source-volume-spike-${local.location_short}-001"
#   log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
#   display_name               = "Log source ingestion spike anomaly (per table)"
#   description                = "Fires per table when a completed 30-minute bin in the last hour is an anomalous spike (>=20% above the table's learned 14-day baseline)."
#   severity                   = "Low"

#   enabled         = true
#   query_frequency = "PT1H"
#   query_period    = "P14D"

#   trigger_operator  = "GreaterThan"
#   trigger_threshold = 0

#   event_grouping {
#     aggregation_method = "AlertPerResult"
#   }

#   query = <<-QUERY
#     let endBin = bin(now(), 30m);
#     let weeklyPeriod = 24 * 14;
#     Usage
#     | where TimeGenerated >= ago(14d)
#     | make-series Volume = sum(Quantity) default = 0.0 on TimeGenerated from endBin - 14d to endBin step 30m by DataType
#     | extend (flag, score, baseline) = series_decompose_anomalies(Volume, 1.5, weeklyPeriod, "linefit")
#     | mv-expand TimeGenerated to typeof(datetime), Volume to typeof(real), flag to typeof(long), score to typeof(real), baseline to typeof(real)
#     | where TimeGenerated >= endBin - 1h and TimeGenerated < endBin
#     | where flag == 1
#     | extend baseline = max_of(baseline, 0.0)
#     | where baseline > 0
#     | extend DeviationPercent = round((Volume - baseline) / baseline * 100, 1)
#     | where DeviationPercent >= 20
#     | project BinTime = TimeGenerated, DataType, ExpectedMB = round(baseline, 2), ActualMB = round(Volume, 2), DeviationPercent, AnomalyScore = round(score, 2)
#     | order by DeviationPercent desc
#   QUERY
# }
