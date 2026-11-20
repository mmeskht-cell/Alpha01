extends Control
## Tool-over-object inspection. Rotation and zoom are optional free viewing.
## The authoritative session still verifies every requested inspection.
signal inspection_requested(payload: Dictionary)
signal hypothesis_requested(model_id: Variant, appearance_id: Variant)
signal extra_attribute_requested(attribute_id: String, value: Variant)
const Gesture = preload("res://src/presentation/inspection_gesture.gd")
const RadioArt = preload("res://src/presentation/radio_art_resource.gd")
const Documents = preload("res://src/content/packaged_documents.gd")
const REGION_PATH: String = "res://data/presentation/radio_regions.json"
const DESIGN := Vector2(1000, 430)
const LOUPE := Rect2(28, 90, 155, 66)
const LIGHT := Rect2(28, 164, 155, 66)
const MATERIAL := Rect2(28, 238, 155, 66)
const BATCH := Rect2(28, 312, 155, 66)
const FUNCTION := Rect2(495, 11, 146, 44)
const TOOL_LABELS: Dictionary = {"wear_detail": "ui.wear_tool", "casing_detail": "ui.casing_tool", "material_detail": "ui.material_tool", "batch_detail": "ui.batch_tool", "function_detail": "component.function_tool", "display_damage_detail": "component.region_panel"}
const FACES: Array[String] = ["ui.view_front", "ui.view_right", "ui.view_back", "ui.view_left"]
var _app: Dictionary = {}
var _art: Dictionary = {}
var _regions: Dictionary = {}
var _visual_regions: Dictionary = {}
var _translate: Callable
var _locked: bool = false
var _compare: bool = false
var _gesture := Gesture.new()
var _face: int = 0
var _zoom: float = 1.0
var _pointer: Vector2 = Vector2(420, 200)
var _turning: bool = false
var _turn_distance: float = 0.0
var _last: Vector2
var _keyboard_pointer: bool = false
var _status: String = ""
var _pickup_press: bool = false
var _last_tool: String = ""

func configure(app: Dictionary, translator: Callable, locked: bool, compare: bool, previous_view: Dictionary = {}) -> void:
	_app = app.duplicate(true)
	_load_regions()
	_art = RadioArt.resolve(str(previous_view.get("art_key", "")))
	if _art.is_empty():
		push_error("RADIO_ART_PROFILE_INVALID")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_translate = translator
	_locked = locked
	_compare = compare
	_face = clampi(int(previous_view.get("face", 0)), 0, 3)
	_last_tool = str(previous_view.get("last_tool", ""))
	_zoom = clampf(float(previous_view.get("zoom", 1.0)), 0.9, 1.12 if _compare else 1.24)
	custom_minimum_size = Vector2.ZERO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	tooltip_text = _t("ui.keyboard_scan_hint")
	queue_redraw()

func gesture_active() -> bool:
	return not _gesture.tool.is_empty()

func view_state() -> Dictionary:
	return {"face": _face, "zoom": _zoom, "last_tool": _last_tool, "art_key": _art.get("key", "")}

## Developer replacement probe. Failed resolution does not replace the current resource.
func select_art(key: String) -> bool:
	var resolved: Dictionary = RadioArt.resolve(key)
	if resolved.is_empty():
		return false
	_art = resolved
	queue_redraw()
	return true

func _t(key: String, args: Dictionary = {}) -> String:
	return str(_translate.call(key, args)) if _translate.is_valid() else key

func _scale() -> Vector2:
	var factor: float = maxf(0.001, minf(size.x / DESIGN.x, size.y / DESIGN.y))
	return Vector2(factor, factor)

func _origin() -> Vector2:
	return (size - DESIGN * _scale()) * 0.5

func _local(point: Vector2) -> Vector2:
	return (point - _origin()) / _scale()

func _radio() -> Rect2:
	var center := Vector2(528, 195) if not _compare else Vector2(416, 195)
	var dimensions := Vector2(365, 190) if _face % 2 == 0 else Vector2(145, 190)
	dimensions *= _zoom
	return Rect2(center - dimensions / 2.0, dimensions)

