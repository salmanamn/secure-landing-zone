variable "subscription_id" {
  type        = string
  description = "Lab subscription ID."
}

variable "location" {
  type    = string
  default = "uaenorth"
}

variable "oidc_subject_prefix" {
  type        = string
  description = "GitHub OIDC sub claim without the context suffix (from oidc-probe), e.g. repo:owner@123/repo@456."

  validation {
    condition     = can(regex("^repo:[^:]+$", var.oidc_subject_prefix))
    error_message = "Must start with 'repo:' and contain no ':' context suffix."
  }
}

variable "github_environment" {
  type        = string
  default     = "azure"
  description = "GitHub environment (with required reviewers) that the apply identity trusts."
}

variable "triage_oidc_subject_prefix" {
  type        = string
  description = "OIDC sub prefix of salmanamn/ticket-triage-agent (Project 3), read from a real token, e.g. repo:owner@123/repo@789."

  validation {
    condition     = can(regex("^repo:[^:]+$", var.triage_oidc_subject_prefix))
    error_message = "Must start with 'repo:' and contain no ':' context suffix."
  }
}
