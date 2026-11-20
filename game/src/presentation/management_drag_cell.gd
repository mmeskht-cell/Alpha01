extends Button
## Local drag data and callback target. No authority mutations.
var token:Dictionary={}
var accepts:Callable
var commit:Callable

func _get_drag_data(_position:Vector2)->Variant:
	if disabled or token.is_empty():
		return null
	var preview:=PanelContainer.new()
	preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var label:=Label.new()
	label.text=str(token.get("id",""))
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	preview.add_child(label)
	set_drag_preview(preview)
	return token.duplicate(true)

func _can_drop_data(_position:Vector2,data:Variant)->bool:
	return not disabled and accepts.is_valid() and bool(accepts.call(data))

func _drop_data(point:Vector2,data:Variant)->void:
	if _can_drop_data(point,data) and commit.is_valid():
		commit.call(data)
