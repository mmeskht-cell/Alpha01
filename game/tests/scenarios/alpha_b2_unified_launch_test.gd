extends SceneTree
## B2 opt-in entry uses the existing multi-service scene and an isolated A/B
## slot. Legacy New Game, cards and commission saves are not silently migrated.
const Entry = preload("res://src/presentation/b2_launch_route.gd")
const Cards = preload("res://scenes/app/alpha_b2_cards.tscn")
const Commission = preload("res://scenes/app/alpha_b2_commission.tscn")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
	return ok

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not check(ResourceLoader.exists(Entry.SCENE_PATH) and
			Entry.SCENE_PATH == "res://scenes/app/alpha_b2_service_multi.tscn",
			"shared B2 menu target resolves to existing verified multi-service scene"):
		quit(1)
		return
	var path: String = "user://zt_rebuild/b2_launch_boundary_" + str(Time.get_ticks_usec())
	var cards: Control = Cards.instantiate()
	cards.save_directory_override = path
	root.add_child(cards)
	await process_frame
	if not check(cards.session != null and not cards._blocked and cards._slot()=="alpha_b2_cards_pilot_v1",
			"legacy B2 card profile remains readable independently"):
		quit(1)
		return
	var cards_before: Dictionary = cards.session.snapshot()
	check(cards._repo.save_session(cards.session,cards._slot()).get("ok",false),
		"prior cards profile saves to its original A/B slot")
	cards.queue_free()
	await process_frame
	var source: PackedScene = load(Entry.SCENE_PATH) as PackedScene
	var host: Control = source.instantiate() if source != null else null
	if not check(host != null,"selected real B2 unified scene instantiates"):
		quit(1)
		return
	host.save_directory_override=path
	root.add_child(host)
	await process_frame
	if not check(host.session!=null and not host._blocked and host._intro
			and host.b2_mode and host.b2_interactive_mode and host.b2_commission_mode
			and host.b2_named_commission_mode and host.b2_service_mode and host.b2_multi_service_mode,
			"unified scene opens fresh with all real B2 authorities, not loaded cards save"):
		quit(1)
		return
	check(host._slot()=="alpha_b2_service_custody_multi_v3"
		and host._slot()!="alpha_b2_cards_pilot_v1" and host._slot()!="alpha_b2_commission_pilot_v1",
		"unified save slot is separate from earlier cards and commission profiles")
	var commission: Control=Commission.instantiate()
	commission.save_directory_override=path
	root.add_child(commission)
	await process_frame
	check(commission.session != null and not commission._blocked
		and commission._slot()=="alpha_b2_commission_pilot_v1" and commission._intro,
		"unified scene does not replace historical standalone commission profile")
	commission.queue_free()
	await process_frame
	var before: Dictionary=host.session.snapshot()
	var command: Dictionary={
		"action_id":"b2_launch_open",
		"expected_revision":before.revision,
		"type":"alpha_open",
		"payload":{}
	}
	check(host.session.execute(command).get("ok",false)
		and host.session.snapshot().alpha_shop.phase=="OPEN_IDLE",
		"same authority can begin B2 business from isolated entry")
	var live: Dictionary=host.session.snapshot()
	check(host._repo.save_session(host.session,host._slot()).get("ok",false),
		"unified B2 session writes only its own profile key")
	host.queue_free()
	await process_frame
	var resumed: Control=source.instantiate()
	resumed.save_directory_override=path
	root.add_child(resumed)
	await process_frame
	check(resumed.session!=null and not resumed._blocked and not resumed._intro
		and resumed.session.snapshot()==live,
		"unified entry resumes the exact same saved session without reset")
	resumed.queue_free()
	await process_frame
	var old: Control=Cards.instantiate()
	old.save_directory_override=path
	root.add_child(old)
	await process_frame
	check(old.session!=null and not old._blocked and not old._intro
		and old.session.snapshot()==cards_before,
		"opening and saving unified B2 does not migrate or alter prior card save")
	old.queue_free()
	await process_frame
	print("ALPHA_B2_UNIFIED_ENTRY_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
