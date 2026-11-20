extends Control
## Direct grid placement: only public owned items. Engine validates final geometry.
signal move_requested(payload: Dictionary)
signal selection_changed
signal placement_rejected
const Grid = preload("res://src/domain/grid_primitives.gd")
const Art = preload("res://src/presentation/stock_art_resource.gd")
const STOCK: String = "player_stock"
const DISPLAY: String = "player_display"
var _rows: Array = []
var _translate: Callable
var _locked: bool = false
var _selected: String = ""
var _rotation: bool = false
var _hover: Dictionary = {}
var _art_cache: Dictionary = {}
var _row_index: Dictionary = {}

func draft_view() -> Dictionary:
	return {"selected": _selected, "rotation": _rotation}

func configure(rows: Array, translator: Callable, locked: bool, draft: Dictionary = {}) -> void:
	_rows = rows.duplicate(true)
	_art_cache.clear()
	_row_index.clear()
	_selected = ""
	_rotation = false
	_hover = {}
	for row: Dictionary in _rows:
		if row.owned and row.inventory in [STOCK, DISPLAY]:
			_row_index[row.id] = row
		var id: String = str(row.get("visual_id", ""))
		if not _art_cache.has(id):
			_art_cache[id] = Art.resolve(id)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_translate = translator
	_locked = locked
	var previous: String = str(draft.get("selected", ""))
	if not _row(previous).is_empty():
		_selected = previous
		_rotation = bool(draft.get("rotation", _row(previous).rotated))
	custom_minimum_size = Vector2(320, 308)
	if not resized.is_connected(_update_layout):
		resized.connect(_update_layout)
	_update_layout()
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	queue_redraw()

func _t(key: String) -> String:
	return _translate.call(key, {}) if _translate.is_valid() else key

func _stacked() -> bool:
	return size.x < 640.0

func _cell() -> float:
	var columns: float = 10.0 if _stacked() else 16.0
	return floorf(minf(42.0, maxf(12.0, (size.x - 34.0) / columns)))

func _origin(id: String) -> Vector2:
	if id == STOCK:
		return Vector2(8, 26)
	return Vector2(8, 58 + _cell() * 6.0) if _stacked() else Vector2(24 + _cell() * 10.0, 26)

func _footer_y() -> float:
	return maxf(_origin(STOCK).y + _cell() * 6, _origin(DISPLAY).y + _cell() * 3) + 23.0

func _update_layout() -> void:
	custom_minimum_size.y = ceilf(_footer_y() + 12.0)
	queue_redraw()

func _dims(id: String) -> Vector2i:
	return Vector2i(10, 6) if id == STOCK else Vector2i(6, 3)

func _rect_for(row: Dictionary) -> Rect2:
	var wh := Vector2(float(row.size[0]), float(row.size[1]))
	if row.rotated:
		wh = Vector2(wh.y, wh.x)
	return Rect2(_origin(row.inventory) + Vector2(row.x, row.y) * _cell(), wh * _cell())

func _item_at(at: Vector2) -> Dictionary:
	for row: Dictionary in _rows:
		if row.owned and row.inventory in [STOCK, DISPLAY] and _rect_for(row).has_point(at):
			return row
	return {}

func _row(id: String) -> Dictionary:
	return _row_index.get(id, {})

func _target(at: Vector2) -> Dictionary:
	for id: String in [STOCK, DISPLAY]:
		var dims: Vector2i = _dims(id)
		if Rect2(_origin(id), Vector2(dims) * _cell()).has_point(at):
			var local: Vector2 = (at - _origin(id)) / _cell()
			return {"inventory": id, "x": floori(local.x), "y": floori(local.y)}
	return {}

func _placement_ok(id: String, target: Dictionary, rotated: bool) -> bool:
	if target.is_empty() or target.get("inventory") not in [STOCK, DISPLAY]:
		return false
	var selected: Dictionary = _row(id)
	if selected.is_empty():
		return false
	var placements: Array = []
	for row: Dictionary in _rows:
		if row.id != id and row.inventory == target.inventory:
			placements.append({"item_id": row.id, "x": row.x, "y": row.y, "width": row.size[0], "height": row.size[1], "rotated": row.rotated})
	placements.append({"item_id": id, "x": target.x, "y": target.y, "width": selected.size[0], "height": selected.size[1], "rotated": rotated})
	var dims: Vector2i = _dims(target.inventory)
	return Grid.validate(dims.x, dims.y, placements).ok

## A deliberate quick transfer uses the same placement validation and command.
## No auto-rotation, no displacement, no new domain operation.
func selection_options() -> Array:
	var result: Array = []
	for row: Dictionary in _rows:
		if _row_index.has(row.id):
			result.append({"id": row.id, "name_key": row.name_key})
	return result

func selected_row() -> Dictionary:
	return _row(_selected).duplicate(true)

func select_item(id: String) -> void:
	var row: Dictionary = _row(id)
	if row.is_empty():
		return
	if _selected != id:
		_rotation = row.rotated
	_selected = id
	_hover = {}
	selection_changed.emit()
	queue_redraw()

func cancel_selection() -> void:
	_selected = ""
	_rotation = false
	_hover = {}
	selection_changed.emit()
	queue_redraw()

func quick_target(destination: String) -> Dictionary:
	var row: Dictionary = _row(_selected)
	if row.is_empty() or row.inventory == destination or destination not in [STOCK, DISPLAY]:
		return {}
	var dims: Vector2i = _dims(destination)
	for y: int in range(dims.y):
		for x: int in range(dims.x):
			var target: Dictionary = {"inventory": destination, "x": x, "y": y}
			if _placement_ok(_selected, target, _rotation):
				return target
	return {}

