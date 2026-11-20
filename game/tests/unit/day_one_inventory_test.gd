extends SceneTree
const PagedRows = preload("res://src/presentation/paged_rows.gd")
const Inventory = preload("res://src/presentation/day_one_inventory.gd")
var failures: int = 0
var checks: int = 0
var intents: Array = []

func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", name)

func translate(key: String, _args: Dictionary) -> String:
	return key

func _initialize() -> void:
	var grid := Inventory.new()
	var rows: Array = [
		{"id": "R001", "owned": true, "inventory": "player_stock", "x": 0, "y": 0, "size": [3, 2], "rotated": false, "name_key": "item.portable_radio"},
		{"id": "blocker", "owned": true, "inventory": "player_display", "x": 0, "y": 0, "size": [2, 1], "rotated": false, "name_key": "item.portable_radio"}
	]
	grid.configure(rows, translate, false)
	grid.move_requested.connect(func(payload: Dictionary) -> void: intents.append(payload))
	var occupied: Dictionary = {"inventory": "player_display", "x": 1, "y": 0}
	var edge: Dictionary = {"inventory": "player_display", "x": 5, "y": 0}
	var valid: Dictionary = {"inventory": "player_display", "x": 3, "y": 0}
	check(not grid._placement_ok("R001", occupied, false), "overlap is rejected by shared grid geometry")
	check(not grid._placement_ok("R001", edge, false), "bounds rejected")
	check(grid._placement_ok("R001", valid, false), "valid preview")
	grid._request("R001", occupied, false)
	grid._request("R001", edge, false)
	check(intents.is_empty(), "invalid preview sends no command")
	grid._request("R001", valid, false)
	check(intents.size() == 1 and intents[0].inventory == "player_display" and intents[0].x == 3, "valid placement sends one detached intent")
	grid.set("_selected", "R001")
	grid.apply_rotation_in_place()
	check(intents.size() == 1, "unchanged orientation does not submit")
	grid.rotate_selected()
	grid.apply_rotation_in_place()
	check(intents.size() == 2 and intents[1].rotated and intents[1].inventory == "player_stock" and intents[1].x == 0, "in-place rotation uses current coordinates")
	grid.configure(rows, translate, true)
	grid._request("R001", valid, false)
	grid.apply_rotation_in_place()
	check(intents.size() == 2, "save lock prevents placement and rotation")
	check(rows[0].rotated == false and rows[0].inventory == "player_stock", "preview never mutates public input")
	grid.configure(rows, translate, false)
	grid.size = Vector2(360, 600)
	check(grid._stacked() and grid._origin("player_display").y > grid._origin("player_stock").y + grid._cell() * 6, "narrow grids stack without overlap")
	check(grid._target(grid._origin("player_display") + Vector2.ONE * grid._cell() * 0.5) == {"inventory": "player_display", "x": 0, "y": 0}, "stacked pointer target accurate")
	grid.size = Vector2(800, 600)
	check(not grid._stacked() and grid._origin("player_display").x > grid._origin("player_stock").x + grid._cell() * 10, "wide grid stays side by side")
	check(grid.selection_options().size() == 2, "indexed selection preserves all owned rows")
	grid.free()
	var records: Array = []
	for i: int in range(10001):
		records.append({"index": i})
	var pages := PagedRows.new()
	pages.configure(records, translate, func(row: Dictionary) -> String: return str(row.index))
	check(pages.page_view() == {"page": 0, "pages": 501, "total": 10001, "first": 0, "end": 20, "rendered": 20}, "10k records render only one bounded page")
	pages.change_page(1)
	check(pages.page_view().first == 20 and pages.page_view().end == 40 and pages.page_view().rendered == 20, "next page correct")
	pages.change_page(10000)
	check(pages.page_view().page == 500 and pages.page_view().end == 10001 and pages.page_view().rendered == 1, "last record accessible, no truncation")
	pages.change_page(1)
	check(pages.page_view().page == 500 and records.size() == 10001, "page limit does not change records")
	pages.change_page(-10000)
	check(pages.page_view().first == 0 and pages.page_view().rendered == 20, "all records remain reachable")
	pages.free()
	print("DAY_ONE_INVENTORY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
