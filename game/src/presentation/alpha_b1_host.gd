extends Control
## B1 single-counter host; no bespoke named-character dialogue scene.
const Seed = preload("res://src/content/alpha_b1_seed.gd")
const B2Seed = preload("res://src/content/alpha_b2_seed.gd")
const CardSeed = preload("res://src/content/alpha_b2_cards_seed.gd")
const CommissionSeed = preload("res://src/content/alpha_b2_commission_seed.gd")
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
var session: RefCounted
var _repo: RefCounted
var _strings: Dictionary = {}
var _intro: bool = true
var _intro_page: int = 0
var _blocked: bool = false
var _message: String = ""
var _contact_focus: String = "" # UI-only selection; never persisted or billed.

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
	var source: Dictionary = CommissionSeed.content() if b2_commission_mode else (CardSeed.content() if b2_interactive_mode else (B2Seed.content() if b2_mode else Seed.content()))
	if source.is_empty():
		_blocked = true
		_message = "B1 콘텐츠를 읽지 못했습니다."
	else:
		session = Session.new()
		if not session.initialize(source.defs, source.state, false, false, {}, source.alpha_profile):
			_blocked = true
			_message = "세션 초기화 오류: " + session.initialization_error()
		else:
			var location: String = save_directory_override if not save_directory_override.is_empty() else ("user://zt_rebuild/alpha_b2_commission" if b2_commission_mode else ("user://zt_rebuild/alpha_b2_cards" if b2_interactive_mode else ("user://zt_rebuild/alpha_b2" if b2_mode else "user://zt_rebuild/alpha_b1")))
			_repo = Repo.new(location)
			var loaded: Dictionary = _repo.load_session(session, _slot())
			if loaded.get("ok", false):
				_intro = false
			elif FileAccess.file_exists(location.path_join(_slot() + ".a.json")) or FileAccess.file_exists(location.path_join(_slot() + ".b.json")):
				_blocked = true
				_message = "기존 저장의 무결성이 확인되지 않아 새 게임으로 덮어쓰지 않습니다."
	refresh()

func _slot() -> String:
	return "alpha_b2_commission_pilot_v1" if b2_commission_mode else ("alpha_b2_cards_pilot_v1" if b2_interactive_mode else ("alpha_b2_trade_slice_v2" if b2_mode else SAVE_SLOT))

func _text(key: String) -> String:
	return str(_strings.get(key, key))

func _button(parent: VBoxContainer, name: String, title: String, callback: Callable) -> Button:
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

## NPC speech uses only accepted/declined price proposals that the actual
## visitor heard, and settled outcomes. Private inspection readings stay private.
func _b2_npc_line(view: Dictionary) -> String:
	var context: Dictionary = view.get("npc_context", {})
	if context.is_empty():
		return ""
	var offer: Dictionary = context.get("current_offer", {})
	if not offer.is_empty():
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

func _show_evening_contact_preview() -> void:
	# A rebuilt counter resets the scrolling position. Ensure the details
	# chosen with a real mouse click actually appear in the visible pane.
	var scroller := find_child("alpha_card_scroll", true, false) as ScrollContainer
	var detail := find_child("alpha_contact_preview", true, false) as Control
	if scroller != null and detail != null and detail.is_visible_in_tree():
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

func refresh() -> void:
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
	outer.add_theme_constant_override("separation", 16)
	margin.add_child(outer)
	var title := Label.new()
	title.text = _text("alpha.heading")
	title.add_theme_font_size_override("font_size", 31)
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
	counter.custom_minimum_size = Vector2(0, 210)
	outer.add_child(counter)
	var bubble := VBoxContainer.new()
	bubble.add_theme_constant_override("separation", 14)
	counter.add_child(bubble)
	var actor := Label.new()
	actor.name = "alpha_actor"
	actor.add_theme_font_size_override("font_size", 27)
	var speech := Label.new()
	speech.name = "alpha_speech"
	speech.add_theme_font_size_override("font_size", 22)
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
			# The current customer's explicit request takes precedence over an
			# older conversation; neither path modifies the save-bound seed.
			if b2_commission_mode:
				for entry: Dictionary in v.commissions.entries:
					if entry.actor_id == row.actor_id and entry.can_accept:
						speech.text = _text(str(entry.text_key))
						break
		elif b2_mode and v.phase == "CUSTOMER_EXIT":
			var completed: String = str(v.npc_context.get("current_outcome", ""))
			if completed == "traded":
				speech.text = _text("b2.npc.exit.traded")
			elif completed == "commission_delivered":
				speech.text = _text("b2.npc.exit.delivered")
	var actions := VBoxContainer.new()
	actions.name = "alpha_actions"
	if b2_interactive_mode:
		var scrolling := ScrollContainer.new()
		scrolling.name = "alpha_card_scroll"
		scrolling.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scrolling.custom_minimum_size = Vector2(0, 190)
		outer.add_child(scrolling)
		scrolling.add_child(actions)
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
		note.text = _text("alpha.contract.header") + " · " + str(id) + " · " + _text("alpha.contract.status." + str(offer.status)) + " · " + str(offer.price.VKC) + " VKC / D" + str(offer.due_day)
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
func _add_b2_card_actions(actions: VBoxContainer, v: Dictionary) -> void:
	var a: Dictionary = v.appraisal
	if a.is_empty():
		var unavailable := Label.new()
		unavailable.text = _text("b2.no_eligible_item")
		actions.add_child(unavailable)
		return
	var item := Label.new()
	item.name = "b2_current_item"
	item.text = _text("b2.we_buy" if a.we_buy else "b2.we_sell") + " · " + _text("b2.item." + str(a.def_id))
	item.add_theme_font_size_override("font_size", 20)
	actions.add_child(item)
	var help := Label.new()
	help.text = _text("b2.inspect.hint")
	actions.add_child(help)
	for tool: Dictionary in a.tools:
		var slot: String = str(tool.id)
		_button(actions,"b2_inspect_" + slot,_text("b2.inspect.action") + " · " + _text(str(tool.text_key)),
			func() -> void: _submit("alpha_inspect",{"slot":slot}))
	for card: Dictionary in a.cards:
		var slot: String = str(card.slot)
		var selected: bool = bool(card.selected)
		var control_name: String = "b2_card_" + slot
		_button(actions,control_name,("☑ " if selected else "□ ") + _text(str(card.text_key)) + " · " + str(card.value),
			func() -> void: _submit("alpha_card_toggle",{"slot":slot,"selected":not selected}))
	for offer: Dictionary in a.offers:
		var speech := Label.new()
		speech.name = "b2_last_response"
		speech.text = _text("b2.offer." + str(offer.response)) + " · " + str(offer.amount) + " " + str(offer.currency)
		actions.add_child(speech)
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
		_button(actions,"b2_trade",_text("b2.trade.confirm") + " · " + str(amount) + " " + str(a.accepted.currency),
			func() -> void: _submit("alpha_trade",payload))
		return
	var current: Dictionary = session.snapshot()
	var active: Dictionary = current.visits[str(v.active.id)]
	var price: Dictionary = active.prices[str(a.item_id)]
	var currency: String = "VKC" if int(price.VKC) > 0 else "USD"
	var price_entry := LineEdit.new()
	price_entry.name = "b2_price_input"
	price_entry.text = str(price[currency])
	price_entry.placeholder_text = _text("b2.price.placeholder")
	price_entry.custom_minimum_size = Vector2(240, 42)
	actions.add_child(price_entry)
	_button(actions,"b2_offer",_text("b2.offer.submit"),
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
