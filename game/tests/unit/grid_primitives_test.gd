extends SceneTree
const Grid = preload("res://src/domain/grid_primitives.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func placement(id: String, x: int, y: int, w: int, h: int, rotated: bool = false) -> Dictionary:
	return {"item_id": id, "x": x, "y": y, "width": w, "height": h, "rotated": rotated}

func _initialize() -> void:
	check(Grid.validate(10, 6, []).ok, "C01 ten by six")
	check(Grid.validate(4, 3, []).ok, "old small grid")
	check(not Grid.validate(11, 6, []).ok, "bounded width")
	check(not Grid.validate(0, 3, []).ok, "zero width")
	check(not Grid.validate(4.5, 3, []).ok, "fractional width")
	check(not Grid.validate(4, 3, {}).ok, "list required")
	var items: Array = [placement("root", 7, 4, 3, 2), placement("part", 0, 0, 1, 1)]
	var before: Array = items.duplicate(true)
	check(Grid.validate(10, 6, items) == {"ok": true, "occupied_count": 7}, "independent roots only")
	check(items == before, "validate is pure")
	check(not Grid.validate(10, 6, [placement("a", 8, 4, 3, 2)]).ok, "right edge")
	check(not Grid.validate(10, 6, [placement("a", 7, 5, 3, 2)]).ok, "bottom edge")
	check(Grid.validate(10, 6, [placement("a", 8, 3, 3, 2, true)]).ok, "rotation at edge")
	check(not Grid.validate(10, 6, [placement("a", -1, 0, 1, 1)]).ok, "negative origin")
	check(not Grid.validate(10, 6, [placement("a", 0, 0, 0, 1)]).ok, "zero footprint")
	check(not Grid.validate(10, 6, [placement("a", 0, 0, 9, 1)]).ok, "oversize footprint")
	check(not Grid.validate(10, 6, [placement("a", 0, 0, 2, 2), placement("b", 1, 1, 1, 1)]).ok, "overlap")
	check(not Grid.validate(10, 6, [placement("a", 0, 0, 1, 1), placement("a", 1, 0, 1, 1)]).ok, "duplicate identity")
	check(not Grid.validate(10, 6, [placement("bad id", 0, 0, 1, 1)]).ok, "invalid ID")
	var bad: Dictionary = placement("bad", 0, 0, 1, 1)
	bad.rotated = "true"
	check(not Grid.validate(10, 6, [bad]).ok, "strict rotation")
	bad = placement("bad", 0, 0, 1, 1)
	bad.x = 0.5
	check(not Grid.validate(10, 6, [bad]).ok, "fractional origin")
	var preview: Dictionary = {"item_id": "new", "width": 2, "height": 1, "rotated": false}
	var preview_before: Dictionary = preview.duplicate(true)
	check(Grid.first_fit(10, 6, items, preview) == {"ok": true, "x": 1, "y": 0, "rotated": false}, "row-major preview")
	check(items == before and preview == preview_before, "preview is pure")
	check(Grid.first_fit(1, 2, [], preview) == {"ok": true, "x": 0, "y": 0, "rotated": true}, "alternate rotation")
	check(Grid.first_fit(1, 2, [], preview, false).error == "no_space", "rotation disabled")
	check(Grid.first_fit(1, 1, [placement("a", 0, 0, 1, 1)], preview).error == "no_space", "full grid")
	preview.item_id = "root"
	check(Grid.first_fit(10, 6, items, preview).error == "placement_id", "preview cannot duplicate ID")
	print("GRID_PRIMITIVES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
