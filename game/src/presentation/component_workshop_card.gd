extends Button
## Preview card drag/drop. Commands are still authorized by GameSession.
signal dropped(data: Dictionary)
var payload: Dictionary = {}
var accepted_kinds: Array = []

func _get_drag_data(_at: Vector2) -> Variant:
	if disabled or payload.is_empty():
		return null
	var preview := PanelContainer.new()
	var caption := Label.new()
	caption.text = text
	preview.add_child(caption)
	set_drag_preview(preview)
	return payload.duplicate(true)

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return not disabled and data is Dictionary and data.get("kind") in accepted_kinds

func _drop_data(at: Vector2, data: Variant) -> void:
	if _can_drop_data(at, data):
		dropped.emit(data)
