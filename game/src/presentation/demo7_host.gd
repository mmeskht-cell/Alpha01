extends Control
## Real playable calendar host; legacy day-one scene remains independently runnable.
const Feedback=preload("res://src/presentation/commit_feedback.gd")
const Preferences=preload("res://src/presentation/ui_preferences.gd")
const Runtime=preload("res://src/application/demo7_runtime.gd")
const CampaignRuntime=preload("res://src/application/campaign42_alpha_runtime.gd")
const ThemeSource=preload("res://src/presentation/ui_theme.gd")
const Appraisal=preload("res://src/presentation/generic_appraisal_panel.gd")
const History=preload("res://src/presentation/generic_trade_history.gd")
const HistoryBrowser=preload("res://src/presentation/native_history_browser.gd")
const Clock=preload("res://src/domain/business_clock.gd")
var runtime:RefCounted
var _body:VBoxContainer
var _app:ScrollContainer
var _history:Control
var native_history_index:bool=false
var _head:Label
var _feedback:Label
var _feedback_key:String=""
var _feedback_suffix:String=""
var _history_button:Button
var _stock_button:Button
var _language:String="ko"
var _history_open:bool=false
var _view:Dictionary={}
var _intro:bool=false
var save_directory_override:String=""
@export var campaign42_alpha:bool=false
@export var hold_market_eval:bool=false
@export var civilian_candidate:bool=false
@export var condition_pricing:bool=false
@export var condition_version:int=1
const CivilianPrice=preload("res://src/domain/civilian_condition_price.gd")
var _directory:String=""
var _prefs:Dictionary={}
var _feedback_audio:Control
var _counter:ScrollContainer
var _stock:ScrollContainer
var _stock_open:bool=false
var _compact_appraisal:bool=false
var _perspective_scroll:Dictionary={}
var _perspective_visit:String=""
var _slot:OptionButton
var _slot_open:Button
var _slot_index:int=0
var _workspace_button:Button
var _pack_panel:PanelContainer
var _pack_name:LineEdit
var _pack_status:Label
var _settings_labels:Dictionary={}
var _settings_toggle:Button
var _locale_epoch:int=0
var _locale_boot_error:bool=false
var separate_settings:bool=false
# Standalone native evaluation uses the same dedicated settings overlay,
# without requiring a main-menu owner or removing its independent save slots.
var compact_settings_overlay:bool=false
var _gameplay_margin:MarginContainer
var _settings_controls:Array[Control]=[]
var _settings_pages:Dictionary={}
var _settings_tabs:Dictionary={}
var _settings_page:String="general"
signal settings_closed
signal main_menu_requested

func word(ko:String,en:String)->String:
	return ko if _language=="ko" else en

func tr_key(key:String,arguments:Dictionary={})->String:
	return runtime.localization.text(key,arguments)

# Official base language remains the fallback for any unmigrated text.
# A validated overlay can translate keyed text without altering the campaign.
func _apply_locale_preference()->void:
	_language=_prefs.language
	runtime.localization.clear_pack()
	runtime.localization.select_language(_language)
	_locale_boot_error=false
	var filename:String=_prefs.get("language_pack","")
	if not filename.is_empty():
		_locale_boot_error=not runtime.localization.install_pack(filename).get("ok",false)
	_locale_epoch+=1

