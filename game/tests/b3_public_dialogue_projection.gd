extends SceneTree
const Alpha = preload("res://src/domain/alpha_shop_cycle.gd")
const Dialogue = preload("res://src/presentation/b3_counter_dialogue.gd")
const Quote = preload("res://src/presentation/b3_ratio_offer.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func _initialize() -> void:
	var notes := {"offers":[{"action_id":"z_offer"}],"claim_challenges":[{"action_id":"a_challenge","slot":"function_detail","verified_reading":"SECRET"}],"statements":[{"action_id":"m_withdraw","kind":"withdraw","slot":"wear_detail"}]}
	var state := {"commands":[{"action_id":"z_offer"},{"action_id":"a_challenge"},{"action_id":"private_inspection"}]}
	var before := notes.duplicate(true)
	var newest := Alpha._latest_spoken_event(state,notes)
	check(newest=={"kind":"challenge","slot":"function_detail"},"journal order not lexical ID or private inspection")
	var context := {"latest_spoken":newest,"current_offer":{"response":"declined","public_slots":["wear_detail"]}}
	check(Dialogue.line(context,true).contains("작동 상태"),"new challenge outranks old offer")
	check(not Dialogue.line(context,true).contains("SECRET"),"no private reading rendered")
	state.commands.append({"action_id":"m_withdraw"})
	context.latest_spoken=Alpha._latest_spoken_event(state,notes)
	check(Dialogue.line(context,true).contains("취소"),"withdrawal follows later public event")
	notes.statements.append({"action_id":"aa_reaffirm","kind":"reaffirm","slot":"wear_detail"})
	state.commands.append({"action_id":"aa_reaffirm"})
	context.latest_spoken=Alpha._latest_spoken_event(state,notes)
	check(Dialogue.line(context,true).contains("아까 말씀대로"),"reaffirmation response")
	notes.offers.append({"action_id":"b_new_offer"})
	state.commands.append({"action_id":"b_new_offer"})
	context.latest_spoken=Alpha._latest_spoken_event(state,notes)
	check(context.latest_spoken=={"kind":"offer"} and Dialogue.line(context,true).contains("사용 흔적"),"later offer supersedes challenge and references submitted evidence")
	context.current_offer={"response":"declined","public_slots":[],"active_slots":["material_detail"]}
	check(Dialogue.line(context,true).contains("재질") and Dialogue.line(context,true).contains("기억"),"prior disclosed evidence remembered")
	context.current_offer={"response":"accepted"}
	check(Dialogue.line(context,true).contains("넘기죠") and Dialogue.line(context,false).contains("사겠습니다"),"actual response and trade direction")
	check(Alpha._latest_spoken_event(state,{}).is_empty(),"unrelated visitor sees no conversation")
	check(Dialogue.line({"current_offer":{"response":"declined","public_slots":[]},"private_reading":"SECRET"},true)==Dialogue.line({"current_offer":{"response":"declined","public_slots":[]}},true),"private facts cannot affect speech")
	var first := Quote.basis({"estimate":{"VKC":{"low":180,"high":220}}},"VKC")
	var revised := Quote.basis({"estimate":{"VKC":{"low":140,"high":180}}},"VKC")
	check(Quote.amount(first,500)==100 and Quote.amount(revised,500)==80 and first.amount==200,"new valuation does not mutate prior basis; same ratio preview")
	check(before.offers[0]==notes.offers[0] and before.claim_challenges==notes.claim_challenges,"old public event records preserved")
	var voices := {}
	var samples := {}
	for actor: String in ["G01","G02","G03","G04","G05","G06","G07","G08","G09","G10","G11","G12"]:
		voices[Dialogue.voice(actor)] = true
		samples[Dialogue.line({},true,actor)] = true
	check(voices.size()>1 and samples.size()>1,"stable visitor wording is varied")
	check(Dialogue.line({},true,"G01")==Dialogue.line({},true,"G01"),"same visitor stable after refresh")
	var public := {"current_offer":{"response":"declined","public_slots":["material_detail"]}}
	var secret := public.duplicate(true)
	secret["private_reading"]="SECRET"
	check(Dialogue.line(public,true,"G02")==Dialogue.line(secret,true,"G02") and Dialogue.line(public,true,"G02").contains("재질"),"variant remains grounded in public topic")
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(Dialogue.PATH))
	check(Dialogue.validate(catalog),"external dialogue catalog schema valid")
	var extended: Dictionary = catalog.duplicate(true)
	extended.lines.opening_buy.append("추가 인사")
	check(Dialogue.validate(extended),"additional wording needs no code change")
	extended.actor_lines["G01"]={"opening_buy":["인물별 인사"]}
	check(Dialogue.validate(extended),"per-actor wording is supported by the data schema")
	var invalid_actor: Dictionary = extended.duplicate(true)
	invalid_actor.actor_lines.G01["challenge_topic"]=["잘못된 {amount}"]
	check(not Dialogue.validate(invalid_actor),"actor override must preserve the public substitution contract")
	extended.lines.challenge_topic=["관찰 {unknown}"]
	check(not Dialogue.validate(extended),"invalid substitution token rejected")
	var missing: Dictionary = catalog.duplicate(true)
	missing.lines.erase("accept_buy")
	check(not Dialogue.validate(missing),"required dialogue missing is rejected")
	check(Dialogue.bid("bid_open",123).contains("123 VKC"),"public quote renders actual amount")
	check(Dialogue.subject("f3_part_a")=="모듈 A 관찰","public civilian component topic retained")
	print("B3_PUBLIC_DIALOGUE: ",checks," checks, ",failures," failures")
	quit(1 if failures>0 else 0)
