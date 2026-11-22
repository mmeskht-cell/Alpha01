extends Control
## B1 single-counter host; no bespoke named-character dialogue scene.
const Seed = preload("res://src/content/alpha_b1_seed.gd")
const B2Seed = preload("res://src/content/alpha_b2_seed.gd")
const CardSeed = preload("res://src/content/alpha_b2_cards_seed.gd")
const CommissionSeed = preload("res://src/content/alpha_b2_commission_seed.gd")
const NamedCommissionSeed = preload("res://src/content/alpha_b2_named_commission_seed.gd")
const ServiceSeed = preload("res://src/content/alpha_b2_service_seed.gd")
const RecoverySeed = preload("res://src/content/alpha_b2_service_recovery_seed.gd")
const MultiServiceSeed = preload("res://src/content/alpha_b2_service_multi_seed.gd")
const B2_KO_PATH = "res://data/alpha_b2/ko.json"
const Session = preload("res://src/domain/game_session.gd")
const Alpha = preload("res://src/domain/alpha_shop_cycle.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const ThemeSource = preload("res://src/presentation/ui_theme.gd")
const KO_PATH = "res://data/alpha_b1/ko.json"
const SAVE_SLOT = "alpha_b1_profile_v3"
@export var save_directory_override: String = ""
@export var b2_mode: bool = false
@export var b2_interactive_mode: bool = false
@export var b2_commission_mode: bool = false
@export var b2_named_commission_mode: bool = false
@export var b2_service_mode: bool = false
@export var b2_recovery_mode: bool = false
@export var b2_multi_service_mode: bool = false
var session: RefCounted
var _repo: RefCounted
var _strings: Dictionary = {}
var _intro: bool = true
var _intro_page: int = 0
var _blocked: bool = false
var _message: String = ""
var _contact_focus: String = "" # UI-only selection; never persisted or billed.
var _b2_zoomed: bool = false # UI-only larger view of the already-loaded external item image.
var _b2_zoom_item: String = ""
var _b2_view_context: String = "" # UI-only visit/item identity.
var _b2_price_draft: String = "" # Not persisted or publicly offered.
var _b2_refresh_epoch: int = 0

func _ready() -> void:
	# The UI asset pipeline prepares an exact hash-pinned OFL CJK font.
	# The new alpha counter must inherit it too; Godot's default typeface
	# renders Korean as missing-glyph boxes even when mouse tests succeed.
	if not ThemeSource.apply_to(self):
		_blocked = true
		_message = "한국어 글꼴을 확인할 수 없어 화면을 시작할 수 없습니다."
		refresh()
		return
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(KO_PATH))
	if catalog is Dictionary and catalog.get("strings") is Dictionary:
		_strings = catalog.strings
	if b2_mode:
		var b2_locale: Variant = JSON.parse_string(FileAccess.get_file_as_string(B2_KO_PATH))
		if b2_locale is Dictionary and b2_locale.get("strings") is Dictionary:
			_strings.merge(b2_locale.strings, true)
	var source: Dictionary = MultiServiceSeed.content() if b2_multi_service_mode else (RecoverySeed.content() if b2_recovery_mode else (ServiceSeed.content() if b2_service_mode else (NamedCommissionSeed.content() if b2_named_commission_mode else (CommissionSeed.content() if b2_commission_mode else (CardSeed.content() if b2_interactive_mode else (B2Seed.content() if b2_mode else Seed.content()))))))
	if source.is_empty():
		_blocked = true
		_message = "B1 콘텐츠를 읽지 못했습니다."
	else:
		session = Session.new()
		if not session.initialize(source.defs, source.state, false, false, {}, source.alpha_profile):
			_blocked = true
			_message = "세션 초기화 오류: " + session.initialization_error()
		else:
			var location: String = save_directory_override if not save_directory_override.is_empty() else ("user://zt_rebuild/alpha_b2_service_multi" if b2_multi_service_mode else ("user://zt_rebuild/alpha_b2_service_recovery" if b2_recovery_mode else ("user://zt_rebuild/alpha_b2_service" if b2_service_mode else ("user://zt_rebuild/alpha_b2_named_commission" if b2_named_commission_mode else ("user://zt_rebuild/alpha_b2_commission" if b2_commission_mode else ("user://zt_rebuild/alpha_b2_cards" if b2_interactive_mode else ("user://zt_rebuild/alpha_b2" if b2_mode else "user://zt_rebuild/alpha_b1")))))))
			_repo = Repo.new(location)
			var loaded: Dictionary = _repo.load_session(session, _slot())
			if loaded.get("ok", false):
				_intro = false
			elif FileAccess.file_exists(location.path_join(_slot() + ".a.json")) or FileAccess.file_exists(location.path_join(_slot() + ".b.json")):
				_blocked = true
				_message = "기존 저장의 무결성이 확인되지 않아 새 게임으로 덮어쓰지 않습니다."
	refresh()

func _slot() -> String:
	return "alpha_b2_service_custody_multi_v3" if b2_multi_service_mode else ("alpha_b2_service_custody_recovery_v2" if b2_recovery_mode else ("alpha_b2_service_custody_pilot_v1" if b2_service_mode else ("alpha_b2_named_commission_parity_v1" if b2_named_commission_mode else ("alpha_b2_commission_pilot_v1" if b2_commission_mode else ("alpha_b2_cards_pilot_v1" if b2_interactive_mode else ("alpha_b2_trade_slice_v2" if b2_mode else SAVE_SLOT))))))

func _text(key: String) -> String:
	return str(_strings.get(key, key))

func _button(parent: Control, name: String, title: String, callback: Callable) -> Button:
	var control := Button.new()
	control.name = name
	control.text = title
	control.custom_minimum_size = Vector2(290, 50)
	control.pressed.connect(callback)
	parent.add_child(control)
	return control

func _actor_label(actor_id: String) -> String:
	var key: String = "alpha.named." + actor_id
	return _text(key) if _strings.has(key) else (_text("alpha.actor.regular") % actor_id)

## Read-only shop work surface beside the existing physical counter.
## Inventory and cash are taken from the same authoritative snapshot; never
## substitute a virtual showroom, mint stock, or expose NPC private evidence.
func _board_line(parent: VBoxContainer, name: String, value: String, heading: bool = false) -> Label:
	var label := Label.new()
	label.name = name
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 21 if heading else 17)
	parent.add_child(label)
	return label

