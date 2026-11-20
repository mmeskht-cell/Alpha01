extends Control
## Isolated generic counter preview. No direct domain, persistence or fixture access.
## The host is fed public DTO and revision by the application/test adapter.
const GenericPanelScript = preload("res://src/presentation/generic_appraisal_panel.gd")
const UiTheme = preload("res://src/presentation/ui_theme.gd")
const HistoryScript = preload("res://src/presentation/generic_trade_history.gd")
signal action_requested(kind: String, payload: Dictionary, expected_revision: int)
signal language_requested(locale: String)

var _panel: ScrollContainer
var _header: Label
var _message: Label
var _next: Button
var _decline: Button
var _gaze: Button
var _language_button: Button
var _view: Dictionary = {}
var _revision: int = -1
var _translator: Callable
var _locale: String = "ko"
var _down: bool = true
var _locked: bool = true
var _active: String = ""
var _offsets: Dictionary = {"appraisal":0,"customer":0}
var _generation: int = 0
var _motion_enabled: bool = true
var _transitioning: bool = false
var _gaze_tween: Tween
var _motion_button: Button
var _history_button: Button
var _history_panel: ScrollContainer
var _history_open: bool = false

func _word(ko: String,en: String) -> String:
	return ko if _locale == "ko" else en

func _mode() -> String:
	return "appraisal" if _down else "customer"

func _ready() -> void:
	if not UiTheme.apply_to(self):
		return
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+edge,16)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_header = Label.new()
	_header.add_theme_font_size_override("font_size",22)
	column.add_child(_header)
	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	_next = _make(toolbar,"admit_visit")
	_decline = _make(toolbar,"decline_active")
	_gaze = _make(toolbar,"toggle_gaze")
	_language_button = _make(toolbar,"switch_language")
	_motion_button = _make(toolbar,"toggle_motion")
	_history_button = _make(toolbar,"toggle_history")
	_history_button.pressed.connect(_toggle_history)
	_motion_button.pressed.connect(func() -> void: set_motion_enabled(not _motion_enabled))
	_next.pressed.connect(func() -> void:
		if not _locked and not _transitioning and not _history_open and _active.is_empty() and _view.get("visits",{}).get("can_next",false):
			action_requested.emit("calendar_next_visit",{},_revision))
	_decline.pressed.connect(func() -> void:
		if not _locked and not _transitioning and not _history_open and not _active.is_empty():
			action_requested.emit("calendar_decline_visit",{"visit_id":_active},_revision))
	_gaze.pressed.connect(toggle_gaze)
	_language_button.pressed.connect(func() -> void:
		if not _transitioning:
			language_requested.emit("en" if _locale == "ko" else "ko"))
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)
	_panel = GenericPanelScript.new()
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_panel)
	_history_panel = HistoryScript.new()
	_history_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_panel.visible = false
	column.add_child(_history_panel)
	_panel.action_requested.connect(func(kind: String,payload: Dictionary,rev: int) -> void:
		if not _locked and not _transitioning and not _history_open and rev == _revision and payload.get("visit_id") == _active:
			action_requested.emit(kind,payload,rev))
	_render()

func _make(parent: Control,id: String) -> Button:
	var b := Button.new()
	b.name = id
	parent.add_child(b)
	return b

func configure(dto: Dictionary,revision: int,translator: Callable,locale: String = "ko",locked: bool = false,feedback: String = "") -> void:
	_cancel_transition()
	var next_active: String = str(dto.get("visits",{}).get("active",""))
	if next_active != _active:
		_down = true
		_offsets = {"appraisal":0,"customer":0}
	elif is_instance_valid(_panel) and not _history_open:
		_offsets[_mode()] = _panel.scroll_vertical
	_view = dto.duplicate(true)
	if not _view.has("trade_history"):
		_history_open = false
	_revision = revision
	_translator = translator
	_locale = locale
	_locked = locked
	_active = next_active
	if is_instance_valid(_message):
		_message.text = feedback
	_render()

