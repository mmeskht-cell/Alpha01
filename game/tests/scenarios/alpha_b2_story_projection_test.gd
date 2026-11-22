extends SceneTree
## Source-bound representative story beats; no new encounter, quest or payout.
const Seed = preload("res://src/content/alpha_b2_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Story = preload("res://src/domain/alpha_story_projection.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
	return ok

func go(s: RefCounted, action: String) -> bool:
	var state: Dictionary = s.snapshot()
	return bool(s.execute({"action_id":"source_story_"+str(state.revision+1),"expected_revision":state.revision,"type":action,"payload":{}}).ok)

func _initialize() -> void:
	var config: Dictionary = Story.config()
	check(config.get("beats",[]).size()==5,"S01/S03 grounded events plus S02/S04 conditional remote fallback data are registered")
	var data: Dictionary=Seed.content()
	var s:=Session.new()
	if not check(not data.is_empty() and s.initialize(data.defs,data.state,false,false,{},data.alpha_profile),"real B2 source initializes"):
		quit(1)
		return
	check(Story.view(s.snapshot()).speech_key.is_empty() and Story.view(s.snapshot()).fact_key.is_empty(),"D1 before actual customer has no fabricated story")
	check(go(s,"alpha_open") and go(s,"alpha_next_customer") and go(s,"alpha_ack_entry"),"real G01 enters existing D1 counter")
	var current: Dictionary=s.snapshot()
	check(Story.view(current).speech_key=="b2.story.s01.g01" and Story.view(current).fact_key.is_empty(),"S01 opening comes from actual G01 ownership of R001")
	check(s.snapshot()==current,"read-only story projection cannot change wallet, ownership, ledger, save commands")
	var wrong_owner: Dictionary=current.duplicate(true)
	wrong_owner.items.R001.owner_id="player"
	check(Story.view(wrong_owner).speech_key.is_empty(),"do not narrate an item if visitor did not own it")
	var wrong_visit: Dictionary=current.duplicate(true)
	wrong_visit.visits.visit_g01.seller="G09"
	check(Story.view(wrong_visit).speech_key.is_empty(),"do not attribute somebody else's item or visit to G01")
	check(go(s,"alpha_finish_customer") and Story.view(s.snapshot()).speech_key.is_empty(),"no lingering G01 visit speech at exit")
	check(s.snapshot().wallets==current.wallets and s.snapshot().ledger==current.ledger,"projection and ordinary customer exit mint no money or events")
	check(go(s,"alpha_ack_exit") and go(s,"alpha_close") and go(s,"alpha_settle")
		and go(s,"alpha_next_day") and go(s,"alpha_prepare_day"),"D1 closes without fake Jack/Sora event")
	check(Story.view(s.snapshot()).notices.is_empty(),"D2 unopen morning has no premature radio notice")
	check(go(s,"alpha_open"),"real D2 shop opening triggers authored remote fallback")
	var day2: Dictionary=s.snapshot()
	var sora: Array=Story.view(day2).notices
	check(sora.size()==1 and sora[0].id=="S02_SORA_REMOTE" and sora[0].source_id=="sora"
		and sora[0].channel=="radio","S02 takes documented Sora-only remote path when Jack has no real visit")
	check(s.snapshot()==day2 and not day2.wallets.has("sora") and not day2.wallets.has("jack")
		and day2.ledger.is_empty() and day2.alpha_shop.profile.days[1].size()>0,
		"S02 radio notice creates no NPC wallet, visitor, money or ledger entry")
	var alternate: Dictionary=day2.duplicate(true)
	alternate.alpha_shop.profile.days[1].append({"actor_id":"jack"})
	check(Story.view(alternate).notices.is_empty(),"real authored Jack encounter would suppress Sora fallback rather than duplicate main scene")
	for next_day: int in range(3,8):
		if not check(go(s,"alpha_close") and go(s,"alpha_settle") and go(s,"alpha_next_day")
			and go(s,"alpha_prepare_day") and go(s,"alpha_open"),"original finite schedule advances to D"+str(next_day)):
			quit(1)
			return
		if next_day == 3:
			check(Story.view(s.snapshot()).notices.is_empty(),"S02 contact cannot repeat on D3 as a second economic event")
	var day7: Dictionary=s.snapshot()
	var nael: Array=Story.view(day7).notices
	check(nael.size()==1 and nael[0].id=="S04_NAEL_REMOTE" and nael[0].source_id=="nael",
		"S04 shows authored Nael schedule notice in absence of a real Tan visit")
	check(not day7.wallets.has("nael") and not day7.wallets.has("tan")
		and s.snapshot()==day7,"S04 remote notice never creates named market actors or synthetic encounter")
	alternate=day7.duplicate(true)
	alternate.alpha_shop.profile.days[6].append({"actor_id":"tan"})
	check(Story.view(alternate).notices.is_empty(),"actual Tan scheduled visit would suppress Nael substitute")
	check(go(s,"alpha_next_customer") and Story.view(s.snapshot()).notices.is_empty(),
		"remote notice never overlays an active visitor's speech")
	print("B2_STORY_SOURCE_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