func _normalized_rect(raw: Variant) -> Rect2:
	if not raw is Array or raw.size() != 4:
		return Rect2()
	for value: Variant in raw:
		if (not value is int and not value is float) or not is_finite(float(value)) or value < 0.0 or value > 1.0:
			return Rect2()
	var rect := Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
	if not rect.has_area() or rect.end.x > 1.0 or rect.end.y > 1.0:
		return Rect2()
	return rect

func _load_regions() -> void:
	_regions.clear()
	_visual_regions.clear()
	var data: Dictionary = Documents.read_object(REGION_PATH)
	if data.get("version") != 1 or not data.get("regions") is Dictionary or not data.get("visual_regions") is Dictionary:
		return
	for id: String in ["display", "scratch", "side", "casing", "material"]:
		var row: Variant = data.regions.get(id)
		if not row is Dictionary or row.get("face") not in [0, 1, 2, 3]:
			continue
		var rect: Rect2 = _normalized_rect(row.get("rect"))
		if rect.has_area():
			_regions[id] = {"face": int(row.face), "rect": rect}
	var display: Rect2 = _normalized_rect(data.visual_regions.get("display"))
	if display.has_area():
		_visual_regions["display"] = display

func _region_rect(id: String, face: int) -> Rect2:
	var row: Dictionary = _regions.get(id, {})
	return row.rect if row.get("face", -1) == face else Rect2()

func _feature(rect: Rect2, ratio: Rect2) -> Rect2:
	return Rect2(rect.position + rect.size * ratio.position, rect.size * ratio.size)

func _target_at(point: Vector2) -> String:
	if _radio().has_point(point):
		if _gesture.tool == "wear_detail" and _face == 0 and _feature(_radio(), _region_rect("display", _face)).has_point(point) and _has_tool("display_damage_detail"):
			return Gesture.TARGETS["display_damage_detail"]
		if _gesture.tool == "display_damage_detail" and not _feature(_radio(), _region_rect("display", _face)).has_point(point):
			return ""
		var region: String = {"wear_detail":"scratch", "casing_detail":"casing", "material_detail":"material", "batch_detail":"side"}.get(_gesture.tool, "")
		if not region.is_empty() and not _feature(_radio(), _region_rect(region, _face)).has_point(point):
			return ""
		return str(Gesture.TARGETS.get(_gesture.tool, ""))
	return ""

func _has_tool(id: String) -> bool:
	if id == "display_damage_detail" and not _region_rect("display", 0).has_area():
		return false
	for tool: Dictionary in _app.get("tools", []):
		if tool.tool_id == id:
			return true
	return false

func _available(id: String) -> bool:
	if _locked or not _has_tool(id):
		return false
	for tool: Dictionary in _app.get("tools", []):
		if tool.tool_id == id:
			return tool.available
	return false

func _known(id: String) -> bool:
	for tool: Dictionary in _app.get("tools", []):
		if tool.tool_id == id:
			return bool(tool.known)
	return false

func _usable(id: String) -> bool:
	return _available(id) or _known(id)

func _tool_at(point: Vector2) -> String:
	if LOUPE.has_point(point):
		return "wear_detail"
	if LIGHT.has_point(point):
		return "casing_detail"
	if MATERIAL.has_point(point):
		return "material_detail"
	if BATCH.has_point(point):
		return "batch_detail"
	if FUNCTION.has_point(point) and _has_tool("function_detail"):
		return "function_detail"
	return ""

func _turn(direction: int) -> void:
	_gesture.cancel()
	_face = posmod(_face + direction, 4)
	_turn_distance = 0.0
	_status = ""
	queue_redraw()

func zoom_by(amount: float) -> void:
	_set_zoom(amount)

func _set_zoom(amount: float) -> void:
	_gesture.cancel()
	_zoom = clampf(_zoom + amount, 0.9, 1.12 if _compare else 1.24)
	queue_redraw()

