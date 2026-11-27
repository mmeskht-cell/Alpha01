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
	# Authored profiles are allowed only for matching acquired surface facts.
	var profiles := {"material_detail":{"family":"metal","target":"shell"},"wear_detail":{"family":"metal","target":"shell"}}
	var metal: Dictionary = Surface.observed(cards,"wear_detail",42,profiles)
	check("authored metal uses matching overlay",metal.base=="metal" and str(metal.overlay).begins_with("metal_wear_"))
	check("same shell material and wear combine",Surface.observed(cards,"material_detail",42,profiles)==metal)
	check("unobserved wear not synthesized",Surface.observed([cards[0]],"material_detail",42,profiles).get("overlay")=="")
	check("no unobserved profile reveal",Surface.observed([],"material_detail",42,profiles).is_empty())
	check("new same seed deterministic",metal==Surface.observed(cards,"wear_detail",42,profiles))
	var varied: Dictionary = Surface.observed(cards,"wear_detail",43,profiles)
	check("different seed changes placement",metal.offset_x!=varied.offset_x or metal.offset_y!=varied.offset_y)
	var other := profiles.duplicate(true)
	other.wear_detail.target = "different"
	check("different targets never combined",Surface.observed(cards,"material_detail",42,other).get("overlay")=="")
	var stale := [{"slot":"wear_detail","value":"43","surface_current":false}]
	check("historical card cannot supply a current texture",Surface.observation_slots(stale).is_empty()
		and Surface.observed(stale,"wear_detail",42,profiles).is_empty())
	var maximum := [{"slot":"wear_detail","value":"100"}]
	var extreme: Dictionary = Surface.observed(maximum,"wear_detail",42,profiles)
	var relocated: Dictionary = Surface.observed(maximum,"wear_detail",43,profiles)
	var extreme_frame := _overlay_frame(extreme)
	var relocated_frame := _overlay_frame(relocated)
	check("maximum damage leaves space for seeded placement",extreme_frame.position!=relocated_frame.position
		and Rect2i(0,0,256,256).encloses(extreme_frame) and Rect2i(0,0,256,256).encloses(relocated_frame))
	check("maximum damage placement changes actual pixels",_pixels(extreme)!=_pixels(relocated))
	check("missing or unrelated overlay does not fabricate a clean plate",Surface.texture_for({"base":"glass","overlay":"metal_wear_1"})==null)
	for family: String in Surface.MATERIALS:
		var typed := {"wear_detail":{"family":family,"target":"shell"}}
		var observed: Dictionary = Surface.observed(cards,"wear_detail",42,typed)
		check("matching material "+family,observed.base==family and str(observed.overlay).begins_with(family+"_wear_"))
		var clear: Dictionary = Surface.observed([{"slot":"wear_detail","value":"0"}],"wear_detail",42,typed)
		check("zero damage "+family,clear.get("overlay")=="")
		var pristine := _pixels(clear)
		var live_pixels := _pixels(observed)
		check("visible current marks "+family,not pristine.is_empty() and live_pixels.size()==pristine.size() and live_pixels!=pristine)
		var previous := pristine
		for grade in range(3):
			var pixels := _pixels(Surface.reference_sample(family,grade))
			check("distinct pixels for reference %s grade %d"%[family,grade],pixels.size()==pristine.size() and pixels!=previous)
			previous = pixels
	var Domain = preload("res://src/domain/appraisal_surface_profiles.gd")
	var item := {"def_id":"portable_radio","provenance_id":"demo_R001","field_versions":{"functional":0,"restored":0,"composition":0}}
	var fact := {"slot":"wear_detail","value":43,"kind":"fact","version":item.field_versions.duplicate()}
	check("domain no unread profile",Domain.project("R001",item,{}).is_empty())
	check("domain authored acquired wear",Domain.project("R001",item,{"wear_detail":fact}).get("wear_detail",{}).get("family")=="metal")
	check("domain foreign item blocked",Domain.project("R003",item,{"wear_detail":fact}).is_empty())
	var wrong := fact.duplicate(true)
	wrong.value = 44
	check("domain does not extrapolate an authored wear state",Domain.project("R001",item,{"wear_detail":wrong}).is_empty())
	check("domain does not move a fact between slots",Domain.project("R001",item,{"display_damage_detail":fact}).is_empty())
	fact.version.functional = 1
	check("domain stale profile blocked",Domain.project("R001",item,{"wear_detail":fact}).is_empty())
	var first_week := {"spatial_opening":1,"week_proposal":"first_week_proposal_1"}
	var watch := {"def_id":"fictional_watch_p2","provenance_id":"p2_watch_a","field_versions":{"functional":0,"restored":0,"composition":0}}
	var authored := Domain.authored_readings(first_week,"WAT02",watch)
	check("watch has distinct authored front and back",authored.size()==3 and authored.wear_detail.side=="back" and authored.display_damage_detail.side=="front")
	check("old profiles do not gain new readings",Domain.authored_readings({},"WAT02",watch).is_empty())
	check("foreign watch identity rejected",Domain.authored_readings(first_week,"W002",watch).is_empty())
	var acquired := {}
	for slot: String in authored:
		acquired[slot] = {"slot":slot,"value":authored[slot].value,"kind":"fact","version":watch.field_versions.duplicate(true)}
	var surfaces := Domain.project("WAT02",watch,acquired)
	check("watch caseback and crystal have separate targets",surfaces.size()==3 and surfaces.wear_detail.target!=surfaces.display_damage_detail.target and surfaces.wear_detail.family=="metal" and surfaces.display_damage_detail.family=="glass")
	check("no unacquired watch surfaces",Domain.project("WAT02",watch,{}).is_empty())
	watch.field_versions.restored = 1
	check("changed watch has no fabricated current reading",Domain.authored_readings(first_week,"WAT02",watch).is_empty() and Domain.project("WAT02",watch,acquired).is_empty())
	for example: Array in [["BAT02","battery","demo_BAT02","plastic"],["TL04","demo_tool","demo_TL04","metal"],["HY05","demo_hygiene","demo_HY05","paper"]]:
		var sample_item := {"def_id":example[1],"provenance_id":example[2],"field_versions":{"functional":0,"restored":0,"composition":0}}
		var readings := Domain.authored_readings(first_week,example[0],sample_item)
		var reading := {"slot":"wear_detail","value":readings.get("wear_detail",{}).get("value"),"kind":"fact","version":sample_item.field_versions.duplicate(true)}
		var projected := Domain.project(example[0],sample_item,{"wear_detail":reading})
		check("authored real SKU "+example[0],readings.size()==1 and projected.get("wear_detail",{}).get("family")==example[3])
	var Supply = preload("res://src/domain/b3_civilian_supply.gd")
	var SupplySeed = preload("res://src/content/b3_civilian_supply_seed.gd")
	var Baseline = preload("res://src/content/b3_f3_composite_seed.gd")
	var Session = preload("res://src/domain/game_session.gd")
	var Art = preload("res://src/presentation/native_v23_art.gd")
	var seen := {}
	for seed_value: int in [101,102,103,104]:
		var source: Dictionary = SupplySeed.content(seed_value)
		var base: Dictionary = Baseline.content(seed_value)
		check("civilian supply source exists "+str(seed_value),not source.is_empty())
		if source.is_empty(): continue
		check("civilian expansion deterministic "+str(seed_value),source==SupplySeed.content(seed_value))
		check("old wallets and original items unchanged",source.state.wallets==base.state.wallets and base.state.items.keys().all(func(id:String)->bool:return source.state.items.get(id)==base.state.items[id]))
		check("four finite additional packages",source.state.items.size()==base.state.items.size()+4 and source.state.visits.size()==base.state.visits.size()+8)
		var session := Session.new()
		var initialized := session.initialize(source.defs,source.state,false,false,{},source.alpha_profile)
		check("expanded real session initializes "+session.initialization_error(),initialized)
		if initialized and seed_value==104:
			var Repo = preload("res://src/persistence/save_repository.gd")
			var disk := Repo.new("user://zt_rebuild/civilian_supply_fixed_"+str(Time.get_ticks_usec()))
			check("isolated revision-zero save",disk.save_session(session,"civilian_supply").get("ok",false))
			var resumed := Session.new()
			var ready := resumed.initialize(source.defs,source.state,false,false,{},source.alpha_profile)
			check("same content save resumes exact snapshot",ready and disk.load_session(resumed,"civilian_supply").get("ok",false) and resumed.snapshot()==session.snapshot())
			var legacy := Session.new()
			if legacy.initialize(base.defs,base.state,false,false,{},base.alpha_profile):
				var unchanged := legacy.snapshot()
				check("expanded save rejected by legacy source without mutation",not disk.load_session(legacy,"civilian_supply").get("ok",false) and legacy.snapshot()==unchanged)
			else:
				check("legacy source remains valid",false)
		for row: Dictionary in Supply.selected(seed_value):
			seen[row.id] = true
			check("real matching counter and stock art "+str(row.model),Art.ITEMS.model_texture(row.model,"counter")!=null and Art.ITEMS.model_texture(row.model,"stock")!=null)
			var actual: Dictionary = source.state.items[row.id]
			check("package cannot appear in old profile",Domain.authored_readings(base.alpha_profile,row.id,actual).is_empty())
			var readings := Domain.authored_readings(source.alpha_profile,row.id,actual)
			if not readings.is_empty():
				var evidence := {"slot":"wear_detail","kind":"fact","value":readings.wear_detail.value,"version":actual.field_versions.duplicate(true)}
				check("actual authored wrapper projects "+str(row.id),not Domain.project(row.id,actual,{"wear_detail":evidence}).is_empty())
	check("eight models across four seeds",seen.size()==8)
	print("B3 surface projection: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)

func _overlay_frame(sample: Dictionary) -> Rect2i:
	var extent := roundi(256.0*float(sample.coverage))
	var room := 256-extent
	return Rect2i(roundi(room*float(sample.offset_x)),roundi(room*float(sample.offset_y)),extent,extent)

func _pixels(sample: Dictionary) -> PackedByteArray:
	var texture := Surface.texture_for(sample)
	if texture==null: return PackedByteArray()
	var image := texture.get_image()
	if image==null or (image.is_compressed() and image.decompress()!=OK): return PackedByteArray()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	return image.get_data()
