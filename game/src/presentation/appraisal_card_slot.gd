extends Button
## Explicit assessment destination. Drag carries exactly one publicly available field.
signal card_placed(field: String, value: Variant, revision: int)
var field: String = ""
var revision: int = -1

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return not disabled and data is Dictionary and data.get("kind") == "appraisal_hypothesis" and data.get("attribute_id") == field and data.get("revision") == revision and data.has("attribute_value")

func _drop_data(point: Vector2, data: Variant) -> void:
	if _can_drop_data(point,data):
		card_placed.emit(field,data.attribute_value,revision)