func _press(point: Vector2) -> void:
	_pointer = point
	_last = point
	_status = ""
	_pickup_press = false
	if not _gesture.tool.is_empty():
		queue_redraw()
		return
	var id: String = _tool_at(point)
	if not id.is_empty():
		if _usable(id):
			_gesture.begin(id, point)
			_pickup_press = true
		else:
			_status = "ui.scan_unavailable"
	elif _radio().has_point(point):
		_turning = true
		_turn_distance = 0.0
	queue_redraw()

func _move(point: Vector2) -> void:
	_pointer = point
	if not _gesture.tool.is_empty():
		_gesture.step(point, _target_at(point))
	elif _turning:
		_turn_distance += point.x - _last.x
		if absf(_turn_distance) >= 85.0:
			_turn(1 if _turn_distance > 0.0 else -1)
	_last = point
	queue_redraw()

func _release(point: Vector2) -> void:
	_pointer = point
	_turning = false
	if not _gesture.tool.is_empty():
		var id: String = _gesture.tool
		if _pickup_press and _tool_at(point) == id:
			_pickup_press = false
			queue_redraw()
			return
		var payload: Dictionary = _gesture.release(_target_at(point))
		if payload.is_empty():
			_status = "ui.scan_incomplete"
		elif _known(payload.tool_id):
			_last_tool = payload.tool_id
			_status = "ui.observation_review"
		elif _available(payload.tool_id):
			_last_tool = payload.tool_id
			_status = ""
			inspection_requested.emit(payload)
		else:
			_status = "ui.scan_unavailable"
	_pickup_press = false
	queue_redraw()

func _can_drop_data(point: Vector2, data: Variant) -> bool:
	return false # Assessment cards belong to explicit slip slots, not the specimen.

