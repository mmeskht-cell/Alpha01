extends RefCounted
const Base = preload("res://src/content/b3_f3_composite_seed.gd")
const Supply = preload("res://src/domain/b3_civilian_supply.gd")

static func content(seed_value: int) -> Dictionary:
	return Supply.extend(Base.content(seed_value),2)
