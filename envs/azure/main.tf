variable "subscription_id" {
  description = "Lab subscription (set in gitignored terraform.tfvars)"
  type        = string
}

variable "location" {
  type    = string
  default = "uaenorth"
}

variable "hardened" {
  description = "No default on purpose: every apply states the profile. Order: false -> true -> destroy (D5)."
  type        = bool
}

module "stack" {
  source   = "../../modules/stack"
  name     = "slz-azure"
  location = var.location
  hardened = var.hardened

  # Emulator switches (log_analytics_enabled, role_assignments_enabled, storage_cmk_enabled)
  # are deliberately left at their defaults (true): real Azure gets the full stack.

  tags = {
    project    = "secure-landing-zone"
    managed_by = "terraform"
    env        = "azure-lab"
  }
}

output "summary" {
  value = module.stack
}
