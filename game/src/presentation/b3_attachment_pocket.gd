extends Label

signal attach(slot: String)
var visit := ""
var cards: Dictionary

func bind(visit_id: String,slips: Dictionary) -> void:
	name = "attachment_pocket"
	visit = visit_id
	cards = slips
	var selected := PackedStringArray()
	for slot: String in cards:
		if cards[slot].selected: selected.append(str(cards[slot].caption))
	text = "첨부 예정   %d장"%selected.size()
	tooltip_text = ", ".join(selected)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	var edge := StyleBoxFlat.new()
	edge.bg_color = Color("#39352e")
	edge.border_width_bottom = 2
	edge.border_color = Color("#ad9773")
	add_theme_stylebox_override("normal",edge)

func _can_drop_data(_position: Vector2,data: Variant) -> bool:
	if not data is Dictionary or data.get("visit")!=visit: return false
	var slot := str(data.get("slot",""))
	return cards.has(slot) and not cards[slot].selected

func _drop_data(at: Vector2,data: Variant) -> void:
	if _can_drop_data(at,data): attach.emit(str(data.slot))
