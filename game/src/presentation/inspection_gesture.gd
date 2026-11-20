extends RefCounted
## Direct tool placement, not a dexterity minigame. Presentation only.
const TARGETS: Dictionary = {"wear_detail": "visible_wear_detail", "casing_detail": "additional_casing_evidence", "material_detail": "shell_material_sample", "batch_detail": "batch_stamp_sample", "function_detail": "whole_function_sample", "display_damage_detail": "display_damage_sample"}
var tool: String = ""
var target: String = ""

func begin(id: String, _point: Vector2) -> bool:
	cancel()
	if not TARGETS.has(id):
		return false
	tool = id
	return true

func _resolved(area: String) -> String:
	if tool.is_empty():
		return ""
	if area == TARGETS[tool]:
		return tool
	if tool == "wear_detail" and area == TARGETS["display_damage_detail"]:
		return "display_damage_detail"
	return ""

func step(_point: Vector2, area: String) -> void:
	target = area if not _resolved(area).is_empty() else ""

func progress() -> float:
	return 0.0 if target.is_empty() else 1.0

func release(area: String) -> Dictionary:
	var result: Dictionary = {}
	var resolved: String = _resolved(area)
	if not resolved.is_empty():
		result = {"item_id": "R001", "tool_id": resolved, "target": area}
	cancel()
	return result

func cancel() -> void:
	tool = ""
	target = ""