func _ready()->void:
	if not ThemeSource.apply_to(self):
		return
	runtime=CampaignRuntime.new() if campaign42_alpha else Runtime.new()
	var directory:String=(("user://zt_rebuild/demo7/alpha_playtest" if condition_version==3 else ("user://zt_rebuild/demo7/civilian_condition_v2" if condition_version==2 else "user://zt_rebuild/demo7/civilian_condition")) if condition_pricing and civilian_candidate else ("user://zt_rebuild/demo7/civilian_candidate" if civilian_candidate else "user://zt_rebuild/demo7"))
	if campaign42_alpha:
		directory=CampaignRuntime.PREFIX
	elif hold_market_eval:
		directory="user://zt_rebuild/demo7/hold_market_alpha"
	if not save_directory_override.is_empty():
		directory=save_directory_override
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--demo-dir="):
			directory=arg.trim_prefix("--demo-dir=")
	if not runtime.open(directory,civilian_candidate,condition_pricing,condition_version) if campaign42_alpha else runtime.open(directory,civilian_candidate,condition_pricing,condition_version,hold_market_eval):
		push_error("ZT_DEMO_OPEN_FAILED "+runtime.error)
		return
	_directory=directory
	_prefs=Preferences.read(_directory.path_join("ui_preferences.json"))
	_apply_locale_preference()
	theme.default_font_size=int(_prefs.font_size)
	_intro=runtime.snapshot().revision==0 and not runtime.blocked
	var backdrop:=TextureRect.new()
	backdrop.name="demo_backdrop"
	backdrop.texture=preload("res://assets/art/scenes/counter_pilot_bg.svg")
	backdrop.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.modulate=Color(0.35,0.35,0.35,0.32)
	backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin:=MarginContainer.new()
	_gameplay_margin=margin
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge:String in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+edge,16)
	var root:=VBoxContainer.new()
	margin.add_child(root)
	_head=Label.new()
	_head.add_theme_font_size_override("font_size",22)
	root.add_child(_head)
	var tools:=HFlowContainer.new()
	root.add_child(tools)
	var lang:=Button.new()
	lang.name="language_toggle"
	lang.text="한국어 / EN"
	tools.add_child(lang)
	_settings_controls.append(lang)
	lang.pressed.connect(func()->void:
		_prefs.language="en" if _language=="ko" else "ko"
		_prefs.language_pack=""
		_apply_locale_preference()
		_store_preferences()
		refresh())
	var history:=Button.new()
	_history_button=history
	history.name="history_toggle"
	history.text="기록 / History"
	tools.add_child(history)
	history.pressed.connect(func()->void:
		_history_open=not _history_open
		_stock_open=false
		refresh())
	var stock:=Button.new()
	_stock_button=stock
	stock.name="stock_toggle"
	stock.text="창고 / Stock"
	tools.add_child(stock)
	stock.pressed.connect(func()->void:
		_stock_open=not _stock_open
		_history_open=false
		refresh())
	_workspace_button=Button.new()
	_workspace_button.name="workspace_toggle"
	_workspace_button.text="감정 / Counter"
	tools.add_child(_workspace_button)
	_workspace_button.pressed.connect(_toggle_workspace)
	var font:=Button.new()
	font.name="font_toggle"
	font.text="A / A+ / A++"
	tools.add_child(font)
	_settings_controls.append(font)
	font.pressed.connect(func()->void:
		_prefs.font_size=20 if _prefs.font_size==16 else (24 if _prefs.font_size==20 else 16)
		theme.default_font_size=int(_prefs.font_size)
		_store_preferences()
		refresh())
	var sound:=Button.new()
	sound.name="sound_toggle"
	sound.text="♪"
	sound.toggle_mode=true
	sound.button_pressed=_prefs.sound
	tools.add_child(sound)
	_settings_controls.append(sound)
	sound.toggled.connect(func(enabled:bool)->void:
		_prefs.sound=enabled
		_feedback_audio.set_sound(enabled)
		_store_preferences())
	_slot=OptionButton.new()
	_slot.name="save_slot"
	for i:int in range(1,4):
		_slot.add_item("Slot "+str(i))
	tools.add_child(_slot)
	_slot_open=Button.new()
	_slot_open.name="open_slot"
	_slot_open.text="열기 / Open"
	tools.add_child(_slot_open)
	_slot_open.pressed.connect(_switch_slot)
	_build_language_panel(root,tools)
	if separate_settings:
		_slot.hide()
		_slot_open.hide()
		var menu:=Button.new()
		menu.name="return_main_menu"
		menu.text=tr_key("menu.title")
		_settings_labels[menu]="menu.title"
		tools.add_child(menu)
		menu.pressed.connect(func()->void:
			if not runtime.pending:
				main_menu_requested.emit())
	_feedback=Label.new()
	_feedback.name="game_feedback"
	_feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_feedback)
	var split:=HBoxContainer.new()
	split.size_flags_vertical=Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var scroll:=ScrollContainer.new()
	_counter=scroll
	scroll.custom_minimum_size.x=320
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	_body=VBoxContainer.new()
	_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_app=Appraisal.new()
	_app.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	split.add_child(_app)
	_app.action_requested.connect(func(kind:String,p:Dictionary,revision:int)->void: _act(kind,p,revision))
	_history=HistoryBrowser.new() if native_history_index else History.new()
	_history.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	split.add_child(_history)
	_stock=ScrollContainer.new()
	_stock.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_stock.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	split.add_child(_stock)
	_feedback_audio=Feedback.new()
	_feedback_audio.configure_preferences(_prefs)
	add_child(_feedback_audio)
	_feedback_audio.prime(int(runtime.snapshot().revision))
	resized.connect(_refresh_visibility)
	refresh()
	if _locale_boot_error:
		_set_feedback("settings.pack.invalid")
	print("ZT_DEMO_HOST_READY")

