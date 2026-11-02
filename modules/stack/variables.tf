variable "name" {
  description = "Name stem, e.g. slz-local or slz-dev"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,10}$", var.name))
    error_message = "name: 3-11 chars, lowercase letters/digits/hyphens, starts with a letter."
  }
}

variable "location" {
  type = string
}

variable "hardened" {
  description = "true = secure baseline. false = deliberately weak baseline (Prowler 'before')."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
