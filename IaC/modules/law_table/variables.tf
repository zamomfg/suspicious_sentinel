
variable "name" {
  type = string
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9_]{1,59}_CL$", var.name))
    error_message = "A custom table must only contain letter numbers and underscores, start with a letter, end with '_CL' and not be longer then 63 characters."
  }
}

variable "law_workspace_id" {
  type = string
}

variable "retention_in_days" {
  type = number
  nullable = true
  default = null
}

variable "totalRetentionInDays" {
  type = number
  nullable = true
  default = null
}

variable "table_struct_file_path" {
  type = string
}

variable "plan" {
  type = string
  default = "Analytics"
}