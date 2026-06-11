
# resource "azurerm_sentinel_alert_rule_anomaly_built_in" "name" {

# }

# Per-table ingestion anomaly detection. A 14-day, 30-minute-binned time series per
# table is decomposed (series_decompose_anomalies) so each source is judged against its
# own learned seasonal baseline — tables that normally spike/dip do not false-positive.
# Evaluation targets the last fully-closed 30-minute bin (the current bin is partial and,
# given Usage-table lag, would read low). Fires only when that bin is both a flagged
# anomaly and >=20% off baseline.
# A drop can indicate a broken/blocked log source (Medium); a spike is informational (Low).
resource "azurerm_sentinel_alert_rule_scheduled" "log_source_volume_drop" {
  name                       = "log-source-volume-drop-${local.location_short}-001"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
  display_name               = "Log source ingestion drop anomaly (per table)"
  description                = "Fires per table when the last completed 30-minute bin is an anomalous drop (>=20% below the table's learned 14-day baseline)."
  severity                   = "Medium"
  tactics                    = ["DefenseEvasion"]

  enabled         = true
  query_frequency = "PT30M"
  query_period    = "P14D"

  trigger_operator  = "GreaterThan"
  trigger_threshold = 0

  event_grouping {
    aggregation_method = "AlertPerResult"
  }

  query = <<-QUERY
    let endBin = bin(now(), 30m);
    Usage
    | where TimeGenerated >= ago(14d)
    | make-series Volume = sum(Quantity) default = 0.0 on TimeGenerated from endBin - 14d to endBin step 30m by DataType
    | extend (flag, score, baseline) = series_decompose_anomalies(Volume, 1.5, -1, "linefit")
    | mv-expand TimeGenerated to typeof(datetime), Volume to typeof(real), flag to typeof(long), score to typeof(real), baseline to typeof(real)
    | where TimeGenerated == endBin - 30m
    | where flag == -1
    | extend baseline = max_of(baseline, 0.0)
    | where baseline > 0
    | extend DeviationPercent = round((Volume - baseline) / baseline * 100, 1)
    | where DeviationPercent <= -20
    | project DataType, ExpectedMB = round(baseline, 2), ActualMB = round(Volume, 2), DeviationPercent, AnomalyScore = round(score, 2)
    | order by DeviationPercent asc
  QUERY
}

resource "azurerm_sentinel_alert_rule_scheduled" "log_source_volume_spike" {
  name                       = "log-source-volume-spike-${local.location_short}-001"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
  display_name               = "Log source ingestion spike anomaly (per table)"
  description                = "Fires per table when the last completed 30-minute bin is an anomalous spike (>=20% above the table's learned 14-day baseline)."
  severity                   = "Low"

  enabled         = true
  query_frequency = "PT30M"
  query_period    = "P14D"

  trigger_operator  = "GreaterThan"
  trigger_threshold = 0

  event_grouping {
    aggregation_method = "AlertPerResult"
  }

  query = <<-QUERY
    let endBin = bin(now(), 30m);
    Usage
    | where TimeGenerated >= ago(14d)
    | make-series Volume = sum(Quantity) default = 0.0 on TimeGenerated from endBin - 14d to endBin step 30m by DataType
    | extend (flag, score, baseline) = series_decompose_anomalies(Volume, 1.5, -1, "linefit")
    | mv-expand TimeGenerated to typeof(datetime), Volume to typeof(real), flag to typeof(long), score to typeof(real), baseline to typeof(real)
    | where TimeGenerated == endBin - 30m
    | where flag == 1
    | extend baseline = max_of(baseline, 0.0)
    | where baseline > 0
    | extend DeviationPercent = round((Volume - baseline) / baseline * 100, 1)
    | where DeviationPercent >= 20
    | project DataType, ExpectedMB = round(baseline, 2), ActualMB = round(Volume, 2), DeviationPercent, AnomalyScore = round(score, 2)
    | order by DeviationPercent desc
  QUERY
}
