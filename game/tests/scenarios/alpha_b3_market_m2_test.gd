extends SceneTree
## B3-M2: eight authored but conditional, truly funded buyer interests across
## seven days. No invented stock/wallet, no automatic bonus or story event.
const Source = preload("res://src/content/alpha_b3_market_m2_seed.gd")
const M1 = preload("res://src/content/alpha_b3_market_seed.gd")
const B2 = preload("res://src/content/alpha_b2_service_multi_seed.gd")
const Market = preload("res://src/domain/alpha_b3_market_interest.gd")
const Capacity = preload("res://src/domain/alpha_b3_visit_capacity.gd")
const Session = preload("res://src/domain/game_session.gd")
const Alpha = preload("res://src/domain/alpha_shop_cycle.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const WATCH_ID = "alpha_b3_g08_watch_d4"
const ELECTRONICS_ID = "alpha_b3_g08_electronics_d7"
var checks: int=0
var failures: int=0

func check(ok: bool, reason: String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",reason)
	return ok

func fresh(data: Dictionary) -> RefCounted:
	var s:=Session.new()
	if data.is_empty() or not s.initialize(data.defs,data.state,false,false,{},data.alpha_profile):
		printerr("M2_INITIALIZATION_FAILURE ",s.initialization_error())
		return null
	return s

func cmd(s: RefCounted, action: String, payload: Dictionary={}) -> Dictionary:
	return {"action_id":"b3_m2_"+str(s.snapshot().revision+1),"expected_revision":s.snapshot().revision,
		"type":action,"payload":payload}

func go(s: RefCounted, action: String, payload: Dictionary={}) -> bool:
	var r: Dictionary=s.execute(cmd(s,action,payload))
	if not bool(r.get("ok",false)):
		printerr("M2_COMMAND_FAILURE ",action," ",r)
	return bool(r.get("ok",false))

func deny(s: RefCounted, action: String, payload: Dictionary={}) -> bool:
	var before: Dictionary=s.snapshot()
	return not s.execute(cmd(s,action,payload)).get("ok",false) and s.snapshot()==before

func trade(visit_id: String, item_id: String, seller: String, buyer: String, amount: int, destination: String, x: int=0, y: int=0) -> Dictionary:
	return {"visit_id":visit_id,"item_id":item_id,"seller":seller,"buyer":buyer,
		"currency":"VKC","amount":amount,"inventory":destination,"x":x,"y":y,"rotated":false}

func step_visitors(s: RefCounted, day: int, special: String="") -> bool:
	if not go(s,"alpha_open"):
		return false
	var seen_special: bool=false
	var seen: Dictionary={}
	while int(s.alpha_view().remaining)>0:
		if not go(s,"alpha_next_customer"):
			return false
		var row: Dictionary=s.alpha_view().active
		var id: String=str(row.id)
		if seen.has(id):
			return check(false,"same finite daily visit reappeared "+id)
		seen[id]=true
		if not go(s,"alpha_ack_entry"):
			return false
		if id==special:
			seen_special=true
			if day==2 and id=="watch_a":
				if not go(s,"alpha_price_offer",{"amount":80}) or not go(s,"alpha_trade",trade("watch_a","WAT02","G04","player",80,"player_stock",0,0)):
					return false
			elif day==4 and id==WATCH_ID:
				if not check(s.alpha_view().active.actor_id=="G08","G08 is actual buyer for the existing watch"):
					return false
				if not go(s,"alpha_price_offer",{"amount":140}) or not go(s,"alpha_trade",trade(id,"WAT02","player","G08",140,"G08_grid",6,4)):
					return false
			elif day==6 and id=="electronics_buy":
				if not go(s,"alpha_price_offer",{"amount":80}) or not go(s,"alpha_trade",trade("electronics_buy","EL06","G06","player",80,"player_stock",1,0)):
					return false
			else:
				return check(false,"unknown special visitor action "+id)
			if not go(s,"alpha_ack_exit"):
				return false
		else:
			if not go(s,"alpha_finish_customer") or not go(s,"alpha_ack_exit"):
				return false
	if not special.is_empty() and not check(seen_special,"scheduled real special visit "+special):
		return false
	if day==2 and special=="watch_a":
		if not check(s.snapshot().items.WAT02.owner_id=="player" and s.snapshot().wallets.player.VKC==100,
				"existing 80 VKC watch has been acquired after passing same-day buyer"):
			return false
		if not go(s,"alpha_display",{"item_id":"WAT02","x":0,"y":0,"rotated":false}):
			return false
	if day==4 and special==WATCH_ID:
		var state: Dictionary=s.snapshot()
		if not check(state.items.WAT02.owner_id=="G08" and state.items.WAT02.inventory=="G08_grid"
				and state.wallets.G08.VKC==25 and state.wallets.player.VKC==240 and state.ledger.size()==2,
				"140 VKC watch sale: same item ID, two finite transfers and exhausted buyer budget"):
			return false
	if day==6 and special=="electronics_buy":
		if not check(s.snapshot().items.EL06.owner_id=="player" and s.snapshot().wallets.player.VKC==160,
				"new inventory is a real 80 VKC D6 electronics purchase"):
			return false
		if not go(s,"alpha_display",{"item_id":"EL06","x":1,"y":0,"rotated":false}):
			return false
		check(not Market.eligible(s.snapshot(),ELECTRONICS_ID)
			and s.snapshot().items.EL06.inventory=="storefront_grid",
			"listed D6 electronics cannot make previously spent G08 wallet afford D7 order")
	return true

func end_day(s: RefCounted, day: int) -> bool:
	if not go(s,"alpha_close") or not go(s,"alpha_settle") or not go(s,"alpha_next_day"):
		return false
	if day<7:
		return go(s,"alpha_prepare_day")
	return s.snapshot().alpha_shop.phase=="COMPLETE"

func _initialize() -> void:
	var source: Dictionary=Source.content()
	var b2: Dictionary=B2.content()
	var m1: Dictionary=M1.content()
	if not check(not source.is_empty() and not b2.is_empty() and not m1.is_empty(),
			"three independent B2/M1/M2 source-bound economies load"):
		quit(1)
		return
	check(source.state.items==b2.state.items and source.state.wallets==b2.state.wallets
		and source.state.ledger==b2.state.ledger and source.state.visits.size()==b2.state.visits.size()+8,
		"eight buyer opportunities add no item, cash, origin change or ledger entry")
	var policy: Dictionary=Market.config(Market.CONTENT_VERSION_M2)
	check(policy.offers.size()==8 and Market.config().offers.size()==1
		and m1.alpha_profile.content_version==Market.CONTENT_VERSION,
		"new eight-offer market does not overwrite M1's one-offer content and save binding")
	check(Alpha.profile_valid(source.alpha_profile,source.state)
		and source.alpha_profile.content_version==Market.CONTENT_VERSION_M2,
		"every offer is a dated original quote with matching real buyer/actor wallet")
	var counts: Array=[]
	var unconditional: Array=[]
	var review: Dictionary=Capacity.audit(source)
	for row: Dictionary in review.get("days",[]):
		counts.append(int(row.authored))
		unconditional.append(int(row.guaranteed))
	check(review.get("ok",false) and not review.ready and counts==[5,7,6,6,4,4,2]
		and unconditional==[5,5,4,3,1,2,0] and review.total_conditional==14
		and review.total_authored==34,
		"B3-M2 34 authored, 20 unconditional, 14 conditional visits; no false seven-day completion")
	var ids: Dictionary={}
	for offer: Dictionary in policy.offers:
		check(not ids.has(offer.visit_id) and source.state.wallets.has(offer.actor_id)
			and source.state.items.has(offer.item_id)
			and source.state.visits[offer.visit_id].prices[offer.item_id]==source.state.visits[offer.quote_source_visit_id].prices[offer.item_id],
			"existing priced item and finite buyer wallet: "+str(offer.visit_id))
		ids[offer.visit_id]=true

	var forged: Dictionary=source.duplicate(true)
	forged.state.visits[WATCH_ID].prices.WAT02.VKC=1
	check(not Alpha.profile_valid(forged.alpha_profile,forged.state),
		"forged secondary purchase price rejected before session creation")
	forged=source.duplicate(true)
	forged.alpha_profile.days[3].append({"id":"alpha_b3_duplicate","actor_id":"G08","kind":"regular",
		"purpose_key":"b3.market.interest.watch","contact_offer":false})
	check(not Alpha.profile_valid(forged.alpha_profile,forged.state),
		"duplicate actor within D4 cannot be inserted through market config")

	var empty: RefCounted=fresh(source)
	if not check(empty!=null,"M2 separate seven-day source starts"):
		quit(1)
		return
	var baseline: Dictionary=empty.snapshot()
	for day in range(1,8):
		check(not Market.eligible(empty.snapshot(),WATCH_ID)
			and not Market.eligible(empty.snapshot(),ELECTRONICS_ID),
			"undisplayed future stock cannot attract D4/D7 buyers")
		# Explicitly close without admitting visitors. The new day/phase
		# system must not conjure customer money or force a purchase.
		if not go(empty,"alpha_open") or not end_day(empty,day):
			check(false,"no-inventory daily close through D"+str(day))
			break
	check(empty.snapshot().alpha_shop.phase=="COMPLETE"
		and empty.snapshot().wallets==baseline.wallets
		and empty.snapshot().items==baseline.items and empty.snapshot().ledger.is_empty(),
		"seven idle days do not mint stock, fees, actor wallets or new purchases")

	var real: RefCounted=fresh(source)
	if not check(real!=null,"independent fully playable seven-day M2 counter"):
		quit(1)
		return
	# Day 1: do not buy R001; G09's D2 prospective radio is never eligible.
	check(step_visitors(real,1) and end_day(real,1),"D1 real visit cycle without virtual goods")
	# Day 2: buy WAT02 at G04, decline G05's pre-authored same-day purchase;
	# only display it AFTER that visit, leaving a genuine D4 opportunity.
	check(step_visitors(real,2,"watch_a") and end_day(real,2),
		"D2 physical watch acquisition and actual shelf reservation")
	check(Market.eligible(real.snapshot(),WATCH_ID) and real.snapshot().items.WAT02.inventory=="storefront_grid",
		"the existing actual watch and G08's seeded 165 VKC allow D4 demand")
	check(step_visitors(real,3) and end_day(real,3),"D3 customers without duplicated visitor")
	check(step_visitors(real,4,WATCH_ID) and end_day(real,4),
		"D4 source-price 140 watch sold once to G08, real buyer ownership and ledger")
	check(not Market.eligible(real.snapshot(),ELECTRONICS_ID)
		and real.snapshot().wallets.G08.VKC==25,
		"after a real watch purchase G08 cannot also pay 115 VKC for electronics")
	check(step_visitors(real,5) and end_day(real,5),"D5 finite market visits")
	check(step_visitors(real,6,"electronics_buy") and end_day(real,6),
		"D6 authentic electronics purchased and displayed without G07 resale")
	check(real.snapshot().items.EL06.owner_id=="player"
		and not Market.eligible(real.snapshot(),ELECTRONICS_ID),
		"cross-day depleted buyer remains disqualified despite actual D7 inventory")
	check(step_visitors(real,7) and end_day(real,7),"D7 no artificially spawned G08 buyer, proper complete state")
	var result: Dictionary=real.snapshot()
	check(result.alpha_shop.phase=="COMPLETE" and result.ledger.size()==3
		and result.wallets.player.VKC==160 and result.wallets.G08.VKC==25
		and result.items.EL06.owner_id=="player"
		and result.items.WAT02.owner_id=="G08",
		"seven-day B3-M2 economic result is conserved and replayable")

	var store:=Repo.new("user://zt_rebuild/b3_m2_"+str(Time.get_ticks_usec()))
	check(store.save_session(real,"b3_market_m2").get("ok",false),"separate M2 A/B save accepted")
	var cold: RefCounted=fresh(source)
	check(cold!=null and store.load_session(cold,"b3_market_m2").get("ok",false)
		and cold.snapshot()==result and cold.alpha_view()==real.alpha_view(),
		"exact 7-day item and budget memory cold-restore under new content version")
	var old: RefCounted=fresh(m1)
	check(old!=null and not old.restore(result),"M1 session refuses M2 authored visits and state")
	old=fresh(b2)
	check(old!=null and not old.restore(result),"B2 session refuses M2 state without touching legacy slot")

	print("ALPHA_B3_MARKET_M2_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