func _build_language_panel(root:VBoxContainer,tools:Control)->void:
	var toggle:=Button.new()
	toggle.name="language_pack_toggle"
	_settings_toggle=toggle
	toggle.text=tr_key("settings.panel.title")
	toggle.tooltip_text=tr_key("settings.pack.title")
	tools.add_child(toggle)
	_pack_panel=PanelContainer.new()
	_pack_panel.name="language_pack_panel"
	var fields:=VBoxContainer.new()
	var audio_fields:VBoxContainer=fields
	var shell:VBoxContainer=null
	if separate_settings or compact_settings_overlay:
		add_child(_pack_panel)
		_pack_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_pack_panel.z_index=90
		shell=VBoxContainer.new()
		shell.name="settings_fixed_shell"
		_pack_panel.add_child(shell)
		var heading:=Label.new()
		heading.text=tr_key("settings.panel.title")
		heading.add_theme_font_size_override("font_size",28)
		_settings_labels[heading]="settings.panel.title"
		shell.add_child(heading)
		var tabs:=HBoxContainer.new()
		tabs.name="settings_categories"
		shell.add_child(tabs)
		for id:String in ["general","audio","pack"]:
			var key:String={"general":"settings.category.general","audio":"settings.audio.title","pack":"settings.pack.title"}[id]
			var tab:=Button.new()
			tab.name="settings_category_"+id
			tab.text=tr_key(key)
			tab.custom_minimum_size.y=48
			tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			tab.clip_text=true
			_settings_labels[tab]=key
			_settings_tabs[id]=tab
			tabs.add_child(tab)
			tab.pressed.connect(func()->void: _show_settings_page(id))
		var content:=VBoxContainer.new()
		content.name="settings_page_content"
		content.size_flags_vertical=Control.SIZE_EXPAND_FILL
		shell.add_child(content)
		var general:=VBoxContainer.new()
		general.name="settings_page_general"
		content.add_child(general)
		_settings_pages["general"]=general
		audio_fields=VBoxContainer.new()
		audio_fields.name="settings_page_audio"
		content.add_child(audio_fields)
		_settings_pages["audio"]=audio_fields
		fields.name="settings_page_pack"
		content.add_child(fields)
		_settings_pages["pack"]=fields
		for control:Control in _settings_controls:
			control.reparent(general)
			control.custom_minimum_size.y=48
			var key:String={"language_toggle":"settings.general.language","font_toggle":"settings.general.font","sound_toggle":"settings.general.sound"}.get(str(control.name),"")
			if not key.is_empty():
				_settings_labels[control]=key
				control.set("text",tr_key(key))
		if compact_settings_overlay and not separate_settings:
			_slot.reparent(general)
			_slot_open.reparent(general)
			_slot.custom_minimum_size.y=48
			_slot_open.custom_minimum_size.y=48
	else:
		root.add_child(_pack_panel)
		_pack_panel.add_child(fields)
	var note:=Label.new()
	note.text=tr_key("settings.pack.instructions")
	_settings_labels[note]="settings.pack.instructions"
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(note)
	_pack_name=LineEdit.new()
	_pack_name.name="language_pack_filename"
	_pack_name.placeholder_text="language.json"
	_pack_name.max_length=69
	_pack_name.text=str(_prefs.get("language_pack",""))
	fields.add_child(_pack_name)
	_pack_status=Label.new()
	_pack_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(_pack_status)
	var actions:=HBoxContainer.new()
	fields.add_child(actions)
	var apply:=Button.new()
	apply.name="language_pack_apply"
	apply.text=tr_key("settings.pack.apply")
	_settings_labels[apply]="settings.pack.apply"
	actions.add_child(apply)
	apply.pressed.connect(func()->void:
		var filename:String=_pack_name.text.strip_edges()
		var result:Dictionary=runtime.localization.install_pack(filename)
		if not result.get("ok",false):
			_pack_status.text=tr_key("settings.pack.invalid")
			return
		_prefs.language_pack=filename
		_locale_epoch+=1
		_store_preferences()
		if not separate_settings and not compact_settings_overlay:
			_pack_panel.hide()
		refresh()
		_pack_status.text=tr_key("settings.pack.applied")
		_set_feedback("settings.pack.applied"))
	var clear:=Button.new()
	clear.name="language_pack_clear"
	clear.text=tr_key("settings.pack.clear")
	_settings_labels[clear]="settings.pack.clear"
	actions.add_child(clear)
	clear.pressed.connect(func()->void:
		_prefs.language_pack=""
		_apply_locale_preference()
		_pack_name.clear()
		_store_preferences()
		if not separate_settings and not compact_settings_overlay:
			_pack_panel.hide()
		refresh()
		_pack_status.text=tr_key("settings.pack.current",{"locale":str(runtime.localization.current_locale())}))
	var cancel:=Button.new()
	cancel.name="language_pack_cancel"
	var close_key:String="menu.back" if separate_settings or compact_settings_overlay else "settings.pack.cancel"
	cancel.text=tr_key(close_key)
	_settings_labels[cancel]=close_key
	actions.add_child(cancel)
	cancel.pressed.connect(close_settings)
	_build_audio_settings(audio_fields)
	if shell!=null:
		actions.remove_child(cancel)
		shell.add_child(cancel)
		cancel.custom_minimum_size.y=48
		apply.custom_minimum_size.y=48
		clear.custom_minimum_size.y=48
		_pack_name.custom_minimum_size.y=48
		_show_settings_page("general")
	toggle.pressed.connect(func()->void:
		if _pack_panel.visible:
			close_settings()
		else:
			open_settings())
	_pack_panel.hide()

func _show_settings_page(id:String)->void:
	if not _settings_pages.has(id):
		return
	_settings_page=id
	for key:String in _settings_pages:
		_settings_pages[key].visible=key==id
		_settings_tabs[key].disabled=key==id

func open_settings()->void:
	if not is_instance_valid(_pack_panel):
		return
	_refresh_settings_text()
	if separate_settings or compact_settings_overlay:
		_show_settings_page("general")
	_pack_name.text=str(_prefs.get("language_pack",""))
	_pack_status.text=tr_key("settings.pack.current",{"locale":str(runtime.localization.current_locale())})
	if separate_settings or compact_settings_overlay:
		_gameplay_margin.hide()
	_pack_panel.show()

