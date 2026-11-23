extends SceneTree
## Synthetic contract terms only; never loaded by the game content seed.
const Outbound = preload("res://src/domain/alpha_b3_outbound.gd")
var failures: int = 0

func expect(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr(label)

func _initialize() -> void:
	var state: Dictionary = {"wallets":{"player":{"VKC":5}, "worker":{"VKC":0}},
		"alpha_shop":{"day":2}}
	var terms: Dictionary = {"actor_id":"worker","currency":"VKC","offer_day":2,"advance":6,"cancel_refund":2}
	var send: Dictionary = {"type":"alpha_salvage_dispatch","action_id":"send"}
	var cancel: Dictionary = {"type":"alpha_salvage_cancel","action_id":"cancel"}
	var original: Dictionary = state.duplicate(true)
	expect(not Outbound.apply(state,"one",terms,send).is_empty() and state == original,"insufficient advance leaves state intact")
	terms.advance = 4
	expect(Outbound.apply(state,"one",terms,send).is_empty(),"funded dispatch")
	var sent: Dictionary = state.duplicate(true)
	expect(sent.wallets.player.VKC == 1 and sent.wallets.worker.VKC == 4,"advance conserved")
	expect(not Outbound.apply(state,"two",terms,send).is_empty() and state == sent,"worker busy")
	expect(not Outbound.apply(state,"one",terms,send).is_empty() and state == sent,"duplicate dispatch")
	expect(Outbound.apply(state,"one",terms,cancel).is_empty(),"explicit refund")
	var ended: Dictionary = state.duplicate(true)
	expect(ended.wallets.player.VKC == 3 and ended.wallets.worker.VKC == 2 and ended.alpha_shop.outbound.one.payments.size() == 2,"refund conserved")
	expect(not Outbound.apply(state,"one",terms,cancel).is_empty() and state == ended,"no duplicate refund")
	var row: Dictionary = {"status":"dispatched", "actor_id":"worker"}
	Outbound.apply_evidence(state, row, {"status":"delayed"})
	expect(row.status == "delayed", "late contact does not settle")
	Outbound.apply_evidence(state, row, {"status":"unreachable"})
	expect(row.status == "unreachable", "absence remains unconfirmed")
	Outbound.apply_evidence(state, row, {"status":"empty"})
	expect(row.status == "empty" and state == ended, "empty result creates no inventory or refund")
	Outbound.apply_evidence(state, row, {"status":"delayed"})
	expect(row.status == "empty", "terminal event cannot reopen")
	quit(0 if failures == 0 else 1)
