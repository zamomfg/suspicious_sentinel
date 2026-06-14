
module "log_source_volume_drop" {
  source = "./modules/detection_rule"

  display_name      = "Log source ingestion drop anomaly"
  alert_title       = "Log source ingestion drop: {{DataType}}"
  alert_description = "A table's latest 30-minute ingested volume dropped >=20% below its learned 14-day baseline — a possible broken or blocked log source."
  severity          = "medium"
  category          = "DefenseEvasion"
  mitre_techniques  = ["T1562"]
  schedule_period   = "1H"

  metadata = {
    author  = "Zamomfg"
    website = "https://github.com/zamomfg"
  }

  query_text = <<-KQL
    let weeklyPeriod = 24 * 14;
    let endBin = bin(now(), 30m);
    Usage
    | where TimeGenerated >= ago(14d)
    | make-series Volume = sum(Quantity) default = 0.0 on TimeGenerated from endBin - 14d to endBin step 30m by DataType, ResourceUri
    | extend (flag, score, baseline) = series_decompose_anomalies(Volume, 1.5, weeklyPeriod, "linefit")
    | mv-expand TimeGenerated to typeof(datetime), Volume to typeof(real), flag to typeof(long), score to typeof(real), baseline to typeof(real)
    | where TimeGenerated >= endBin - 1h and TimeGenerated < endBin
    | where flag == -1
    | extend baseline = max_of(baseline, 0.0)
    | where baseline > 0
    | extend DeviationPercent = round((Volume - baseline) / baseline * 100, 1)
    | where DeviationPercent <= -20
    | extend Timestamp = TimeGenerated
    | project Timestamp, ResourceUri, DataType, ExpectedMB = round(baseline, 2), ActualMB = round(Volume, 2), DeviationPercent, AnomalyScore = round(score, 2)
  KQL
}

module "log_source_volume_spike" {
  source = "./modules/detection_rule"

  display_name      = "Log source ingestion spike anomaly"
  alert_title       = "Log source ingestion spike: {{DataType}}"
  alert_description = "A table's latest 30-minute ingested volume rose >=20% above its learned 14-day baseline."
  severity          = "low"
  category          = "SuspiciousActivity"
  schedule_period   = "1H"

  query_text = <<-KQL
    let weeklyPeriod = 24 * 14;
    let endBin = bin(now(), 30m);
    Usage
    | where TimeGenerated >= ago(14d)
    | make-series Volume = sum(Quantity) default = 0.0 on TimeGenerated from endBin - 14d to endBin step 30m by DataType, ResourceUri
    | extend (flag, score, baseline) = series_decompose_anomalies(Volume, 1.5, weeklyPeriod, "linefit")
    | mv-expand TimeGenerated to typeof(datetime), Volume to typeof(real), flag to typeof(long), score to typeof(real), baseline to typeof(real)
    | where TimeGenerated >= endBin - 1h and TimeGenerated < endBin
    | where flag == 1
    | extend baseline = max_of(baseline, 0.0)
    | where baseline > 0
    | extend DeviationPercent = round((Volume - baseline) / baseline * 100, 1)
    | where DeviationPercent >= 20
    | extend Timestamp = TimeGenerated
    | project Timestamp, ResourceUri, DataType, ExpectedMB = round(baseline, 2), ActualMB = round(Volume, 2), DeviationPercent, AnomalyScore = round(score, 2)
  KQL
}
