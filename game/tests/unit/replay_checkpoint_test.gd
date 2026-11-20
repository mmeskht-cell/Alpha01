extends SceneTree
const Probe = preload("res://tests/fixtures/checkpoint_campaign_probe.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func send(s: RefCounted, kind: String, id: String, payload: Dictionary = {}) -> bool:
	return s.execute({"action_id": id, "expected_revision": s.snapshot().revision, "type": kind, "payload": payload}).ok

func _initialize() -> void:
	var s: RefCounted = Probe.session(false)
	if s == null:
		quit(1)
		return
	var ready: bool = send(s, "accept_rad1_contract", "contract") and send(s, "next_visit", "first") and send(s, "decline_visit", "decline") and send(s, "begin_day_one", "begin")
	check(ready, "valid opening and first continuation")
	if not ready:
		quit(1)
		return
	var prior: Dictionary = s.snapshot()
	check(s.replay_diagnostics().steps == 1, "initial continuation replay")
	check(send(s, "day_one_next", "next") and s.replay_diagnostics().steps == 1, "one verified suffix step")
	var current: Dictionary = s.snapshot()
	check(s.validate(current) and s.replay_diagnostics().steps == 0, "exact state cached only after full comparison")
	var forged: Dictionary = current.duplicate(true)
	forged.wallets.player.VKC += 1
	check(not s.restore(forged) and s.snapshot() == current, "matching prefix cannot authenticate altered state")
	check(s.validate(current) and s.replay_diagnostics().steps == 0, "failed restore leaves authority unchanged")
	var cold: RefCounted = Probe.session(false)
	check(cold.restore(current) and cold.replay_diagnostics().steps == current.day_one.commands.size(), "cold disk restore verifies entire replay")
	check(s.restore(prior) and s.replay_diagnostics().steps == prior.day_one.commands.size(), "earlier generation verifies from base")
	check(send(s, "day_one_next", "alternate") and s.snapshot() != current, "legitimate alternative branch")
	check(s.restore(current) and s.replay_diagnostics().steps == current.day_one.commands.size(), "divergent branch never reuses checkpoint")
	check(s.validate(current) and s.replay_diagnostics().steps == 0, "revalidated branch exact reuse")
	var detached: Dictionary = s.snapshot()
	detached.day_one.commands.clear()
	check(not s.validate(detached) and s.snapshot() == current, "detached commands cannot mutate cached authority")
	print("REPLAY_CHECKPOINT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