func _add_b2_shop_board(panel: PanelContainer, view: Dictionary) -> void:
	var current: Dictionary = session.snapshot()
	var inset := MarginContainer.new()
	for side: String in ["left","right","top","bottom"]:
		inset.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(inset)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	inset.add_child(body)
	_board_line(body, "b2_board_title", _text("b2.board.title"), true)
	if view.phase == "CUSTOMER_ACTIVE" and not view.appraisal.is_empty():
		var jumps := HBoxContainer.new()
		jumps.name = "b2_quick_navigation"
		jumps.add_theme_constant_override("separation",4)
		body.add_child(jumps)
		for target: String in ["b2_inspection_sheet","b2_private_sheet","b2_price_sheet"]:
			var section: String = target
			var fast := _button(jumps,"b2_jump_" + section,_text("b2.nav." + section),
				func() -> void: _jump_b2_section(section))
			fast.custom_minimum_size = Vector2(84,36)
	var cash: Dictionary = current.wallets.get("player", {})
	_board_line(body, "b2_board_cash", _text("b2.board.cash") % [int(cash.get("VKC", 0)), int(cash.get("USD", 0))])
	body.add_child(HSeparator.new())
	# At night the chosen consensual contact belongs in the readable right
	# dossier, not in a clipped scroll row beneath unrelated action buttons.
	if view.phase == "EVENING_WORK" and not _contact_focus.is_empty():
		for contact: Dictionary in view.contacts:
			if contact.actor_id == _contact_focus and contact.callable:
				var preview := PanelContainer.new()
				preview.name = "alpha_contact_preview"
				body.add_child(preview)
				var detail := Label.new()
				detail.name = "alpha_contact_preview_text"
				detail.add_theme_font_size_override("font_size", 18)
				detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				detail.text = (_text("alpha.contacts.preview_title") % _actor_label(_contact_focus)) + "\n" + _text("alpha.contacts.preview_conditions")
				preview.add_child(detail)
				return
	var owned: Array = []
	var displayed: int = 0
	var reserved: int = 0
	for id: String in current.items:
		var item: Dictionary = current.items[id]
		if item.owner_id != "player" or item.custodian_id != "player" or item.status != "stock" or not item.parent_id.is_empty():
			continue
		owned.append(item)
		if id in view.displayed_items:
			displayed += 1
		if not str(item.reservation_id).is_empty():
			reserved += 1
	_board_line(body, "b2_board_stock", _text("b2.board.stock") % [owned.size(), displayed, reserved], true)
	var count: int = 0
	for item: Dictionary in owned:
		if count >= 4:
			break
		var location_key: String = "b2.board.reserved" if not str(item.reservation_id).is_empty() else ("b2.board.displayed" if item.inventory == "storefront_grid" else "b2.board.stored")
		_board_line(body, "b2_board_item_" + str(count), "• " + _text("b2.item." + str(item.def_id)) + " · " + _text(location_key))
		count += 1
	if owned.size() > count:
		_board_line(body, "b2_board_more", _text("b2.board.more") % (owned.size() - count))
	if owned.is_empty():
		_board_line(body, "b2_board_empty", _text("b2.board.empty"))
	body.add_child(HSeparator.new())
	var appraisal: Dictionary = view.appraisal
	if not appraisal.is_empty():
		var shown: int = 0
		for card: Dictionary in appraisal.cards:
			if card.selected:
				shown += 1
		_board_line(body, "b2_board_evidence", _text("b2.board.evidence") % [appraisal.cards.size(), shown], true)
		_board_line(body, "b2_board_offer_count", _text("b2.board.offers") % appraisal.offers.size())
	else:
		_board_line(body, "b2_board_waiting", _text("b2.board.waiting"))
	_board_line(body, "b2_board_caution", _text("b2.board.note"))

## Customer property is shown separately from owner stock, never silently
## counted as player-owned displayable inventory.
func _add_b2_service_actions(actions: VBoxContainer, v: Dictionary) -> void:
	for entry: Dictionary in v.services.entries:
		if v.phase == "CUSTOMER_ACTIVE" and (v.active.is_empty() or str(v.active.actor_id) != str(entry.actor_id)):
			continue
		var label := Label.new()
		label.name = "b2_service_status_" + str(entry.job_id)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = _text("b2.service.receipt") % [
			_text("b2.item." + str(entry.def_id)), int(entry.due_day),
			int(entry.fee.VKC), _text("b2.service.status." + str(entry.status))]
		if entry.status == "overdue_custody" and int(entry.recovery_day) > 0:
			label.text += "\n" + (_text("b2.service.recovery.note") % int(entry.recovery_day))
		actions.add_child(label)
		var job_id: String = str(entry.job_id)
		if entry.can_accept:
			_button(actions,"b2_service_accept",_text("b2.service.accept"),
				func() -> void: _submit("alpha_service_accept",{"job_id":job_id}))
			_button(actions,"b2_service_decline",_text("b2.service.decline"),
				func() -> void: _submit("alpha_service_decline",{"job_id":job_id}))
		if entry.can_repair:
			var item_id: String = str(entry.item_id)
			_button(actions,"b2_service_repair",_text("b2.service.repair"),
				func() -> void: _submit("alpha_service_repair",{"job_id":job_id,"item_id":item_id}))
		if entry.can_deliver:
			_button(actions,"b2_service_deliver",_text("b2.service.deliver"),
				func() -> void: _submit("alpha_service_deliver",{"job_id":job_id}))
		if entry.can_return:
			_button(actions,"b2_service_return_unpaid",_text("b2.service.return_unpaid"),
				func() -> void: _submit("alpha_service_return_unpaid",{"job_id":job_id}))

