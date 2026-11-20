extends VBoxContainer
const PagedRows = preload("res://src/presentation/paged_rows.gd")
const Clock = preload("res://src/domain/business_clock.gd")
## Existing known transaction records only. Collapsed by default; no tier indicator or command.
func configure(history: Dictionary, translator: Callable) -> void:
	var toggle := Button.new()
	toggle.text = translator.call("lineage.open", {})
	toggle.toggle_mode = true
	toggle.custom_minimum_size.y = 44
	add_child(toggle)
	var body := VBoxContainer.new()
	body.visible = false
	add_child(body)
	toggle.toggled.connect(func(open: bool) -> void: body.visible = open)
	var rows: Array = history.get("records", [])
	if rows.is_empty():
		_line(body, translator.call("lineage.empty", {}))
	var pages := PagedRows.new()
	body.add_child(pages)
	pages.configure(rows, translator, func(row: Dictionary) -> String:
		var minute: int = row.minute
		var day: int = Clock.day_index(minute)
		var time: String = Clock.clock_text(minute)
		var direction: String = translator.call("lineage.purchase" if row.direction == "purchase" else "lineage.sale", {})
		var price: String = translator.call("lineage.group_price", {})
		if row.amounts != null:
			price = "%d VKC / %d USD" % [row.amounts.VKC, row.amounts.USD]
		return translator.call("lineage.row", {"day": str(day), "time": time, "direction": direction, "price": price}))
	if history.get("omitted", 0) > 0:
		_line(body, translator.call("lineage.older", {"count": str(history.omitted)}))
	_line(body, translator.call("lineage.unknown", {}))

func _line(parent: Control, value: String) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
