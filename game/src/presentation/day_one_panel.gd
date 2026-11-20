extends VBoxContainer
## Day-one presentation adapter: only public DTOs and intent signals.
signal requested(kind: String, payload: Dictionary)
const PagedRows = preload("res://src/presentation/paged_rows.gd")
const Inventory = preload("res://src/presentation/day_one_inventory.gd")
const Surface = preload("res://src/presentation/day_one_service_mat.gd")
const CompositePanel = preload("res://src/presentation/campaign_composite_panel.gd")
var _translate: Callable
var _locked: bool = false
var inventory: Control
var service_surface: Control


func _t(key: String, args: Dictionary = {}) -> String:
	return _translate.call(key, args)

func _line(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label

func _button(text: String, callback: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.disabled = _locked or disabled
	button.pressed.connect(callback)
	add_child(button)
	return button

func _command(kind: String, payload: Dictionary = {}) -> void:
	if not _locked:
		requested.emit(kind, payload)

func _sale(visit: String, buyer: String, price: int, grid: String) -> void:
	_command("trade", {"visit_id": visit, "item_id": "R001", "seller": "player", "buyer": buyer, "currency": "VKC", "amount": price, "inventory": grid, "x": 0, "y": 0, "rotated": false})

func _restore() -> void:
	_command("restore_item", {"actor": "player", "item_id": "W001"})

func configure(dto: Dictionary, translator: Callable, locked: bool, section: String = "counter", stock_draft: Dictionary = {}, service_draft: Dictionary = {}) -> void:
	_translate = translator
	_locked = locked
	var day: Dictionary = dto.day_one
	if not day.get("started", false):
		return
	add_theme_constant_override("separation", 8)
	_line(_t("dayone.phase_evening" if day.phase == "workshop" else ("dayone.phase_morning" if day.day == 2 else "dayone.phase_shop")))
	_line(_t("wallet.balance", {"amount": str(dto.wallet.VKC), "currency": "VKC"}))
	if section == "stock":
		if day.phase == "workshop":
			_line(_t("dayone.stock_evening_hint"))
		var grid := Inventory.new()
		inventory = grid
		add_child(grid)
		grid.configure(day.stock, translator, locked, stock_draft)
		grid.move_requested.connect(func(payload: Dictionary) -> void: _command("move", payload))
		_line(_t("dayone.grid_hint"))
		var selector := OptionButton.new()
		selector.custom_minimum_size.y = 44
		selector.add_item(_t("dayone.select_stock"))
		selector.set_item_metadata(0, "")
		for entry: Dictionary in grid.selection_options():
			selector.add_item(_t(entry.name_key) + " · " + entry.id)
			selector.set_item_metadata(selector.item_count - 1, entry.id)
		add_child(selector)
		var detail: Label = _line("")
		var placement: Label = _line("")
		var rotate: Button = _button(_t("dayone.rotate"), grid.rotate_selected)
		var rotate_commit: Button = _button(_t("dayone.rotate_commit"), grid.apply_rotation_in_place)
		var send_display: Button = _button(_t("dayone.quick_display"), grid.quick_move.bind("player_display"))
		var send_stock: Button = _button(_t("dayone.quick_stock"), grid.quick_move.bind("player_stock"))
		var clear: Button = _button(_t("dayone.clear_selection"), grid.cancel_selection)
		var refresh_selection: Callable = func() -> void:
			var row: Dictionary = grid.selected_row()
			var draft: Dictionary = grid.draft_view()
			var selected: bool = not row.is_empty()
			for index: int in range(selector.item_count):
				if selector.get_item_metadata(index) == draft.selected:
					selector.select(index)
					break
			detail.text = _t("dayone.stock_detail", {"item": _t(row.name_key) + " · " + row.id, "basis": str(row.basis.VKC), "location": _t("dayone.stock" if row.inventory == "player_stock" else "dayone.display")}) if selected else _t("dayone.select_stock")
			placement.text = ""
			rotate.disabled = locked or not selected
			rotate_commit.disabled = locked or not selected or draft.rotation == row.get("rotated")
			send_display.disabled = locked or grid.quick_target("player_display").is_empty()
			send_stock.disabled = locked or grid.quick_target("player_stock").is_empty()
			clear.disabled = not selected
		grid.selection_changed.connect(refresh_selection)
		grid.placement_rejected.connect(func() -> void: placement.text = _t("ui.no_space"))
		selector.item_selected.connect(func(index: int) -> void:
			var id: String = str(selector.get_item_metadata(index))
			if id.is_empty():
				grid.cancel_selection()
			else:
				grid.select_item(id))
		refresh_selection.call()
		var owned: Array = day.stock.filter(func(row: Dictionary) -> bool: return row.owned)
		var stock_pages := PagedRows.new()
		add_child(stock_pages)
		stock_pages.configure(owned, translator, func(row: Dictionary) -> String:
			return _t("dayone.stock_line", {"item": _t(row.name_key) + " · " + row.id, "basis": str(row.basis.VKC)}))
		if not dto.acquired_appraisal.is_empty():
			var slip: Dictionary = dto.acquired_appraisal
			_line(_t("ui.acquired_appraisal"))
			for fact: Dictionary in slip.evidence:
				_line(_t(fact.text_key))
			if slip.reference.get("estimate") != null:
				_line(_t("ui.reference_partial", {"amount": str(slip.reference.estimate), "currency": "VKC"}))
		return
	if section in ["counter", "workshop"] and dto.has("composite_pilot") and ((day.phase == "workshop") == (section == "workshop")):
		var composite := CompositePanel.new()
		add_child(composite)
		composite.requested.connect(_command)
		composite.configure(dto.composite_pilot, translator, locked)
	if section == "counter" and day.day == 1 and day.phase == "shop":
		_line(_t("dayone.retail_terms", {"price": str(day.retail_price)}))
		if day.active_visit == day.retail_visit:
			_button(_t("dayone.retail", {"price": str(day.retail_price)}), _sale.bind(day.retail_visit, "G02", day.retail_price, "g02_grid"), not day.can_retail)
		_button(_t("dayone.wholesale", {"price": str(day.wholesale_price)}), _sale.bind(day.wholesale_visit, day.wholesaler, day.wholesale_price, "wholesale_grid"), not day.can_wholesale)
		if day.active_visit != null:
			var message: String = "dayone.service_offer" if day.active_visit == "visit_g02_service" else "dayone.retail_active"
			_line(_t(message))
		if day.can_accept_service:
			_button(_t("dayone.accept_service"), _command.bind("day_one_accept_service", {}))
		_button(_t("dayone.decline"), _command.bind("day_one_decline", {}), not day.can_decline)
		_button(_t("ui.door"), _command.bind("day_one_next", {}), not day.can_next)
		_line(_t("dayone.closing_warning", {"cost": str(day.closing_cost), "remaining": str(maxi(0, 3-int(day.cursor)))}))
		_button(_t("dayone.close"), _command.bind("day_one_close", {"confirm": true}), not day.can_close_shop)
	if section in ["counter", "workshop"] and day.service != null:
		_line(_t("dayone.service_" + day.service.status))
		_line(_t("dayone.service_terms", {"fee": str(day.service.fee), "cost": str(day.service.direct_cost)}))
	if section == "workshop" and day.phase == "workshop":
		if day.service != null and day.service.status == "accepted":
			_line(_t("dayone.surface_hint"))
			var surface := Surface.new()
			service_surface = surface
			add_child(surface)
			var visual: String = ""
			for row: Dictionary in day.stock:
				if row.id == "W001":
					visual = str(row.get("visual_id", ""))
			surface.configure(translator, locked or not day.can_work, service_draft, visual)
			var commit: Button = _button(_t("dayone.commit_work", {"cost": str(day.service.direct_cost)}), _restore, not day.can_work or not surface.ready_to_commit())
			surface.prepared.connect(func() -> void: commit.disabled = _locked or not day.can_work)
			# Equivalent accessible confirmation, no persistent simulation of the gesture.
			_button(_t("dayone.prepare_accessible"), surface.prepare_accessible, not day.can_work)
		if day.can_cancel_service:
			_button(_t("dayone.cancel_service"), _command.bind("day_one_cancel_service", {}))
		_button(_t("dayone.morning"), _command.bind("day_one_next_morning", {}), not day.can_morning)
	elif section == "counter" and day.day == 2:
		for news: Dictionary in day.news:
			_line(_t(news.source_key))
			_line(_t(news.text_key))
		_button(_t("dayone.deliver"), _command.bind("day_one_deliver_service", {}), not day.can_deliver)
		if day.can_cancel_service:
			_button(_t("dayone.cancel_service"), _command.bind("day_one_cancel_service", {}))
		_button(_t("dayone.recovery", {"price": str(day.recovery_price)}), _sale.bind(day.recovery_visit, day.recovery_buyer, day.recovery_price, "day2_buyer_grid"), not day.can_recovery)
		if day.closing != null and day.closing.debt > 0:
			_button(_t("dayone.pay_overhead"), _command.bind("day_one_pay_overhead", {}), not day.can_pay_overhead)
		_line(_t("dayone.slice_end"))
	if section != "ledger":
		return
	if day.closing != null:
		_line(_t("dayone.overhead_record", {"paid": str(day.closing.paid), "debt": str(day.closing.debt)}))
	var history = preload("res://src/presentation/item_history_panel.gd").new()
	add_child(history)
	history.configure(dto.item_history, translator)
	_line(_t("dayone.ledger"))
	var ledger_pages := PagedRows.new()
	add_child(ledger_pages)
	ledger_pages.configure(day.ledger, translator, func(row: Dictionary) -> String:
		var identification: String = ", ".join(PackedStringArray(row.item_ids))
		var value: String = _t("dayone.ledger_sale" if row.direction == "sale" else "dayone.ledger_purchase", {"item": identification, "amount": str(row.amounts.VKC)})
		if row.margin != null:
			value += "\n" + _t("dayone.margin", {"margin": str(row.margin)})
		return value)
	var settlement_pages := PagedRows.new()
	add_child(settlement_pages)
	settlement_pages.configure(day.settlements, translator, func(row: Dictionary) -> String:
		return _t("dayone.settlement_" + row.kind, {"amount": str(row.amount)}))