## NPC speech uses only accepted/declined price proposals that the actual
## visitor heard, and settled outcomes. Private inspection readings stay private.
func _b2_npc_line(view: Dictionary) -> String:
	var context: Dictionary = view.get("npc_context", {})
	if context.is_empty():
		return ""
	var challenges: Array = context.get("current_challenges",[])
	if not challenges.is_empty():
		var latest: Dictionary = challenges[challenges.size()-1]
		return _text("b2.npc.claim.challenged") % _text("b2.inspect." + str(latest.slot))
	var offer: Dictionary = context.get("current_offer", {})
	if not offer.is_empty():
		if str(offer.response) == "declined":
			if int(offer.disclosed_count) == 0:
				var known_slots: Array = offer.get("known_slots",[])
				if not known_slots.is_empty():
					var current_public: Array = offer.get("active_slots",[])
					var withdrawn: Array = offer.get("withdrawn_slots",[])
					if current_public.is_empty() and not withdrawn.is_empty():
						return _text("b2.npc.rebuttal.withdrawn") % [_text("b2.inspect." + str(withdrawn[0])), int(offer.amount), str(offer.currency)]
					if not current_public.is_empty():
						return _text("b2.npc.rebuttal.remembered") % [_text("b2.inspect." + str(current_public[0])), int(offer.amount), str(offer.currency)]
				return _text("b2.npc.rebuttal.no_evidence") % [int(offer.amount), str(offer.currency)]
			var public_slots: Array = offer.get("public_slots",[])
			if not public_slots.is_empty():
				return _text("b2.npc.rebuttal.evidence") % [_text("b2.inspect." + str(public_slots[0])), int(offer.amount), str(offer.currency)]
		var response_key: String = "b2.npc.offer." + str(offer.response)
		return (_text(response_key) % [int(offer.amount), str(offer.currency), int(offer.disclosed_count)]) if _strings.has(response_key) else ""
	var previous: Dictionary = context.get("prior", {})
	if previous.is_empty():
		return ""
	var last: Dictionary = previous.get("offer", {})
	if not last.is_empty():
		var outcome_key: String = "b2.npc.previous." + ("traded" if previous.outcome == "traded" else str(last.response))
		return (_text(outcome_key) % [int(last.amount), str(last.currency)]) if _strings.has(outcome_key) else ""
	if previous.outcome == "traded":
		return _text("b2.npc.previous.settled")
	if previous.outcome == "commission_delivered":
		return _text("b2.npc.previous.delivered")
	return ""

func _choose_evening_contact(actor_id: String) -> void:
	if _blocked or _intro or session == null:
		return
	var view: Dictionary = Alpha.view(session.snapshot())
	if view.phase != "EVENING_WORK":
		return
	for contact: Dictionary in view.contacts:
		if contact.actor_id == actor_id and contact.callable:
			_contact_focus = "" if _contact_focus == actor_id else actor_id
			refresh()
			if not _contact_focus.is_empty():
				call_deferred("_show_evening_contact_preview")
			return

## Navigation changes only the viewport, never a priced offer or appraisal.
func _jump_b2_section(target_name: String) -> void:
	# Wait until the navigation-button mouse event is fully processed before
	# repositioning the sibling ScrollContainer. The direct offset handles
	# layouts where ensure_control_visible alone left the scroll at zero.
	call_deferred("_jump_b2_section_apply",target_name)

func _jump_b2_section_apply(target_name: String) -> void:
	var scroller := find_child("alpha_card_scroll", true, false) as ScrollContainer
	var target := find_child(target_name, true, false) as Control
	if scroller != null and target != null:
		# The target is a panel in the left work pane. A relative global
		# offset works even when the ScrollContainer focus helper declines
		# to scroll a nested PanelContainer.
		var delta: float = target.get_global_rect().position.y - scroller.get_global_rect().position.y
		scroller.scroll_vertical = maxi(0,scroller.scroll_vertical + int(delta) - 8)

func _show_evening_contact_preview() -> void:
	# A rebuilt counter resets the scrolling position. Ensure the details
	# chosen with a real mouse click actually appear in the visible pane.
	var scroller := find_child("alpha_card_scroll", true, false) as ScrollContainer
	var detail := find_child("alpha_contact_preview", true, false) as Control
	if scroller != null and detail != null and detail.is_visible_in_tree() and scroller.is_ancestor_of(detail):
		scroller.ensure_control_visible(detail)

## Read-only conditions, sourced from an actual consensual contact. No
## phantom salvage stock, advance, fund transfer or dispatch command.
func _add_evening_contacts(actions: VBoxContainer, view: Dictionary) -> void:
	var heading := Label.new()
	heading.name = "alpha_contacts_heading"
	heading.text = _text("alpha.contacts.heading") + " · " + str(view.contacts.size())
	heading.add_theme_font_size_override("font_size", 22)
	actions.add_child(heading)
	if view.contacts.is_empty():
		var empty := Label.new()
		empty.name = "alpha_contacts"
		empty.text = _text("alpha.contacts.empty")
		actions.add_child(empty)
		return
	for contact: Dictionary in view.contacts:
		var actor_id: String = str(contact.actor_id)
		var status: String = _text("alpha.contacts.available" if contact.callable else "alpha.contacts.none")
		var entry: String = _actor_label(actor_id) + " · " + (_text("alpha.contacts.acquired") % int(contact.acquired_day)) + " · " + status
		var control: Button = _button(actions, "alpha_contact_" + actor_id, entry, func() -> void: _choose_evening_contact(actor_id))
		control.disabled = not bool(contact.callable)
		control.tooltip_text = _text("alpha.contacts.preview_hint")
	if _contact_focus.is_empty():
		var hint := Label.new()
		hint.name = "alpha_contacts"
		hint.text = _text("alpha.contacts.preview_hint")
		actions.add_child(hint)
		return
	if b2_interactive_mode:
		# The selected contact's real conditions are shown in the right dossier.
		return
	for contact: Dictionary in view.contacts:
		if contact.actor_id == _contact_focus and contact.callable:
			var panel := PanelContainer.new()
			panel.name = "alpha_contact_preview"
			actions.add_child(panel)
			var detail := Label.new()
			detail.name = "alpha_contact_preview_text"
			detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			detail.text = (_text("alpha.contacts.preview_title") % _actor_label(_contact_focus)) + "\n" + _text("alpha.contacts.preview_conditions")
			panel.add_child(detail)
			return

func intro_next() -> void:
	if not _intro or _blocked:
		return
	if _intro_page < 1:
		_intro_page += 1
	else:
		intro_skip()

func intro_skip() -> void:
	if _blocked:
		return
	_intro = false
	refresh()

