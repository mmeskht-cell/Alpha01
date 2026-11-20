extends Control
## Isolated owned-stock component UX preview; no campaign or snapshot access.
const Runtime = preload("res://src/application/foundation_runtime.gd")
const UiTheme = preload("res://src/presentation/ui_theme.gd")
const Card = preload("res://src/presentation/component_workshop_card.gd")
const Readout = preload("res://src/presentation/component_readout.gd")
const TOOL_KEYS: Dictionary = {"component_texture": "ui.material_tool", "component_damage": "ui.wear_tool", "component_mark": "ui.batch_tool", "component_function": "component.function_tool"}
const ROLE_KEYS: Dictionary = {"radio_shell": "component.shell", "board": "component.board", "speaker": "component.speaker", "antenna": "component.antenna"}
const FIELD_NAMES: Dictionary = {"material_id": "ui.material_cards", "condition_id": "ui.condition_cards", "series_id": "ui.batch_cards"}
const SERIES_KEYS: Dictionary = {"series_early": "batch.early", "series_late": "batch.late", "series_rebuilt": "batch.rebuilt"}
const MATERIAL_KEYS: Dictionary = {"molded_polymer": "material.polymer", "light_alloy": "material.alloy", "coated_steel": "material.steel"}
const CONDITION_KEYS: Dictionary = {"light_wear": "catalog.radio.wear.light", "visible_wear": "catalog.radio.wear.visible", "heavy_wear": "catalog.radio.wear.heavy"}
@export var customer_policy: String = ""
@export var market_preview: bool = false
var _rt: RefCounted
var _body: VBoxContainer
var _scroll: ScrollContainer
var _selected: String = "D001"
var _region: String = "primary"
var _tool: String = ""
var _message: String = ""
var _blocked: bool = false
var _lang: String = "ko"
var _recovery_ids: Array = ["D001", "D001_A", "D001_B", "D001_C"]

func _ready() -> void:
	if not UiTheme.apply_to(self):
		return
	_rt = Runtime.new()
	var suffix: String = str(Time.get_unix_time_from_system()).replace(".", "_") + "_" + str(Time.get_ticks_usec())
	var ready: bool
	if market_preview:
		ready = _rt.initialize_component_market_preview("user://zt_rebuild/component_market_previews/" + suffix)
	elif customer_policy.is_empty():
		ready = _rt.initialize_component_preview("user://zt_rebuild/component_previews/" + suffix)
	else:
		ready = _rt.initialize_customer_inspection_preview("user://zt_rebuild/customer_inspection_previews/" + suffix, customer_policy)
	if not ready:
		push_error("COMPONENT_PREVIEW_INITIALIZATION_FAILED")
		return
	_refresh()

func _exit_tree() -> void:
	if _rt != null:
		_rt.shutdown()

func _t(key: String, args: Dictionary = {}) -> String:
	return _rt.localization.text(key, args)

func _label(parent: Control, value: String) -> Label:
	var l := Label.new()
	l.text = value
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l

