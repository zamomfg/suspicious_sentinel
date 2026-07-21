
resource "azurerm_sentinel_threat_intelligence_indicator" "test_malicious_ip" {
  workspace_id      = azurerm_log_analytics_workspace.law.id
  pattern_type      = "ipv4-addr"
  pattern           = "[ipv4-addr:value = '198.51.100.42']"
  source            = "Microsoft Sentinel"
  validate_from_utc = "2026-06-22T00:00:00Z"
  display_name      = "Test malicious IP 198.51.100.42"
  description       = "Test threat intelligence indicator (RFC 5737 documentation address); not a real threat."
  threat_types      = ["malicious-activity"]
  confidence        = 100
}
