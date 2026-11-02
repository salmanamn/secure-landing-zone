package main

import rego.v1

key_vaults contains rc if {
	some rc in input.resource_changes
	rc.type == "azurerm_key_vault"
	rc.change.after != null
}

deny contains msg if {
	some rc in key_vaults
	rc.change.after.rbac_authorization_enabled != true
	msg := sprintf("%s: Azure RBAC permission model must be enabled", [rc.address])
}

deny contains msg if {
	some rc in key_vaults
	rc.change.after.purge_protection_enabled != true
	msg := sprintf("%s: purge protection must be enabled", [rc.address])
}

deny contains msg if {
	some rc in key_vaults
	rc.change.after.public_network_access_enabled != false
	msg := sprintf("%s: public network access must be disabled", [rc.address])
}

deny contains msg if {
	some rc in key_vaults
	rc.change.after.network_acls[0].default_action != "Deny"
	msg := sprintf("%s: firewall default action must be Deny", [rc.address])
}