extends Control
## Explicit development scene with replaceable placeholder art, not release art.
## Reads only public DTOs. No snapshot, hidden truth, direct money or inventory writes.
const Runtime = preload("res://src/application/foundation_runtime.gd")
const UiTheme = preload("res://src/presentation/ui_theme.gd")
const CommitFeedback = preload("res://src/presentation/commit_feedback.gd")
const Preferences = preload("res://src/presentation/ui_preferences.gd")
const Clock = preload("res://src/domain/business_clock.gd")
const RadioWorkbench = preload("res://src/presentation/radio_workbench.gd")
const AttributeCard = preload("res://src/presentation/appraisal_attribute_card.gd")
const AppraisalSlot = preload("res://src/presentation/appraisal_card_slot.gd")
const DeckCard = preload("res://src/presentation/negotiation_deck_card.gd")
const DeckTarget = preload("res://src/presentation/negotiation_deck_target.gd")
const DayOnePanel = preload("res://src/presentation/day_one_panel.gd")
@export var full_day_slice: bool = false
@export var registry_storage: bool = false
@export var composite_pilot: bool = false
var composite_pilot_id: String = "integrated"
@export var inspection_preview: bool = false
## Explicitly isolated scene smoke/preview; never opens the persistent day-one slot.
@export var isolated_day_one_preview: bool = false
## Test-only explicit identifier for relaunching the same isolated preview. Never used by real slot.
var isolated_preview_id: String = ""
const COUNTER_BG = preload("res://assets/art/scenes/counter_pilot_bg.svg")
const COUNTER_FG = preload("res://assets/art/scenes/counter_pilot_fg.svg")
const CUSTOMER_G01 = preload("res://tests/fixtures/art/legacy_gate1/g01_pilot.svg")
const LAYOUT: String = "res://data/campaign/gate1_1/counter_layout.json"
var _runtime: RefCounted
var _layout: Dictionary = {}
var _controls: Control
var _modal: Control
var _document_scroll: ScrollContainer
var _scroll_document: String = ""
var _scroll_offset: int = 0
var _document: String = ""
var _workbench: RadioWorkbench
var _bench_view: Dictionary = {}
var _feedback_key: String = ""
var _save_blocked: bool = false
var _load_blocked: bool = false
var _language: String = "ko"
var _document_font_size: int = 16
var _preferences_path: String = ""
var _preferences_saved: bool = true
var _commit_feedback: CommitFeedback
# UI-only draft scoped to a specific customer visit.
var _offer_draft: Dictionary = {}
var _offer_amount: SpinBox
var _offer_evidence: OptionButton
var _offer_ids: Array = []
var _offer_visit: String = ""
var _day_section: String = "counter"
var _day_panel: Control
var _stock_draft: Dictionary = {}
var _service_draft: Dictionary = {}
var _service_draft_revision: int = -1
var _section_scroll: Dictionary = {}
var _gaze_enabled: bool = false
var _gaze_down: bool = false
var _gaze_blend: float = 0.0
var _gaze_transition: bool = false
var _closing: bool = false
var _owns_close: bool = false

func _ready() -> void:
	if not UiTheme.apply_to(self):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if not parsed is Dictionary:
		push_error("COUNTER_LAYOUT_INVALID")
		return
	_layout = parsed
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_runtime = Runtime.new()
	var save_directory: String = "user://zt_rebuild/saves"
	if inspection_preview:
		save_directory = "user://zt_rebuild/inspection_previews/" + str(Time.get_unix_time_from_system()).replace(".", "_") + "_" + str(Time.get_ticks_usec())
	var slot: String = "gate1_1_v3"
	var initialized: bool
	if composite_pilot and full_day_slice:
		if not composite_pilot_id.is_valid_identifier() or composite_pilot_id.length() > 64:
			return
		save_directory = "user://zt_rebuild/composite_pilots/" + composite_pilot_id
		slot = "gate1_composite_pilot_v3"
		initialized = _runtime.initialize_composite_pilot(save_directory, registry_storage)
	elif full_day_slice:
		save_directory = "user://zt_rebuild/day_one"
		if isolated_day_one_preview:
			if not isolated_preview_id.is_empty() and isolated_preview_id.is_valid_identifier() and isolated_preview_id.length() <= 64:
				save_directory = save_directory.path_join("preview_" + isolated_preview_id)
			else:
				save_directory = save_directory.path_join("preview_" + str(Time.get_ticks_usec()) + "_" + str(get_instance_id()))
		slot = "gate1_day_one_v3"
		initialized = _runtime.initialize_day_one(save_directory, registry_storage)
	else:
		initialized = _runtime.initialize_gate1_opening(slot, save_directory)
	if not initialized:
		_load_blocked = true
		push_error("COUNTER_INITIALIZE_FAILED")
		return
	var has_save: bool = FileAccess.file_exists(save_directory.path_join(slot + ".a.json")) or FileAccess.file_exists(save_directory.path_join(slot + ".b.json"))
	if _runtime.persistence_view().load_failed:
		_load_blocked = true
		_feedback_key = "ui.load_save_failed"
	elif not _runtime.persistence_view().get("registry_storage", false) and has_save:
		var result: Dictionary = _runtime.load_saved()
		if not result.ok:
			_load_blocked = true
			_feedback_key = "ui.load_save_failed"
	if full_day_slice and not _load_blocked and _runtime.counter_view().get("day_one", {}).get("started", false):
		_document = "day_one"
		_day_section = "workshop" if _runtime.counter_view().day_one.phase == "workshop" else "counter"
	# Real play shares a single UI profile; every explicit preview is isolated.
	_preferences_path = "user://zt_rebuild/preferences_v1.json"
	if inspection_preview or isolated_day_one_preview or composite_pilot:
		_preferences_path = save_directory.path_join("preferences_v1.json")
	var preferences: Dictionary = Preferences.read(_preferences_path)
	_language = preferences.language
	_document_font_size = preferences.font_size
	_runtime.localization.select_language(_language)
	_commit_feedback = CommitFeedback.new()
	_commit_feedback.configure_preferences(preferences)
	add_child(_commit_feedback)
	_commit_feedback.prime(int(_runtime.counter_view().revision))
	resized.connect(queue_redraw)
	_refresh()
	# Main counter only; isolated scene probes and sub-scenes never own global quit.
	if not inspection_preview and not isolated_day_one_preview and not composite_pilot:
		_owns_close = true
		get_tree().auto_accept_quit = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _owns_close:
		_request_close.call_deferred()

