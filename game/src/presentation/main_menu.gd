extends Control
## Startup shell. The actual integrated candidate stays the sole game authority.
## Menu and settings are presentation only; no command, clock or save mutation.
const GameScene=preload("res://scenes/app/integrated_b_candidate.tscn")
const AlphaScene=preload("res://scenes/app/alpha_playtest_candidate.tscn")
const B1ScenePath="res://scenes/app/alpha_b1.tscn"
const CampaignScene=preload("res://scenes/app/alpha42_mechanics_host.tscn")
const HoldScene=preload("res://scenes/app/alpha_hold_market_host.tscn")
const Street=preload("res://src/presentation/menu_street.gd")
const ThemeSource=preload("res://src/presentation/ui_theme.gd")
const Runtime=preload("res://src/application/demo7_runtime.gd")
const CampaignRuntime=preload("res://src/application/campaign42_alpha_runtime.gd")
var game:Control
var menu:Control
var save_directory_override:String=""
@export var alpha_playtest:bool=false
@export var campaign42_alpha:bool=false
@export var hold_market_eval:bool=false
var _street:Control
var _title_column:VBoxContainer
var _title_label:Label
var _buttons:VBoxContainer
var _status:Label
var _labels:Dictionary={}
var _continue:Button
var _load:Button
var _settings_from_title:bool=false
var _loading:bool=false

func _ready()->void:
	if not ThemeSource.apply_to(self):
		return
	ThemeSource.apply_native(theme)
	game=(CampaignScene.instantiate() if campaign42_alpha else (HoldScene.instantiate() if hold_market_eval else (AlphaScene.instantiate() if alpha_playtest else GameScene.instantiate()))) as Control
	game.name="integrated_game"
	game.separate_settings=true
	game.save_directory_override=save_directory_override
	game.hide()
	add_child(game)
	if game.runtime==null or not is_instance_valid(game._feedback_audio):
		game.show()
		return
	game.settings_closed.connect(_settings_closed)
	game.main_menu_requested.connect(_show_menu)
	menu=Control.new()
	menu.name="title_screen"
	add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_street=Street.new()
	_street.name="street_background"
	menu.add_child(_street)
	_street.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column:=VBoxContainer.new()
	_title_column=column
	column.name="title_column"
	menu.add_child(column)
	column.anchor_left=0.075
	column.anchor_right=0.46
	column.anchor_top=0.12
	column.anchor_bottom=0.91
	column.add_theme_constant_override("separation",13)
	var title:=Label.new()
	_title_label=title
	title.text="EXIT NOT\nINCLUDED"
	title.add_theme_font_size_override("font_size",52)
	title.add_theme_color_override("font_color",Color("#E3D9C3"))
	title.add_theme_color_override("font_shadow_color",Color("#171A1D"))
	title.add_theme_constant_override("shadow_offset_x",2)
	title.add_theme_constant_override("shadow_offset_y",3)
	column.add_child(title)
	var rule:=ColorRect.new()
	rule.custom_minimum_size=Vector2(0,2)
	rule.color=Color("#967754")
	rule.mouse_filter=Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	_buttons=VBoxContainer.new()
	_buttons.add_theme_constant_override("separation",4)
	column.add_child(_buttons)
	_status=Label.new()
	_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible=2
	_status.add_theme_color_override("font_color",Color("#C6B293"))
	column.add_child(_status)
	var footer:=Label.new()
	footer.text=tr_key("menu.version")
	footer.add_theme_color_override("font_color",Color("#9A9C94"))
	footer.add_theme_font_size_override("font_size",14)
	_labels[footer]="menu.version"
	column.add_child(footer)
	resized.connect(_layout_title)
	_layout_title()
	_show_menu()
	print("ZT_MAIN_MENU_READY")

# Reserve a usable menu column rather than shrinking its input targets.
func _layout_title()->void:
	if not is_instance_valid(_title_column):
		return
	var compact:bool=size.y<680.0
	var left:float=maxf(24.0,size.x*0.075)
	var width:float=minf(maxf(360.0,size.x*0.385),size.x-left-24.0)
	_title_column.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_title_column.position=Vector2(left,maxf(16.0,size.y*(0.04 if compact else 0.08)))
	_title_column.size=Vector2(width,1.0)
	_title_column.add_theme_constant_override("separation",8 if compact else 13)
	_title_label.add_theme_font_size_override("font_size",40 if compact else 52)

func tr_key(key:String)->String:
	return game.tr_key(key)

func _line_style(fill:Color,edge:Color)->StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=fill
	style.border_color=edge
	style.border_width_left=3
	style.content_margin_left=15
	style.content_margin_right=12
	style.content_margin_top=7
	style.content_margin_bottom=7
	return style

func _button(id:String,label:String,action:Callable)->Button:
	var node:=Button.new()
	node.name=id
	node.text=label
	node.alignment=HORIZONTAL_ALIGNMENT_LEFT
	node.custom_minimum_size.y=48
	node.add_theme_font_size_override("font_size",maxi(24,int(game._prefs.font_size)))
	node.clip_text=true
	node.tooltip_text=label
	node.add_theme_stylebox_override("normal",_line_style(Color(0.08,0.10,0.11,0.22),Color.TRANSPARENT))
	node.add_theme_stylebox_override("hover",_line_style(Color(0.45,0.32,0.20,0.26),Color("#C4A474")))
	node.add_theme_stylebox_override("pressed",_line_style(Color(0.32,0.23,0.15,0.39),Color("#D18A4F")))
	node.add_theme_stylebox_override("focus",_line_style(Color(0.32,0.23,0.15,0.16),Color("#B99B70")))
	node.add_theme_stylebox_override("disabled",_line_style(Color.TRANSPARENT,Color.TRANSPARENT))
	node.pressed.connect(action)
	_buttons.add_child(node)
	return node

