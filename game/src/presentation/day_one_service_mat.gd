extends Control
## Game-only abstract surface restoration. Local marks are UI progress, not save data.
signal prepared
const Art = preload("res://src/presentation/stock_art_resource.gd")
var _visual: Dictionary = {}
var _marks: Array = [false, false, false]
var _held: bool = false
var _picked: bool = false
var _locked: bool = false
var _pointer: Vector2 = Vector2.ZERO
var _translate: Callable
var _ready_to_commit: bool = false

func draft_view() -> Dictionary:
	return {"marks": _marks.duplicate(), "ready": _ready_to_commit}

func ready_to_commit() -> bool:
	return _ready_to_commit

func prepare_accessible() -> void:
	if _locked:
		return
	_marks = [true, true, true]
	_ready_to_commit = true
	prepared.emit()
	queue_redraw()

func configure(translator: Callable, locked: bool, draft: Dictionary = {}, visual_id: String = "fictional_gear") -> void:
	_visual = Art.resolve(visual_id)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_translate = translator
	_locked = locked
	var marks: Variant = draft.get("marks")
	if marks is Array and marks.size() == 3 and marks.all(func(value: Variant) -> bool: return value is bool):
		_marks = marks.duplicate()
		_ready_to_commit = _marks == [true, true, true]
	custom_minimum_size = Vector2(420, 250)
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func _tool() -> Rect2:
	return Rect2(12, 44, 80, 80)

func _specimen() -> Rect2:
	return Rect2(112, 20, maxf(220, size.x - 132), 208)

func _zone(i: int) -> Rect2:
	var r: Rect2 = _specimen()
	return Rect2(r.position + Vector2((0.05 + i * 0.30) * r.size.x, r.size.y * 0.18), Vector2(r.size.x * 0.27, r.size.y * 0.64))

func _sample(at: Vector2) -> void:
	if not _held or not _picked or _locked:
		return
	for i: int in range(3):
		if _zone(i).has_point(at):
			_marks[i] = true
	if not _ready_to_commit and _marks == [true, true, true]:
		_ready_to_commit = true
		prepared.emit()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if _locked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer = event.position
		_held = event.pressed
		if event.pressed and _tool().has_point(_pointer):
			_picked = true
		_sample(_pointer)
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion:
		_pointer = event.position
		_sample(_pointer)
		queue_redraw()
		accept_event()

func displayed_art() -> String:
	return str(_visual.get("key", ""))

func _draw() -> void:
	var r: Rect2 = _specimen()
	draw_rect(r.grow(5), Color("#1d231f"))
	draw_rect(r, Color("#39483e"))
	for x: int in range(10):
		var dx: float = r.size.x * x / 10.0
		draw_line(r.position + Vector2(dx, 0), r.position + Vector2(dx, r.size.y), Color("#4a5548"))
	Art.paint(self, r.grow(-12), _visual)
	draw_rect(r, Color("#a6ab95"), false, 2.0)
	for i: int in range(3):
		var zone: Rect2 = _zone(i)
		draw_rect(zone, Color(0.40, 0.64, 0.45, 0.23) if _marks[i] else Color(0.37, 0.32, 0.22, 0.25))
		draw_rect(zone, Color("#b6c0a4"), false, 1)
		if not _marks[i]:
			for j: int in range(3):
				var a: Vector2 = zone.position + Vector2(zone.size.x * (0.15 + j * 0.17), zone.size.y * 0.28)
				draw_line(a, a + Vector2(zone.size.x * 0.24,zone.size.y * 0.4), Color("#b6a78b"), 2)
	draw_rect(_tool(), Color("#4a5549"))
	draw_rect(_tool().grow(-12), Color("#d0be8d"), false, 3)
	if _picked:
		draw_rect(Rect2(_pointer - Vector2(16,12),Vector2(32,24)), Color("#d0be8d"))
	if _translate.is_valid():
		draw_string(get_theme_default_font(), Vector2(12, 28), _translate.call("dayone.surface_tool", {}), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#d6d1bf"))