func _request_close() -> void:
	if _closing or not is_inside_tree():
		return
	_closing = true
	set_process_input(false)
	set_process_unhandled_key_input(false)
	if is_instance_valid(_controls):
		_controls.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(_commit_feedback):
		_commit_feedback.shutdown_audio()
	# Keep the audio server/tree alive long enough to release stopped playbacks.
	await get_tree().create_timer(0.25,true,false,true).timeout
	if is_inside_tree():
		get_tree().quit()

func _exit_tree() -> void:
	if _owns_close and get_tree() != null:
		get_tree().auto_accept_quit = true
	if _runtime != null:
		_runtime.shutdown()

func _t(key: String, args: Dictionary = {}) -> String:
	return _runtime.localization.text(key, args)

func _rect(key: String) -> Rect2:
	var a: Array = _layout.anchors[key]
	return Rect2(Vector2(a[0], a[1]) * size, Vector2(a[2], a[3]) * size)

func _anchor(node: Control, key: String) -> void:
	var a: Array = _layout.anchors[key]
	node.anchor_left = a[0]
	node.anchor_top = a[1]
	node.anchor_right = a[0] + a[2]
	node.anchor_bottom = a[1] + a[3]
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0

func _color(key: String) -> Color:
	return Color(str(_layout.palette[key]))

func _draw() -> void:
	if _layout.is_empty():
		return
	var canvas := Rect2(Vector2.ZERO, size)
	var shift: float = -size.y * 0.22 * _gaze_blend
	var gaze_canvas := Rect2(Vector2(0,shift),Vector2(size.x,size.y-shift))
	draw_texture_rect(COUNTER_BG, gaze_canvas, false)
	if _runtime != null and not _load_blocked:
		var dto: Dictionary = _runtime.counter_view()
		if not dto.is_empty() and dto.customer != null and _gaze_blend < 0.99:
			var area: Rect2 = _rect("customer")
			area.position.y -= size.y * 0.60 * _gaze_blend
			var fit: float = minf(area.size.x / 120.0, area.size.y / 132.0)
			var extent := Vector2(120, 132) * fit
			draw_texture_rect(CUSTOMER_G01, Rect2(area.position + Vector2((area.size.x - extent.x) * 0.5, area.size.y - extent.y), extent), false)
	draw_texture_rect(COUNTER_FG, gaze_canvas if _gaze_enabled else canvas, false)

