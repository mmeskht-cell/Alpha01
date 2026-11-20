extends Control
## Development-only empty host. No campaign, art or automatic save creation.
const Runtime = preload("res://src/application/foundation_runtime.gd")
var _runtime: RefCounted

func _ready() -> void:
	_runtime = Runtime.new()
	var empty_state := {"revision": 0, "game_minutes": 0, "wallets": {"player": {"VKC": 0, "USD": 0}}, "inventories": {"player_grid": {"owner_id": "player", "width": 4, "height": 3}}, "items": {}, "ledger": [], "receipts": {}}
	if not _runtime.initialize(empty_state):
		push_error("ZONE_TRADER_FOUNDATION_BOOT_FAILED")
		get_tree().quit(1)
		return
	print("ZONE_TRADER_GATE_0_B_BOOT_OK")

func _exit_tree() -> void:
	if _runtime != null:
		_runtime.shutdown()
