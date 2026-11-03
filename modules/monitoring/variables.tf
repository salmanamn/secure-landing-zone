variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "retention_days" {
  description = "30-730. 30 is the free-retention tier."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_days >= 30 && var.retention_days <= 730
    error_message = "Retention must be 30-730 days."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
