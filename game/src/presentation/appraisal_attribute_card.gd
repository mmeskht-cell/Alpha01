extends Button
## A presentation card: dragging places the player's hypothesis, never an observed fact.
var model_id: Variant = null
var appearance_id: Variant = null
var attribute_id: String = ""
var attribute_value: Variant = null
var revision: int = -1

func _get_drag_data(_position: Vector2) -> Variant:
	if disabled:
		return null
	var preview := PanelContainer.new()
	var caption := Label.new()
	caption.text = text
	preview.add_child(caption)
	set_drag_preview(preview)
	return {"kind": "appraisal_hypothesis", "model_id": model_id, "appearance_id": appearance_id, "attribute_id": attribute_id, "attribute_value": attribute_value, "revision": revision}
