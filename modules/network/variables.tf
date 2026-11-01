variable "name" {
  description = "Name stem, e.g. slz-local"
  type        = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "address_space" {
  type    = string
  default = "10.20.0.0/16"
}

variable "pe_subnet_prefix" {
  type    = string
  default = "10.20.1.0/24"
}

variable "tags" {
  type    = map(string)
  default = {}
}