func _render() -> void:
	if not is_instance_valid(_panel):
		return
	_generation += 1
	_header.text = _word("감정 카운터 시험","Appraisal counter pilot")+"  ·  "+_word("시간 ","Minute ")+str(_view.get("minute",0))
	_next.text = _word("다음 손님","Next customer")
	_decline.text = _word("거래 거절","Decline visit")
	_gaze.text = _word("고객 보기 (SPACE)","Look up (SPACE)") if _down else _word("물품 보기 (SPACE)","Look down (SPACE)")
	_language_button.text = "EN" if _locale == "ko" else "한국어"
	_motion_button.text = _word("모션 켜짐","Motion on") if _motion_enabled else _word("모션 감소","Reduced motion")
	_language_button.disabled = _transitioning
	_motion_button.disabled = _transitioning
	_next.disabled = _locked or _transitioning or _history_open or not _view.get("visits",{}).get("can_next",false)
	_decline.disabled = _locked or _transitioning or _history_open or _active.is_empty()
	_gaze.disabled = _locked or _transitioning or _history_open or _view.get("appraisal",{}).is_empty()
	_history_button.visible = _view.has("trade_history")
	_history_button.disabled = _transitioning
	_history_button.text = _word("닫기","Close history") if _history_open else _word("거래 기록","History")
	_panel.visible = not _history_open
	_history_panel.visible = _history_open
	if _history_open:
		_history_panel.configure(_view.get("trade_history",{}),_translator,_locale)
	_panel.configure(_view.get("appraisal",{}),_revision,_translator,_locale,_locked or _transitioning or _history_open,_mode())
	_restore_scroll.call_deferred(_generation,int(_offsets.get(_mode(),0)))

func _toggle_history() -> void:
	if _transitioning or get_viewport().gui_is_dragging() or not _view.has("trade_history"):
		return
	if not _history_open:
		_offsets[_mode()] = _panel.scroll_vertical
	_history_open = not _history_open
	_render()

func _restore_scroll(generation: int,offset: int) -> void:
	await get_tree().process_frame
	if generation == _generation and is_instance_valid(_panel):
		_panel.scroll_vertical = offset

func toggle_gaze() -> void:
	if not is_instance_valid(_gaze) or _gaze.disabled or get_viewport().gui_is_dragging():
		return
	_offsets[_mode()] = _panel.scroll_vertical
	if not _motion_enabled:
		_down = not _down
		_render()
		return
	_transitioning = true
	_render()
	_gaze_tween = create_tween()
	_gaze_tween.tween_property(_panel,"modulate:a",0.12,0.17)
	_gaze_tween.tween_callback(_gaze_midpoint)
	_gaze_tween.tween_property(_panel,"modulate:a",1.0,0.17)
	_gaze_tween.tween_callback(_gaze_finished)

func _gaze_midpoint() -> void:
	if not _transitioning:
		return
	_down = not _down
	_render()

func _gaze_finished() -> void:
	_transitioning = false
	_render()

func _cancel_transition() -> void:
	if _gaze_tween != null and _gaze_tween.is_valid():
		_gaze_tween.kill()
	_gaze_tween = null
	_transitioning = false
	if is_instance_valid(_panel):
		_panel.modulate.a = 1.0

func _exit_tree() -> void:
	_cancel_transition()

func set_motion_enabled(enabled: bool) -> void:
	_cancel_transition()
	_motion_enabled = enabled
	_render()

func transition_active() -> bool:
	return _transitioning

func gaze_mode() -> String:
	return _mode()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not is_instance_valid(_gaze):
		return
	if event is InputEventKey and (event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE) and event.pressed and not event.echo:
		var focus: Control = get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return
		if _transitioning or _history_open or get_viewport().gui_is_dragging():
			get_viewport().set_input_as_handled()
			return
		if _gaze.disabled:
			return
		get_viewport().set_input_as_handled()
		toggle_gaze()
