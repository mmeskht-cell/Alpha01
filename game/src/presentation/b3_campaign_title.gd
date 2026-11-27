extends Control
## The default title owns no gameplay or checkpoint. The selected shop does.
const Slots = preload("res://src/content/b3_campaign_slots.gd")
const Preferences = preload("res://src/presentation/ui_preferences.gd")
const ThemeSource = preload("res://src/presentation/ui_theme.gd")
const Street = preload("res://src/presentation/menu_street.gd")
const Feedback = preload("res://src/presentation/commit_feedback.gd")
const Locale = preload("res://src/presentation/localization_service.gd")
const Shop = preload("res://scenes/app/b3_campaign_shop.tscn")
var save_directory_override := ""
var _prefs: Dictionary
var _locale := Locale.new()
var _sound: Feedback
var _street: Control
var _column: VBoxContainer
var _title: Label
var _actions: VBoxContainer
var _status: Label
var _slots: Array = []
var _page := "main"
var _leaving := false
var _localized := false

func _ready() -> void:
	if not ThemeSource.apply_to(self):
		return
	ThemeSource.apply_native(theme)
	_prefs = Preferences.read(Slots.preferences_path(_save_root()))
	if not FileAccess.file_exists(Slots.preferences_path(_save_root())):
		_prefs = Preferences.read("user://zt_rebuild/demo7/civilian_condition_v2/ui_preferences.json")
	_localized = _locale.initialize()
	if _localized: _locale.select_language(_prefs.language)
	AudioServer.set_bus_mute(0,not _prefs.sound)
	_sound = Feedback.new()
	_sound.configure_preferences(_prefs)
	add_child(_sound)
	_street = Street.new()
	_street.name = "street_background"
	add_child(_street)
	_street.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_street.animated = _prefs.motion
	_column = VBoxContainer.new()
	_column.name = "title_column"
	_column.add_theme_constant_override("separation",14)
	add_child(_column)
	_title = Label.new()
	_title.text = "EXIT NOT\nINCLUDED"
	_title.add_theme_color_override("font_color",Color("#e3d9c3"))
	_title.add_theme_color_override("font_shadow_color",Color("#171a1d"))
	_title.add_theme_constant_override("shadow_offset_x",2)
	_title.add_theme_constant_override("shadow_offset_y",3)
	_column.add_child(_title)
	var rule := ColorRect.new()
	rule.color = Color("#967754")
	rule.custom_minimum_size.y = 2
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(rule)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation",4)
	_column.add_child(_actions)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color",Color("#e3d9c3"))
	_column.add_child(_status)
	resized.connect(_layout_title)
	_layout_title()
	_read_slots()
	_build("main")
	print("ZT_MAIN_MENU_READY")
	print("ZT_B3_CAMPAIGN_TITLE_READY")

func _save_root() -> String:
	return Slots.ROOT if save_directory_override.is_empty() else save_directory_override

func _exit_tree() -> void:
	if _localized: _locale.shutdown()

func _layout_title() -> void:
	var left := maxf(24.0,size.x*0.075)
	_column.position = Vector2(left,maxf(16.0,size.y*0.075))
	_column.size = Vector2(minf(maxf(360.0,size.x*0.385),size.x-left-24.0),1)
	_title.add_theme_font_size_override("font_size",40 if size.y<670 else 52)

func _copy(ko: String,en: String) -> String:
	return en if _prefs.language=="en" else ko

func _label(key: String) -> String:
	return _locale.text("menu."+key) if _localized else key

func _button(id: String,label: String,action: Callable,disabled: bool=false) -> Button:
	var button := Button.new()
	button.name = id
	button.text = label
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size",int(_prefs.font_size)+6)
	button.disabled = disabled
	button.pressed.connect(action)
	_actions.add_child(button)
	return button

func _read_slots() -> void:
	_slots.clear()
	for i: int in range(Slots.COUNT):
		_slots.append(Slots.inspect(_save_root(),i))

func _slot_with(status: String) -> int:
	var result := -1
	for i: int in range(_slots.size()):
		if _slots[i].status==status and (result<0 or int(_slots[i].stamp)>int(_slots[result].stamp)):
			result = i
	return result

