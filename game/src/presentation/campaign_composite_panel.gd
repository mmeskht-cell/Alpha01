extends VBoxContainer
## Public DTOs only; all commands go through the hosting counter's revision guard.
signal requested(kind: String, payload: Dictionary)
const ROLE: Dictionary = {"radio_shell": "component.shell", "board": "component.board", "speaker": "component.speaker", "antenna": "component.antenna"}
const TOOLS: Dictionary = {"component_texture": "ui.material_tool", "component_damage": "ui.wear_tool", "component_mark": "ui.batch_tool", "component_function": "component.function_tool"}
var _translate: Callable
var _locked: bool

func _t(key: String, args: Dictionary = {}) -> String:
	return _translate.call(key, args)

func _line(value: String) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)

func _button(value: String, kind: String, p: Dictionary = {}, disabled: bool = false) -> void:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 44
	button.disabled = _locked or disabled
	button.pressed.connect(func() -> void: requested.emit(kind, p))
	add_child(button)

func configure(pilot: Dictionary, translator: Callable, locked: bool) -> void:
	_translate = translator
	_locked = locked
	_line(_t("pilot.title"))
	if pilot.can_offer:
		_button(_t("pilot.offer"), "day_one_composite_offer")
	var dto: Dictionary = pilot.workshop
	if dto.is_empty():
		return
	var c: Dictionary = dto.customer
	_line(_t("consent.status_" + c.status))
	_line(_t("consent.price", {"amount": str(c.ask)}))
	if dto.phase == "shop":
		_button(_t("consent.request"), "day_one_composite_request", {}, not c.can_request)
		_button(_t("consent.close"), "day_one_composite_close", {}, not c.can_close)
		_button(_t("consent.buy"), "trade", {"visit_id": c.visit_id, "item_id": c.item_id, "seller": c.seller, "buyer": c.buyer, "currency": c.currency, "amount": c.ask, "inventory": "player_stock", "x": 6, "y": 0, "rotated": false}, not c.can_buy)
		_button(_t("consent.decline"), "day_one_composite_decline", {}, not c.can_decline)
		_line(_t("consent.scope"))
	for part: Dictionary in dto.parts:
		_line(_t(ROLE[part.role]) + " · " + part.id)
		for region: Dictionary in part.regions:
			for tool: String in region.tools:
				var key: String = region.tools[tool]
				var known: bool = false
				for fact: Dictionary in part.observations:
					if fact.observation_key == key and fact.current:
						known = true
				_button(_t("pilot.inspect", {"part": part.id, "region": _t(region.label_key), "tool": _t(TOOLS[tool])}), "observe", {"actor": "player", "item_id": part.id, "key": key}, known)
		_facts(part.observations)
		if dto.phase == "workshop" and part.id != "D001":
			if not part.parent_id.is_empty():
				var x: int = int({"D001_A": 0, "D001_B": 3, "D001_C": 5}.get(part.id, 0))
				_button(_t("pilot.detach", {"part": part.id}), "detach", {"actor": "player", "root_id": part.parent_id, "child_id": part.id, "inventory": "player_stock", "x": x, "y": 3, "rotated": false})
			else:
				_button(_t("pilot.attach", {"part": part.id}), "attach", {"actor": "player", "root_id": "D001", "child_id": part.id})
				# Capability and actual result remain authority decisions. No hidden success flag.
				_button(_t("pilot.restore", {"part": part.id, "cost": "5"}), "restore_item", {"actor": "player", "item_id": part.id}, dto.wallet.VKC < 5)
	for note: Dictionary in dto.notes:
		_line(_t("consent.retained_notes") + " · " + note.id)
		_facts(note.observations)

func _facts(records: Array) -> void:
	for fact: Dictionary in records:
		var value: String = str(fact.observed_value)
		match fact.tool_key:
			"component_texture": value = _t("component.pattern_" + value)
			"component_function":
				value = _t("component.partial") if value == "partial" else _t("component.working" if fact.observed_value == true or value == "serviceable" else "component.faulty")
		_line(_t(fact.region_label_key) + " · " + _t(TOOLS[fact.tool_key]) + ": " + value + ("" if fact.current else " · " + _t("component.stale")))