func close_settings()->void:
	_store_preferences()
	_pack_panel.hide()
	if separate_settings or compact_settings_overlay:
		_gameplay_margin.show()
		refresh()
	settings_closed.emit()

func _build_audio_settings(fields:VBoxContainer)->void:
	var heading:=Label.new()
	heading.text=tr_key("settings.audio.title")
	_settings_labels[heading]="settings.audio.title"
	fields.add_child(heading)
	var grid:=GridContainer.new()
	grid.columns=1 if separate_settings or compact_settings_overlay else 2
	fields.add_child(grid)
	for channel:String in ["music","ambience","sfx","ui"]:
		var line:=HBoxContainer.new()
		line.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		grid.add_child(line)
		var title:=Label.new()
		if separate_settings or compact_settings_overlay:
			title.custom_minimum_size.x=180
		var key:String="settings.audio."+channel
		title.text=tr_key(key)
		_settings_labels[title]=key
		line.add_child(title)
		var slider:=HSlider.new()
		slider.name="audio_level_"+channel
		slider.min_value=0
		slider.max_value=100
		slider.step=1
		slider.custom_minimum_size=Vector2(90,48 if separate_settings or compact_settings_overlay else 32)
		slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		slider.value=int(_prefs.levels[channel])
		line.add_child(slider)
		var percent:=Label.new()
		percent.text=str(int(slider.value))+"%"
		line.add_child(percent)
		slider.value_changed.connect(func(value:float)->void:
			_prefs.levels[channel]=int(value)
			_feedback_audio.set_level(channel,int(value))
			percent.text=str(int(value))+"%")
		slider.drag_ended.connect(func(changed:bool)->void:
			if changed:
				_store_preferences())
		slider.gui_input.connect(func(event:InputEvent)->void:
			if event is InputEventKey and not event.pressed:
				_store_preferences())
	var motion:=CheckButton.new()
	if separate_settings or compact_settings_overlay:
		motion.custom_minimum_size.y=48
	motion.name="motion_toggle"
	motion.text=tr_key("settings.motion")
	_settings_labels[motion]="settings.motion"
	motion.button_pressed=_prefs.motion
	fields.add_child(motion)
	motion.toggled.connect(func(enabled:bool)->void:
		_prefs.motion=enabled
		_feedback_audio.set_motion(enabled)
		_store_preferences()
		_configure_app())

# Feedback remains a presentation key, not a stale rendered translation.
# The original runtime error suffix is retained verbatim for diagnosis.
func _set_feedback(key:String,suffix:String="")->void:
	_feedback_key=key
	_feedback_suffix=suffix
	_refresh_feedback()

func _refresh_feedback()->void:
	if is_instance_valid(_feedback) and not _feedback_key.is_empty():
		_feedback.text=tr_key(_feedback_key)+_feedback_suffix

func _refresh_native_navigation()->void:
	if not native_history_index:
		return
	_history_button.text=tr_key("ui.location.history")
	_stock_button.text=tr_key("ui.location.inventory")
	_slot_open.text=tr_key("ui.copy.open_fc52508")
	for i:int in range(_slot.item_count):
		_slot.set_item_text(i,tr_key("ui.format.slot_number",{"number":str(i+1)}))

func _refresh_settings_text()->void:
	if is_instance_valid(_settings_toggle):
		_settings_toggle.text=tr_key("settings.panel.title")
		_settings_toggle.tooltip_text=tr_key("settings.pack.title")
	for node:Control in _settings_labels:
		node.set("text",tr_key(_settings_labels[node]))
	if separate_settings or compact_settings_overlay:
		for control:Control in _settings_controls:
			if control.name=="language_toggle":
				control.set("text",tr_key("ui.format.settings_language",{"language":"한국어" if _language=="ko" else "English"}))
			elif control.name=="font_toggle":
				control.set("text",tr_key("ui.format.settings_font",{"percent":str(int(_prefs.font_size)*100/16)}))

func _store_preferences()->void:
	if not Preferences.write(_directory.path_join("ui_preferences.json"),_prefs):
		_set_feedback("ui.copy.preferences_could_not_be_saved_c2ce093d")
		if is_instance_valid(_pack_status) and _pack_panel.visible:
			_pack_status.text=_feedback.text

func _switch_slot()->void:
	if runtime.pending or _slot.selected==_slot_index:
		return
	var index:int=_slot.selected
	var path:String=_directory if index==0 else _directory.path_join("slot_"+str(index+1))
	# Inspect candidate before changing active runtime. Both are read-only until a player command.
	var candidate=CampaignRuntime.new() if campaign42_alpha else Runtime.new()
	if not candidate.open(path,civilian_candidate,condition_pricing,condition_version) if campaign42_alpha else candidate.open(path,civilian_candidate,condition_pricing,condition_version,hold_market_eval):
		candidate.close()
		_apply_locale_preference()
		_slot.select(_slot_index)
		_set_feedback("ui.copy.could_not_open_slot_f5e11150")
		return
	runtime.close()
	runtime=candidate
	# Closing the previous locale service unregisters shared resources; reinitialize.
	runtime.localization.shutdown()
	if not runtime.localization.initialize():
		runtime.blocked=true
		runtime.error="locale_invalid"
	_apply_locale_preference()
	_slot_index=index
	_intro=runtime.snapshot().revision==0 and not runtime.blocked
	_history_open=false
	_stock_open=false
	_compact_appraisal=false
	_feedback_audio.prime(int(runtime.snapshot().revision))
	_set_feedback("ui.copy.new_session_c88df2bc" if _intro else "ui.copy.saved_session_resumed_cf6fd88a")
	refresh()

