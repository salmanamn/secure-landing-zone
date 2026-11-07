terraform {
  required_version = ">= 1.17.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }

  # Settings come from backend.hcl (names only, committed). Same state account as envs/azure, separate key.
  backend "azurerm" {}
}
