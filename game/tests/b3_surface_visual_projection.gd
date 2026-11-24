extends SceneTree
## W15 synthetic projection checks; run only in the later integrated pass.
const Surface = preload("res://src/presentation/surface_visuals.gd")
var checks: int = 0
var failures: int = 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var cards: Array = [{"slot":"material_detail","value":"parallel"},{"slot":"wear_detail","value":"43"},{"slot":"display_damage_detail","value":"12"}]
	var copy: Array = cards.duplicate(true)
	check("no unobserved sample",Surface.observed([],"wear_detail",42).is_empty())
	check("unsupported slot",Surface.observed(cards,"function_detail",42).is_empty())
	check("surface-only slots",Surface.observation_slots(cards)==Surface.SLOTS)
	check("pattern does not infer actual material",Surface.observed(cards,"material_detail",42).get("base")=="parallel")
	check("unknown pattern rejected",Surface.observed([{"slot":"material_detail","value":"metal"}],"material_detail",42).is_empty())
	var sample: Dictionary = Surface.observed(cards,"wear_detail",42)
	check("repeat deterministic",sample==Surface.observed(cards,"wear_detail",42))
	check("wear does not infer actual material",sample.get("base")=="neutral")
	check("display does not infer glass",Surface.observed(cards,"display_damage_detail",42).get("base")=="neutral")
	var none: Dictionary = Surface.observed([{"slot":"wear_detail","value":"0"}],"wear_detail",42)
	check("zero signal no overlay",none.get("overlay")=="")
	check("out of bounds rejected",Surface.observed([{"slot":"wear_detail","value":"101"}],"wear_detail",42).is_empty())
	check("non-numeric rejected",Surface.observed([{"slot":"wear_detail","value":"unknown"}],"wear_detail",42).is_empty())
	var severe: Dictionary = Surface.observed([{"slot":"wear_detail","value":"90"}],"wear_detail",42)
	check("larger observed signal changes coverage",float(severe.coverage)>float(sample.coverage) and severe.overlay==sample.overlay)
	check("no mutation",cards==copy)
	check("unknown reference rejected",Surface.reference_sample("wood",0).is_empty())
	check("five reference families",Surface.MATERIALS.size()==5)
	for material: String in Surface.MATERIALS:
		var low: Dictionary = Surface.reference_sample(material,0)
		var high: Dictionary = Surface.reference_sample(material,2)
		check("reference examples distinct "+material,low.base==material and high.coverage>low.coverage and high.opacity>low.opacity)
	print("B3 surface projection: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)
