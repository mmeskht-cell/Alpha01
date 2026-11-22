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
	check(config.get("beats",[]).size()==3,"only authored S01 greeting and two factual S03 states are registered")
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
	print("B2_STORY_SOURCE_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