func _submit(kind: String, payload: Dictionary = {}) -> void:
	if _intro or _blocked:
		return
	var c: Dictionary = {"action_id": "alpha_b1_" + str(session.snapshot().revision + 1),
		"expected_revision": session.snapshot().revision, "type": kind, "payload": payload}
	var result: Dictionary = session.execute(c)
	if not result.ok:
		_message = "입력 거절: " + str(result.error)
	else:
		var stored: Dictionary = _repo.save_session(session, _slot())
		_message = "" if stored.get("ok", false) else "저장에 실패했습니다: " + str(stored.get("error", "unknown"))
		if not stored.get("ok", false):
			_blocked = true
	refresh()

func _restore_b2_scroll(previous_y: int, epoch: int) -> void:
	# Rebuilding a counter replaces the old scroll node. Keep the customer's
	# work location when the visit and specimen did not change.
	await get_tree().process_frame
	if epoch != _b2_refresh_epoch or not is_inside_tree():
		return
	var scrolling := find_child("alpha_card_scroll",true,false) as ScrollContainer
	if scrolling != null:
		scrolling.scroll_vertical = previous_y

func refresh() -> void:
	var preserved_scroll: int = -1
	var context: String = ""
	if b2_interactive_mode and not _intro and not _blocked and session != null:
		var present: Dictionary = Alpha.view(session.snapshot())
		var active: Dictionary = present.get("active",{})
		var appraisal: Dictionary = present.get("appraisal",{})
		if str(present.get("phase","")) == "CUSTOMER_ACTIVE" and not active.is_empty() and not appraisal.is_empty():
			context = str(active.get("id","")) + "|" + str(appraisal.get("item_id",""))
	if not context.is_empty() and context == _b2_view_context:
		var prior_scroll := find_child("alpha_card_scroll",true,false) as ScrollContainer
		var prior_price := find_child("b2_price_input",true,false) as LineEdit
		if prior_scroll != null:
			preserved_scroll = prior_scroll.scroll_vertical
		if prior_price != null:
			_b2_price_draft = prior_price.text
	else:
		_b2_price_draft = ""
	_b2_view_context = context
	_b2_refresh_epoch += 1
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("#1B1E21")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 38)
	margin.add_theme_constant_override("margin_top", 25)
	margin.add_theme_constant_override("margin_right", 38)
	margin.add_theme_constant_override("margin_bottom", 25)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12 if b2_interactive_mode else 16)
	margin.add_child(outer)
	var title := Label.new()
	title.text = _text("alpha.heading")
	title.add_theme_font_size_override("font_size", 27 if b2_interactive_mode else 31)
	outer.add_child(title)
	if _blocked:
		var blocked := Label.new()
		blocked.text = _message
		outer.add_child(blocked)
		return
	if _intro:
		var intro := PanelContainer.new()
		outer.add_child(intro)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 18)
		intro.add_child(inner)
		var content := Label.new()
		content.name = "intro_subtitle"
		content.text = _text("alpha.intro." + str(_intro_page))
		content.add_theme_font_size_override("font_size", 27)
		content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inner.add_child(content)
		_button(inner, "intro_next", _text("alpha.intro.next" if _intro_page == 0 else "alpha.intro.start"), intro_next)
		_button(inner, "intro_skip", _text("alpha.intro.skip"), intro_skip)
		return
	var v: Dictionary = Alpha.view(session.snapshot())
	if v.phase != "EVENING_WORK":
		_contact_focus = ""
	var top := Label.new()
	top.name = "alpha_phase_label"
	top.text = "DAY %d · %s · 남은 방문 %d" % [int(v.day), _text("alpha.phase." + str(v.phase)), int(v.remaining)]
	top.add_theme_font_size_override("font_size", 23)
	outer.add_child(top)
	var counter := PanelContainer.new()
	counter.name = "alpha_counter"
	# Keep the NPC speech readable while reclaiming unused 720p vertical space
	# for the actual physical object. Other (legacy) profiles stay unchanged.
	counter.custom_minimum_size = Vector2(0, 112 if b2_interactive_mode else 210)
	outer.add_child(counter)
	var bubble := VBoxContainer.new()
	bubble.add_theme_constant_override("separation", 9 if b2_interactive_mode else 14)
	counter.add_child(bubble)
	var actor := Label.new()
	actor.name = "alpha_actor"
	actor.add_theme_font_size_override("font_size", 25 if b2_interactive_mode else 27)
	var speech := Label.new()
	speech.name = "alpha_speech"
	speech.add_theme_font_size_override("font_size", 21 if b2_interactive_mode else 22)
	speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.add_child(actor)
	bubble.add_child(speech)
	var row: Dictionary = v.active
	if row.is_empty():
		actor.text = "크라벤스크 · 상점 카운터"
		speech.text = _text("alpha.evening.note") if v.phase == "EVENING_WORK" else _text("alpha.b1.notice")
	else:
		actor.text = _actor_label(str(row.actor_id))
		var say: String = "alpha.say.enter" if v.phase == "CUSTOMER_ENTER" else ("alpha.say.exit" if v.phase == "CUSTOMER_EXIT" else row.purpose_key)
		speech.text = _text(say)
		if b2_mode and v.phase == "CUSTOMER_ACTIVE":
			var public_reply: String = _b2_npc_line(v)
			if not public_reply.is_empty():
				speech.text = public_reply
			# Named suppliers explain their actual existing contract instead
			# of repeating an empty generic line. Their specialized RAD-1 payment
			# authority remains untouched and is never called a normal item order.
			for contract_id: String in v.contracts:
				var terms: Dictionary = v.contracts[contract_id]
				if str(terms.supplier) == str(row.actor_id) and terms.can_accept:
					speech.text = _text("b2.npc.named.supplier") % [int(terms.price.VKC), int(terms.due_day)]
					break
			# The current customer's explicit request takes precedence over an
			# older conversation; neither path modifies the save-bound seed.
			if b2_commission_mode:
				for entry: Dictionary in v.commissions.entries:
					if entry.actor_id != row.actor_id:
						continue
					if entry.can_accept:
						speech.text = _text(str(entry.text_key))
						break
					if entry.can_deliver:
						speech.text = _text("b2.npc.commission.pickup") % _text("b2.item." + str(entry.target_def_id))
						break
			if b2_service_mode:
				for entry: Dictionary in v.services.entries:
					if str(entry.actor_id) == str(row.actor_id):
						if entry.can_accept:
							speech.text = _text("b2.service.offer")
						elif entry.can_deliver:
							speech.text = (_text("b2.service.recovery.pickup") if entry.status == "overdue_custody" else _text("b2.service.pickup")) % _text("b2.item." + str(entry.def_id))
						elif entry.can_return and entry.status == "overdue_custody":
							speech.text = _text("b2.service.recovery.unpaid")
						elif entry.can_return:
							speech.text = _text("b2.service.unfinished")
						break
		elif b2_mode and v.phase == "CUSTOMER_EXIT":
			var completed: String = str(v.npc_context.get("current_outcome", ""))
			if completed == "traded":
				speech.text = _text("b2.npc.exit.traded")
			elif completed == "commission_delivered":
				speech.text = _text("b2.npc.exit.delivered")
			elif completed == "service_delivered":
				speech.text = _text("b2.npc.exit.serviced")
	var actions := VBoxContainer.new()
	actions.name = "alpha_actions"
	if b2_interactive_mode:
		var work_area := HBoxContainer.new()
		work_area.name = "alpha_work_area"
		work_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
		work_area.add_theme_constant_override("separation", 16)
		outer.add_child(work_area)
		var scrolling := ScrollContainer.new()
		scrolling.name = "alpha_card_scroll"
		scrolling.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scrolling.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scrolling.custom_minimum_size = Vector2(430, 180)
		work_area.add_child(scrolling)
		actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_theme_constant_override("separation", 8)
		scrolling.add_child(actions)
		var board := PanelContainer.new()
		board.name = "alpha_shop_board"
		board.custom_minimum_size = Vector2(320, 0)
		board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		work_area.add_child(board)
		_add_b2_shop_board(board, v)
	else:
		outer.add_child(actions)
	match str(v.phase):
		"DAY_PREP":
			_button(actions, "alpha_open", _text("alpha.button.open"), func() -> void: _submit("alpha_open"))
		"OPEN_IDLE":
			if b2_mode:
				_add_b2_display_action(actions, v)
			if b2_commission_mode:
				_add_b2_commission_actions(actions, v)
			if b2_service_mode:
				_add_b2_service_actions(actions, v)
			if int(v.remaining) > 0:
				_button(actions, "alpha_next_customer", _text("alpha.button.next"), func() -> void: _submit("alpha_next_customer"))
			_button(actions, "alpha_close", _text("alpha.button.close"), func() -> void: _submit("alpha_close"))
		"CUSTOMER_ENTER":
			_button(actions, "alpha_ack_entry", _text("alpha.button.enter"), func() -> void: _submit("alpha_ack_entry"))
		"CUSTOMER_ACTIVE":
			if b2_interactive_mode:
				_add_b2_card_actions(actions, v)
			elif b2_mode:
				_add_b2_trade_action(actions, v)
			_add_contract_actions(actions, v)
			if b2_commission_mode:
				_add_b2_commission_actions(actions, v)
			if b2_service_mode:
				_add_b2_service_actions(actions, v)
			if bool(v.can_exchange):
				_button(actions, "alpha_exchange_contact", _text("alpha.button.exchange"), func() -> void: _submit("alpha_exchange_contact", {"actor_id": row.actor_id, "accepted": true}))
			_button(actions, "alpha_finish_customer", _text("alpha.button.leave"), func() -> void: _submit("alpha_finish_customer"))
		"CUSTOMER_EXIT":
			_button(actions, "alpha_ack_exit", _text("alpha.button.exit"), func() -> void: _submit("alpha_ack_exit"))
		"CLOSE_SETTLE":
			_add_contract_actions(actions, v)
			_button(actions, "alpha_settle", _text("alpha.button.settle"), func() -> void: _submit("alpha_settle"))
		"EVENING_WORK":
			if b2_mode:
				_add_b2_display_action(actions, v)
			_add_contract_actions(actions, v)
			if b2_commission_mode:
				_add_b2_commission_actions(actions, v)
			if b2_service_mode:
				_add_b2_service_actions(actions, v)
			_add_evening_contacts(actions, v)
			_button(actions, "alpha_next_day", _text("alpha.button.evening"), func() -> void: _submit("alpha_next_day"))
		"NEXT_DAY":
			_button(actions, "alpha_prepare_day", _text("alpha.button.prepare"), func() -> void: _submit("alpha_prepare_day"))
		"COMPLETE":
			speech.text = _text("alpha.complete")
	for news: Dictionary in v.news:
		var notice := Label.new()
		notice.name = "alpha_news_" + str(news.id)
		notice.text = _text("alpha.news." + str(news.text_key))
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		outer.add_child(notice)
	if not _message.is_empty():
		var message := Label.new()
		message.text = _message
		outer.add_child(message)
	if preserved_scroll >= 0:
		call_deferred("_restore_b2_scroll",preserved_scroll,_b2_refresh_epoch)


