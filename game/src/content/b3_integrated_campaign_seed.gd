extends RefCounted
## The regular campaign inherits the complete F5 source and adds the catalog.
const FirstWeek = preload("res://src/content/b3_f3_composite_seed.gd")
const Catalog = preload("res://src/domain/b3_integrated_catalog.gd")

static func content(seed_value: int) -> Dictionary:
	return Catalog.extend(FirstWeek.content(seed_value))