func _build(page: String) -> void:
	_page = page
	for child: Node in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	_status.text = ""
	_status.add_theme_font_size_override("font_size",int(_prefs.font_size))
	var first: Button
	match page:
		"load":
			for i: int in range(Slots.COUNT):
				var status: String = _slots[i].status
				var caption := _copy("손상된 저장","Damaged save") if status=="damaged" else _label("occupied" if status=="valid" else "empty")
				var row := _button("menu_slot_"+str(i+1),"%s %d · %s"%[_label("slot"),i+1,caption],_launch.bind(i,false),status!="valid")
				if first==null and not row.disabled: first = row
			var back := _button("menu_slot_back",_label("back"),_build.bind("main"))
			if first==null: first = back
		"settings":
			first = _button("menu_language",_copy("언어 · 한국어","Language · English"),func()->void: _change_preference("language","ko" if _prefs.language=="en" else "en"))
			_button("menu_reading_scale",_copy("글자 크기 · ","Reading size · ")+str(roundi(int(_prefs.font_size)*6.25))+"%",func()->void:
				_change_preference("font_size",16 if _prefs.font_size==24 else int(_prefs.font_size)+4))
			_button("menu_sound",_copy("소리 · ","Sound · ")+(_copy("켜짐","On") if _prefs.sound else _copy("꺼짐","Off")),func()->void: _change_preference("sound",not _prefs.sound))
			_button("menu_motion",_copy("화면 움직임 · ","Motion · ")+(_copy("켜짐","On") if _prefs.motion else _copy("줄임","Reduced")),func()->void: _change_preference("motion",not _prefs.motion))
			_button("menu_settings_back",_label("back"),_build.bind("main"))
		_:
			first = _button("menu_new",_label("new"),func()->void: _choose_slot("empty"))
			_button("menu_continue",_label("continue"),func()->void: _choose_slot("valid"),_slot_with("valid")<0)
			# Keep damaged slots visible in Load so the player can identify them.
			_button("menu_load",_label("load"),_build.bind("load"),_slots.all(func(slot: Dictionary)->bool: return slot.status=="empty"))
			_button("menu_settings",_label("settings"),_build.bind("settings"))
			_button("menu_quit",_label("quit"),_quit)
	first.grab_focus()

func _change_preference(key: String,value: Variant) -> void:
	var updated := _prefs.duplicate(true)
	updated[key] = value
	if not Preferences.write(Slots.preferences_path(_save_root()),updated):
		_status.text = _copy("설정을 저장하지 못했습니다.","Settings could not be saved.")
		return
	_prefs = updated
	if _localized: _locale.select_language(_prefs.language)
	AudioServer.set_bus_mute(0,not _prefs.sound)
	_sound.set_sound(_prefs.sound)
	_sound.set_motion(_prefs.motion)
	_street.animated = _prefs.motion
	_build("settings")

func _choose_slot(status: String) -> void:
	_read_slots()
	var index := _slot_with(status)
	if index<0:
		_build("main")
		_status.text = _label("full" if status=="empty" else "no_save")
		return
	_launch(index,status=="empty")

func _launch(index: int,new_game: bool) -> void:
	if _leaving: return
	var expected := "empty" if new_game else "valid"
	if Slots.inspect(_save_root(),index).status!=expected:
		_read_slots()
		_build(_page)
		_status.text = _label("blocked")
		return
	_leaving = true
	_sound.remember_score_position()
	_sound.shutdown_audio()
	await get_tree().create_timer(0.25).timeout
	if not is_inside_tree(): return
	var shop := Shop.instantiate()
	shop.set("save_directory_override",Slots.directory(_save_root(),index))
	shop.set("campaign_save_root",_save_root())
	shop.set("title_preferences",_prefs.duplicate(true))
	shop.set("launch_intent","new" if new_game else "load")
	get_tree().change_scene_to_node(shop)

func _quit() -> void:
	if _leaving: return
	_leaving = true
	_sound.shutdown_audio()
	await get_tree().create_timer(0.25).timeout
	if is_inside_tree(): get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if not _leaving and _page!="main" and event.is_action_pressed("ui_cancel"):
		_build("main")
		get_viewport().set_input_as_handled()
