extends SceneTree
const Runtime = preload("res://src/application/foundation_runtime.gd")
const CheckpointProbe = preload("res://tests/fixtures/checkpoint_campaign_probe.gd")
var checks: int = 0
var failures: int = 0
var rt: RefCounted
var serial: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func send(kind: String, payload: Dictionary = {}) -> bool:
	serial += 1
	var r: Dictionary = rt.submit({"action_id": "maint_" + str(serial), "expected_revision": rt.counter_view().revision, "type": kind, "payload": payload})
	return r.ok and r.get("persisted", false)

func _initialize() -> void:
	var directory: String = "user://zt_rebuild/day_one/maint_" + str(Time.get_ticks_usec())
	rt = Runtime.new()
	if not rt.initialize_day_one(directory):
		printerr("FAIL: maintenance init")
		quit(1)
		return
	var start_bytes: int = rt.save_capacity_view().bytes
	var ready: bool = send("accept_rad1_contract") and send("next_visit")
	ready = ready and send("inspect_radio", {"item_id": "R001", "tool_id": "function_detail", "target": "whole_function_sample"})
	ready = ready and send("make_offer", {"amount": 125, "evidence_id": null})
	var id: String = "maint_" + str(serial)
	ready = ready and send("confirm_purchase", {"offer_id": id, "inventory": "player_stock", "x": 0, "y": 0, "rotated": false}) and send("begin_day_one")
	check(ready, "maintenance save sample setup")
	if not ready:
		quit(1)
		return
	var base_bytes: int = rt.save_capacity_view().bytes
	var durations: Array[int] = []
	var all_moves: bool = true
	for i: int in range(12):
		var start: int = Time.get_ticks_usec()
		if not send("move", {"actor": "player", "item_id": "R001", "inventory": "player_display" if i % 2 == 0 else "player_stock", "x": 0, "y": 0, "rotated": false}):
			all_moves = false
			break
		durations.append(Time.get_ticks_usec() - start)
	check(all_moves and durations.size() == 12, "12 bounded real saved moves")
	var final: Dictionary = rt.snapshot()
	var final_bytes: int = rt.save_capacity_view().bytes
	check(final_bytes >= base_bytes and rt.save_capacity_view().fits, "bounded sample fits existing schema")
	check(final.wallets.player.VKC == 55 and final.game_minutes == 5 and final.ledger.size() == 1, "moves do not duplicate economics or elapsed time")
	var reload_start: int = Time.get_ticks_usec()
	check(rt.load_saved().ok and rt.snapshot() == final, "real saved sample reload identical")
	var reload_us: int = Time.get_ticks_usec() - reload_start
	durations.sort()
	print("ZT_MAINT_SAMPLE ", JSON.stringify({"initial_bytes": start_bytes, "base_bytes": base_bytes, "final_bytes": final_bytes, "moves": durations.size(), "revision": final.revision, "min_save_us": durations[0] if not durations.is_empty() else -1, "median_save_us": durations[floori(durations.size() / 2.0)] if not durations.is_empty() else -1, "max_save_us": durations.back() if not durations.is_empty() else -1, "reload_us": reload_us}))
	var converted: Dictionary = CheckpointProbe.probe(directory, false, final)
	check(converted.get("ok", false), "actual default campaign v3 to isolated v4 exact readback and unchanged originals")
	print("ZT_CAMPAIGN_CHECKPOINT ", JSON.stringify(converted))
	rt.shutdown()
	for filename: String in ["gate1_day_one_v3.a.json", "gate1_day_one_v3.b.json"]:
		DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	print("MAINTENANCE_SAMPLE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
