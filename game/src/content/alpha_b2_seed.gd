extends RefCounted
## B2 isolated sandbox: exact existing actors, finite wallets/visits and objects.
## Storefront is a real player-owned grid with no implicit free stock or buyer.
const B1 = preload("res://src/content/alpha_b1_seed.gd")

static func content() -> Dictionary:
	var original: Dictionary = B1.content()
	if original.is_empty():
		return {}
	var result: Dictionary = original.duplicate(true)
	result.state.inventories["storefront_grid"] = {
		"owner_id": "player", "width": 10, "height": 6, "host_item": ""
	}
	result.alpha_profile.content_version = "b2-preview-1"
	return result
