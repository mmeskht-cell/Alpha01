extends SceneTree
## B2 T05/T09 bounded authority: authored self-report != verified fact,
## private guesses can be wrong; public fact correction cannot erase speech.
## Runs one isolated real G01 visit and one G02 privacy boundary.
const Seed = preload("res://src/content/alpha_b2_cards_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
	return ok

func fresh() -> RefCounted:
	var source: Dictionary = Seed.content()
	var s := Session.new()
	if source.is_empty() or not s.initialize(source.defs,source.state,false,false,{},source.alpha_profile):
		printerr("B2_STATEMENT_INIT: ",s.initialization_error() if not source.is_empty() else "seed")
		return null
	return s

func command(s: RefCounted, action: String, payload: Dictionary={}) -> Dictionary:
	return {"action_id":"b2_statement_"+str(s.snapshot().revision+1),
		"expected_revision":s.snapshot().revision,"type":action,"payload":payload}

func go(s: RefCounted, action: String, payload: Dictionary={}) -> bool:
	var result: Dictionary = s.execute(command(s,action,payload))
	if not result.ok:
		printerr("B2_STATEMENT_ACTION: ",action," ",result)
	return result.ok

func deny(s: RefCounted, action: String, payload: Dictionary={}) -> bool:
	var before: Dictionary = s.snapshot()
	return not s.execute(command(s,action,payload)).ok and s.snapshot()==before

func _initialize() -> void:
	var s: RefCounted = fresh()
	if not check(s != null,"unchanged B2 seed initializes with authored claims"):
		quit(1)
		return
	var initial: Dictionary = s.snapshot()
	check(deny(s,"alpha_hypothesis",{"slot":"function_detail","judgment":"inoperable"}) and deny(s,"alpha_statement_retract",{"slot":"wear_detail"}),"no off-counter private guess or forged public correction")
	if not check(go(s,"alpha_open") and go(s,"alpha_next_customer") and go(s,"alpha_ack_entry"),"G01 original radio at same counter"):
		quit(1)
		return
	var start_view: Dictionary = s.alpha_view()
	check(start_view.appraisal.customer_claims.size()==1 and start_view.appraisal.customer_claims[0].kind=="customer_claim" and start_view.appraisal.customer_claims[0].text_key=="b2.claim.g01_usage","G01's own verbal claim is source-authored, visibly unverified")
	check(start_view.appraisal.cards.is_empty() and start_view.appraisal.commitments.is_empty() and start_view.npc_context.current_offer.is_empty(),"claim cannot become observed fact, customer evidence, or quality guarantee")
	check(deny(s,"alpha_hypothesis",{"slot":"forged","judgment":"serviceable"}) and deny(s,"alpha_hypothesis",{"slot":"wear_detail","judgment":"serviceable"}) and deny(s,"alpha_hypothesis",{"slot":"function_detail","judgment":"superior"}),"arbitrary field guesses and fake values rejected")
	check(go(s,"alpha_hypothesis",{"slot":"function_detail","judgment":"inoperable"}),"player privately guesses a functional radio is broken")
	var guess_view: Dictionary = s.alpha_view()
	check(guess_view.appraisal.hypotheses.size()==1 and guess_view.appraisal.hypotheses[0].kind=="hypothesis" and guess_view.appraisal.hypotheses[0].judgment=="inoperable","wrong provisional judgment allowed and labelled, never auto-corrected")
	check(guess_view.appraisal.cards.is_empty() and guess_view.npc_context.current_offer.is_empty() and s.snapshot().items==initial.items and s.snapshot().wallets==initial.wallets,"private guess cannot inspect, disclose, create stock or move funds")
	check(deny(s,"alpha_hypothesis",{"slot":"function_detail","judgment":"inoperable"}),"unchanged private hypothesis cannot farm events")
	check(go(s,"alpha_inspect",{"slot":"function_detail"}),"actual provenance-bound function test after wrong guess")
	guess_view=s.alpha_view()
	check(guess_view.appraisal.cards[0].value=="serviceable" and guess_view.appraisal.hypotheses[0].judgment=="inoperable","verified fact and false guess remain separately visible to player")
	check(guess_view.appraisal.cards[0].value_signal=="positive" and guess_view.appraisal.cards[0].shop_effect=="hurts","verified working function strengthens seller when player buys; no automatic price changes")
	check(guess_view.npc_context.current_offer.is_empty() and guess_view.appraisal.cards[0].selected==false,"inspecting fact does not publish it or private error")
	check(go(s,"alpha_inspect",{"slot":"wear_detail"}),"independently source-backed wear reading")
	var wear_effect: String = ""
	for card: Dictionary in s.alpha_view().appraisal.cards:
		if card.slot=="wear_detail":
			wear_effect=str(card.shop_effect)
	check(wear_effect=="helps","observable wear favors shop as buyer, opposite of functional evidence")
	check(go(s,"alpha_price_offer",{"amount":94}),"first unsupported price offer leaves private readings unseen")
	var first: Dictionary=s.alpha_view().npc_context.current_offer
	check(first.disclosed_count==0 and first.known_slots.is_empty() and not first.has("hypotheses") and not first.has("claim"),"NPC projection contains only spoken quote, no private hypothesis or unspoken readings")
	check(deny(s,"alpha_statement_retract",{"slot":"wear_detail"}) and deny(s,"alpha_statement_reaffirm",{"slot":"wear_detail"}),"cannot amend facts that were never publicly disclosed")
	check(go(s,"alpha_card_toggle",{"slot":"wear_detail","selected":true}) and go(s,"alpha_price_offer",{"amount":93}),"second price quote explicitly discloses only verified wear")
	var after_offer: Dictionary=s.snapshot()
	check(after_offer.alpha_shop.appraisal.visits.visit_g01.offers[1].revealed.size()==1 and after_offer.alpha_shop.appraisal.visits.visit_g01.offers[1].revealed[0].slot=="wear_detail","source offer receipt binds public wear slot")
	var heard: Dictionary=s.alpha_view().npc_context.current_offer
	check(heard.known_slots==["wear_detail"] and heard.active_slots==["wear_detail"] and heard.withdrawn_slots.is_empty(),"NPC knows only real submitted fact, never wrong private function guess")
	check(go(s,"alpha_statement_retract",{"slot":"wear_detail"}),"player explicitly withdraws earlier public evidence without deleting it")
	var corrected: Dictionary=s.snapshot()
	var row: Dictionary=corrected.alpha_shop.appraisal.visits.visit_g01
	check(row.offers==after_offer.alpha_shop.appraisal.visits.visit_g01.offers and row.statements.size()==1 and row.statements[0].kind=="withdraw" and row.statements[0].source_offer_action_id==row.offers[1].action_id,"immutable actual quote and disclosure receipt, causal correction source and id retained")
	var public: Dictionary=s.alpha_view().npc_context.current_offer
	check(public.known_slots==["wear_detail"] and public.active_slots.is_empty() and public.withdrawn_slots==["wear_detail"],"NPC remembers what was said but knows it was explicitly retracted")
	var retracted_card_selected: bool = false
	for card: Dictionary in s.alpha_view().appraisal.cards:
		if card.slot == "wear_detail":
			retracted_card_selected = bool(card.selected)
	check(not retracted_card_selected and s.alpha_view().appraisal.public_standing.withdrawn_slots==["wear_detail"],"retracted card not silently selected for next offer")
	check(deny(s,"alpha_statement_retract",{"slot":"wear_detail"}) and deny(s,"alpha_statement_reaffirm",{"slot":"function_detail"}),"duplicate retraction and correction of private observation refused")
	check(go(s,"alpha_price_offer",{"amount":95}),"later offer does not automatically republish retracted wear")
	var third: Dictionary=s.alpha_view().npc_context.current_offer
	check(third.response=="declined" and third.public_slots.is_empty() and third.known_slots==["wear_detail"] and third.withdrawn_slots==["wear_detail"],"past evidence not re-publicized or converted to price advantage")
	check(go(s,"alpha_statement_reaffirm",{"slot":"wear_detail"}),"player may explicitly reaffirm an earlier factual statement without a new quote")
	var final_state: Dictionary=s.snapshot()
	var final_public: Dictionary=s.alpha_view().npc_context.current_offer
	check(final_public.active_slots==["wear_detail"] and final_public.withdrawn_slots.is_empty() and final_public.known_slots==["wear_detail"],"reaffirmed standing is visible but historical quote remains unchanged")
	check(final_state.alpha_shop.appraisal.visits.visit_g01.statements.size()==2 and final_state.alpha_shop.appraisal.visits.visit_g01.offers[1]==row.offers[1] and final_state.alpha_shop.appraisal.visits.visit_g01.offers[2].revealed.is_empty(),"withdraw and reaffirm events both immutable; last proposal did not gain disclosure")
	check(deny(s,"alpha_statement_reaffirm",{"slot":"wear_detail"}) and deny(s,"alpha_price_offer",{"amount":96}),"no duplicate reaffirmation or hidden fourth offer")
	check(final_state.wallets==initial.wallets and final_state.items==initial.items and final_state.ledger.is_empty(),"claims, guesses, correction never create financial or ownership events")
	var repository := Repo.new("user://zt_rebuild/b2_statement_batch_"+str(Time.get_ticks_usec()))
	check(repository.save_session(s,"statement").ok,"cold save after two public correction events")
	var reloaded: RefCounted=fresh()
	check(reloaded!=null and repository.load_session(reloaded,"statement").ok and reloaded.snapshot()==final_state and reloaded.alpha_view().npc_context==s.alpha_view().npc_context,"exact command replay of wrong guess, published fact, withdrawal and reaffirmation")
	# Full GameSession tamper/immutable-replay regression is already part of
	# the unchanged fixed suite. One exact cold replay here covers new fields
	# without repeating expensive O(history) deliberate-corruption restores.
	check(go(s,"alpha_finish_customer") and go(s,"alpha_ack_exit") and go(s,"alpha_next_customer") and go(s,"alpha_ack_entry"),"unrelated G02 seller-turned-buyer enters")
	var other: Dictionary=s.alpha_view()
	check(other.active.actor_id=="G02" and other.npc_context.prior.is_empty() and other.npc_context.current_offer.is_empty(),"no cross-customer transfer of a correction, claim or private guess")
	check(other.appraisal.is_empty(),"G02 cannot inspect or inherit private/claimed facts about R001 when G01 did not sell it and the shelf is empty")
	print("ALPHA_B2_STATEMENT_AUTHORITY_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
