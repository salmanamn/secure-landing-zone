# Run: conftest verify --policy policy/
package main

import rego.v1

good_sa := {
	"https_traffic_only_enabled": true,
	"min_tls_version": "TLS1_2",
	"allow_nested_items_to_be_public": false,
	"public_network_access_enabled": false,
	"shared_access_key_enabled": false,
	"infrastructure_encryption_enabled": true,
	"blob_properties": [{"delete_retention_policy": [{"days": 7}]}],
	"customer_managed_key": [{"user_assigned_identity_id": "x"}],
}

good_kv := {
	"rbac_authorization_enabled": true,
	"purge_protection_enabled": true,
	"public_network_access_enabled": false,
	"network_acls": [{"default_action": "Deny"}],
}

# Builds a minimal plan JSON with one resource.
plan(type, after) := {"resource_changes": [{
	"address": sprintf("module.x.%s.this", [type]),
	"type": type,
	"change": {"actions": ["create"], "after": after},
}]}

test_hardened_storage_passes if {
	count(deny) == 0 with input as plan("azurerm_storage_account", good_sa)
}

test_shared_key_fails if {
	bad := json.patch(good_sa, [{"op": "replace", "path": "/shared_access_key_enabled", "value": true}])
	count(deny) == 1 with input as plan("azurerm_storage_account", bad)
}

test_public_storage_fails_twice if {
	bad := json.patch(good_sa, [
		{"op": "replace", "path": "/public_network_access_enabled", "value": true},
		{"op": "replace", "path": "/allow_nested_items_to_be_public", "value": true},
	])
	count(deny) == 2 with input as plan("azurerm_storage_account", bad)
}

test_missing_soft_delete_fails if {
	bad := json.patch(good_sa, [{"op": "replace", "path": "/blob_properties", "value": []}])
	count(deny) == 1 with input as plan("azurerm_storage_account", bad)
}

test_hardened_kv_passes if {
	count(deny) == 0 with input as plan("azurerm_key_vault", good_kv)
}

test_weak_kv_fails_all_four if {
	bad := {
		"rbac_authorization_enabled": false,
		"purge_protection_enabled": false,
		"public_network_access_enabled": true,
		"network_acls": [{"default_action": "Allow"}],
	}
	count(deny) == 4 with input as plan("azurerm_key_vault", bad)
}

test_deletes_ignored if {
	p := {"resource_changes": [{
		"address": "x",
		"type": "azurerm_key_vault",
		"change": {"actions": ["delete"], "after": null},
	}]}
	count(deny) == 0 with input as p
}

test_missing_cmk_fails if {
	bad := json.patch(good_sa, [{"op": "remove", "path": "/customer_managed_key"}])
	count(deny) == 1 with input as plan("azurerm_storage_account", bad)
}