func _button(parent: Control, value: String, callback: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	button.disabled = disabled
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _part(id: String) -> Dictionary:
	for part: Dictionary in _rt.component_workshop_view().parts:
		if part.id == id:
			return part
	return {}

func _submit(kind: String, payload: Dictionary) -> void:
	if _blocked:
		return
	var dto: Dictionary = _rt.component_workshop_view()
	var revision: int = _rt.component_market_view().revision if market_preview else dto.revision
	var result: Dictionary = _rt.submit({"action_id": "bench_" + str(revision + 1), "expected_revision": revision, "type": kind, "payload": payload})
	_blocked = _rt.persistence_view().save_pending or _rt.persistence_view().load_failed
	_message = ("error.save" if _blocked else "ui.action_saved") if result.ok else ("ui.observation_review" if result.get("error") == "evidence_already_known" else "ui.action_failed")
	_tool = ""
	_refresh()

func _retry() -> void:
	_blocked = not _rt.retry_save().ok
	_message = "error.save" if _blocked else "ui.action_saved"
	_refresh()

func _choose(id: String) -> void:
	_choose_region(id, "primary")

func _choose_region(id: String, region_id: String) -> void:
	_selected = id
	_region = region_id
	if not _tool.is_empty():
		_read(id, _tool, region_id)
	else:
		_refresh()

func _read(id: String, tool_key: String, region_id: String = "primary") -> void:
	_selected = id
	_region = region_id
	var p: Dictionary = _part(id)
	if p.is_empty():
		return
	var key: String = ""
	for region: Dictionary in p.regions:
		if region.id == region_id:
			key = str(region.tools.get(tool_key, ""))
			break
	if key.is_empty():
		_tool = ""
		_message = "component.tool_not_applicable"
		_refresh()
		return
	for fact: Dictionary in p.observations:
		if fact.observation_key == key and fact.current:
			_message = "ui.observation_review"
			_tool = ""
			_refresh()
			return
	_submit("observe", {"actor": "player", "item_id": id, "key": key})

func _assign(id: String, field: String, value: Variant) -> void:
	var p: Dictionary = _part(id)
	if p.is_empty() or field not in FIELD_NAMES:
		return
	var h: Dictionary = p.hypothesis.duplicate(true)
	h[field] = value
	h["actor"] = "player"
	h["item_id"] = id
	_selected = id
	_submit("record_component_hypothesis", h)

func _detached_position(id: String) -> int:
	return int({"D001_A": 0, "D001_B": 3, "D001_C": 5}.get(id, -1))

func _detach(id: String) -> void:
	var p: Dictionary = _part(id)
	var x: int = _detached_position(id)
	if p.is_empty() or p.parent_id.is_empty() or x < 0:
		return
	_selected = id
	_submit("detach", {"actor": "player", "root_id": p.parent_id, "child_id": id, "inventory": "player_grid", "x": x, "y": 3, "rotated": false})

func _attach(root: String, child: String) -> void:
	_selected = child
	_submit("attach", {"actor": "player", "root_id": root, "child_id": child})

func _drop_on_region(id: String, region_id: String, data: Dictionary) -> void:
	if data.get("kind") == "tool":
		_read(id, data.key, region_id)

func _drop_on_part(id: String, data: Dictionary) -> void:
	match data.get("kind"):
		"tool": _read(id, data.key)
		"hypothesis": _assign(id, data.field, data.value)
		"part":
			var row: Dictionary = _part(id)
			if row.get("role") == "radio_shell":
				_attach(id, data.id)

func _card(parent: Control, name: String, payload: Dictionary, kinds: Array, callback: Callable, drop: Callable, disabled: bool = false) -> Button:
	var c := Card.new()
	c.text = name
	c.payload = payload
	c.accepted_kinds = kinds
	c.disabled = disabled
	c.pressed.connect(callback)
	if drop.is_valid():
		c.dropped.connect(drop)
	c.custom_minimum_size.y = 44
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c

func _select_tool(key: String) -> void:
	_tool = key
	_refresh()

func _drop_detach(data: Dictionary) -> void:
	if data.get("kind") == "part":
		_detach(data.id)

func _part_card(parent: Control, part: Dictionary, physical: bool) -> void:
	var id: String = part.id
	var title: String = ("● " if _selected == id else "") + _t(ROLE_KEYS[part.role]) + " · " + id
	if part.component_estimate != null:
		title += " · " + str(part.component_estimate) + " VKC"
	var kinds: Array = ["tool", "hypothesis"]
	if part.role == "radio_shell" and physical:
		kinds.append("part")
	_card(parent, title, {"kind": "part", "id": id} if physical and part.role != "radio_shell" else {}, kinds, _choose.bind(id), func(data: Dictionary) -> void: _drop_on_part.call_deferred(id, data))
	if not part.parent_id.is_empty():
		_label(parent, _t("component.attached") + " " + part.parent_id)

func _buy() -> void:
	var c: Dictionary = _rt.component_workshop_view().customer
	if not c.get("can_buy", false):
		return
	_submit("trade", {"visit_id": c.visit_id, "item_id": c.item_id, "seller": c.seller, "buyer": c.buyer, "currency": c.currency, "amount": c.ask, "inventory": "player_grid", "x": 0, "y": 0, "rotated": false})

func _customer_controls(parent: Control, dto: Dictionary) -> void:
	var c: Dictionary = dto.customer
	if c.is_empty():
		return
	_label(parent, _t("consent.status_" + c.status) + " · " + _t("consent.policy_" + c.policy) + " · " + _t("consent.price", {"amount": str(c.ask)}))
	if dto.phase != "shop":
		return
	var row := HFlowContainer.new()
	parent.add_child(row)
	_button(row, _t("consent.request"), func() -> void: _submit("request_open_inspection", {}), _blocked or not c.can_request)
	_button(row, _t("consent.close"), func() -> void: _submit("close_inspection", {}), _blocked or not c.can_close)
	_button(row, _t("consent.buy"), _buy, _blocked or not c.can_buy)
	_button(row, _t("consent.decline"), func() -> void: _submit("decline_component_visit", {}), _blocked or not c.can_decline)
	if c.can_buy and dto.minute < c.close_minute:
		_button(row, _t("consent.wait"), func() -> void: _submit("advance_time", {"minutes": mini(240, int(c.close_minute) - int(dto.minute))}), _blocked)
	_button(row, _t("consent.evening"), func() -> void: _submit("finish_component_visit", {}), _blocked or not c.can_finish)
	_label(parent, _t("consent.scope"))

func _fact_text(fact: Dictionary) -> String:
	var value: String = str(fact.observed_value)
	match fact.tool_key:
		"component_texture":
			value = _t("component.pattern_" + value)
		"component_function":
			if fact.observed_value is String and fact.observed_value == "partial":
				value = _t("component.partial")
			else:
				var working: bool = (fact.observed_value is bool and fact.observed_value) or (fact.observed_value is String and fact.observed_value == "serviceable")
				value = _t("component.working" if working else "component.faulty")
	return _t(fact.region_label_key) + " · " + _t(TOOL_KEYS[fact.tool_key]) + ": " + value + (" · " + _t("component.stale") if not fact.current else "")

func _review_notes(parent: Control, dto: Dictionary) -> void:
	if dto.notes.is_empty():
		return
	var section := VBoxContainer.new()
	parent.add_child(section)
	_label(section, _t("consent.retained_notes"))
	for note: Dictionary in dto.notes:
		_label(section, _t(ROLE_KEYS[note.role]) + " · " + note.id)
		for fact: Dictionary in note.observations:
			_label(section, _fact_text(fact))
		for field: String in FIELD_NAMES:
			var selected: Variant = note.hypothesis[field]
			if selected == null:
				continue
			var key: String = SERIES_KEYS[selected] if field == "series_id" else (MATERIAL_KEYS[selected] if field == "material_id" else CONDITION_KEYS[selected])
			_label(section, _t(FIELD_NAMES[field]) + ": " + _t(key))
		if note.component_estimate != null:
			_label(section, str(note.component_estimate) + " VKC")

func _refresh() -> void:
	var previous_scroll: int = 0
	if is_instance_valid(_scroll):
		previous_scroll = _scroll.scroll_vertical
		remove_child(_scroll)
		_scroll.queue_free()
	_scroll = ScrollContainer.new()
	add_child(_scroll)
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 18
	_scroll.offset_right = -18
	_scroll.offset_top = 12
	_scroll.offset_bottom = -12
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	_body.add_theme_constant_override("separation", 6)
	var market: Dictionary = _rt.component_market_view()
	if market.get("started", false):
		_show_market(market)
		return
	var dto: Dictionary = _rt.component_workshop_view()
	var physical: bool = dto.phase == "workshop"
	var top := HBoxContainer.new()
	_body.add_child(top)
	var title: Label = _label(top, _t("component.title" if physical else "consent.title") + " · " + (_t("component.evening") if physical else _t("consent.elapsed", {"minutes": str(dto.minute)})) + " · " + str(dto.wallet.VKC) + " VKC")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(top, _t("ui.language"), func() -> void:
		_lang = "en" if _lang == "ko" else "ko"
		_rt.localization.select_language(_lang)
		_refresh())
	_customer_controls(_body, dto)
	_review_notes(_body, dto)
	if market_preview:
		_label(_body, _t("component.market_terms"))
		_button(_body, _t("component.market_prepare"), func() -> void: _submit("open_component_sale", {}), _blocked or not market.get("can_open", false))
	_label(_body, _t("component.instructions" if physical else "consent.instructions"))
	var tool_row := HBoxContainer.new()
	_body.add_child(tool_row)
	for key: String in TOOL_KEYS:
		_card(tool_row, ("● " if _tool == key else "") + _t(TOOL_KEYS[key]), {"kind": "tool", "key": key}, [], _select_tool.bind(key), Callable(), _blocked)
	var assembly := HBoxContainer.new()
	_body.add_child(assembly)
	for root: Dictionary in dto.parts:
		if root.role != "radio_shell":
			continue
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		assembly.add_child(column)
		_part_card(column, root, physical)
		_label(column, _t("component.whole_catalog") + ": " + (str(root.whole_catalog_reference) + " VKC" if root.whole_catalog_reference != null else _t("ui.unconfirmed")))
		for child: Dictionary in dto.parts:
			if child.parent_id == root.id:
				_part_card(column, child, physical)
	if physical:
		var tray := HBoxContainer.new()
		_body.add_child(tray)
		var mat: Button = _card(tray, _t("component.detach_tray"), {}, ["part"], func() -> void:
			_detach(_selected), func(data: Dictionary) -> void: _drop_detach.call_deferred(data), _blocked)
		mat.custom_minimum_size.x = 250
		for part: Dictionary in dto.parts:
			if part.role != "radio_shell" and part.parent_id.is_empty():
				_part_card(tray, part, physical)
	var selected: Dictionary = _part(_selected)
	if not selected.is_empty():
		var panel := HBoxContainer.new()
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_body.add_child(panel)
		var facts := VBoxContainer.new()
		facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_child(facts)
		_label(facts, _t("ui.observed_fact") + " · " + _selected)
		var regions := HFlowContainer.new()
		facts.add_child(regions)
		for region: Dictionary in selected.regions:
			var region_id: String = region.id
			var available: PackedStringArray = []
			for tool_key: String in region.tools:
				available.append(_t(TOOL_KEYS[tool_key]))
			var region_button: Button = _card(regions, ("● " if _region == region_id else "") + _t(region.label_key), {}, ["tool"], _choose_region.bind(_selected, region_id), func(data: Dictionary) -> void: _drop_on_region.call_deferred(selected.id, region_id, data), _blocked)
			region_button.tooltip_text = " / ".join(available)
		for fact: Dictionary in selected.observations:
			var reading_row := HBoxContainer.new()
			facts.add_child(reading_row)
			var sample := Readout.new()
			sample.configure(fact.tool_key, fact.observed_value)
			reading_row.add_child(sample)
			var description: Label = _label(reading_row, _fact_text(fact))
			description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if selected.observations.is_empty():
			_label(facts, _t("ui.unconfirmed"))
		if not physical:
			_label(facts, _t("consent.scope"))
		elif not selected.can_inspect:
			_label(facts, _t("component.detach_first" if selected.regions.is_empty() else "component.visible_only"))
		else:
			if selected.role in ["speaker", "board", "antenna"]:
				_button(facts, _t("component.repair"), func() -> void: _submit("restore_item", {"actor": "player", "item_id": _selected}), _blocked)
			if selected.role != "radio_shell":
				for root: Dictionary in dto.parts:
					if root.role == "radio_shell":
						_button(facts, _t("component.attach") + " " + root.id, _attach.bind(root.id, _selected), _blocked)
		var guide := VBoxContainer.new()
		guide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_child(guide)
		_label(guide, _t("ui.catalog") + " · " + _t("component.component_reference") + ": " + str(selected.component_reference) + " VKC")
		_label(guide, _t("ui.damage_guide"))
		_label(guide, _t("component.series_guide"))
		var swatches := HBoxContainer.new()
		guide.add_child(swatches)
		for material: Dictionary in dto.materials:
			var sample := Readout.new()
			sample.configure("component_texture", material.pattern)
			sample.custom_minimum_size = Vector2(60, 24)
			swatches.add_child(sample)
			_label(swatches, _t(MATERIAL_KEYS[material.id]))
		for field: String in FIELD_NAMES:
			var row := HFlowContainer.new()
			guide.add_child(row)
			_label(row, _t(FIELD_NAMES[field]))
			_card(row, _t("ui.unconfirmed"), {"kind": "hypothesis", "field": field, "value": null}, [], _assign.bind(_selected, field, null), Callable(), _blocked or not selected.can_hypothesize or selected.hypothesis[field] == null)
			var entries: Array = dto.materials if field == "material_id" else (dto.conditions if field == "condition_id" else dto.series)
			for entry: Variant in entries:
				var id: String = entry if field == "series_id" else entry.id
				var name: String = _t(SERIES_KEYS[id] if field == "series_id" else (MATERIAL_KEYS[id] if field == "material_id" else CONDITION_KEYS[id]))
				if field == "material_id":
					name += " · " + _t("component.pattern_" + entry.pattern) + " " + ("%+d" % int(entry.delta))
				elif field == "condition_id":
					name += " · " + str(entry.factor) + "%"
				_card(row, ("✓ " if selected.hypothesis[field] == id else "") + name, {"kind": "hypothesis", "field": field, "value": id}, [], _assign.bind(_selected, field, id), Callable(), _blocked or not selected.can_hypothesize or selected.hypothesis[field] == id)
	var recovery: Dictionary = _rt.component_recovery_view(_recovery_ids) if physical else {"ok": false}
	if recovery.ok:
		_label(_body, _t("component.recovery") + ": " + str(recovery.subtotal) + " VKC · " + _t("component.unknown_count", {"count": str(recovery.unknown_count)}) + " · " + _t("component.exclusive"))
	var capacity: Dictionary = _rt.save_capacity_view()
	if not capacity.is_empty():
		_label(_body, _t("component.save_usage", {"used": str(capacity.bytes), "limit": str(capacity.limit_bytes)}))
		if capacity.warning:
			_label(_body, _t("component.save_warning"))
	if not _message.is_empty():
		_label(_body, _t(_message))
	if _blocked:
		_button(_body, _t("ui.retry_save"), _retry)
	_scroll.set_deferred("scroll_vertical", previous_scroll)

func _show_market(market: Dictionary) -> void:
	_label(_body, _t("component.market_title"))
	_label(_body, _t("wallet.balance", {"amount": str(market.wallet.VKC), "currency": "VKC"}))
	_button(_body, _t("ui.language"), func() -> void:
		_lang = "en" if _lang == "ko" else "ko"
		_rt.localization.select_language(_lang)
		_refresh())
	if market.sold:
		_label(_body, _t("component.market_done"))
		if market.margin != null:
			_label(_body, _t("component.market_margin", {"margin": str(market.margin)}))
	else:
		_label(_body, _t("component.market_terms"))
		_button(_body, _t("component.market_sell"), func() -> void: _submit("trade", market.payload), _blocked)
	if not _message.is_empty():
		_label(_body, _t(_message))
	if _blocked:
		_button(_body, _t("ui.retry_save"), _retry)