## A bounded B2 first trade slice, using the physical inventory grid rather
## than an unlimited virtual market entry. No appraisal/commission completion.
func _add_b2_display_action(actions: VBoxContainer, v: Dictionary) -> void:
	var stock: Dictionary = session.snapshot()
	var label := Label.new()
	label.name = "alpha_b2_shelf"
	var displayed_names: PackedStringArray = []
	for displayed_id: String in v.displayed_items:
		if stock.items.has(displayed_id):
			displayed_names.append(_text("b2.item." + str(stock.items[displayed_id].def_id)))
	label.text = _text("b2.shelf") + ": " + ", ".join(displayed_names)
	actions.add_child(label)
	for item_id: String in stock.items:
		var item: Dictionary = stock.items[item_id]
		if item.owner_id == "player" and item.custodian_id == "player" and item.inventory == "player_stock" and item.status == "stock" and not item.protected and item.reservation_id.is_empty() and item.parent_id.is_empty():
			_button(actions, "b2_display_" + item_id, _text("b2.display") + " · " + _text("b2.item." + str(item.def_id)),
				func() -> void: _submit("alpha_display", {"item_id": item_id, "x": 0, "y": 0, "rotated": false}))
			break

func _add_b2_trade_action(actions: VBoxContainer, v: Dictionary) -> void:
	var visit_id: String = str(v.active.get("id", ""))
	var current: Dictionary = session.snapshot()
	if not current.visits.has(visit_id):
		return
	var visit: Dictionary = current.visits[visit_id]
	if visit.scope.completed or visit.prices.is_empty():
		return
	var item_id: String = str(visit.prices.keys()[0])
	var ask: Dictionary = visit.prices[item_id]
	if not current.items.has(item_id):
		return
	var currency: String = "VKC" if int(ask.VKC) > 0 else "USD"
	var amount: int = int(ask[currency])
	var buying: bool = visit.buyer == "player"
	if not buying and (item_id not in v.displayed_items or current.items[item_id].inventory != "storefront_grid"):
		var note := Label.new()
		note.text = _text("b2.not_listed")
		actions.add_child(note)
		return
	var payload: Dictionary = {
		"visit_id": visit_id, "item_id": item_id,
		"seller": visit.seller, "buyer": visit.buyer,
		"currency": currency, "amount": amount,
		"inventory": "player_stock" if buying else str(visit.buyer) + "_grid",
		"x": 0 if buying else 5, "y": 0 if buying else 4, "rotated": false
	}
	_button(actions, "b2_trade", (_text("b2.buy") if buying else _text("b2.sell")) + " · " + str(amount) + " " + currency,
		func() -> void: _submit("alpha_trade", payload))


