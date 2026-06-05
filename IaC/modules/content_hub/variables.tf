
variable "log_analytics_workspace_id" {
  type        = string
  description = "Resource ID of the Sentinel-enabled Log Analytics workspace to install content into."
}

variable "content_id" {
  type        = string
  description = <<-EOT
    The contentId of the Content Hub solution to install, e.g.
    "azuresentinel.azure-sentinel-solution-uebaessentials". This is the
    properties.contentId from the contentProductPackages catalog.
  EOT
}

# Pin the solution version, e.g. "3.0.6". When null the module tracks whatever
# the catalog reports as latest, so a new gallery release would be picked up on
# the next apply. Set this to a fixed version to freeze the solution, then bump
# it deliberately to update. (Named solution_version, not version, because
# `version` is a reserved meta-argument inside a module block.)
variable "solution_version" {
  type        = string
  default     = null
  description = "Exact solution version to install. Null = latest from catalog."
}

# Which content kinds from the solution to actually deploy as contentTemplates.
# Installing the solution package alone only makes the items *available*; flip a
# kind to true here to have its items created in the workspace.
variable "install" {
  type = object({
    workbooks       = optional(bool, false)
    hunting_queries = optional(bool, false)
    analytics_rules = optional(bool, false)
    playbooks       = optional(bool, false)
    parsers         = optional(bool, false)
    data_connectors = optional(bool, false)
    watchlists      = optional(bool, false)
    summary_rules   = optional(bool, false)
  })
  default     = {}
  description = "Toggle which content kinds from the solution to deploy."
}
