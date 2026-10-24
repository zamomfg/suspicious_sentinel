variable "rule_id" {
  description = "Client-provided unique identifier of the rule (Graph requires an id on create). Stable, e.g. \"mikrotik-port-scan\"."
  type        = string
}

variable "title" {
  description = "Sigma title; also the rule display name and the alert title."
  type        = string

  validation {
    condition     = length(var.title) <= 256
    error_message = "title must be at most 256 characters (Sigma title limit)."
  }
}

variable "description" {
  description = "Sigma description; also the rule description and the alert description. Per SigmaHQ convention it starts with \"Detects\"."
  type        = string
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
  description = "How often the rule runs, as an ISO 8601 duration: PT1H, PT3H, PT12H, PT24H, or NTR (near-real-time)"
  type        = string
  default     = "PT24H"

  validation {
    condition     = contains(["NTR", "PT1H", "PT3H", "PT12H", "PT24H"], var.schedule_frequency)
    error_message = "schedule_frequency must be one of: NTR, PT1H, PT3H, PT12H, PT24H."
  }
}

# --- Alert template -------------------------------------------------------

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
  description = "Alert category, e.g. \"Execution\", \"Malware\", \"Persistence\". Defaults to the first MITRE tactic."
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
    MITRE ATT&CK tactics and their techniques. All are rendered as Sigma tags;
    only the first is sent to Defender, whose API accepts a single tactic. Example:
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

# --- Sigma metadata (rendered as a KQL comment header) --------------------
# https://sigmahq.io/sigma-specification/specification/sigma-rules-specification.html

variable "status" {
  description = "Sigma rule maturity (not whether the rule runs; see is_enabled). New rules start as experimental."
  type        = string

  validation {
    condition     = contains(["stable", "test", "experimental", "deprecated", "unsupported"], var.status)
    error_message = "status must be one of: stable, test, experimental, deprecated, unsupported."
  }
}

variable "logsource" {
  description = "Sigma logsource: lower-case category/product/service the query reads, e.g. { category = \"firewall\", product = \"mikrotik\" }."
  type = object({
    category = optional(string)
    product  = optional(string)
    service  = optional(string)
  })

  validation {
    condition     = anytrue([for v in values(var.logsource) : v != null])
    error_message = "logsource must set at least one of category, product or service."
  }

  validation {
    condition     = alltrue([for v in values(var.logsource) : v == null || can(regex("^[a-z0-9_]+$", v))])
    error_message = "logsource values must be lower case with underscores instead of spaces."
  }
}

variable "author" {
  description = "Sigma author of the rule."
  type        = string
}

variable "date" {
  description = "Sigma creation date, YYYY-MM-DD."
  type        = string

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.date))
    error_message = "date must be YYYY-MM-DD."
  }
}

variable "modified" {
  description = "Sigma last-modified date, YYYY-MM-DD. Empty to omit."
  type        = string
  default     = ""

  validation {
    condition     = var.modified == "" || can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.modified))
    error_message = "modified must be YYYY-MM-DD."
  }
}

variable "references" {
  description = "Sigma references: public URLs explaining the detection. No MITRE ATT&CK URLs; those belong in mitre_tactics."
  type        = list(string)
}

variable "false_positives" {
  description = "Sigma falsepositives: known benign triggers. Use \"Unknown\" or \"Unlikely\" if none are known."
  type        = list(string)

  validation {
    condition     = length(var.false_positives) > 0
    error_message = "false_positives must list at least one entry (use \"Unknown\" or \"Unlikely\" if none are known)."
  }
}

variable "tags" {
  description = "Extra Sigma tags beyond the attack.* tags derived from mitre_tactics, e.g. \"detection.threat_hunting\"."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for t in var.tags : can(regex("^[a-z0-9_-]+\\.[a-z0-9_.-]+$", t))])
    error_message = "tags must be namespaced lower-case Sigma tags, e.g. \"detection.threat_hunting\"."
  }
}
