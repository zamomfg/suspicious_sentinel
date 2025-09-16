
variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type     = map(string)
  nullable = true
}

variable "kind" {
  type     = string
  default  = null
  nullable = true
}

variable "law_destinations_workspace_id" {
  type        = list(string)
  description = "A list of destination law workspace ids"
}

# variable "data_sources" {
#   description = "Data sources"
#   type = list(object({
#     data_import          = optional(object)
#     extentions           = optional(object)
#     iis_logs             = optional(object)
#     log_file             = optional(object)
#     performance_counter  = optional(object)
#     platform_telemetry   = optional(object)
#     prometheus_forwarder = optional(object)
#     syslog               = optional(object)
#     windows_event_log    = optional(object)
#     windows_firewall_log = optional(object)
#   }))
#   default  = null
#   nullable = true
# }

variable "data_sources_syslog" {
  description = "Data sources"
  type = list(object({
    name           = string
    streams        = list(string)
    facility_names = list(string)
    log_levels     = list(string)
  }))
  default  = null
  nullable = true
}

variable "data_flows" {
  description = "List of data flows"
  type = list(object({
    destinations       = list(string)
    streams            = list(string)
    built_in_transform = optional(string)
    output_stream      = optional(string)
    transform_kql      = optional(string)
  }))
}

variable "logging_workspace_id" {
  type     = string
  default  = null
  nullable = true
}

variable "stream_declarations" {
  type = list(object({
    stream_name = string
    column_schema = list(object({
      name = string
      type = string
    }))
  }))
  default = []

  validation {
    condition = alltrue([
      for stream in var.stream_declarations : can(regex("^Custom-", stream.stream_name))
    ])
    error_message = "Stream names must start with 'Custom-'."
  }
}

variable "data_collection_endpoint_id" {
  type     = string
  default  = null
  nullable = true
}

variable "vm_association_ids" {
  type     = list(string)
  default  = null
  nullable = true
}
