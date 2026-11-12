
variable "name" {
  type = string
}

variable "law_workspace_id" {
  type = string
}

variable "display_name" {
  type = string
}

variable "query" {
  type = string
}

variable "destination_table" {
  type = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{1,59}_CL$", var.destination_table))
    error_message = "destination_table must only contain letters, numbers and underscores, start with a letter, end with '_CL' and not be longer than 63 characters."
  }
}

variable "interval" {
  type        = string
  description = "How often the rule runs, and the size of the time window each run summarizes."
  validation {
    condition     = contains(["20m", "30m", "1h", "2h", "3h", "6h", "12h", "24h", "1d"], var.interval)
    error_message = "interval must be one of 20m, 30m, 1h, 2h, 3h, 6h, 12h, 24h (or 1d)."
  }
}

variable "delay" {
  type        = number
  description = "Seconds to wait after a window closes before summarizing it, to let late data arrive."
  nullable    = true
  default     = null
  validation {
    condition     = var.delay == null || var.delay >= 0
    error_message = "delay must be a non-negative number of seconds."
  }
}

variable "start_time" {
  type        = string
  description = "UTC RFC 3339 timestamp of the first window, e.g. 2026-11-12T00:00:00Z."
  nullable    = true
  default     = null
  validation {
    condition     = var.start_time == null || can(formatdate("YYYY", var.start_time))
    error_message = "start_time must be an RFC 3339 timestamp, e.g. 2026-11-12T00:00:00Z."
  }
}
