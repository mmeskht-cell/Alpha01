extends Label

signal attach(slot: String)
const PaperProp = preload("res://src/presentation/b3_paper_prop.gd")
var _paper: PaperProp
var visit := ""
var item_id := ""
var cards: Dictionary
var use_desk_finish := false
var _rest: StyleBoxFlat
var _ready_for_card: StyleBoxFlat

func _ready() -> void:
	if use_desk_finish:
		_paper = PaperProp.new()
		_paper.form = "card"
		_paper.show_behind_parent = true
		add_child(_paper)
		add_theme_color_override("font_color",PaperProp.INK)
		_rest = _edge(Color.TRANSPARENT,Color.TRANSPARENT)
		_ready_for_card = _edge(Color("#a9804f42"),Color("#946236"))
	# Legacy pocket has no R2 hover styles; processing is opt-in on drag.
	set_process(false)

func _edge(fill: Color, rim: Color) -> StyleBoxFlat:
	var edge := StyleBoxFlat.new()
	edge.bg_color = fill
	edge.border_color = rim
	edge.border_width_bottom = 2
	edge.content_margin_left = 9
	edge.content_margin_right = 9
	return edge

func bind(visit_id: String,slips: Dictionary,owner_item: String = "",language: String = "ko") -> void:
	name = "attachment_pocket"
	visit = visit_id
	item_id = owner_item
	cards = slips
	var selected := PackedStringArray()
	var shown := PackedStringArray()
	for slot: String in cards:
		if cards[slot].selected: selected.append(str(cards[slot].caption))
		if cards[slot].get("public",false): shown.append(str(cards[slot].caption))
	text = "여기에 근거 카드 놓기"
	if use_desk_finish:
		_paper.size = size
		if not selected.is_empty() and not shown.is_empty():
			text = "대기 %d장  /  공개 %d장"%[selected.size(),shown.size()]
		elif not selected.is_empty():
			text = "값과 함께 건넬 근거 %d장"%selected.size()
		elif not shown.is_empty():
			text = "손님에게 공개한 근거 %d장"%shown.size()
		elif cards.is_empty():
			text = "감정한 근거를 여기에 제시"
		if language=="en":
			text = "Lay evidence here"
			if not selected.is_empty() and not shown.is_empty():
				text = "To show %d  /  Shown %d"%[selected.size(),shown.size()]
			elif not selected.is_empty():
				text = "With next offer · %d"%selected.size()
			elif not shown.is_empty():
				text = "Shown to customer · %d"%shown.size()
	else:
		if not selected.is_empty(): text = "제시 예정 · "+", ".join(selected)
		elif not shown.is_empty(): text = "공개한 근거 · "+", ".join(shown)
		elif cards.is_empty(): text = "아직 제시할 감정 카드 없음"
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tooltip_text = ("With next offer: " if language=="en" else "제시 예정: ")+", ".join(selected)+\
		("\nShown to customer: " if language=="en" else "\n공개된 근거: ")+", ".join(shown)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("normal",_rest if use_desk_finish else _edge(Color("#39352e"),Color("#ad9773")))

func _notification(what: int) -> void:
	if not use_desk_finish or _rest==null: return
	if what==NOTIFICATION_DRAG_BEGIN:
		set_process(true)
	elif what==NOTIFICATION_DRAG_END:
		set_process(false)
		add_theme_stylebox_override("normal",_rest)

func _process(_delta: float) -> void:
	if not use_desk_finish or _rest == null or _ready_for_card == null:
		set_process(false)
		return
	var pointer := get_local_mouse_position()
	var valid := is_visible_in_tree() and Rect2(Vector2.ZERO,size).has_point(pointer) and _can_drop_data(pointer,get_viewport().gui_get_drag_data())
	var skin := _ready_for_card if valid else _rest
	if get_theme_stylebox("normal")!=skin: add_theme_stylebox_override("normal",skin)

func _can_drop_data(_position: Vector2,data: Variant) -> bool:
	if not data is Dictionary or data.get("visit")!=visit: return false
	if not item_id.is_empty() and data.get("item")!=item_id: return false
	var slot := str(data.get("slot",""))
	return cards.has(slot) and not cards[slot].selected

func _drop_data(at: Vector2,data: Variant) -> void:
	if _can_drop_data(at,data): attach.emit(str(data.slot))
