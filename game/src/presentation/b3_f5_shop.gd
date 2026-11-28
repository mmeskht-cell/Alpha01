extends "res://src/presentation/b3_f3_shop.gd"
## The existing combined civilian composite / regional market profile uses its own F5 save.
const Preferences = preload("res://src/presentation/ui_preferences.gd")
const TITLE_PREFERENCES := "user://zt_rebuild/demo7/civilian_condition_v2/ui_preferences.json"
var counter_preferences: Dictionary
var title_preferences: Dictionary

func _slot() -> String:
	return "b3_f5_counter_v1"

func _counter_preferences_path() -> String:
	return save_directory_override.path_join("ui_preferences.json")

func _ready() -> void:
	var own_path := _counter_preferences_path()
	var title := Preferences.read(TITLE_PREFERENCES) if title_preferences.is_empty() else Preferences.normalize(title_preferences)
	counter_preferences = Preferences.read(own_path) if FileAccess.file_exists(own_path) else title.duplicate(true)
	counter_language = title.language
	counter_preferences.language = counter_language
	reading_scale = roundi(float(counter_preferences.font_size)*100.0/16.0)
	reduce_motion = not counter_preferences.motion
	AudioServer.set_bus_mute(0,not counter_preferences.sound)
	sound.configure_preferences(counter_preferences)
	super._ready()

func _store_counter_preferences() -> void:
	counter_preferences.font_size = roundi(16.0*reading_scale/100.0)
	counter_preferences.motion = not reduce_motion
	counter_preferences.sound = not AudioServer.is_bus_mute(0)
	Preferences.write(_counter_preferences_path(),counter_preferences)
