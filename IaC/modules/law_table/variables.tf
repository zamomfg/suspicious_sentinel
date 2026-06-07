
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{1,59}_CL$", var.name))
    error_message = "A custom table must only contain letter numbers and underscores, start with a letter, end with '_CL' and not be longer then 63 characters."
  }
}

variable "law_workspace_id" {
  type = string
}

variable "retention_in_days" {
  type     = number
  nullable = true
  default  = null
}

variable "totalRetentionInDays" {
  type     = number
  nullable = true
  default  = null
}

variable "table_struct_file_path" {
  type     = string
  nullable = true
  default  = null

  validation {
    condition     = var.columns != null || var.table_struct_file_path != null
    error_message = "Provide either `columns` (inline) or `table_struct_file_path`."
  }
}

# Inline column schema, as an alternative to table_struct_file_path. When set it
# takes precedence over the file. Same shape as the struct JSON files
# (name, type, optional description).
variable "columns" {
  type = list(object({
    name        = string
    type        = string
    description = optional(string)
  }))
  nullable = true
  default  = null

  validation {
    condition     = var.columns == null || length(var.columns) > 0
    error_message = "columns, when set, must contain at least one column."
  }
}

variable "plan" {
  type    = string
  default = "Analytics"
}