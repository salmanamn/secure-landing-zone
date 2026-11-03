# Input: `terraform show -json tfplan`. Every deny = one violation.
package main

import rego.v1

# Every storage account that will exist after apply (create, update or unchanged).
storage_accounts contains rc if {
	some rc in input.resource_changes
	rc.type == "azurerm_storage_account"
	rc.change.after != null
}

deny contains msg if {
	some rc in storage_accounts
	rc.change.after.https_traffic_only_enabled != true
	msg := sprintf("%s: HTTPS-only traffic must be enabled", [rc.address])
}

deny contains msg if {
	some rc in storage_accounts
	rc.change.after.min_tls_version != "TLS1_2"
	msg := sprintf("%s: min_tls_version must be TLS1_2", [rc.address])
}

deny contains msg if {
	some rc in storage_accounts
	rc.change.after.allow_nested_items_to_be_public != false
	msg := sprintf("%s: anonymous blob access must be disabled", [rc.address])
}

deny contains msg if {
	some rc in storage_accounts
	rc.change.after.public_network_access_enabled != false
	msg := sprintf("%s: public network access must be disabled", [rc.address])
}

deny contains msg if {
	some rc in storage_accounts
	rc.change.after.shared_access_key_enabled != false
	msg := sprintf("%s: Shared Key auth must be disabled (Entra ID only)", [rc.address])
}

deny contains msg if {
	some rc in storage_accounts
	rc.change.after.infrastructure_encryption_enabled != true
	msg := sprintf("%s: infrastructure encryption must be enabled", [rc.address])
}

deny contains msg if {
	some rc in storage_accounts
	not blob_soft_delete_ok(rc.change.after)
	msg := sprintf("%s: blob soft delete must be >= 7 days", [rc.address])
}

blob_soft_delete_ok(after) if {
	after.blob_properties[0].delete_retention_policy[0].days >= 7
}