## Contract actions are short responses in the same counter, never an
## unrelated quest/options window. Money moves only after explicit pay click.
func _add_contract_actions(actions: VBoxContainer, v: Dictionary) -> void:
	for id: String in v.contracts:
		var offer: Dictionary = v.contracts[id]
		# Other characters' contracts belong in the quiet shop management
		# phases, not in the currently speaking customer's counter actions.
		if v.phase == "CUSTOMER_ACTIVE" and (v.active.is_empty() or str(v.active.actor_id) != str(offer.supplier)):
			continue
		var note := Label.new()
		note.name = "alpha_contract_" + id
		# The internal contract ID belongs in authority/receipts, not player prose.
		note.text = _text("alpha.contract.header") + " · " + _text("alpha.contract.status." + str(offer.status)) + " · " + str(offer.price.VKC) + " VKC / D" + str(offer.due_day)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		actions.add_child(note)
		if offer.can_accept:
			_button(actions, "alpha_contract_accept", _text("alpha.contract.accept"),
				func() -> void: _submit("alpha_contract_accept", {"contract_id": id}))
			_button(actions, "alpha_contract_decline", _text("alpha.contract.decline"),
				func() -> void: _submit("alpha_contract_decline", {"contract_id": id}))
		if offer.can_pay:
			_button(actions, "alpha_contract_pay", _text("alpha.contract.pay"),
				func() -> void: _submit("alpha_contract_pay", {"contract_id": id}))
		if offer.can_extend:
			_button(actions, "alpha_contract_extend", _text("alpha.contract.extend"),
				func() -> void: _submit("alpha_contract_extend", {"contract_id": id}))