func _open_basic_review(visit_id:String,revision:int)->void:
	if _intro or _stock_open or _history_open or get_viewport().gui_is_dragging() or not runtime.open_basic_review(visit_id,revision):
		return
	_compact_appraisal=true
	refresh()

func _toggle_workspace()->void:
	if _intro or _stock_open or _history_open or _view.get("appraisal",{}).is_empty() or get_viewport().gui_is_dragging():
		return
	_perspective_scroll["appraisal" if _compact_appraisal else "customer"]=_app.scroll_vertical
	_compact_appraisal=not _compact_appraisal
	_configure_app()
	_feedback_audio.local_page()
	_refresh_visibility()

func _input(event:InputEvent)->void:
	if not is_visible_in_tree() or (is_instance_valid(_pack_panel) and _pack_panel.visible):
		return
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode!=KEY_SPACE or not is_instance_valid(_workspace_button) or not _workspace_button.is_visible_in_tree() or get_viewport().gui_is_dragging():
		return
	var focus:Control=get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	get_viewport().set_input_as_handled()
	_toggle_workspace()

func _configure_app()->void:
	var app:Dictionary=_view.get("appraisal",{})
	var visit:String=str(app.get("visit_id",""))
	if visit!=_perspective_visit:
		_perspective_scroll.clear()
		_perspective_visit=visit
	var mode:String="appraisal" if _compact_appraisal else "customer"
	_app.configure(app,_view.revision,tr_key,_language,_view.locked or _view.complete,"production_"+mode)
	_app.set_deferred("scroll_vertical",int(_perspective_scroll.get(mode,0)))

func _refresh_visibility()->void:
	if not is_instance_valid(_counter) or _view.is_empty():
		return
	var app_active:bool=not _view.get("appraisal",{}).is_empty()
	var compact:bool=size.x<1000
	_workspace_button.visible=not _intro and app_active and not _stock_open and not _history_open
	_workspace_button.text=tr_key("ui.workspace.customer") if _compact_appraisal else tr_key("ui.workspace.item")
	_counter.visible=_intro or (not _stock_open and not _history_open and (not compact or not app_active))
	_app.visible=not _intro and not _stock_open and not _history_open and app_active
	_history.visible=not _intro and _history_open
	_stock.visible=not _intro and _stock_open

func _stock_view()->void:
	for child:Node in _stock.get_children():
		_stock.remove_child(child)
		child.queue_free()
	var body:=VBoxContainer.new()
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_stock.add_child(body)
	for grid:Dictionary in _view.stock_grids:
		var title:=Label.new()
		title.text=tr_key("ui.copy.stock_bf0ad62f") if grid.id=="player_stock" else tr_key("ui.copy.customer_custody_78fdebe1")
		body.add_child(title)
		var cells:=GridContainer.new()
		cells.name="grid_"+grid.id
		cells.columns=int(grid.width)
		body.add_child(cells)
		for y:int in range(int(grid.height)):
			for x:int in range(int(grid.width)):
				var cell:=Label.new()
				cell.custom_minimum_size=Vector2(48,48)
				cell.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
				cell.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
				cell.text="·"
				var frame:=PanelContainer.new()
				cells.add_child(frame)
				frame.add_child(cell)
				for item:Dictionary in _view.stock:
					if item.inventory==grid.id and x>=item.x and x<item.x+item.width and y>=item.y and y<item.y+item.height:
						cell.text=item.id if x==item.x and y==item.y else "■"
						cell.tooltip_text=tr_key(item.label)+" · "+(tr_key("ui.copy.owned_cff2f00c") if item.owned else tr_key("ui.copy.custody_a1f910"))
						break
	for item:Dictionary in _view.stock:
		var row:=Label.new()
		row.text=item.id+" · "+tr_key(item.label)+" · "+(tr_key("ui.copy.owned_cff2f00c") if item.owned else tr_key("ui.copy.custody_a1f910"))
		body.add_child(row)

func _line(message:String)->void:
	var label:=Label.new()
	label.text=message
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)

func _button(id:String,title:String,kind:String,p:Dictionary={},off:bool=false)->void:
	var b:=Button.new()
	b.name=id
	b.text=title
	b.disabled=off or _view.locked or _view.complete
	b.custom_minimum_size.y=48
	_body.add_child(b)
	var revision:int=_view.revision
	b.pressed.connect(func()->void: _act(kind,p,revision))

