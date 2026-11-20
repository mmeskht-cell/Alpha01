extends RefCounted
## Pure geometry for independently placed objects. Does not establish ownership or permission.
## Caller must build one complete list of placed objects for the selected inventory.
const Rules = preload("res://src/domain/value_rules.gd")
const MAX_WIDTH: int = 10
const MAX_HEIGHT: int = 10
const MAX_FOOTPRINT: int = 8

static func validate(width: Variant, height: Variant, placements: Variant) -> Dictionary:
	if not Rules.integer(width, 1, MAX_WIDTH) or not Rules.integer(height, 1, MAX_HEIGHT):
		return {"ok": false, "error": "grid_dimensions"}
	if not placements is Array or placements.size() > int(width) * int(height):
		return {"ok": false, "error": "grid_placements"}
	var cells: Dictionary = {}
	var ids: Dictionary = {}
	for entry: Variant in placements:
		if not Rules.keys(entry, ["item_id", "x", "y", "width", "height", "rotated"]):
			return {"ok": false, "error": "placement_shape"}
		if not Rules.identifier(entry.item_id) or ids.has(entry.item_id):
			return {"ok": false, "error": "placement_id"}
		if not Rules.integer(entry.x, 0, int(width) - 1) or not Rules.integer(entry.y, 0, int(height) - 1):
			return {"ok": false, "error": "placement_origin"}
		if not Rules.integer(entry.width, 1, MAX_FOOTPRINT) or not Rules.integer(entry.height, 1, MAX_FOOTPRINT) or not entry.rotated is bool:
			return {"ok": false, "error": "placement_footprint"}
		var w: int = int(entry.height if entry.rotated else entry.width)
		var h: int = int(entry.width if entry.rotated else entry.height)
		var x: int = int(entry.x)
		var y: int = int(entry.y)
		if x + w > int(width) or y + h > int(height):
			return {"ok": false, "error": "placement_bounds"}
		for row: int in range(y, y + h):
			for col: int in range(x, x + w):
				var cell: int = row * int(width) + col
				if cells.has(cell):
					return {"ok": false, "error": "placement_overlap"}
				cells[cell] = entry.item_id
		ids[entry.item_id] = true
	return {"ok": true, "occupied_count": cells.size()}

## Deterministic preview for storage placement. No command, no reservation, no mutation.
## Tries current orientation first then optional alternate; scans rows left to right.
## An existing item must first be excluded from the input list by the trusted caller.
static func first_fit(width: Variant, height: Variant, placements: Variant, item: Variant, allow_rotation: bool = true) -> Dictionary:
	var base: Dictionary = validate(width, height, placements)
	if not base.ok:
		return base
	if not Rules.keys(item, ["item_id", "width", "height", "rotated"]):
		return {"ok": false, "error": "preview_shape"}
	if not Rules.identifier(item.item_id) or not Rules.integer(item.width, 1, MAX_FOOTPRINT) or not Rules.integer(item.height, 1, MAX_FOOTPRINT) or not item.rotated is bool:
		return {"ok": false, "error": "preview_item"}
	for p: Dictionary in placements:
		if p.item_id == item.item_id:
			return {"ok": false, "error": "placement_id"}
	var orientations: Array = [item.rotated]
	if allow_rotation and item.width != item.height:
		orientations.append(not item.rotated)
	var trial: Array = placements.duplicate(true)
	var candidate: Dictionary = item.duplicate(true)
	trial.append(candidate)
	for rotated: bool in orientations:
		candidate.rotated = rotated
		for y: int in range(int(height)):
			for x: int in range(int(width)):
				candidate.x = x
				candidate.y = y
				if validate(width, height, trial).ok:
					return {"ok": true, "x": x, "y": y, "rotated": rotated}
	return {"ok": false, "error": "no_space"}