func _button(parent: Control, label: String, action: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = label
	button.clip_text = true
	button.tooltip_text = label
	button.custom_minimum_size.y = 42
	button.disabled = disabled
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _scene_button(anchor: String, label: String, action: Callable, disabled: bool = false) -> Button:
	var b: Button = _button(_controls, label, action, disabled)
	_anchor(b, anchor)
	b.custom_minimum_size = Vector2.ZERO
	return b

func _label(parent: Control, value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _scene_label(anchor: String, value: String) -> Label:
	# Independent, readable plate rather than light text over the scene texture.
	var backing := ColorRect.new()
	backing.color = Color(0.10, 0.14, 0.12, 0.94)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls.add_child(backing)
	_anchor(backing, anchor)
	var label: Label = _label(_controls, value)
	_anchor(label, anchor)
	label.offset_left = 6
	label.offset_right = -6
	label.offset_top = 2
	label.offset_bottom = -2
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("#ede5d3"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _locked() -> bool:
	if _closing or _runtime == null:
		return true
	var persistence: Dictionary = _runtime.persistence_view()
	return _load_blocked or persistence.save_pending or persistence.load_failed

func _submit(kind: String, payload: Dictionary = {}) -> void:
	if _locked():
		return
	var dto: Dictionary = _runtime.counter_view()
	var command: Dictionary = {"action_id": "counter_" + str(dto.revision + 1) + "_" + kind, "expected_revision": dto.revision, "type": kind, "payload": payload}
	var result: Dictionary = _runtime.submit(command)
	if result.ok:
		_save_blocked = not result.get("persisted", false)
		_feedback_key = "error.save" if _save_blocked else "ui.action_saved"
		if kind == "begin_day_one":
			_document = "day_one"
			_day_section = "counter"
		elif kind == "day_one_close":
			_day_section = "workshop"
			_scroll_offset = 0
		elif kind == "day_one_next_morning":
			_day_section = "counter"
			_scroll_offset = 0
		elif kind == "confirm_purchase":
			_feedback_key = "ui.trade_unsaved" if _save_blocked else "ui.trade_saved"
			_document = ""
		elif kind == "decline_visit":
			_document = ""
			if not _save_blocked:
				_feedback_key = "ui.visit_declined"
	else:
		match result.get("error", ""):
			"insufficient_funds": _feedback_key = "ui.insufficient_funds"
			"inventory_placement", "trade_inventory": _feedback_key = "ui.no_space"
			"inspection_time_short": _feedback_key = "ui.inspection_time_short"
			"offer_already_recorded": _feedback_key = "ui.offer_duplicate"
			_: _feedback_key = "ui.action_failed"
	_refresh()
	if result.ok and _commit_feedback != null:
		_commit_feedback.committed(kind, int(dto.revision), int(_runtime.counter_view().revision), bool(result.get("persisted", false)))

func _retry() -> void:
	if _load_blocked:
		return
	var result: Dictionary = _runtime.retry_save()
	_save_blocked = not result.ok
	_feedback_key = "error.save" if _save_blocked else "ui.action_saved"
	_refresh()

func _open(name: String) -> void:
	if name != _document:
		if is_instance_valid(_commit_feedback):
			_commit_feedback.local_page()
		_scroll_offset = 0
		_scroll_document = ""
	_document = name
	_refresh()

func _submit_from_revision(kind: String, payload: Dictionary, revision: int) -> void:
	if _locked() or _runtime.counter_view().revision != revision:
		return
	_submit(kind, payload)

func _inspect_from_bench(payload: Dictionary) -> void:
	_submit_from_revision.call_deferred("inspect_radio", payload, int(_runtime.counter_view().revision))

func _save_preferences() -> void:
	if _preferences_path.is_empty() or not is_instance_valid(_commit_feedback):
		return
	var value: Dictionary = {"version": 1, "language": _language, "font_size": _document_font_size, "sound": _commit_feedback.sound_enabled, "motion": _commit_feedback.motion_enabled, "levels": _commit_feedback.diagnostic_view().levels}
	_preferences_saved = Preferences.write(_preferences_path, value)
	if not _preferences_saved:
		push_warning("ZT_UI_PREFERENCES_SAVE_FAILED")

func _switch_language() -> void:
	_language = "en" if _language == "ko" else "ko"
	_runtime.localization.select_language(_language)
	_save_preferences()
	_refresh()

func _refresh() -> void:
	_capture_offer_draft()
	if is_instance_valid(_day_panel) and is_instance_valid(_day_panel.inventory):
		_stock_draft = _day_panel.inventory.draft_view()
	if is_instance_valid(_day_panel) and is_instance_valid(_day_panel.service_surface):
		_service_draft = _day_panel.service_surface.draft_view()
	_day_panel = null
	if is_instance_valid(_document_scroll) and _scroll_document == _document:
		_scroll_offset = _document_scroll.scroll_vertical
	_document_scroll = null
	if is_instance_valid(_workbench):
		_bench_view = _workbench.view_state()
	_workbench = null
	if _controls != null:
		remove_child(_controls)
		_controls.queue_free()
	_controls = Control.new()
	add_child(_controls)
	_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal = null
	var dto: Dictionary = _runtime.counter_view()
	if dto.customer == null or dto.customer.visit_id != _offer_draft.get("visit_id", ""):
		_offer_draft.clear()
	var time: String = Clock.clock_text(int(dto.minute))
	var status: String = _t("ui.clock", {"day": str(dto.day), "time": time}) + "  |  " + _t("wallet.balance", {"amount": str(dto.wallet.VKC), "currency": "VKC"}) + "  |  " + _t("ui.rad1_doses", {"count": str(dto.personal_rad1_doses)}) + "  |  " + _t("ui.rad1_remaining", {"hours": str(snappedf(maxf(0.0, float(dto.rad1_effect_until_minute - dto.minute) / 60.0), 0.1))})
	_scene_label("status", status)
	_scene_button("language", _t("ui.language"), _switch_language)
	if _load_blocked:
		_scene_label("dialogue", _t("ui.load_save_failed"))
		queue_redraw()
		return
	var extension: Dictionary = dto.get("day_one", {})
	if full_day_slice and extension.get("started", false):
		_refresh_day_one(dto)
		return
	if full_day_slice and extension.get("can_begin", false):
		_scene_button("door", _t("dayone.begin"), func() -> void: _submit("begin_day_one"), _locked())
	else:
		_scene_button("door", _t("ui.door"), func() -> void: _submit("next_visit"), _locked() or not dto.can_call_next)
	_scene_button("contract", _t("ui.contract_document"), func() -> void: _open("contract"))
	if dto.customer != null:
		_scene_button("catalog", _t("ui.catalog"), func() -> void: _open("catalog"))
		_scene_button("offer", _t("ui.offer"), func() -> void: _open("offer"))
		var dialogue: String = _t(dto.customer.dialogue_key)
		if not dto.negotiation.offers.is_empty():
			dialogue = _t(dto.negotiation.offers.back().response_key)
		var spoken: Dictionary = dto.appraisal.get("card_dialogue", {})
		if not _gaze_enabled and not spoken.is_empty():
			dialogue = _t(spoken.speaker_key, {"value": _t(spoken.label_key)}) + "\n" + _t(spoken.response_key)
		var reply: Dictionary = dto.get("negotiation_deck",{}).get("latest_reply",{})
		if _gaze_enabled and not reply.is_empty():
			dialogue = _t(reply.speaker_key,{"value":_t(reply.label_key)}) + "\n" + _t(reply.response_key)
		_scene_label("dialogue", dialogue)
		if not _gaze_enabled or _gaze_down:
			_show_inline_appraisal(dto.appraisal)
			if _gaze_enabled:
				_show_deck(dto,true)
		else:
			_show_deck(dto,false)
			if _document.is_empty():
				_show_counter_offer(dto)
		_scene_button("slip", _t("appraisal.look_up" if _gaze_down else "appraisal.look_down"), _toggle_gaze)

	else:
		_scene_label("dialogue", _t("ui.counter_empty") if dto.negotiation.outcome == null else _t("ui.day1_slice_end"))
		if not dto.acquired_appraisal.is_empty():
			_scene_button("catalog", _t("ui.acquired_appraisal"), func() -> void: _open("acquired_slip"))
	var feedback: String = _t("ui.preview_session" if inspection_preview else "ui.dev_counter") if _feedback_key.is_empty() else _t(_feedback_key)
	feedback += "  |  " + _t("ui.customers_remaining", {"count": str(dto.remaining_visits)}) + "  |  " + _t("ui.business_remaining", {"minutes": str(maxi(0, 600 - int(dto.minute)))})
	if _save_blocked:
		_scene_button("feedback", feedback + " · " + _t("ui.retry_save"), _retry)
	else:
		_scene_label("feedback", feedback)
	if not _document.is_empty():
		_show_document(dto)
	queue_redraw()

func _can_toggle_gaze() -> bool:
	return not _gaze_transition and _runtime != null and _runtime.counter_view().get("customer") != null and not _locked() and _document in ["","offer"] and not get_viewport().gui_is_dragging() and (not is_instance_valid(_workbench) or not _workbench.gesture_active())

func _set_gaze_blend(value: float) -> void:
	_gaze_blend = value
	queue_redraw()

func _toggle_gaze() -> void:
	if not _can_toggle_gaze():
		return
	_gaze_enabled = true
	_gaze_down = not _gaze_down
	_document = ""
	var target: float = 1.0 if _gaze_down else 0.0
	if not is_instance_valid(_commit_feedback) or not _commit_feedback.motion_enabled:
		_set_gaze_blend(target)
		_refresh()
		return
	_gaze_transition = true
	_controls.hide()
	var animation := create_tween()
	animation.tween_method(_set_gaze_blend,_gaze_blend,target,0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await animation.finished
	_gaze_transition = false
	_refresh()

func _deck_command(op: String, slot: String, argument: Variant, revision: int) -> void:
	if _gaze_transition or _runtime.counter_view().revision != revision:
		return
	var payload: Dictionary = {"op":op,"slot":slot,"argument":argument}
	if op == "present":
		for candidate: Dictionary in _runtime.counter_view().appraisal.argument_candidates:
			if candidate.argument.slot == slot:
				payload["current_argument"] = candidate.argument
				break
	_submit_from_revision("deck_action",payload,revision)

func _show_deck(dto: Dictionary, down: bool) -> void:
	var scroll := ScrollContainer.new()
	_controls.add_child(scroll)
	_anchor(scroll,"evidence_strip" if down else "cards")
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows := HBoxContainer.new()
	scroll.add_child(rows)
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rev: int = int(dto.revision)
	var deck: Dictionary = dto.negotiation_deck
	if down:
		for candidate: Dictionary in dto.appraisal.argument_candidates:
			var arg: Dictionary = candidate.argument
			var ready: bool = false
			for entry: Dictionary in deck.ready:
				if entry.argument.slot == arg.slot and entry.current:
					ready = true
			var label: String = _t("appraisal.argument_prepare",{"value":_t(candidate.label_key),"count":str(candidate.evidence_ids.size())})
			var button: Button = _button(rows,_t("appraisal.deck_ready",{"value":_t(candidate.label_key)}) if ready else label,_deck_command.bind("prepare",arg.slot,arg,rev),_locked() or ready)
			button.clip_text = false
	else:
		var target := DeckTarget.new()
		target.name = "NegotiationDropTarget"
		target.text = _t("appraisal.deck_target")
		target.revision = rev
		target.disabled = _locked()
		target.card_presented.connect(func(arg: Dictionary, expected: int) -> void: _deck_command.call_deferred("present",arg.slot,arg,expected))
		_controls.add_child(target)
		_anchor(target,"deck_target")
		for row: Dictionary in deck.ready:
			var arg: Dictionary = row.argument
			var column := VBoxContainer.new()
			rows.add_child(column)
			var card := DeckCard.new()
			card.text = _t("appraisal.deck_present",{"value":_t(row.label_key)})
			card.tooltip_text = card.text
			card.argument = arg.duplicate(true)
			card.revision = rev
			card.disabled = _locked() or not row.current
			card.custom_minimum_size = Vector2(132,64)
			card.pressed.connect(_deck_command.bind("present",arg.slot,arg,rev))
			column.add_child(card)
			_button(column,_t("appraisal.deck_remove"),_deck_command.bind("remove",arg.slot,null,rev),_locked())
		var history := ScrollContainer.new()
		_controls.add_child(history)
		_anchor(history,"deck_history")
		history.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var statements := VBoxContainer.new()
		history.add_child(statements)
		statements.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(statements,_t("appraisal.deck_history"))
		for row: Dictionary in deck.presented:
			_label(statements,_t(row.speaker_key,{"value":_t(row.label_key)}))
			_label(statements,_t(row.response_key))
			if row.claim_key != null:
				var claim := PanelContainer.new()
				statements.add_child(claim)
				var claim_body := VBoxContainer.new()
				claim.add_child(claim_body)
				_label(claim_body,_t("appraisal.customer_unconfirmed"))
				_label(claim_body,_t(row.claim_key))

## No new authority: the same manual offer and settlement commands as the legacy modal.
func _show_counter_offer(dto: Dictionary) -> void:
	var n: Dictionary = dto.negotiation
	var panel := PanelContainer.new()
	_controls.add_child(panel)
	_anchor(panel,"counter_offer")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_label(body,_t("ui.offer_amount"))
	_label(body,_t("ui.offers_left",{"count":str(n.remaining_offers)}))
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = maxi(1,int(dto.wallet.VKC))
	amount.step = 1
	var initial: int = int(dto.customer.ask if n.offers.is_empty() else n.offers.back().amount)
	amount.value = clampi(int(_offer_draft.get("amount",initial)),1,int(amount.max_value))
	body.add_child(amount)
	_offer_amount = amount
	_offer_visit = dto.customer.visit_id
	var ids: Array = []
	for row: Dictionary in dto.negotiation_deck.presented:
		ids.append(row.presentation_id)
	_label(body,_t("appraisal.counter_basis",{"count":str(ids.size())}))
	var revision: int = int(dto.revision)
	_button(body,_t("appraisal.counter_propose"),func() -> void:
		var payload: Dictionary = {"amount":int(amount.value),"evidence_id":null} if ids.is_empty() else {"amount":int(amount.value),"presented_ids":ids}
		_submit_from_revision("make_offer",payload,revision),_locked() or not n.can_offer or dto.wallet.VKC < 1)
	if n.can_confirm:
		var last: Dictionary = n.offers.back()
		_button(body,_t("appraisal.counter_confirm",{"amount":str(last.amount)}),func() -> void:
			_submit_from_revision("confirm_purchase",{"offer_id":last.offer_id,"inventory":"player_stock","x":0,"y":0,"rotated":false},revision),_locked() or int(last.amount) > int(dto.wallet.VKC))
	elif not n.offers.is_empty():
		_label(body,_t(n.offers.back().response_key))
	_button(body,_t("ui.decline"),func() -> void:
		_submit_from_revision("decline_visit",{},revision),_locked() or not n.can_decline)

func _refresh_day_one(dto: Dictionary) -> void:
	var day: Dictionary = dto.day_one
	if is_instance_valid(_commit_feedback):
		_commit_feedback.set_phase(str(day.phase))
	# Reset UI-only preparation whenever authoritative state changes.
	if _service_draft_revision != int(dto.revision):
		_service_draft.clear()
		_service_draft_revision = int(dto.revision)
	_scene_button("catalog", _t("dayone.management"), func() -> void: _open("day_one"))
	_scene_button("contract", _t("ui.contract_document"), func() -> void: _open("contract"))
	_scene_label("dialogue", _t("dayone.phase_evening" if day.phase == "workshop" else ("dayone.phase_morning" if day.day == 2 else "dayone.phase_shop")))
	if _save_blocked:
		_scene_button("feedback", _t("ui.retry_save"), _retry)
	else:
		_scene_label("feedback", _t("dayone.management") if _feedback_key.is_empty() else _t(_feedback_key))
	if not _document.is_empty():
		_show_document(dto)
	queue_redraw()

func _select_day_section(section: String) -> void:
	if section not in ["counter", "stock", "workshop", "ledger"]:
		return
	if is_instance_valid(_document_scroll):
		_section_scroll[_day_section] = _document_scroll.scroll_vertical
	_day_section = section
	_scroll_document = ""
	_refresh()

func _function_label(app: Dictionary) -> String:
	match app.get("function_status", "unknown"):
		"serviceable": return _t("day1.radio.function_serviceable")
		"inoperable": return _t("day1.radio.function_inoperable")
	return _t("day1.radio.unknown")

func _show_inline_appraisal(app: Dictionary) -> void:
	var results: PackedStringArray = []
	for fact: Dictionary in app.evidence:
		results.append(_t(fact.text_key))
	if results.is_empty():
		results.append(_t(app.visible_key))
	results.append(_function_label(app))
	var latest: String = results[results.size() - 2]
	if not _gaze_enabled:
		_scene_label("evidence_strip", latest + "  ·  " + _function_label(app))
	_workbench = RadioWorkbench.new()
	_workbench.configure(app, _t, _locked(), true, _bench_view)
	_workbench.inspection_requested.connect(_inspect_from_bench)
	_workbench.extra_attribute_requested.connect(func(attribute: String, value: Variant) -> void: _apply_slot.call_deferred(attribute, value, int(_runtime.counter_view().revision)))
	_controls.add_child(_workbench)
	_anchor(_workbench, "workbench")
	var card_scroll := ScrollContainer.new()
	_controls.add_child(card_scroll)
	_anchor(card_scroll, "cards")
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_scroll.follow_focus = true
	var cards := VBoxContainer.new()
	card_scroll.add_child(cards)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 2)
	var estimate: String = _t("ui.reference_unselected")
	if app.reference.get("estimate") != null:
		estimate = _t("ui.reference_partial", {"amount": str(app.reference.estimate), "currency": "VKC"})
	var heading := HBoxContainer.new()
	cards.add_child(heading)
	var summary: Label = _label(heading, estimate)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(heading, _t("ui.tool_guide"), func() -> void: _open("tools")).custom_minimum_size.y = 36
	_button(heading, _t("ui.appraisal_document"), func() -> void: _open("slip")).custom_minimum_size.y = 27
	_button(heading, _t("ui.zoom_in"), func() -> void: _workbench.zoom_by(0.1)).custom_minimum_size.y = 27
	_button(heading, _t("ui.zoom_out"), func() -> void: _workbench.zoom_by(-0.1)).custom_minimum_size.y = 27
	var model_row := HBoxContainer.new()
	cards.add_child(model_row)
	_card_label(model_row, _t("ui.model_cards"))
	_assessment_slot(model_row, app, "model_id", app.catalog.model_candidates)
	_extra_card(model_row, _t("ui.unconfirmed"), "model_id", null, app.hypothesis.model_id == null)
	for candidate: Dictionary in app.catalog.model_candidates:
		_extra_card(model_row, _t(candidate.name_key) + " · " + str(candidate.reference_amount) + " VKC", "model_id", candidate.id, app.hypothesis.model_id == candidate.id)
	var condition_row := HBoxContainer.new()
	cards.add_child(condition_row)
	_card_label(condition_row, _t("ui.condition_cards"))
	_assessment_slot(condition_row, app, "appearance_id", app.catalog.appearance_candidates)
	_extra_card(condition_row, _t("ui.unconfirmed"), "appearance_id", null, app.hypothesis.appearance_id == null)
	for condition: Dictionary in app.catalog.appearance_candidates:
		_extra_card(condition_row, _t(condition.label_key) + " · " + str(condition.factor_percent) + "%", "appearance_id", condition.id, app.hypothesis.appearance_id == condition.id)
	_extra_rows(cards, app)

func _card_label(parent: Control, value: String) -> void:
	var label: Label = _label(parent, value)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size.x = 140
	label.tooltip_text = value

func _extra_rows(parent: Control, app: Dictionary) -> void:
	for field: String in ["material_id", "batch_id"]:
		var row := HBoxContainer.new()
		parent.add_child(row)
		_card_label(row, _t("ui.material_cards" if field == "material_id" else "ui.batch_cards"))
		var candidates: Array = app.catalog.material_candidates if field == "material_id" else app.catalog.batch_candidates
		_assessment_slot(row, app, field, candidates)
		_extra_card(row, _t("ui.unconfirmed"), field, null, app.hypothesis.get(field) == null)
		for entry: Dictionary in candidates:
			var label: String = _t(entry.label_key)
			if field == "material_id":
				label += " · " + ("%+d" % int(entry.delta))
			_extra_card(row, label, field, entry.id, app.hypothesis.get(field) == entry.id)

func _assessment_slot(parent: Control, app: Dictionary, field: String, candidates: Array) -> void:
	var target := AppraisalSlot.new()
	target.field = field
	target.revision = int(_runtime.counter_view().revision)
	var label: String = _t("ui.unconfirmed")
	for entry: Dictionary in candidates:
		if entry.id == app.hypothesis.get(field):
			label = _t(entry.get("name_key", entry.get("label_key", "")))
	target.text = "◆ " + label
	target.tooltip_text = _t("appraisal.drop_hint") + " · " + label
	target.disabled = _locked()
	target.custom_minimum_size = Vector2(100, 26)
	target.clip_text = true
	target.add_theme_color_override("font_color", Color("#e2c991"))
	target.card_placed.connect(func(f: String, v: Variant, rev: int) -> void: _apply_slot.call_deferred(f, v, rev))
	parent.add_child(target)

func _extra_card(parent: Control, label: String, field: String, value: Variant, selected: bool) -> void:
	var card := AttributeCard.new()
	card.text = ("✓ " if selected else "+ ") + label
	card.attribute_id = field
	card.attribute_value = value
	card.disabled = _locked() or selected
	card.revision = int(_runtime.counter_view().revision)
	card.pressed.connect(_apply_slot.bind(field, value, card.revision))
	parent.add_child(card)
	card.clip_text = true
	card.tooltip_text = label
	card.custom_minimum_size.y = 26
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _apply_slot(field: String, value: Variant, revision: int) -> void:
	if field not in ["model_id", "appearance_id", "material_id", "batch_id"] or _locked():
		return
	var dto: Dictionary = _runtime.counter_view()
	if dto.revision != revision or dto.appraisal.is_empty() or dto.appraisal.hypothesis.get(field) == value:
		return
	var hypothesis: Dictionary = dto.appraisal.hypothesis
	hypothesis[field] = value
	hypothesis["item_id"] = "R001"
	hypothesis["card_slot"] = field
	var links: Dictionary = dto.appraisal.get("card_links", {}).duplicate(true)
	if value == null:
		links.erase(field)
	hypothesis["card_links"] = links
	_submit_from_revision("record_hypothesis", hypothesis, revision)

func _toggle_card_link(field: String, evidence_id: String, revision: int) -> void:
	if _locked():
		return
	var dto: Dictionary = _runtime.counter_view()
	if dto.revision != revision or dto.appraisal.is_empty() or dto.appraisal.hypothesis.get(field) == null:
		return
	var links: Dictionary = dto.appraisal.get("card_links", {}).duplicate(true)
	var ids: Array = links.get(field, [])
	if evidence_id in ids:
		ids.erase(evidence_id)
	else:
		ids.append(evidence_id)
		ids.sort()
	if ids.is_empty():
		links.erase(field)
	else:
		links[field] = ids
	var p: Dictionary = dto.appraisal.hypothesis
	p["item_id"] = "R001"
	p["link_slot"] = field
	p["card_links"] = links
	_submit_from_revision("record_hypothesis", p, revision)

func _show_history(parent: Control, dto: Dictionary) -> void:
	var history = preload("res://src/presentation/item_history_panel.gd").new()
	parent.add_child(history)
	history.configure(dto.item_history, _t)

func _cycle_document_scale() -> void:
	_document_font_size = 20 if _document_font_size == 16 else (24 if _document_font_size == 20 else 16)
	_save_preferences()
	_refresh()

func _show_document(dto: Dictionary) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.05, 0.04, 0.78)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_controls.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal = shade
	var panel := PanelContainer.new()
	shade.add_child(panel)
	_anchor(panel, "overlay")
	var document_theme: Theme = theme.duplicate()
	document_theme.default_font_size = _document_font_size
	panel.theme = document_theme
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 8)
	panel.add_child(frame)
	var toolbar := HBoxContainer.new()
	frame.add_child(toolbar)
	var close: Button = _button(toolbar, _t("ui.close_document"), func() -> void: _open(""))
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scale_button: Button = _button(toolbar, _t("ui.document_scale", {"percent": str(roundi(_document_font_size * 100.0 / 16.0))}), _cycle_document_scale)
	scale_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _document != "feedback_settings":
		var settings: Button = _button(toolbar, _t("ui.feedback_settings"), func() -> void: _open("feedback_settings"))
		settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _document == "day_one":
		var tabs := HFlowContainer.new()
		frame.add_child(tabs)
		for section: String in ["counter", "stock", "workshop", "ledger"]:
			var tab: Button = _button(tabs, _t("dayone.tab_" + section), _select_day_section.bind(section))
			# Flow layout must retain the natural translated label width. Clipped
			# buttons advertise only their stylebox width and collapse into slivers.
			tab.clip_text = false
			tab.custom_minimum_size = Vector2(96, 48)
			tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tab.toggle_mode = true
			tab.button_pressed = _day_section == section
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(scroll)
	_document_scroll = scroll
	if _scroll_document != _document:
		_scroll_offset = int(_section_scroll.get(_day_section, 0)) if _document == "day_one" else 0
	_scroll_document = _document
	scroll.set_deferred("scroll_vertical", _scroll_offset)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	var body := VBoxContainer.new()
	scroll.add_child(body)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	if _document == "feedback_settings":
		_label(body, _t("ui.feedback_settings_hint"))
		var save_notice: Label = _label(body, _t("ui.preferences_save_failed"))
		save_notice.visible = not _preferences_saved
		_button(body, _t("ui.sound_on" if _commit_feedback.sound_enabled else "ui.sound_off"), func() -> void:
			_commit_feedback.set_sound(not _commit_feedback.sound_enabled)
			_save_preferences()
			_refresh())
		_button(body, _t("ui.motion_on" if _commit_feedback.motion_enabled else "ui.motion_off"), func() -> void:
			_commit_feedback.set_motion(not _commit_feedback.motion_enabled)
			_save_preferences()
			_refresh())
		for channel: String in ["music", "ambience", "sfx", "ui"]:
			var label: Label = _label(body, _t("ui.audio_level", {"channel": _t("ui.audio_" + channel), "percent": str(_commit_feedback.level(channel))}))
			var slider := HSlider.new()
			slider.name = "Volume_" + channel
			slider.min_value = 0
			slider.max_value = 100
			slider.step = 5
			slider.custom_minimum_size.y = 44
			slider.value = _commit_feedback.level(channel)
			body.add_child(slider)
			slider.value_changed.connect(func(value: float) -> void:
				_commit_feedback.set_level(channel, int(value))
				_save_preferences()
				save_notice.visible = not _preferences_saved
				label.text = _t("ui.audio_level", {"channel": _t("ui.audio_" + channel), "percent": str(int(value))}))
		return
	if _document == "tools" and dto.customer != null:
		_label(body, _t("ui.scan_hint"))
		_label(body, _t("ui.keyboard_scan_hint"))
		for tool: Dictionary in dto.appraisal.tools:
			var name: String = _t(RadioWorkbench.TOOL_LABELS.get(tool.tool_id, "ui.inspect"))
			var cost: String = _t("ui.observation_review") if tool.known else _t("ui.tool_cost", {"minutes": str(tool.minutes)}) if tool.available else _t("ui.scan_unavailable")
			_label(body, name + " · " + cost)
		return
	if _document == "day_one" and dto.get("day_one", {}).get("started", false):
		if _save_blocked:
			_button(body, _t("ui.retry_save"), _retry)
		if not _feedback_key.is_empty():
			_label(body, _t(_feedback_key))
		var panel_ui := DayOnePanel.new()
		_day_panel = panel_ui
		body.add_child(panel_ui)
		var displayed_revision: int = int(dto.revision)
		panel_ui.requested.connect(func(kind: String, payload: Dictionary) -> void: _submit_from_revision.call_deferred(kind, payload, displayed_revision))
		panel_ui.configure(dto, _t, _locked(), _day_section, _stock_draft, _service_draft)
		return
	if _document == "contract":
		if _save_blocked:
			_button(body, _t("ui.retry_save"), _retry)
		_label(body, _t("day1.marcus.offer"))
		_label(body, _t("ui.contract_pending", {"amount": str(dto.contract.amount), "currency": dto.contract.currency}))
		if dto.contract.status == "reserved":
			_label(body, _t("ui.contract_reserved"))
		else:
			_button(body, _t("ui.contract_accept"), func() -> void: _submit("accept_rad1_contract"), _locked())
		return
	if _document == "acquired_slip" and not dto.acquired_appraisal.is_empty():
		_label(body, _t("ui.acquired_appraisal"))
		_slip(body, dto.acquired_appraisal)
		_show_history(body, dto)
		return
	if dto.customer == null:
		_label(body, _t("ui.counter_empty"))
		return
	var app: Dictionary = dto.appraisal
	if not _feedback_key.is_empty():
		_label(body, _t(_feedback_key))
	if _save_blocked:
		_button(body, _t("ui.retry_save"), _retry)
	match _document:
		"catalog":
			_catalog(body, app)

		"slip":
			_slip(body, app)
			_show_history(body, dto)
		"offer":
			_offer(body, dto)

func _catalog(body: VBoxContainer, app: Dictionary) -> void:
	_label(body, _t(app.catalog.source_key))
	for candidate: Dictionary in app.catalog.model_candidates:
		_label(body, _t(candidate.name_key) + " · " + str(candidate.reference_amount) + " VKC   " + _t(candidate.description_key))
	_label(body, _t("ui.model_cards"))
	var model_row := HFlowContainer.new()
	body.add_child(model_row)
	_assessment_slot(model_row, app, "model_id", app.catalog.model_candidates)
	_extra_card(model_row, _t("ui.unconfirmed"), "model_id", null, app.hypothesis.model_id == null)
	for candidate: Dictionary in app.catalog.model_candidates:
		_extra_card(model_row, _t(candidate.name_key) + " · " + str(candidate.reference_amount) + " VKC", "model_id", candidate.id, app.hypothesis.model_id == candidate.id)
	_label(body, _t("ui.condition_cards"))
	var condition_row := HFlowContainer.new()
	body.add_child(condition_row)
	_assessment_slot(condition_row, app, "appearance_id", app.catalog.appearance_candidates)
	_extra_card(condition_row, _t("ui.unconfirmed"), "appearance_id", null, app.hypothesis.appearance_id == null)
	for condition: Dictionary in app.catalog.appearance_candidates:
		_extra_card(condition_row, _t(condition.label_key) + " · " + str(condition.factor_percent) + "%", "appearance_id", condition.id, app.hypothesis.appearance_id == condition.id)
	_label(body, _t("ui.material_cards"))
	for entry: Dictionary in app.catalog.material_candidates:
		_label(body, _t(entry.label_key) + " · " + _t(entry.description_key) + " · " + ("%+d VKC" % int(entry.delta)))
	_label(body, _t("ui.batch_cards"))
	for entry: Dictionary in app.catalog.batch_candidates:
		_label(body, _t(entry.label_key) + " · " + entry.pattern + " · " + _t(entry.description_key))
	_label(body, _t("ui.damage_guide"))
	_extra_rows(body, app)
	_slip(body, app)

func _attribute_card(parent: Control, label: String, model: Variant, appearance: Variant, selected: bool) -> void:
	var card := AttributeCard.new()
	card.text = ("✓ " if selected else "+ ") + label
	card.model_id = model
	card.appearance_id = appearance
	card.disabled = _locked() or selected
	card.pressed.connect(_apply_card.bind(model, appearance))
	parent.add_child(card)
	card.clip_text = true
	card.tooltip_text = label
	card.custom_minimum_size.y = 26
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _apply_card(model: Variant, appearance: Variant) -> void:
	var h: Dictionary = _runtime.counter_view().appraisal.hypothesis
	_submit("record_hypothesis", {"item_id": "R001", "model_id": model, "appearance_id": appearance, "material_id": h.get("material_id"), "batch_id": h.get("batch_id")})

func _slip(body: VBoxContainer, app: Dictionary) -> void:
	_label(body, _t("ui.observed_fact"))
	for fact: Dictionary in app.evidence:
		_label(body, _t(fact.text_key))
	_label(body, _function_label(app))
	_label(body, _t("ui.player_estimate"))
	if app.reference.get("estimate") == null:
		_label(body, _t("ui.reference_unselected"))
	else:
		_label(body, _t("ui.reference_partial", {"amount": str(app.reference.estimate), "currency": "VKC"}))
	if app.reference.get("material_delta") != null:
		_label(body, _t("ui.material_adjustment", {"amount": "%+d" % int(app.reference.material_delta)}))
	_label(body, _t("ui.reference_not_offer"))
	if app.get("tools", []).is_empty() or app.evidence.is_empty():
		return
	_label(body, _t("appraisal.links_heading"))
	var revision: int = int(_runtime.counter_view().revision)
	var groups: Dictionary = {"model_id":"ui.model_cards", "appearance_id":"ui.condition_cards", "material_id":"ui.material_cards", "batch_id":"ui.batch_cards"}
	for field: String in groups:
		if app.hypothesis.get(field) == null:
			continue
		_label(body, _t(groups[field]))
		for fact: Dictionary in app.evidence:
			var linked: bool = fact.evidence_id in app.get("card_links", {}).get(field, [])
			_button(body, ("✓ " if linked else "+ ") + _t(fact.text_key), _toggle_card_link.bind(field, fact.evidence_id, revision), _locked())

func _capture_offer_draft() -> void:
	if is_instance_valid(_offer_amount):
		var basis: Variant = _offer_draft.get("evidence_id") if _offer_draft.get("visit_id","") == _offer_visit else null
		if is_instance_valid(_offer_evidence) and _offer_evidence.selected >= 0 and _offer_evidence.selected < _offer_ids.size():
			basis = _offer_ids[_offer_evidence.selected]
		_offer_draft = {"visit_id":_offer_visit,"amount":int(_offer_amount.value),"evidence_id":basis}
	_offer_amount = null
	_offer_evidence = null
	_offer_ids = []
	_offer_visit = ""

func _offer(body: VBoxContainer, dto: Dictionary) -> void:
	var n: Dictionary = dto.negotiation
	_label(body, _t(dto.customer.dialogue_key))
	_label(body, _t("ui.offers_left", {"count": str(n.remaining_offers)}))
	for row: Dictionary in n.offers:
		_label(body, _t("ui.price_history", {"amount": str(row.amount), "response": _t(row.response_key)}))
		if row.evidence_response_key != null:
			_label(body, _t(row.evidence_response_key))
	_label(body, _t("ui.offer_amount"))
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = maxi(1, int(dto.wallet.VKC))
	amount.step = 1
	var initial: int = int(dto.customer.ask if n.offers.is_empty() else n.offers.back().amount)
	amount.value = clampi(int(_offer_draft.get("amount", initial)), 1, int(amount.max_value))
	body.add_child(amount)
	var evidence := OptionButton.new()
	body.add_child(evidence)
	evidence.add_item(_t("ui.no_evidence"))
	var ids: Array = [null]
	var presented_ids: Array = []
	for row: Dictionary in dto.get("negotiation_deck",{}).get("presented",[]):
		presented_ids.append(row.presentation_id)
	if _gaze_enabled and not presented_ids.is_empty():
		evidence.add_item(_t("appraisal.deck_basis"))
		ids.append({"presented_ids":presented_ids})
	for fact: Dictionary in dto.appraisal.evidence:
		evidence.add_item(_t(fact.text_key))
		ids.append(fact.evidence_id)
	# Prepared cards are local drafts. A changed source invalidates them before submission.
	var prepared: Variant = _offer_draft.get("evidence_id")
	for candidate: Dictionary in dto.appraisal.get("argument_candidates",[]):
		if prepared == candidate.argument:
			evidence.add_item(_t("appraisal.argument_prepared", {"value":_t(candidate.label_key)}))
			ids.append(candidate.argument)
	var selected: int = ids.find(prepared)
	evidence.select(1 if selected < 0 and _gaze_enabled and not presented_ids.is_empty() else maxi(0, selected))
	_offer_amount = amount
	_offer_evidence = evidence
	_offer_ids = ids.duplicate()
	_offer_visit = dto.customer.visit_id
	_label(body, _t("appraisal.argument_heading"))
	for candidate: Dictionary in dto.appraisal.get("argument_candidates",[]):
		var label: String = _t("appraisal.argument_prepared", {"value":_t(candidate.label_key)})
		_button(body, _t("appraisal.argument_prepare", {"value":_t(candidate.label_key), "count":str(candidate.evidence_ids.size())}), func() -> void:
			var index: int = ids.find(candidate.argument)
			if index < 0:
				evidence.add_item(label)
				ids.append(candidate.argument.duplicate(true))
				_offer_ids = ids.duplicate(true)
				index = ids.size()-1
			evidence.select(index), _locked() or not n.can_offer)
	_label(body, _t("wallet.balance", {"amount": str(dto.wallet.VKC), "currency": "VKC"}))
	_button(body, _t("ui.offer"), func() -> void:
		var chosen: Variant = ids[evidence.selected]
		var payload: Dictionary = {"amount":int(amount.value)}
		if chosen is Dictionary and chosen.has("presented_ids"):
			payload["presented_ids"] = chosen.presented_ids
		elif chosen is Dictionary:
			payload["argument"] = chosen
		else:
			payload["evidence_id"] = chosen
		_submit("make_offer",payload), _locked() or not n.can_offer or dto.wallet.VKC < 1)
	if n.can_confirm:
		_label(body, _t("ui.purchase_placement"))
		var offer_id: String = n.offers.back().offer_id
		_button(body, _t("ui.accept_trade"), func() -> void: _submit("confirm_purchase", {"offer_id": offer_id, "inventory": "player_stock", "x": 0, "y": 0, "rotated": false}), _locked() or int(n.offers.back().amount) > int(dto.wallet.VKC))
		if int(n.offers.back().amount) > int(dto.wallet.VKC):
			_label(body, _t("ui.insufficient_funds"))
	_button(body, _t("ui.decline"), func() -> void: _submit("decline_visit"), _locked() or not n.can_decline)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE):
		var focus: Control = get_viewport().gui_get_focus_owner()
		if not focus is LineEdit and not focus is TextEdit and _document.is_empty() and _can_toggle_gaze():
			get_viewport().set_input_as_handled()
			_toggle_gaze()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _document.is_empty():
		_open("")
		get_viewport().set_input_as_handled()
