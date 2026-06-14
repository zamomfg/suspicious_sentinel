variable "display_name" {
  description = "Display name of the custom detection rule."
  type        = string
}

variable "is_enabled" {
  description = "Whether the detection rule is enabled and runs on its schedule."
  type        = bool
  default     = true
}

variable "query_text" {
  description = "The Kusto Query Language (KQL) query that powers the detection rule."
  type        = string
}

variable "strip_comments" {
  description = <<-EOT
    When true, strip KQL line comments (`//` to end of line) from query_text
    before deploying the rule. KQL only has line comments (no block comments).
    This uses a simple regex, so it will also remove `//` that appears inside
    string literals or URLs — leave it off for queries that contain those.
  EOT
  type        = bool
  default     = false
}

variable "schedule_period" {
  description = "How often the rule runs. One of the periods accepted by the API (e.g. \"0\", \"1H\", \"3H\", \"12H\", \"24H\")."
  type        = string
  default     = "24H"

  validation {
    condition     = contains(["0", "1H", "3H", "12H", "24H"], var.schedule_period)
    error_message = "schedule_period must be one of: \"0\", \"1H\", \"3H\", \"12H\", \"24H\"."
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
  description = "Alert category (MITRE-aligned), e.g. \"Execution\", \"Malware\", \"Persistence\"."
  type        = string
}

variable "mitre_techniques" {
  description = "List of MITRE ATT&CK technique IDs associated with the alert (e.g. [\"T1059\"])."
  type        = list(string)
  default     = []
}

variable "recommended_actions" {
  description = "Recommended actions to display on the alert. Null to omit."
  type        = string
  default     = null
}

variable "impacted_assets" {
  description = <<-EOT
    Assets impacted by the alert. Each entry's `odata_type` is the short asset
    type name. The binding identifier is fixed per known asset type (and dictates
    the column the query must project); for other types set `identifier` directly.
      impactedDeviceAsset        -> DeviceId
      impactedUserAsset          -> AccountObjectId
      impactedMailboxAsset       -> AccountUpn
      impactedAzureResourceAsset -> ResourceUri
  EOT
  type = list(object({
    odata_type = string
    identifier = optional(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for asset in var.impacted_assets :
      contains(
        ["impactedDeviceAsset", "impactedUserAsset", "impactedMailboxAsset", "impactedAzureResourceAsset"],
        asset.odata_type,
      ) || asset.identifier != null
    ])
    error_message = "Each impacted_assets[].odata_type must be a known type, or set identifier explicitly."
  }
}

# --- Response actions / scope --------------------------------------------

variable "response_actions" {
  description = <<-EOT
    Automated response actions to run when the rule matches.

    Each entry's `type` e.g. "isolateDeviceResponseAction",
    "forceUserPasswordResetResponseAction", "disableUserResponseAction".

    `identifier` is the query column that identifies the target entity.
    `settings` carries any action-specific fields (e.g. { isolationType = "full" })
    and is merged into the action verbatim.

    Defaults to no response actions.
  EOT
  type = list(object({
    type       = string
    identifier = optional(string)
    settings   = optional(map(string), {})
  }))
  default = []
}

variable "organizational_scope" {
  description = "Optional organizational scope restricting where the rule applies. Null applies it tenant-wide."
  type        = any
  default     = null
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