extends SceneTree
const Registry = preload("res://src/domain/dormant_registry.gd")
const Tracking = preload("res://src/domain/selective_tracking.gd")
const Codec = preload("res://src/persistence/registry_pilot_format.gd")
const Fixture = preload("res://tests/fixtures/gate0_c_state.gd")
const Session = preload("res://src/domain/game_session.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Rules = preload("res://src/domain/value_rules.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	var s := Session.new()
	var initial: Dictionary = Fixture.make()
	initial.game_minutes = 10
	initial.visits.purchase.expires = 5
	check(s.initialize(Fixture.definitions(), initial), "expired fixture valid")
	var full: Dictionary = s.snapshot()
	var p: Dictionary = Registry.begin(full, s)
	check(not p.is_empty(), "partition created only from validated authority")
	if p.is_empty():
		quit(1)
		return
	check(Registry.sleep_family(p, "X01_A", s).is_empty(), "cannot split family")
	var asleep: Dictionary = Registry.sleep_family(p, "X01", s)
	check(not asleep.is_empty() and asleep.state.items.is_empty() and asleep.dormant.X01.size() == full.items.size(), "whole composite moved to separate dormant index")
	if asleep.is_empty():
		quit(1)
		return
	check(Registry.materialize(asleep, s) == full and s.snapshot() == full, "lossless reconstruction without authority change")
	check(Registry.locate(asleep, "X01_A") == "dormant" and Registry.locate(asleep, "unknown") == "unknown", "independent child identity retained")
	check(Registry.wake_family(asleep, "X01", s) == p, "same family exact reactivation")
	check(Registry.wake_family(asleep, "unknown", s).is_empty(), "unknown identity not resurrected")
	var invalid: Dictionary = asleep.duplicate(true)
	invalid.state.items.X01_A = full.items.X01_A.duplicate(true)
	check(Registry.materialize(invalid, s).is_empty(), "duplicate active and dormant rejected")
	invalid = asleep.duplicate(true)
	invalid.dormant.X01.erase("X01_A")
	invalid.state.items.X01_A = full.items.X01_A.duplicate(true)
	check(Registry.materialize(invalid, s).is_empty(), "half family rejected")
	invalid = asleep.duplicate(true)
	invalid.state.tombstones.X01 = {}
	check(Registry.materialize(invalid, s).is_empty(), "terminal collision rejected")
	var active: Dictionary = initial.duplicate(true)
	active.visits.purchase.expires = 600
	var open_session := Session.new()
	check(open_session.initialize(Fixture.definitions(), active), "open fixture")
	check(Registry.sleep_family(Registry.begin(open_session.snapshot(), open_session), "X01", open_session).is_empty(), "pending visit prevents dormancy")
	active = initial.duplicate(true)
	active.items.X01.protected = true
	var protected_session := Session.new()
	check(protected_session.initialize(Fixture.definitions(), active), "protected fixture")
	check(Registry.sleep_family(Registry.begin(protected_session.snapshot(), protected_session), "X01", protected_session).is_empty(), "protected root denied")
	var protected_partition: Dictionary = Registry.begin(protected_session.snapshot(), protected_session)
	var protected_tracking: Dictionary = Tracking.promote(protected_partition, "X01_A", "tracked", false, protected_session)
	check(not protected_tracking.is_empty() and Tracking.suspend(protected_tracking, "X01_A", protected_session).is_empty() and not Tracking.can_suspend(protected_session.snapshot(), "X01_A"), "protected ancestor blocks suspension including storage check")
	var tracked: Dictionary = Tracking.promote(asleep, "X01_A", "narrative", true, s)
	check(not tracked.is_empty() and Tracking.suspend(tracked, "X01_A", s).is_empty(), "pinned narrative cannot be suspended")
	check(Tracking.retain_reference(tracked, "X01_A", "invented_event", s).is_empty(), "no invented event")
	tracked = Tracking.promote(tracked, "X01_B", "narrative", false, s)
	check(Tracking.promote(tracked, "X01_C", "narrative", false, s).is_empty(), "authored budget")
	var stopped: Dictionary = Tracking.suspend(tracked, "X01_B", s)
	check(not stopped.is_empty() and stopped.tracking.has("X01_B") and not stopped.tracking.X01_B.enabled, "suspension preserves retained record")
	var encoded: String = Codec.pack(stopped, s, full)
	check(not encoded.is_empty() and Codec.unpack(encoded, s, full).get("state") == full, "versioned partition exact roundtrip")
	var bad: Dictionary = JSON.parse_string(encoded)
	bad.body.partition.tracking.X01_B.refs.append("nonexistent")
	bad.checksum = Rules.canonical(bad.body).sha256_text()
	check(Codec.unpack(Rules.canonical(bad), s, full).is_empty(), "semantic invalidity rejected even with checksum")
	print("REGISTRY_PILOT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
