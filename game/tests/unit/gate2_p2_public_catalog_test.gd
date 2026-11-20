extends SceneTree
const Catalog = preload("res://src/domain/public_appraisal_catalog.gd")
const Radio = preload("res://src/domain/gate1_appraisal.gd")
const Docs = preload("res://src/content/packaged_documents.gd")
const PATH: String = "res://data/campaign/gate2/watch_public_catalog.json"
var checks: int = 0
var failures: int = 0
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func _initialize() -> void:
	var raw: Dictionary = Docs.read_object(PATH)
	var profile: Dictionary = Catalog.parse(raw)
	check(not profile.is_empty(),"public fictional watch profile")
	if profile.is_empty():
		quit(1)
		return
	check(profile.slots.size() == 5,"applicable categories only; history separate")
	check(Catalog.estimate(profile,{}).estimate == null,"empty selection remains unknown")
	check(Catalog.estimate(profile,{"appearance_id":"visible_wear"}).estimate == null,"condition first allowed")
	check(Catalog.estimate(profile,{"model_id":"meridian_12"}).estimate == null,"model without appearance remains partial")
	var selection: Dictionary = {"model_id":"meridian_12","appearance_id":"visible_wear","material_id":"decorative_case","function_id":"inoperable","mark_id":"commemorative_mark"}
	var preview: Dictionary = Catalog.estimate(profile,selection)
	check(preview.estimate == 112 and preview.partial,"single factor and independent adjustment, conjecture only")
	var reverse: Dictionary = {"mark_id":"commemorative_mark","function_id":"inoperable","material_id":"decorative_case","appearance_id":"visible_wear","model_id":"meridian_12"}
	check(Catalog.estimate(profile,reverse) == preview,"placement order invariant")
	reverse.function_id = "serviceable"
	check(Catalog.estimate(profile,reverse).estimate == preview.estimate,"nonprice function does not auto alter reference")
	reverse.model_id = "meridian_12a"
	check(Catalog.estimate(profile,reverse).estimate == 160,"alternative selected model allowed")
	reverse.erase("material_id")
	check(Catalog.estimate(profile,reverse).estimate == 144,"remove optional adjustment")
	reverse.appearance_id = null
	check(Catalog.estimate(profile,reverse).estimate == null,"clear condition")
	check(Catalog.estimate(profile,{"model_id":"selvar_r18"}).is_empty(),"other profile candidate rejected")
	check(Catalog.estimate(profile,{"history_id":"unknown"}).is_empty(),"no illegal slot")
	check(Catalog.estimate(profile,{"model_id":true}).is_empty(),"shape validation")
	var broken: Dictionary = raw.duplicate(true)
	broken.slots.append(broken.slots[0].duplicate(true))
	check(Catalog.parse(broken).is_empty(),"duplicate slot rejected")
	broken = raw.duplicate(true)
	broken.slots[1].candidates[0].value = 501
	check(Catalog.parse(broken).is_empty(),"modifier bounded")
	broken = raw.duplicate(true)
	broken.slots[0].candidates.append(broken.slots[0].candidates[0].duplicate(true))
	check(Catalog.parse(broken).is_empty(),"duplicate candidate rejected")
	broken = raw.duplicate(true)
	broken["truth"] = "meridian_12"
	check(Catalog.parse(broken).is_empty(),"public schema excludes truth")
	broken = raw.duplicate(true)
	broken.slots[3].candidates[0].value = 10
	check(Catalog.parse(broken).is_empty(),"nonprice slot no hidden bonus")
	var ref: Dictionary = Radio.public_reference()
	check(Radio.estimate({"model_id":"selvar_r18","appearance_id":"visible_wear"},ref).estimate == 160,"legacy R001 unchanged")
	check(Radio.estimate({"model_id":"selvar_r18","appearance_id":"visible_wear","material_id":"light_alloy","batch_id":"series_late"},ref).estimate == 172,"legacy adjustment unchanged")
	check(Radio.estimate({"model_id":"selvar_r18s","appearance_id":"visible_wear"},ref).estimate == 192,"legacy alternative unchanged")
	check(Radio.estimate({"model_id":null,"appearance_id":null},ref).estimate == null,"legacy empty unchanged")
	print("GATE2_P2_PUBLIC_CATALOG: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
