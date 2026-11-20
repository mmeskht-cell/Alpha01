extends RefCounted
const Session = preload("res://src/domain/game_session.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Context = preload("res://tests/fixtures/gate0_c_state.gd")
const Calendar = preload("res://src/domain/campaign_calendar.gd")
const Queue = preload("res://src/domain/campaign_visit_queue.gd")
const Rules = preload("res://src/domain/value_rules.gd")
const Observation = preload("res://src/domain/visit_appraisal_observation.gd")

static func fresh(enabled: bool = true, wrong: bool = false, claims: bool = false, lifecycle: bool = false, tracking: bool = false) -> RefCounted:
	var defs: Dictionary = {"fictional_watch_p2":{"def_id":"fictional_watch_p2","category":"fixture","localization_key":"p2.watch.meridian12","render_key":"placeholder_none","width":1,"height":1}}
	var items: Dictionary = {}
	items["W001"] = Objects.fresh_item("fictional_watch_p2","seller","seller_grid",0,0,"wrong" if wrong else "p2_watch_a")
	items["W002"] = Objects.fresh_item("fictional_watch_p2","seller","seller_grid",1,0,"p2_watch_b")
	items["W002"]["functional"] = false
	var visits: Dictionary = {}
	for pair: Array in [["watch_a","W001"],["watch_b","W002"]]:
		var visit_id: String = pair[0]
		var subject_id: String = pair[1]
		var prices: Dictionary = {}
		prices[subject_id] = {"VKC":90,"USD":0}
		var visit: Dictionary = Context.visit(visit_id,"seller","player",prices)
		visit["opens"] = 0
		visit["expires"] = 600
		visit["allow_inspection"] = true
		visits[visit_id] = visit
	var seed: Dictionary = {"object_schema":3,"revision":0,"game_minutes":0,"wallets":{"player":{"VKC":180,"USD":0},"seller":{"VKC":0,"USD":0}},"inventories":{"player_grid":{"owner_id":"player","width":4,"height":3,"host_item":""},"seller_grid":{"owner_id":"seller","width":4,"height":3,"host_item":""}},"items":items,"ledger":[],"receipts":{},"receipt_archive":{},"tombstones":{},"object_events":[],"visits":visits,"phase":"shop","knowledge":{}}
	var ids: Array = ["d1","d2","d3","d4","d5","d6","d7"]
	var schedule: Dictionary = {}
	for id: String in ids:
		schedule[id] = []
	schedule["d1"] = ["watch_a","watch_b"]
	var profile: Dictionary = {"id":"demo_7","content_version":"p2-watch-claims-1" if claims and enabled else "p2-watch-authority-1","day_ids":ids,"visit_days":schedule}
	if enabled:
		profile["appraisal_profile"] = "watch_p2_v1"
	if lifecycle:
		profile["lifecycle_version"] = Calendar.LIFECYCLE_VERSION
	if tracking:
		profile["tracking_candidates"] = {"W001":{"tier":"tracked","pinned":false}}
	# Strict registry IDs are String, not StringName; never create IDs using dot syntax.
	for id: Variant in items:
		if not Rules.identifier(id) or not Rules.keys(items[id],Objects.ITEM_FIELDS):
			printerr("FAIL: fixture identity shape ",str(id)," type=",typeof(id))
			return null
	var s := Session.new()
	if s.initialize(defs,seed,false,false,profile):
		return s
	if not wrong:
		var normalized_defs: Dictionary = {}
		for id: String in defs:
			normalized_defs[id] = Objects.definition(defs[id])
		var definitions_ok: bool = not normalized_defs.fictional_watch_p2.is_empty()
		var calendar_seed: Dictionary = Calendar.seed(seed,normalized_defs,profile)
		print("P2_FIXTURE_DIAGNOSTIC enabled=",enabled," definitions=",definitions_ok," objects=",Objects.validate(seed,normalized_defs) if definitions_ok else false," profile=",Calendar.profile_valid(profile)," queue=",not Queue.seed(seed,profile).is_empty()," sample_binding=",not Observation.seed(seed,profile).is_empty() if enabled else true," calendar_seed=",not calendar_seed.is_empty())
		print("P2_FIXTURE_VISITS ", Rules.canonical(seed.visits))
		print("P2_OBJECT_GUARD ",Objects.validation_error(seed,normalized_defs) if definitions_ok else "definitions")
		print("P2_FIXTURE_ITEMS ",Rules.canonical(seed.items))
		print("P2_FIXTURE_GRIDS ",Rules.canonical(seed.inventories))
		print("P2_FIXTURE_INIT_STAGE ",s.initialization_error())
	return null