func _drop_data(point: Vector2, data: Variant) -> void:
	if _can_drop_data(point, data):
		_gesture.cancel()
		if data.get("attribute_id", "") in ["material_id", "batch_id"]:
			extra_attribute_requested.emit(data.attribute_id, data.get("attribute_value"))
		else:
			hypothesis_requested.emit(data.model_id, data.appearance_id)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_zoom(0.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_zoom(-0.1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				grab_focus()
				_keyboard_pointer = false
				_press(_local(event.position))
			else:
				_release(_local(event.position))
		else:
			return
		accept_event()
	elif event is InputEventMouseMotion:
		_move(_local(event.position))
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q: _turn(-1)
			KEY_E: _turn(1)
			KEY_EQUAL, KEY_KP_ADD: _set_zoom(0.1)
			KEY_MINUS, KEY_KP_SUBTRACT: _set_zoom(-0.1)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				var id: String = ["wear_detail", "casing_detail", "material_detail", "batch_detail", "function_detail", "display_damage_detail"][int(event.keycode - KEY_1)]
				if _usable(id):
					var region: String = {"wear_detail":"scratch","casing_detail":"casing","material_detail":"material","batch_detail":"side","display_damage_detail":"display"}.get(id, "")
					if not region.is_empty() and _regions.has(region):
						_face = int(_regions[region].face)
					_keyboard_pointer = true
					_pointer = _feature(_radio(), _region_rect(region, _face)).get_center() if not region.is_empty() else _radio().get_center()
					_gesture.begin(id, _pointer)
					_pickup_press = false
			KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
				_keyboard_pointer = true
				var direction := Vector2.ZERO
				if event.keycode == KEY_LEFT: direction.x = -1.0
				if event.keycode == KEY_RIGHT: direction.x = 1.0
				if event.keycode == KEY_UP: direction.y = -1.0
				if event.keycode == KEY_DOWN: direction.y = 1.0
				_move((_pointer + direction * 9.0).clamp(Vector2.ZERO, DESIGN))
			KEY_ENTER, KEY_KP_ENTER:
				_release(_pointer)
			KEY_ESCAPE:
				if _gesture.tool.is_empty():
					return
				_gesture.cancel()
				_turning = false
				_status = ""
			_:
				return
		queue_redraw()
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_EXIT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_gesture.cancel()
		_turning = false
		queue_redraw()

func _text(point: Vector2, value: String, font_size: int = 17, color: Color = Color("#ded5bd")) -> void:
	draw_string(get_theme_default_font(), point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _box(rect: Rect2, color: Color, edge: Color = Color("#141b19"), width: float = 2.0) -> void:
	draw_rect(rect, color)
	draw_rect(rect, edge, false, width)

func _radio_art(rect: Rect2, face: int, specimen: bool, double_line: bool = false) -> void:
	if specimen and face == 0 and not _art.is_empty():
		draw_rect(Rect2(rect.position + Vector2(8, 12), rect.size), Color(0.04, 0.06, 0.05, 0.55))
		draw_texture_rect(_art.texture, RadioArt.draw_rect_for(rect, _art.body), false)
		return
	var p: Vector2 = rect.position
	var s: Vector2 = rect.size
	var casing := Color("#747c72") if specimen else Color("#899087")
	var dark := Color("#28312e")
	# The same neutral casing in the reference cards. Public variants differ by side accent only.
	draw_rect(Rect2(p + Vector2(8, 12), s), Color(0.04, 0.06, 0.05, 0.55))
	_box(rect, casing, dark, 3.0)
	draw_line(p + s * Vector2(0.02, 0.04), p + s * Vector2(0.97, 0.04), Color("#bcc3ad"), 3.0)
	draw_rect(Rect2(p + s * Vector2(0.04, 0.94), s * Vector2(0.92, 0.04)), Color("#404b45"))
	if face == 0:
		var grille := Rect2(p + s * Vector2(0.075, 0.16), s * Vector2(0.62, 0.56))
		_box(grille, Color("#353d3a"), dark)
		for i: int in range(10):
			var y: float = 0.19 + i * 0.052
			draw_line(p + s * Vector2(0.105, y), p + s * Vector2(0.66, y), Color("#71796c"), 1.5)
		var display: Rect2 = _feature(rect, _visual_regions.get("display", Rect2()))
		if display.has_area():
			_box(display, Color("#c3b990"), dark)
			for j: int in range(5):
				var x: float = display.position.x + display.size.x * (0.14 + j * 0.16)
				draw_line(Vector2(x, display.position.y + display.size.y * 0.15), Vector2(x, display.position.y + display.size.y * 0.54), dark, 1.0)
		for j: int in range(2):
			var center: Vector2 = p + s * Vector2(0.83, 0.45 + j * 0.22)
			draw_circle(center, s.y * 0.078, dark)
			draw_arc(center, s.y * 0.06, 0, TAU, 24, Color("#a0a18d"), 2.0)
		if specimen:
			for i: int in range(6):
				var a: Vector2 = p + s * Vector2(0.09 + i * 0.067, 0.83 + 0.02 * (i % 2))
				draw_line(a, a + s * Vector2(0.035, -0.024), Color("#aaa28b"), maxf(1.0, _zoom * 1.3))
				draw_line(a + Vector2(1, 2), a + s * Vector2(0.045, -0.008), Color("#535a50"), 1.0)
	elif face == 1:
		_box(Rect2(p + s * Vector2(0.12, 0.12), s * Vector2(0.76, 0.73)), Color("#59625b"), dark)
		draw_line(p + s * Vector2(0.19, 0.41), p + s * Vector2(0.82, 0.41), Color("#aaa68d"), 3.0)
		if double_line:
			draw_line(p + s * Vector2(0.19, 0.49), p + s * Vector2(0.82, 0.49), Color("#aaa68d"), 3.0)
			_box(Rect2(p + s * Vector2(0.52, 0.61), s * Vector2(0.25, 0.09)), Color("#b3b29c"), dark, 1.0)
		if specimen:
			draw_rect(Rect2(p + s * Vector2(0.22, 0.34), s * Vector2(0.60, 0.26)), Color("#686e63"))
			draw_line(p + s * Vector2(0.20, 0.40), p + s * Vector2(0.33, 0.40), Color("#8c8a76"), 2.0)
			draw_line(p + s * Vector2(0.68, 0.48), p + s * Vector2(0.78, 0.48), Color("#8c8a76"), 2.0)
			for i: int in range(7):
				var a: Vector2 = p + s * Vector2(0.38 + i * 0.048, 0.39 + 0.018 * (i % 3))
				draw_line(a, a + s * Vector2(0.08, 0.09), Color("#92917e"), 1.2)
	elif face == 2:
		_box(Rect2(p + s * Vector2(0.1, 0.17), s * Vector2(0.8, 0.65)), Color("#606860"), dark)
		draw_line(p + s * Vector2(0.13, 0.72), p + s * Vector2(0.87, 0.72), dark, 2.0)
		for i: int in range(6):
			draw_line(p + s * Vector2(0.2, 0.25 + i * 0.055), p + s * Vector2(0.8, 0.25 + i * 0.055), dark, 2.0)
	else:
		draw_rect(Rect2(p + s * Vector2(0.26, 0.16), s * Vector2(0.48, 0.60)), Color("#606860"))
		for i: int in range(3):
			draw_circle(p + s * Vector2(0.5, 0.29 + 0.18 * i), s.x * 0.085, dark)

func _tool_art(id: String, center: Vector2, opacity: float = 1.0) -> void:
	var steel := Color(0.66, 0.70, 0.65, opacity)
	var dark := Color(0.16, 0.20, 0.18, opacity)
	if id in ["material_detail", "batch_detail", "function_detail"]:
		var body := Rect2(center - Vector2(27, 18), Vector2(54, 36))
		_box(body, steel, dark)
		_box(Rect2(center - Vector2(18, 12), Vector2(36, 18)), dark)
		_text(center + Vector2(-14, 2), "MAT" if id == "material_detail" else ("LOT" if id == "batch_detail" else "FUN"), 12, Color("#c6d9ab"))
		draw_line(center + Vector2(0, 18), center + Vector2(0, 28), steel, 4.0)
	elif id == "wear_detail":
		draw_line(center + Vector2(20, 20), center + Vector2(48, 48), dark, 16.0)
		draw_circle(center, 33.0, Color(0.70, 0.82, 0.78, 0.13 * opacity))
		draw_arc(center, 34.0, 0, TAU, 48, dark, 8.0, true)
		draw_arc(center, 30.0, 0, TAU, 48, steel, 3.0, true)
	else:
		draw_line(center + Vector2(-34, 28), center + Vector2(-7, 5), dark, 23.0)
		draw_line(center + Vector2(-7, 5), center + Vector2(9, -9), steel, 27.0)
		draw_line(center + Vector2(7, -12), center + Vector2(16, -2), Color(0.85, 0.80, 0.56, opacity), 9.0)

func _texture_sample(rect: Rect2, pattern: String) -> void:
	_box(rect, Color("#717a6e"), Color("#3a4139"), 1.0)
	match pattern:
		"parallel":
			for i: int in range(8):
				var x: float = rect.position.x + 5 + i * (rect.size.x - 10) / 8.0
				draw_line(Vector2(x, rect.position.y + 4), Vector2(x, rect.end.y - 4), Color("#c1c3b1"), 1.6)
		"cross":
			for i: int in range(5):
				var x: float = rect.position.x + 5 + i * (rect.size.x - 10) / 5.0
				draw_line(Vector2(x, rect.position.y + 4), Vector2(x, rect.end.y - 4), Color("#c1c3b1"), 1.2)
			for i: int in range(4):
				var y: float = rect.position.y + 4 + i * (rect.size.y - 8) / 4.0
				draw_line(Vector2(rect.position.x + 4, y), Vector2(rect.end.x - 4, y), Color("#bab9a9"), 1.2)
		"pore":
			for i: int in range(5):
				for j: int in range(3):
					draw_circle(rect.position + Vector2(7 + i * (rect.size.x - 14) / 5.0 + (j % 2) * 3, 6 + j * (rect.size.y - 12) / 3.0), 1.8, Color("#303a34"))

func _draw_readout() -> void:
	var reading: Dictionary = {}
	for fact: Dictionary in _app.get("evidence", []):
		if fact.get("tool_id") == _last_tool:
			reading = fact.get("reading", {})
			break
	if reading.is_empty():
		return
	var sample := Rect2(224, 305, 400, 65)
	_box(sample, Color("#151f1b"), Color("#748176"), 1.0)
	_text(Vector2(236, 324), _t(TOOL_LABELS[_last_tool]), 15)
	match reading.kind:
		"damage_index":
			var bar := Rect2(238, 338, 240, 16)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * 0.26, bar.size.y)), Color("#678875"))
			draw_rect(Rect2(bar.position + Vector2(bar.size.x * 0.26, 0), Vector2(bar.size.x * 0.40, bar.size.y)), Color("#b7a36a"))
			draw_rect(Rect2(bar.position + Vector2(bar.size.x * 0.66, 0), Vector2(bar.size.x * 0.34, bar.size.y)), Color("#a76357"))
			var needle: float = bar.position.x + bar.size.x * float(reading.value) / 100.0
			draw_line(Vector2(needle, 330), Vector2(needle, 362), Color("#eae6d1"), 3.0)
			_text(Vector2(495, 352), str(reading.value) + " / 100", 20)
		"function_status":
			_text(Vector2(238, 354), _t("component.working" if reading.value == "serviceable" else "component.faulty"), 20)
		"texture":
			_texture_sample(Rect2(238, 331, 135, 32), str(reading.value))
			_text(Vector2(385, 353), _t("ui.compare_pattern"), 15)
		_:
			_text(Vector2(238, 354), str(reading.value), 24, Color("#d3d9a7"))

