extends "res://src/presentation/b3_civilian_supply_shop.gd"
## Same physical counter and command transport as F5, with a new source and slot.
const Campaign = preload("res://src/content/b3_integrated_campaign_seed.gd")
const Slots = preload("res://src/content/b3_campaign_slots.gd")
var campaign_save_root := Slots.ROOT

func _slot() -> String:
	return Slots.KEY

func _week_source(seed_value: int) -> Dictionary:
	return Campaign.content(seed_value)

func _week_source_for_selection(seed_value: int,selection: Dictionary) -> Dictionary:
	# New Game remains v1 until the comparative planner trial is accepted.
	# Load uses the existing save's actual source, never today's default.
	var version: int = Campaign.DEFAULT_VERSION if selection.get("new",false) else int(selection.get("campaign_version",1))
	return Campaign.content(seed_value,version)

func _counter_preferences_path() -> String:
	return Slots.preferences_path(campaign_save_root)

func _ready() -> void:
	if save_directory_override.is_empty():
		save_directory_override = Slots.directory(campaign_save_root,0)
	if title_preferences.is_empty() and FileAccess.file_exists(_counter_preferences_path()):
		title_preferences = Preferences.read(_counter_preferences_path())
	super._ready()

func _title_destination() -> Node:
	var scene := load("res://scenes/app/main_menu.tscn") as PackedScene
	var title := scene.instantiate()
	title.set("save_directory_override",campaign_save_root)
	return title

func _text(key: String) -> String:
	if counter_language=="en":
		match key:
			"b2.value.serviceable": return "Functional in this check"
			"b2.value.inoperable": return "Fault in this check"
	return super._text(key)