func _clear_buttons()->void:
	for node:Node in _buttons.get_children():
		_buttons.remove_child(node)
		node.queue_free()
	_continue=null
	_load=null

func _build_buttons()->void:
	_clear_buttons()
	_loading=false
	_button("menu_new",tr_key("menu.new"),_new_game)
	_button("menu_b1","신규 영업 프로필 · B1",func()->void: get_tree().change_scene_to_file(B1ScenePath))
	_continue=_button("menu_continue",tr_key("menu.continue"),_continue_game)
	_load=_button("menu_load",tr_key("menu.load"),_show_slots)
	if alpha_playtest:
		_button("menu_mode_switch","7일 알파로 / 7-day" if campaign42_alpha else "42일 기술 알파 / 42-day mechanics",func()->void:
			get_tree().change_scene_to_file("res://scenes/app/alpha_playtest_menu.tscn" if campaign42_alpha else "res://scenes/app/alpha42_mechanics_menu.tscn"))
	if alpha_playtest and not campaign42_alpha:
		_button("menu_hold_mode","기존 알파로 / Original alpha" if hold_market_eval else "재고 보유형 알파 / Holding market",func()->void:
			get_tree().change_scene_to_file("res://scenes/app/alpha_playtest_menu.tscn" if hold_market_eval else "res://scenes/app/alpha_hold_market_menu.tscn"))
	_button("menu_settings",tr_key("menu.settings"),_open_settings)
	_button("menu_quit",tr_key("menu.quit"),_quit_game)
	var occupied:bool=_latest_slot()>=0
	_continue.disabled=not occupied
	_load.disabled=not occupied
	for node:Control in _labels:
		node.set("text",tr_key(_labels[node]))

func _path(index:int)->String:
	return game._directory if index==0 else game._directory.path_join("slot_"+str(index+1))

# Presence is not validity. Only the existing runtime's A/B repository may
# validate a save; never treat a damaged existing generation as a new slot.
func _slot_time(index:int)->int:
	var latest:int=-1
	for generation:String in ["a","b"]:
		var save_key:String=CampaignRuntime.CAMPAIGN_SLOT if campaign42_alpha else (Runtime.ALPHA_HOLD_SLOT if hold_market_eval else (Runtime.ALPHA_SLOT if alpha_playtest else Runtime.CONDITION_SLOT_V2))
		var path:String=_path(index).path_join(save_key+".v4."+generation+".json")
		if FileAccess.file_exists(path):
			latest=maxi(latest,int(FileAccess.get_modified_time(path)))
	# Avoid replacing an occupied but unsaved in-memory session.
	if index==game._slot_index and (game.runtime.pending or int(game.runtime.snapshot().revision)>0):
		latest=maxi(latest,0)
	return latest

func _latest_slot()->int:
	var index:int=-1
	var latest:int=-1
	for i:int in range(3):
		var stamp:int=_slot_time(i)
		if stamp>=0 and (index<0 or stamp>latest):
			index=i
			latest=stamp
	return index

func _new_game()->void:
	for i:int in range(3):
		if _slot_time(i)<0:
			_enter(i,true)
			return
	_status.text=tr_key("menu.full")

func _continue_game()->void:
	var index:int=_latest_slot()
	if index<0:
		_status.text=tr_key("menu.no_save")
		return
	_enter(index,false)

func _show_slots()->void:
	_clear_buttons()
	_loading=true
	for i:int in range(3):
		var exists:bool=_slot_time(i)>=0
		var row:=_button("menu_slot_"+str(i+1),tr_key("menu.slot")+" "+str(i+1)+" · "+tr_key("menu.occupied" if exists else "menu.empty"),func()->void: _enter(i,false))
		row.disabled=not exists
	_button("menu_slot_back",tr_key("menu.back"),_back_from_slots)

func _back_from_slots()->void:
	_status.text=""
	_build_buttons()

func _enter(index:int,empty_only:bool)->void:
	if game.runtime.pending or (empty_only and _slot_time(index)>=0) or (not empty_only and _slot_time(index)<0):
		_status.text=tr_key("menu.blocked")
		return
	game._slot.select(index)
	game._switch_slot()
	if game._slot_index!=index or (empty_only and (game.runtime.blocked or int(game.runtime.snapshot().revision)!=0)):
		_status.text=tr_key("menu.blocked")
		return
	menu.hide()
	game.show()

func _show_menu()->void:
	if game.runtime.pending:
		return
	game.hide()
	_settings_from_title=false
	_status.text=""
	_street.animated=bool(game._prefs.motion)
	_build_buttons()
	_layout_title()
	menu.show()
	var first:=menu.find_child("menu_new",true,false) as Button
	if first!=null:
		first.grab_focus()

func _open_settings()->void:
	_settings_from_title=true
	menu.hide()
	game.show()
	game.open_settings()

func _settings_closed()->void:
	if _settings_from_title:
		_show_menu()

func _quit_game()->void:
	if not game.runtime.pending:
		game._feedback_audio.shutdown_audio()
		get_tree().quit()

func _unhandled_input(event:InputEvent)->void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode!=KEY_ESCAPE:
		return
	if game._pack_panel.is_visible_in_tree():
		game.close_settings()
	elif menu.visible and _loading:
		_back_from_slots()
	elif game.visible and not game.runtime.pending:
		_show_menu()
	else:
		return
	get_viewport().set_input_as_handled()