## Same counter: actual item, inspectable facts, private card choice and one
## customer-facing price proposal. No separate modal or automatic price gains.
## One physical counter: observed facts are PRIVATE until the player
## intentionally selects them and makes a public offer. Panels only organize
## existing click/keyboard commands; no new authority or auto-disclosure.
func _b2_work_section(actions: VBoxContainer, id: String, heading: String, note: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = id
	actions.add_child(panel)
	var pad := MarginContainer.new()
	for side: String in ["left","right","top","bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(pad)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	pad.add_child(body)
	var title := Label.new()
	title.name = id + "_title"
	title.text = heading
	title.add_theme_font_size_override("font_size", 20)
	body.add_child(title)
	var hint := Label.new()
	hint.text = note
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 15)
	body.add_child(hint)
	return body

func _add_b2_card_actions(actions: VBoxContainer, v: Dictionary) -> void:
	var a: Dictionary = v.appraisal
	if a.is_empty():
		# An accepted commission, existing RAD-1 contract or entrusted
		# repair item is not a shelf sale; don't show a false "no item" warning.
		if not v.active.is_empty():
			for contract_id: String in v.contracts:
				if str(v.contracts[contract_id].supplier) == str(v.active.actor_id):
					return
			for entry: Dictionary in v.commissions.entries:
				if str(entry.actor_id) == str(v.active.actor_id):
					return
			for job: Dictionary in v.services.entries:
				if str(job.actor_id) == str(v.active.actor_id):
					return
		var unavailable := Label.new()
		unavailable.text = _text("b2.no_eligible_item")
		actions.add_child(unavailable)
		return
	var item := Label.new()
	item.name = "b2_current_item"
	item.text = _text("b2.we_buy" if a.we_buy else "b2.we_sell") + " · " + _text("b2.item." + str(a.def_id))
	item.add_theme_font_size_override("font_size", 20)
	actions.add_child(item)
	var direction := Label.new()
	direction.name = "b2_card_direction"
	direction.text = _text("b2.offer.direction.buy" if a.we_buy else "b2.offer.direction.sell")
	direction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(direction)
	if _b2_zoom_item != str(a.item_id):
		_b2_zoom_item = str(a.item_id)
		_b2_zoomed = false
	for claim: Dictionary in a.customer_claims:
		var customer_words := Label.new()
		customer_words.name = "b2_customer_claim"
		customer_words.text = _text("b2.evidence.customer_claim") + " · " + _text(str(claim.text_key))
		customer_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		actions.add_child(customer_words)
		if str(claim.check_status) != "not_testable":
			var verification := Label.new()
			verification.name = "b2_claim_status_" + str(claim.claim_key)
			verification.text = _text("b2.claim.status." + str(claim.check_status))
			verification.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			actions.add_child(verification)
			if bool(claim.can_challenge):
				var statement_id: String = str(claim.claim_key)
				_button(actions,"b2_claim_challenge_" + statement_id,_text("b2.claim.challenge"),
					func() -> void: _submit("alpha_claim_challenge",{"claim_key":statement_id}))
			elif bool(claim.challenged):
				var cited := Label.new()
				cited.name = "b2_claim_public_challenge"
				cited.text = _text("b2.claim.challenged")
				actions.add_child(cited)
	var inspect := _b2_work_section(actions,"b2_inspection_sheet",_text("b2.sheet.inspect.title"),_text("b2.sheet.inspect.note"))
	if a.tools.is_empty():
		var done := Label.new()
		done.text = _text("b2.sheet.inspect.done")
		inspect.add_child(done)
	# A single inspectable item surface: each marked hotspot invokes the
	# existing source-bound inspection command. No result is disclosed by a
	# click; the physical card must still be deliberately selected later.
	var surface := PanelContainer.new()
	surface.name = "b2_item_surface"
	surface.custom_minimum_size = Vector2(0,152)
	inspect.add_child(surface)
	var surface_inner := VBoxContainer.new()
	surface_inner.add_theme_constant_override("separation",6)
	surface.add_child(surface_inner)
	var object_name := Label.new()
	object_name.name = "b2_item_surface_title"
	object_name.text = "▣  " + _text("b2.item." + str(a.def_id))
	object_name.add_theme_font_size_override("font_size",25)
	surface_inner.add_child(object_name)
	var instruction := Label.new()
	instruction.text = _text("b2.inspect.surface.hint")
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	surface_inner.add_child(instruction)
	# Art shows only the generic external silhouette, never private readings,
	# hidden condition or counterparty acceptance thresholds.
	var preview_assets: Dictionary = {
		"portable_radio":"res://assets/art/items/radio_face_probe_a.svg",
		"fictional_watch_p2":"res://assets/art/items/watch_wat02_native_pilot.svg",
		"battery":"res://assets/art/items/battery_counter_pilot.svg",
		"demo_tool":"res://assets/art/items/tool_counter_pilot.svg",
		"demo_hygiene":"res://assets/art/items/hygiene_counter_pilot.svg",
		"demo_electronics":"res://assets/art/items/electronics_counter_pilot.svg",
		"fictional_gear":"res://assets/art/items/fictional_gear_pilot.svg",
		"demo_service_10":"res://assets/art/items/fictional_gear_pilot.svg",
		"demo_service_5":"res://assets/art/items/fictional_gear_pilot.svg"
	}
	var preview_path: String = str(preview_assets.get(str(a.def_id), ""))
	if not preview_path.is_empty() and ResourceLoader.exists(preview_path):
		var thumbnail := TextureRect.new()
		thumbnail.name = "b2_item_art"
		thumbnail.texture = ResourceLoader.load(preview_path) as Texture2D
		thumbnail.custom_minimum_size = Vector2(0,260 if _b2_zoomed else 144)
		thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		surface_inner.add_child(thumbnail)
		# The item, not text-heavy inspection instructions, occupies the first
		# viewport. All actual tools remain within the same scrollable surface.
		surface_inner.move_child(thumbnail,0)
		var zoom_button := _button(surface_inner,"b2_zoom_toggle",_text("b2.inspect.zoom.out" if _b2_zoomed else "b2.inspect.zoom.in"),
			func() -> void:
				_b2_zoomed = not _b2_zoomed
				refresh()
		)
		zoom_button.custom_minimum_size = Vector2(150,36)
	var hotspots := GridContainer.new()
	hotspots.name = "b2_item_hotspots"
	hotspots.columns = 2
	surface_inner.add_child(hotspots)
	for tool: Dictionary in a.tools:
		var slot: String = str(tool.id)
		var zone: String = "operation" if slot.contains("function") else ("condition" if slot.contains("condition") else ("markings" if slot in ["identity","casing_detail","batch_detail"] else "surface"))
		var label: String = _text("b2.inspect.surface." + zone) + " · " + _text(str(tool.text_key))
		var marker := _button(hotspots,"b2_inspect_" + slot,label,
			func() -> void: _submit("alpha_inspect",{"slot":slot}))
		marker.custom_minimum_size = Vector2(180,44)
		marker.tooltip_text = _text(str(tool.text_key))
	# Guesses are entirely optional and deliberately separate from inspected
	# fact cards. Guessing never presents a fact or changes negotiation terms.
	for guess: Dictionary in a.hypotheses:
		var slot: String = str(guess.slot)
		var current_guess: String = str(guess.judgment)
		var guess_status := Label.new()
		guess_status.name = "b2_hypothesis_status_" + slot
		guess_status.text = _text("b2.evidence.private_guess") + " · " + _text("b2.inspect." + slot) + " · " + _text("b2.hypothesis." + current_guess)
		guess_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inspect.add_child(guess_status)
		var options := HBoxContainer.new()
		inspect.add_child(options)
		for value: String in ["serviceable","inoperable"]:
			var judgment: String = value
			var choice := _button(options,"b2_guess_" + slot + "_" + judgment,_text("b2.hypothesis.choose") + " · " + _text("b2.value." + judgment),
				func() -> void: _submit("alpha_hypothesis",{"slot":slot,"judgment":judgment}))
			choice.disabled = current_guess == judgment
			choice.custom_minimum_size = Vector2(130,42)
		if current_guess != "unknown":
			_button(inspect,"b2_guess_clear_" + slot,_text("b2.hypothesis.clear"),
				func() -> void: _submit("alpha_hypothesis",{"slot":slot,"judgment":"unknown"}))
	var sheet := _b2_work_section(actions,"b2_private_sheet",_text("b2.sheet.private.title"),_text("b2.sheet.private.note"))
	if a.cards.is_empty():
		var empty := Label.new()
		empty.text = _text("b2.sheet.private.empty")
		sheet.add_child(empty)
	for card: Dictionary in a.cards:
		var slot: String = str(card.slot)
		var selected: bool = bool(card.selected)
		var plain_value: String = str(card.value)
		var value_key: String = "b2.value." + plain_value
		var visible_value: String = _text(value_key) if _strings.has(value_key) else plain_value
		var card_label: String = ("☑ " if selected else "□ ") + _text("b2.evidence.verified_fact") + " · " + _text(str(card.text_key)) + " · " + visible_value
		if str(card.shop_effect) in ["helps","hurts"]:
			card_label += " · " + _text("b2.value.shop." + str(card.shop_effect))
		# A deselected card only changes the NEXT proposal. Previously
		# disclosed information cannot be put back into a private drawer.
		if bool(card.ever_disclosed):
			card_label += " · " + _text("b2.card.already_public")
		elif selected:
			card_label += " · " + _text("b2.card.will_disclose")
		_button(sheet,"b2_card_" + slot,card_label,
			func() -> void: _submit("alpha_card_toggle",{"slot":slot,"selected":not selected}))
		if bool(card.ever_disclosed):
			if bool(card.public_active):
				_button(sheet,"b2_statement_retract_" + slot,_text("b2.statement.withdraw") + " · " + _text(str(card.text_key)),
					func() -> void: _submit("alpha_statement_retract",{"slot":slot}))
			else:
				_button(sheet,"b2_statement_reaffirm_" + slot,_text("b2.statement.reaffirm") + " · " + _text(str(card.text_key)),
					func() -> void: _submit("alpha_statement_reaffirm",{"slot":slot}))
	var bargain := _b2_work_section(actions,"b2_price_sheet",_text("b2.sheet.offer.title"),_text("b2.sheet.offer.note"))
	var promise_note := Label.new()
	promise_note.name = "b2_no_quality_promise"
	promise_note.text = _text("b2.evidence.no_promise")
	promise_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bargain.add_child(promise_note)
	for statement: Dictionary in a.statements:
		var amendment := Label.new()
		amendment.name = "b2_statement_history_" + str(statement.action_id)
		amendment.text = _text("b2.statement." + str(statement.kind)) + " · " + _text("b2.inspect." + str(statement.slot))
		amendment.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bargain.add_child(amendment)
	for offer: Dictionary in a.offers:
		var response := Label.new()
		response.name = "b2_last_response"
		response.text = _text("b2.offer." + str(offer.response)) + " · " + str(offer.amount) + " " + str(offer.currency) + " · " + (_text("b2.sheet.offer.revealed") % offer.public_cards.size())
		response.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bargain.add_child(response)
		if not offer.public_cards.is_empty():
			var disclosed := Label.new()
			disclosed.name = "b2_offer_public_receipt"
			disclosed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var public_details: PackedStringArray = []
			for fact: Dictionary in offer.public_cards:
				public_details.append(_text("b2.inspect." + str(fact.slot)))
			disclosed.text = _text("b2.offer.history.title") + " · " + ", ".join(public_details)
			bargain.add_child(disclosed)
	if not a.accepted.is_empty():
		var amount: int = int(a.accepted.amount)
		var visit_id: String = str(v.active.id)
		var current: Dictionary = session.snapshot()
		var terms: Dictionary = current.visits[visit_id]
		var item_id: String = str(a.item_id)
		var buying: bool = terms.buyer == "player"
		var payload: Dictionary = {
			"visit_id": visit_id,"item_id":item_id,"seller":terms.seller,
			"buyer":terms.buyer,"currency":a.accepted.currency,"amount":amount,
			"inventory":"player_stock" if buying else str(terms.buyer) + "_grid",
			"x":0 if buying else 5,"y":0 if buying else 4,"rotated":false
		}
		_button(bargain,"b2_trade",_text("b2.trade.confirm") + " · " + str(amount) + " " + str(a.accepted.currency),
			func() -> void: _submit("alpha_trade",payload))
		return
	var current: Dictionary = session.snapshot()
	var active: Dictionary = current.visits[str(v.active.id)]
	var price: Dictionary = active.prices[str(a.item_id)]
	var currency: String = "VKC" if int(price.VKC) > 0 else "USD"
	var price_entry := LineEdit.new()
	price_entry.name = "b2_price_input"
	price_entry.text = _b2_price_draft if not _b2_price_draft.is_empty() else str(price[currency])
	price_entry.placeholder_text = _text("b2.price.placeholder")
	price_entry.custom_minimum_size = Vector2(240, 42)
	bargain.add_child(price_entry)
	_button(bargain,"b2_offer",_text("b2.offer.submit"),
		func() -> void:
			if price_entry.text.is_valid_int() and int(price_entry.text) > 0:
				_submit("alpha_price_offer",{"amount":int(price_entry.text)})
			else:
				_message = _text("b2.price.invalid")
				refresh()
	)

## Requests live on the same counter and are recorded as one bounded ledger
## line. Reservations only name real, already purchased player-owned items.
func _add_b2_commission_actions(actions: VBoxContainer, v: Dictionary) -> void:
	for entry: Dictionary in v.commissions.entries:
		# A previous customer's request must not appear in a different
		# visitor's dialogue. In the idle/evening shop, show owned obligations.
		if v.phase == "CUSTOMER_ACTIVE" and (v.active.is_empty() or str(v.active.actor_id) != str(entry.actor_id)):
			continue
		var label := Label.new()
		label.name = "b2_commission_status_" + str(entry.request_id)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var currency: String = "VKC" if int(entry.price.VKC) > 0 else "USD"
		var amount: int = int(entry.price[currency])
		if v.phase == "CUSTOMER_ACTIVE" and not v.active.is_empty() and str(v.active.actor_id) == str(entry.actor_id):
			# The customer already speaks the request; a short terms line avoids
			# repeating their full sentence in the offer's paperwork.
			label.text = _text("b2.commission.current_terms") % [int(entry.due_day), amount, currency, _text("b2.commission.status." + str(entry.status))]
		else:
			label.text = _text(str(entry.text_key)) + " · D" + str(int(entry.due_day)) + " · " + str(amount) + " " + currency + " · " + _text("b2.commission.status." + str(entry.status))
		actions.add_child(label)
		var request_id: String = str(entry.request_id)
		if entry.can_accept:
			_button(actions,"b2_commission_accept",_text("b2.commission.accept"),
				func() -> void: _submit("alpha_commission_accept",{"request_id":request_id}))
			_button(actions,"b2_commission_decline",_text("b2.commission.decline"),
				func() -> void: _submit("alpha_commission_decline",{"request_id":request_id}))
		for good_id: String in entry.reserve_options:
			var current: Dictionary = session.snapshot()
			var label_key: String = "b2.item." + str(current.items[good_id].def_id)
			_button(actions,"b2_commission_reserve_" + good_id,_text("b2.commission.reserve") + " · " + _text(label_key),
				func() -> void: _submit("alpha_commission_reserve",{"request_id":request_id,"item_id":good_id}))
		if entry.can_deliver:
			_button(actions,"b2_commission_deliver",_text("b2.commission.deliver"),
				func() -> void: _submit("alpha_commission_deliver",{"request_id":request_id}))
		if entry.can_cancel and v.phase in ["OPEN_IDLE","EVENING_WORK"]:
			_button(actions,"b2_commission_cancel",_text("b2.commission.cancel"),
				func() -> void: _submit("alpha_commission_cancel",{"request_id":request_id}))