func quick_move(destination: String) -> void:
	if not _locked:
		_request(_selected, quick_target(destination), _rotation)

func _request(id: String, target: Dictionary, rotated: bool) -> void:
	if _locked or _row(id).is_empty():
		return
	var row: Dictionary = _row(id)
	if row.inventory == target.get("inventory") and row.x == target.get("x") and row.y == target.get("y") and row.rotated == rotated:
		return
	if not _placement_ok(id, target, rotated):
		placement_rejected.emit()
		return
	move_requested.emit({"item_id": id, "actor": "player", "inventory": target.inventory, "x": target.x, "y": target.y, "rotated": rotated})

func rotate_selected() -> void:
	if not _locked and not _selected.is_empty():
		_rotation = not _rotation
		selection_changed.emit()
		queue_redraw()

func apply_rotation_in_place() -> void:
	var row: Dictionary = _row(_selected)
	if _locked or row.is_empty() or _rotation == row.rotated:
		return
	_request(row.id, {"inventory": row.inventory, "x": row.x, "y": row.y}, _rotation)

func _get_drag_data(at: Vector2) -> Variant:
	if _locked:
		return null
	var row: Dictionary = _item_at(at)
	if row.is_empty():
		return null
	select_item(row.id)
	var preview := Label.new()
	preview.text = _t(row.name_key) + " · " + row.id
	set_drag_preview(preview)
	return {"kind": "day_one_stock", "id": row.id, "rotated": _rotation}

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if _locked or not data is Dictionary or data.get("kind") != "day_one_stock" or not data.get("rotated") is bool:
		return false
	_hover = _target(at)
	queue_redraw()
	return _placement_ok(str(data.get("id", "")), _hover, data.rotated)

func _drop_data(at: Vector2, data: Variant) -> void:
	if _can_drop_data(at, data):
		_request(data.id, _target(at), data.rotated)

func _gui_input(event: InputEvent) -> void:
	if _locked:
		return
	if event is InputEventMouseMotion:
		_hover = _target(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var row: Dictionary = _item_at(event.position)
		if not row.is_empty():
			select_item(row.id)
			grab_focus()
			queue_redraw()
		elif not _selected.is_empty():
			_request(_selected, _target(event.position), _rotation)
		# Do not consume press: built-in Control drag uses the same pointer.
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		rotate_selected()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_selection()
		accept_event()

func displayed_art(id: String) -> String:
	var row: Dictionary = _row(id)
	return str(_art_cache.get(str(row.get("visual_id", "")), {}).get("key", ""))

func _draw() -> void:
	if not _translate.is_valid():
		return
	var cell: float = _cell()
	var font: Font = get_theme_default_font()
	for id: String in [STOCK, DISPLAY]:
		var dims: Vector2i = _dims(id)
		var origin: Vector2 = _origin(id)
		draw_string(font, origin + Vector2(0, -7), _t("dayone.stock" if id == STOCK else "dayone.display"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#ded7c4"))
		var base: Rect2 = Rect2(origin, Vector2(dims) * cell)
		draw_rect(base.grow(4), Color("#191f1b"))
		draw_rect(base, Color("#303d34"))
		for x: int in range(dims.x):
			for y: int in range(dims.y):
				var tile: Rect2 = Rect2(origin + Vector2(x,y)*cell, Vector2(cell,cell))
				draw_rect(tile.grow(-1), Color("#354239") if (x+y)%2 == 0 else Color("#313c34"))
				draw_rect(tile, Color("#606d5e"), false, 1)
	for row: Dictionary in _rows:
		if not row.owned or row.inventory not in [STOCK, DISPLAY]:
			continue
		var rect: Rect2 = _rect_for(row).grow(-2)
		draw_rect(rect, Color("#24302a"))
		var visual: Dictionary = _art_cache.get(str(row.get("visual_id", "")), {})
		if not visual.is_empty():
			Art.paint(self, Rect2(rect.position + Vector2(2, 2), Vector2(maxf(1, rect.size.x - 4), maxf(1, rect.size.y - 15))), visual, row.rotated)
		draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 13), Vector2(rect.size.x, 13)), Color("#171f1a"))
		draw_rect(rect, Color("#e7c68a") if _selected == row.id else Color("#9ba28d"), false, 2)
		draw_string(font, rect.position + Vector2(2, rect.size.y - 2), row.id, HORIZONTAL_ALIGNMENT_LEFT, maxf(1.0, rect.size.x - 4), 11, Color("#e2dcc8"))
	if not _selected.is_empty():
		var selected: Dictionary = _row(_selected)
		if not selected.is_empty() and not _hover.is_empty():
			var proposed: Dictionary = selected.duplicate(true)
			proposed.merge(_hover, true)
			proposed.rotated = _rotation
			var ghost: Rect2 = _rect_for(proposed).grow(-1)
			var valid: bool = _placement_ok(_selected, _hover, _rotation)
			draw_rect(ghost, Color(0.45, 0.75, 0.5, 0.35) if valid else Color(0.78, 0.32, 0.25, 0.35))
			draw_rect(ghost, Color("#a5ccac") if valid else Color("#d18f80"), false, 2)
		draw_string(font, Vector2(8, _footer_y()), _selected + " · " + _t("dayone.rotate_on" if _rotation else "dayone.rotate_off"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#ded7c4"))
