variable "name" {
  description = "Globally unique, 3-24 lowercase letters/digits"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "Storage account name must be 3-24 lowercase letters or digits."
  }
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "pe_subnet_id" {
  description = "Subnet for the private endpoint"
  type        = string
}

variable "blob_private_dns_zone_id" {
  description = "privatelink.blob.core.windows.net zone ID"
  type        = string
}

variable "hardened" {
  description = "true = secure baseline. false = deliberately weak (Prowler 'before')."
  type        = bool
  default     = true
}

variable "soft_delete_days" {
  type    = number
  default = 7

  validation {
    condition     = var.soft_delete_days >= 7 && var.soft_delete_days <= 365
    error_message = "Soft delete retention must be 7-365 days."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "log_analytics_workspace_id" {
  description = "Destination for resource logs (null when diagnostics are disabled)"
  type        = string
  default     = null
}

variable "diagnostics_enabled" {
  description = "Send resource logs to Log Analytics"
  type        = bool
  default     = true
}
