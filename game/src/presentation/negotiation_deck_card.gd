extends Button
## Drag represents a prepared public argument, not an automatic discount.
var argument: Dictionary = {}
var revision: int = -1

func _get_drag_data(_position: Vector2) -> Variant:
	if disabled or argument.is_empty():
		return null
	var preview := Label.new()
	preview.text = text
	set_drag_preview(preview)
	return {"kind":"negotiation_argument","argument":argument.duplicate(true),"revision":revision}