func _act(kind:String,p:Dictionary,revision:int)->void:
	if is_instance_valid(_app) and _app.visible:
		_perspective_scroll["appraisal" if _compact_appraisal else "customer"]=_app.scroll_vertical
	var result:Dictionary=runtime.submit(kind,p,revision)
	_set_feedback("ui.copy.completed_12ead41e" if result.ok else "ui.copy.unavailable_e8505c55","" if result.ok else str(result.get("error","")))
	if result.ok:
		# One audible user action even if a private world bundle adds revisions.
		var cue:Dictionary={"calendar_next_visit":"next_visit","calendar_decline_visit":"decline_visit","calendar_close":"day_one_close","calendar_morning":"day_one_next_morning","calendar_accept_contract":"accept_rad1_contract","calendar_accept_service":"day_one_accept_service","calendar_deliver_service":"day_one_deliver_service","calendar_return_unpaid":"day_one_cancel_service","inspect_subject":"inspect_radio","calendar_pay_contract":"trade","calendar_pay_overhead":"day_one_pay_overhead"}
		_feedback_audio.committed(cue.get(kind,kind),revision,revision+1,result.get("persisted",false))
		_feedback_audio.prime(int(runtime.snapshot().revision))
		if kind in ["calendar_next_visit","trade","calendar_decline_visit","calendar_close","calendar_morning"]:
			_compact_appraisal=not runtime.view().get("appraisal",{}).is_empty()
	if result.ok and not result.get("persisted",false):
		_set_feedback("ui.copy.save_failed_retry_before_continuing_21aa1c01")
	refresh()

