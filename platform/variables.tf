variable "subscription_id" {
  description = "Target subscription (terraform.tfvars, gitignored)."
  type        = string
}

variable "location" {
  description = "Region for platform resources. Must match the stack region (flow-log storage must be co-located with the VNet)."
  type        = string
  default     = "uaenorth"
}

variable "prefix" {
  description = "Naming prefix."
  type        = string
  default     = "slz"
}

variable "workspace_retention_days" {
  description = "Analytics retention for the platform workspace. AzureActivity is free up to 90 days."
  type        = number
  default     = 90
}

variable "workspace_daily_quota_gb" {
  description = "Daily ingestion cap (GB) as a lab cost guard. -1 = unlimited."
  type        = number
  default     = 1
}

variable "tags" {
  description = "Extra tags merged onto every platform resource."
  type        = map(string)
  default     = {}
}

variable "alert_email" {
  description = "Recipient for security activity-log alerts (terraform.tfvars, gitignored)."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}
