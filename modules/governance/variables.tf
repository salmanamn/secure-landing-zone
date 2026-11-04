variable "name" {
  description = "Prefix for definition/assignment names, e.g. slz-local"
  type        = string
}

variable "resource_group_id" {
  description = "Scope of the assignment"
  type        = string
}

variable "hardened" {
  description = "Assign the baseline only when hardened"
  type        = bool
  default     = true
}

variable "effect" {
  description = "Deny blocks non-compliant writes; Audit only reports them"
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Deny", "Audit", "Disabled"], var.effect)
    error_message = "effect must be Deny, Audit or Disabled."
  }
}
