extends Button
## Delegates both hover validation and commit to the current panel.
var accepts: Callable
var commit: Callable

func _can_drop_data(_position: Vector2,data: Variant) -> bool:
	return not disabled and accepts.is_valid() and bool(accepts.call(data))

func _drop_data(point: Vector2,data: Variant) -> void:
	if _can_drop_data(point,data) and commit.is_valid():
		commit.call(data)
