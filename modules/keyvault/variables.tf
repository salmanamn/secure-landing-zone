variable "name" {
  description = "Globally unique, 3-24 chars, starts with a letter"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "Key Vault name: 3-24 chars, letters/digits/hyphens, start with a letter, no '--'."
  }
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "pe_subnet_id" {
  type = string
}

variable "keyvault_private_dns_zone_id" {
  type = string
}

variable "soft_delete_days" {
  description = "7-90. Lab uses 7 so names free up quickly after destroy."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_days >= 7 && var.soft_delete_days <= 90
    error_message = "Soft delete retention must be 7-90 days."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
