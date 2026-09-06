variable "rule_id" {
  description = "Client-provided unique identifier of the rule (Graph requires an id on create). Stable, e.g. \"mikrotik-port-scan\"."
  type        = string
}

variable "display_name" {
  description = "Display name of the custom detection rule."
  type        = string
}

variable "description" {
  description = "Description of the detection rule. Null to omit."
  type        = string
  default     = null
}

variable "is_enabled" {
  description = "Whether the rule runs on its schedule. Maps to status (enabled/disabled)."
  type        = bool
  default     = true
}

variable "query_text" {
  description = "The Kusto Query Language (KQL) advanced-hunting query that powers the detection rule."
  type        = string
}

variable "strip_comments" {
  description = <<-EOT
    When true, strip KQL line comments (`//` to end of line) from query_text
    before deploying. KQL only has line comments. Uses a simple regex, so it
    also removes `//` inside string literals or URLs — leave off for those.
  EOT
  type        = bool
  default     = false
}

variable "schedule_frequency" {
  description = "How often the rule runs, as an ISO 8601 duration: PT1H, PT3H, PT12H, PT24H, or PT0S for continuous (NRT / near-real-time). NRT requires a single-table query using the supported operator set."
  type        = string
  default     = "PT24H"

  validation {
    condition     = contains(["PT0S", "PT1H", "PT3H", "PT12H", "PT24H"], var.schedule_frequency)
    error_message = "schedule_frequency must be one of: PT0S (NRT), PT1H, PT3H, PT12H, PT24H."
  }
}

# --- Alert template -------------------------------------------------------

variable "alert_title" {
  description = "Title of the alert raised when the rule matches. Defaults to display_name."
  type        = string
  default     = null
}

variable "alert_description" {
  description = "Description shown on alerts raised by this rule."
  type        = string
}

variable "severity" {
  description = "Severity of the raised alert."
  type        = string
  default     = "medium"

  validation {
    condition     = contains(["informational", "low", "medium", "high"], var.severity)
    error_message = "severity must be one of: informational, low, medium, high."
  }
}

variable "category" {
  description = "Alert category, e.g. \"Execution\", \"Malware\", \"Persistence\". Null to omit."
  type        = string
  default     = null
}

variable "recommended_actions" {
  description = "Recommended actions to display on the alert. Null to omit."
  type        = string
  default     = null
}

variable "mitre_tactics" {
  description = <<-EOT
    MITRE ATT&CK tactics and their techniques, mapped onto the API's tactics[]
    shape. Example:
      mitre_tactics = [{ tactic = "Execution", techniques = ["T1059.001"] }]
  EOT
  type = list(object({
    tactic     = string
    techniques = optional(list(string), [])
  }))
  default = []
}

variable "entity_mappings" {
  description = <<-EOT
    alertTemplate.entityMappings passed verbatim (Graph beta shape): an object of
    typed arrays keyed by entity, each binding query columns. Example:
      entity_mappings = {
        hosts    = [{ deviceIdColumn = "DeviceId", nameColumn = "DeviceName" }]
        accounts = [{ nameColumn = "AccountName", sidColumn = "AccountSid" }]
      }
    Null to omit.
  EOT
  type        = any
  default     = null
}

# --- Detection action extras ----------------------------------------------

variable "detection_action_extra" {
  description = <<-EOT
    Extra detectionAction fields merged verbatim alongside alertTemplate (Graph
    beta shape), e.g. automatedActions and organizationalScope:
      detection_action_extra = {
        automatedActions    = { isolateDevices = [{ deviceIdColumn = "DeviceId", isolationType = "full" }] }
        organizationalScope = { scopeType = "allDevices" }
      }
  EOT
  type        = any
  default     = {}
}

variable "metadata" {
  description = "Optional SIGMA-style metadata rendered as a KQL comment header on the query."
  type = object({
    author          = string
    description     = optional(string)
    website         = optional(string)
    references      = optional(list(string), [])
    false_positives = optional(list(string), [])
  })
  default  = null
  nullable = true
}
