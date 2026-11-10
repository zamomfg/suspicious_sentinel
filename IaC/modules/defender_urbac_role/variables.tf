variable "display_name" {
  description = "Display name of the Defender unified RBAC role."
  type        = string
}

variable "permissions" {
  description = "Allowed resource actions of the role, e.g. \"microsoft.xdr/secops/securitydata/alerts/manage\"."
  type        = list(string)

  validation {
    condition     = length(var.permissions) > 0
    error_message = "permissions must contain at least one action."
  }
}

variable "assignments" {
  description = <<-EOT
    Role assignments. Each assignment grants the role to principal_ids over:
      data_sources     - Defender workloads: Mde, Mdo, Mda, Mdc, SecureScoreExternal, Sai,
                         or "AllIncludingFutureDataSources".
      data_collections - Sentinel workspace ids the assignment can query,
                         or "AllExistingAndFutureWorkspaces".
  EOT
  type = list(object({
    display_name     = string
    principal_ids    = list(string)
    data_sources     = optional(list(string), [])
    data_collections = optional(list(string), [])
  }))
  default = []

  validation {
    condition     = length(distinct([for a in var.assignments : a.display_name])) == length(var.assignments)
    error_message = "Assignment display_name values must be unique."
  }

  validation {
    condition = alltrue([for a in var.assignments : alltrue([
      for s in a.data_sources : contains(["Mde", "Mdo", "Mda", "Mdc", "SecureScoreExternal", "Sai", "AllIncludingFutureDataSources"], s)
    ])])
    error_message = "data_sources values must be Mde, Mdo, Mda, Mdc, SecureScoreExternal, Sai or AllIncludingFutureDataSources."
  }

  validation {
    condition = alltrue([for a in var.assignments :
      !contains(a.data_sources, "AllIncludingFutureDataSources") || length(a.data_sources) == 1
    ])
    error_message = "AllIncludingFutureDataSources can't be combined with other data_sources."
  }

  validation {
    condition = alltrue([for a in var.assignments :
      !contains(a.data_collections, "AllExistingAndFutureWorkspaces") || length(a.data_collections) == 1
    ])
    error_message = "AllExistingAndFutureWorkspaces can't be combined with workspace ids."
  }

  validation {
    condition     = alltrue([for a in var.assignments : length(a.principal_ids) > 0 && length(a.data_sources) + length(a.data_collections) > 0])
    error_message = "Each assignment needs at least one principal_id and at least one data_source or data_collection."
  }
}