func refresh()->void:
	if runtime==null or not is_instance_valid(_body):
		return
	_view=runtime.view()
	_view["locale_epoch"]=_locale_epoch
	_refresh_settings_text()
	_refresh_native_navigation()
	_refresh_feedback()
	# On a failed save, keep retry/recovery controls reachable from all overlays.
	if _view.locked:
		_stock_open=false
		_history_open=false
	_feedback_audio.set_phase("workshop" if _view.phase!="shop" else "shop")
	_slot_open.disabled=runtime.pending
	_head.text=tr_key("ui.format.legacy_hud",{"candidate":tr_key("ui.copy.composite_candidate_5191b827") if civilian_candidate else "","day":str(43 if campaign42_alpha and _view.complete else (8 if _view.complete else _view.day)),"time":Clock.clock_text(int(_view.minute)),"vkc":str(_view.wallet.VKC),"usd":str(_view.wallet.USD)})
	for child:Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	if _view.recovered and not _view.locked:
		_line(tr_key("ui.copy.recovered_from_the_previous_valid_save_1e032a02"))
	if _view.locked:
		_line(tr_key("ui.copy.save_load_error_f5af17cd")+_view.error)
		if runtime.pending:
			var retry:=Button.new()
			retry.text=tr_key("ui.copy.retry_save_d398bfc9")
			_body.add_child(retry)
			retry.pressed.connect(func()->void:
				runtime.retry()
				refresh())
	if _intro:
		_line(tr_key("ui.copy.1_november_2032_alexei_barin_38_reopens_his_2c15303e"))
		for pair:Array in [["intro_continue",tr_key("ui.copy.open_the_shutters_8ede7ece")],["intro_skip",tr_key("ui.copy.skip_prologue_3df4eed3")]]:
			var begin:=Button.new()
			begin.name=pair[0]
			begin.text=pair[1]
			_body.add_child(begin)
			begin.pressed.connect(func()->void:
				_intro=false
				refresh())
		_refresh_visibility()
		return
	if _view.complete:
		_line(word("42일 내부 알파 종료 · 미집필 스토리/엔딩과 무관","42-day mechanics alpha complete · story and ending remain un-authored") if campaign42_alpha else tr_key("ui.copy.first_week_complete_the_story_continues_1cec1dd2"))
		_line(tr_key("ui.format.final_cash",{"cash":tr_key("inventory.format.money_pair",{"vkc":str(_view.wallet.VKC),"usd":str(_view.wallet.USD)})}))
		if not campaign42_alpha:
			_line(tr_key("ui.copy.this_is_the_demo_boundary_not_a_campaign_en_5fa73f01"))
		for id:String in _view.get("services",{}):
			var job:Dictionary=_view.services[id]
			if job.status in ["accepted","complete"]:
				_line(tr_key("ui.copy.pending_pickup_11905ce0")+job.item_id+" · "+str(job.fee.VKC)+" VKC")
	else:
		_line(tr_key("ui.copy.kravensk_shop_in_the_sealed_city_6919897b"))
		if _view.day==1:
			_line(tr_key("ui.copy.sora_are_you_open_i_sent_someone_your_way_fbc8270b"))
			_line(tr_key("ui.copy.ian_you_ll_be_all_right_for_a_few_days_but__6be4d982"))
		if _view.day==2:
			_line(tr_key("ui.copy.sora_more_people_are_looking_for_winter_sup_86c1ac8d"))
		if _view.day==4:
			_line(tr_key("ui.copy.marcus_payment_reserves_the_supply_you_do_n_403b17a0"))
		if _view.phase=="shop":
			_line(tr_key("ui.format.remaining_visits",{"count":str(_view.visits.remaining)}))
			if _view.overhead_debt>0:
				_line(tr_key("ui.format.overdue_overhead",{"amount":tr_key("inventory.format.offer_amount",{"amount":str(_view.overhead_debt),"currency":str("VKC")})}))
				_button("pay_overhead",tr_key("ui.copy.pay_overhead_23660013"),"calendar_pay_overhead",{},_view.wallet.VKC<_view.overhead_debt)
			_button("next_customer",tr_key("ui.copy.next_customer_fd07c070"),"calendar_next_visit",{},not _view.visits.can_next)
			var active:String=_view.visits.active
			if not active.is_empty():
				var terms:Dictionary=_view.visits.terms
				var memory:Dictionary=_view.get("customer_memory",{})
				if not memory.is_empty():
					_line(tr_key("history.customer.previous_trade",{"count":str(memory.trades),"day":str(memory.last_day)}))
				var trade:Dictionary=_view.trade
				if not trade.is_empty():
					var asking:int=int(_view.get("appraisal",{}).get("price_offer",{}).get("asking",trade.amount))
					var display_quote:Dictionary=_view.get("condition_quote",{})
					var price_text:String=str(asking)+" "+trade.currency if display_quote.get("can_sell",true) else tr_key("ui.copy.no_confirmed_offer_8858b07c")
					_line(tr_key(trade.label)+"  "+trade.item_id+"  ·  "+price_text)
					if trade.visit_id=="visit_g01":
						_line(tr_key("ui.copy.g01_do_you_buy_things_here_682d8d4f"))
					if trade.visit_id=="radio_return":
						_line(tr_key("ui.copy.g02_i_bought_this_radio_here_before_it_is_n_512d34fd"))
					var art_path:String="res://assets/art/items/radio_face_probe_a.svg" if trade.item_id in ["R001","R003"] else ("res://assets/art/items/fictional_gear_pilot.svg" if trade.item_id=="GE03" else "")
					if not art_path.is_empty():
						var art:=TextureRect.new()
						art.texture=load(art_path) as Texture2D
						art.custom_minimum_size=Vector2(0,125)
						art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
						art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
						_body.add_child(art)
					if _view.get("appraisal",{}).is_empty():
						if _view.get("basic_review_available",false):
							var inspect:=Button.new()
							inspect.name="basic_review_open"
							inspect.text=tr_key("review.basic.open")
							inspect.custom_minimum_size.y=48
							inspect.disabled=_view.locked
							_body.add_child(inspect)
							var revision:int=_view.revision
							inspect.pressed.connect(func()->void: _open_basic_review(active,revision))
						var quote:Dictionary=_view.get("condition_quote",{})
						if not quote.is_empty():
							_line(tr_key("ui.condition."+str(quote.tier)))
						var payload:Dictionary=trade.duplicate()
						payload.erase("label")
						payload.erase("placement")
						payload.merge(trade.placement)
						var unavailable:bool=trade.placement.is_empty() or not quote.get("can_sell",true) or not quote.get("buyer_can_pay",_view.get("trade_can_pay",true))
						_button("settle_trade",tr_key("ui.copy.buy_d5fd742c") if trade.buyer=="player" else tr_key("ui.copy.sell_cece1123"),"trade",payload,unavailable)
						var quality:Dictionary=_view.get("basic_sale_quality",{})
						if trade.seller=="player" and not quality.is_empty():
							_button("settle_sale_quality",tr_key("review.sale.working" if quality.observed_value=="serviceable" else "review.sale.inoperable"),"trade",payload.merged({"sale_quality_evidence_id":quality.evidence_id}),unavailable)
				elif terms.get("kind","").begins_with("service_"):
					_line(tr_key("ui.format.service_summary",{"item":str(terms.item_id),"fee":tr_key("inventory.format.money_pair",{"vkc":str(terms.fee.VKC),"usd":str(terms.fee.USD)})}))
					if terms.kind=="service_offer":
						var cost:Dictionary=_view.get("service_cost_preview",{})
						_line(tr_key("ui.service.unknown_cost") if cost.is_empty() else tr_key("ui.format.service_cost",{"cost":tr_key("inventory.format.money_pair",{"vkc":str(cost.VKC),"usd":str(cost.USD)})}))
						_line(tr_key("ui.service.no_upfront_fee"))
					var p:Dictionary={"visit_id":active,"job_id":terms.job_id}
					if terms.kind=="service_offer":
						_button("accept_service",tr_key("ui.copy.accept_service_ad106ab3"),"calendar_accept_service",p)
					else:
						_button("deliver_service",tr_key("ui.copy.return_and_collect_fee_9378214b"),"calendar_deliver_service",p,terms.status!="complete")
						_button("return_unpaid",tr_key("ui.copy.return_unpaid_460b2b55"),"calendar_return_unpaid",p)
				_button("decline",tr_key("ui.copy.decline_visit_1b22e3e3"),"calendar_decline_visit",{"visit_id":active})
			var due:Dictionary={}
			var total:Dictionary={"VKC":0,"USD":0}
			for id:String in _view.get("obligations",{}).get("contracts",{}):
				var obligation:Dictionary=_view.obligations.contracts[id]
				if obligation.status=="reserved" and obligation.due_day==_view.day:
					due[id]="pay"
					total.VKC+=obligation.price.VKC
					total.USD+=obligation.price.USD
			if due.is_empty():
				_button("close_day",tr_key("ui.copy.close_shop_59b1e7c1"),"calendar_close",{"contract_choices":{}})
			else:
				var after_overhead:int=maxi(0,int(_view.wallet.VKC)-15)
				_line(tr_key("ui.format.closing_settlement",{"due":tr_key("inventory.format.money_pair",{"vkc":str(total.VKC),"usd":str(total.USD)})}))
				_line(tr_key("ui.format.cash_after_overhead",{"cash":tr_key("inventory.format.money_pair",{"vkc":str(after_overhead),"usd":str(_view.wallet.USD)})}))
				_button("close_day",tr_key("ui.copy.pay_due_contracts_close_cdf3db4"),"calendar_close",{"contract_choices":due},after_overhead<total.VKC or int(_view.wallet.USD)<total.USD)
				var unpaid:Dictionary={}
				for id:String in due:
					unpaid[id]="default"
				_button("close_day_without_payment",tr_key("ui.copy.confirm_default_release_reservation_3e38b308"),"calendar_close",{"contract_choices":unpaid})
		else:
			_line(tr_key("ui.copy.evening_workshop_89b959a5"))
			for row:Dictionary in _view.work:
				_button("work_"+row.id,row.id+" · "+tr_key("ui.copy.restore_b51f11f2")+str(row.cost.VKC)+" VKC","restore_item",{"actor":"player","item_id":row.id})
			_button("next_day",tr_key("ui.copy.next_morning_296e989c"),"calendar_morning")
	for id:String in _view.get("obligations",{}).get("contracts",{}):
		var contract:Dictionary=_view.obligations.contracts[id]
		_line(tr_key("ui.format.contract_summary",{"price":tr_key("inventory.format.offer_amount",{"amount":str(contract.price.VKC),"currency":str("VKC")}),"status":tr_key("ui.format.contract_status",{"due":str(contract.due_day),"delivery":str(contract.delivery_day),"status":tr_key("ui.contract.status."+str(contract.status))})}))
		if _view.phase=="shop" and not _view.complete:
			if contract.status=="offered":
				_button("contract_accept",tr_key("ui.copy.accept_marcus_s_offer_db96d1c3"),"calendar_accept_contract",{"contract_id":id})
				_button("contract_decline",tr_key("ui.copy.decline_ed1fb32f"),"calendar_decline_contract",{"contract_id":id})
			if contract.status=="reserved":
				_button("contract_pay",tr_key("ui.copy.pay_contract_e37ce3dd"),"calendar_pay_contract",{"contract_id":id})
				if contract.can_extend:
					_button("contract_extend",tr_key("ui.copy.extend_7853d8ec"),"calendar_extend_contract",{"contract_id":id})
	for news:Dictionary in _view.get("world_news",{}).get("news",[]):
		_line(tr_key("ui.copy.news_d_1010b526")+str(news.day)+" · "+str(news.get(_language,"")))
	var facts:Dictionary=_view.get("obligations",{}).get("facts",{})
	if facts.has("clinic_supply_confirmed"):
		_line(tr_key("ui.copy.ian_thank_you_for_helping_a5e77da9"))
	elif _view.day>=6:
		_line(tr_key("ui.copy.additional_clinic_supplies_have_not_been_co_4d04311"))
	if facts.has("rad1_delivered"):
		_line(tr_key("ui.copy.marcus_your_medicine_has_arrived_b406e251"))
	elif facts.has("rad1_defaulted"):
		_line(tr_key("ui.copy.marcus_this_delivery_did_not_go_through_1d0dcbc8"))
	if _view.day==7:
		_line(tr_key("ui.copy.tan_people_do_get_out_who_and_when_that_s_a_35e3682"))
	_line(tr_key("ui.copy.stock_and_custody_89da3ff3"))
	for row:Dictionary in _view.stock:
		_line(row.id+" · "+tr_key(row.label)+" · "+(tr_key("ui.copy.owned_cff2f00c") if row.owned else tr_key("ui.copy.custody_a1f910")))
	_configure_app()
	if _history_open:
		var index:Dictionary=_view.trade_history.duplicate(true)
		var subject:String=str(_view.get("appraisal",{}).get("item_id",""))
		if not subject.is_empty():
			var targeted:Dictionary=runtime.item_history(subject)
			if not targeted.items.is_empty():
				var entries:Array=[]
				for row:Dictionary in index.items:
					if row.item_id!=subject:
						entries.append(row)
				entries.push_front(targeted.items[0])
				index.items=entries
		if native_history_index:
			_history.configure(index,tr_key,_language,_slot_index)
		else:
			_history.configure(index,tr_key,_language)
	if _stock_open:
		_stock_view()
	_refresh_visibility()

func _notification(what:int)->void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(_feedback_audio):
		_feedback_audio.shutdown_audio()

func _exit_tree()->void:
	if is_instance_valid(_feedback_audio):
		_feedback_audio.shutdown_audio()
	if runtime!=null:
		runtime.close()
