extends RefCounted
const Seed = preload("res://src/content/b3_integrated_campaign_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Catalog = preload("res://src/domain/b3_integrated_catalog.gd")

static func fresh(source: Dictionary) -> RefCounted:
	var session := Session.new()
	if not source.is_empty() and session.initialize(source.defs,source.state,false,false,{},source.alpha_profile):
		return session
	return null

static func command(session: RefCounted,kind: String,payload: Dictionary={}) -> Dictionary:
	var revision: int = session.snapshot().revision
	return {"action_id":"catalog_check_%d"%[revision+1],"expected_revision":revision,"type":kind,"payload":payload}

static func go(session: RefCounted,kind: String,payload: Dictionary={}) -> bool:
	var result: Dictionary = session.execute(command(session,kind,payload))
	if not result.get("ok",false):
		printerr("Catalog route command ",kind," ",result)
	return result.get("ok",false)

static func sequence(session: RefCounted,commands: Array) -> bool:
	for kind: String in commands:
		if not go(session,kind): return false
	return true

static func advance(session: RefCounted) -> bool:
	return sequence(session,["alpha_close","alpha_settle","alpha_next_day","alpha_prepare_day","alpha_open"])

static func next_customer(session: RefCounted) -> bool:
	return sequence(session,["alpha_next_customer","alpha_ack_entry"])

static func leave(session: RefCounted) -> bool:
	if session.alpha_view().active.id=="alpha_marcus_intro" and not go(session,"alpha_contract_decline",{"contract_id":"rad1_first"}):
		return false
	return sequence(session,["alpha_finish_customer","alpha_ack_exit"])

static func reach(session: RefCounted,id: String) -> bool:
	while int(session.alpha_view().remaining)>0:
		if not next_customer(session): return false
		if session.alpha_view().active.id==id: return true
		if not leave(session): return false
	return false

static func transfer(session: RefCounted,id: String) -> Dictionary:
	var snapshot: Dictionary = session.snapshot()
	var visit_id: String = snapshot.alpha_shop.active
	var item_id := Catalog.visit_item(snapshot.alpha_shop.profile,visit_id)
	if item_id!=id: return {}
	var visit: Dictionary = snapshot.visits[visit_id]
	var destination: String = "player_stock" if visit.buyer=="player" else str(visit.buyer)+"_grid"
	var fit: Dictionary = session.spatial_fit(id,destination)
	if not fit.get("ok",false): return {}
	return {"visit_id":visit_id,"item_id":id,"seller":visit.seller,"buyer":visit.buyer,"currency":"VKC","amount":int(visit.prices[id].VKC),"inventory":destination,"x":fit.x,"y":fit.y,"rotated":fit.rotated}

static func display(session: RefCounted,id: String) -> bool:
	var fit: Dictionary = session.spatial_fit(id,"storefront_grid")
	return fit.get("ok",false) and go(session,"alpha_display",{"item_id":id,"x":fit.x,"y":fit.y,"rotated":fit.rotated})

## Returns the exact pre-purchase state, after proving that the normal plans
## on this seed can actually reach both the seller and the funded buyer.
static func trade_witness(target: String,require_fault: bool=false) -> Dictionary:
	for seed_value: int in range(101,181):
		var source := Seed.content(seed_value)
		if source.is_empty() or not source.state.items.has(target):
			continue
		if require_fault and source.state.items[target].functional:
			continue
		var session := fresh(source)
		if session==null or not go(session,"alpha_open"): return {}
		var purchase := Catalog.visit_id(target,true)
		var resale := Catalog.visit_id(target,false)
		var buy_day := int(float(source.state.visits[purchase].opens)/1440.0)+1
		var sale_day := int(float(source.state.visits[resale].opens)/1440.0)+1
		for day: int in range(1,buy_day):
			if not advance(session): return {}
		if purchase not in session.snapshot().alpha_shop.random_visits.plan or not reach(session,purchase):
			continue
		var before: Dictionary = session.snapshot()
		var trade := transfer(session,target)
		if trade.is_empty() or not go(session,"alpha_price_offer",{"amount":trade.amount}) or not go(session,"alpha_trade",trade) or not go(session,"alpha_ack_exit") or not display(session,target):
			return {}
		for day: int in range(buy_day,sale_day):
			if not advance(session): return {}
		if resale in session.snapshot().alpha_shop.random_visits.plan and reach(session,resale):
			return {"source":source,"buy":before,"sale_day":sale_day}
	return {}