func _draw() -> void:
	if _app.is_empty() or size.x <= 0 or size.y <= 0:
		return
	draw_set_transform(_origin(), 0.0, _scale())
	_box(Rect2(Vector2.ZERO, DESIGN), Color("#352f27"), Color("#171c19"))
	_box(Rect2(17, 62, 178, 319), Color("#494b3f"))
	_box(Rect2(210, 62, 770 if not _compare else 427, 319), Color("#283a33"))
	# Tactile work mat and small graduations, not labelled target buttons.
	for i: int in range(24):
		draw_line(Vector2(218 + i * 16, 370), Vector2(218 + i * 16, 376), Color("#647267"), 1.0)
	_text(Vector2(28, 48), _t("ui.inspection_bench"), 22)
	_text(Vector2(330, 48), _t(FACES[_face]) + "  " + str(roundi(_zoom * 100.0)) + "%", 18)
	_text(Vector2(28, 82), _t("ui.tool_tray"), 15)
	var areas: Array = [LOUPE, LIGHT, MATERIAL, BATCH]
	var ids: Array = ["wear_detail", "casing_detail", "material_detail", "batch_detail"]
	for i: int in range(ids.size()):
		var id: String = ids[i]
		var area: Rect2 = areas[i]
		_box(area, Color("#3a4037"))
		var active: bool = _usable(id)
		draw_set_transform(_origin() + (area.position + Vector2(31, 27)) * _scale(), 0.0, _scale() * 0.46)
		_tool_art(id, Vector2.ZERO, 1.0 if active else 0.32)
		draw_set_transform(_origin(), 0.0, _scale())
		_text(area.position + Vector2(52, 24), _t(TOOL_LABELS[id]), 14)
		for tool: Dictionary in _app.get("tools", []):
			if tool.tool_id == id:
				_text(area.position + Vector2(52, 46), _t("ui.observation_review") if tool.known else "+" + str(tool.minutes) + "m", 12)

	if _has_tool("function_detail"):
		_box(FUNCTION, Color("#3a4037"))
		draw_set_transform(_origin() + (FUNCTION.position + Vector2(25, 19)) * _scale(), 0.0, _scale() * 0.56)
		_tool_art("function_detail", Vector2.ZERO, 1.0 if _usable("function_detail") else 0.32)
		draw_set_transform(_origin(), 0.0, _scale())
		_text(FUNCTION.position + Vector2(48, 16), _t("component.function_tool"), 13)
		_text(FUNCTION.position + Vector2(48, 33), _t("ui.observation_review") if _known("function_detail") else "+5m", 12)
	_radio_art(_radio(), _face, true)
	if _face == 0 and _has_tool("display_damage_detail") and _gesture.tool in ["wear_detail", "display_damage_detail"]:
		var area: Rect2 = _feature(_radio(), _region_rect("display", _face))
		draw_rect(area, Color("#d1bc75"), false, 2.0)
		_text(area.position + Vector2(-8, -5), _t("component.region_panel") + (" · " + _t("ui.observation_review") if _known("display_damage_detail") else " +5 min"), 13)
	if not _last_tool.is_empty() and _known(_last_tool):
		_draw_readout()
	if _compare:
		_box(Rect2(651, 62, 329, 319), Color("#b0a486"), Color("#554a38"))
		_text(Vector2(668, 88), _t("ui.catalog"), 19, Color("#342e25"))
		for i: int in range(mini(2, _app.catalog.model_candidates.size())):
			var candidate: Dictionary = _app.catalog.model_candidates[i]
			var y: float = 96.0 + 73.0 * i
			_text(Vector2(667, y + 14), _t(candidate.name_key) + " · " + str(candidate.reference_amount), 14, Color("#342e25"))
			_radio_art(Rect2(673, y + 20, 90, 45), 0, false)
			_radio_art(Rect2(790, y + 20, 30, 45), 1, false, candidate.id == "selvar_r18s")
		var materials: Array = _app.catalog.get("material_candidates", [])
		for i: int in range(materials.size()):
			var row: Dictionary = materials[i]
			var y: float = 254.0 + i * 35.0
			_texture_sample(Rect2(665, y, 64, 27), row.pattern)
			_text(Vector2(739, y + 18), _t(row.label_key), 15, Color("#342e25"))

	if not _gesture.tool.is_empty():
		if _gesture.tool == "casing_detail":
			draw_colored_polygon(PackedVector2Array([_pointer + Vector2(-5, 5), _pointer + Vector2(65, -50), _pointer + Vector2(75, 34)]), Color(1.0, 0.87, 0.52, 0.16))
		elif _gesture.tool == "wear_detail" and _radio().has_point(_pointer):
			draw_circle(_pointer, 30.0, Color("#889080"))
			if _face == 0 and _feature(_radio(), _region_rect("scratch", _face)).has_point(_pointer):
				for i: int in range(5):
					var start: Vector2 = _pointer + Vector2(-17 + i * 7, 9 - (i % 2) * 15)
					draw_line(start, start + Vector2(9, -8), Color("#d0c4a5"), 2.5)
					draw_line(start + Vector2(1, 3), start + Vector2(10, -5), Color("#4a5248"), 1.5)
			else:
				for i: int in range(3):
					draw_line(_pointer + Vector2(-15, -8 + i * 8), _pointer + Vector2(15, -8 + i * 8), Color("#717d6f"), 1.0)
		_tool_art(_gesture.tool, _pointer)
		if not _target_at(_pointer).is_empty():
			draw_arc(_pointer, 41.0, 0.0, TAU, 40, Color("#dfb95f"), 2.0, true)
			_text(Vector2(650, 47), _t("ui.tool_ready"), 16)
	if _keyboard_pointer:
		draw_arc(_pointer, 7.0, 0, TAU, 20, Color("#f1e8c7"), 1.5)
	var message: String = _t("ui.scan_hint") if _status.is_empty() else _t(_status)
	_text(Vector2(22, 409), message, 15)
	draw_set_transform(Vector2.ZERO)
