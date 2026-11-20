extends Button
signal card_presented(argument: Dictionary, revision: int)
var revision: int = -1

func _can_drop_data(_position: Vector2,data: Variant) -> bool:
	return not disabled and data is Dictionary and data.get("kind") == "negotiation_argument" and data.get("revision") == revision and data.get("argument") is Dictionary

func _drop_data(point: Vector2,data: Variant) -> void:
	if _can_drop_data(point,data):
		card_presented.emit(data.argument,revision)
