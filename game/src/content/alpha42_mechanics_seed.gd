extends RefCounted
## Internal 42-day mechanics-alpha *content*, never the seven-day canonical
## seed or a released story. All goods/currency are finite on day one.
const Demo=preload("res://src/content/demo7_seed.gd")
const Objects=preload("res://src/domain/object_schema.gd")
const Session=preload("res://src/domain/game_session.gd")
const Clock=preload("res://src/domain/business_clock.gd")
const Generated=preload("res://src/domain/npc_generated_visits.gd")
const CONFIG="res://data/campaign/alpha42/finite_market.json"

static func _cash(n:int)->Dictionary:
	return {"VKC":n,"USD":0}

static func content()->Dictionary:
	var original:Dictionary=Demo.content()
	var config:Variant=JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if original.is_empty() or not config is Dictionary or config.get("version")!=1:
		return {}
	var state:Dictionary=original.state.duplicate(true)
	var profile:Dictionary=original.profile.duplicate(true)
	var defs:Dictionary=original.defs.duplicate(true)
	profile.id="campaign_42"
	profile.day_ids=[]
	for i:int in range(1,43):
		var day:String="d"+str(i)
		profile.day_ids.append(day)
		if not profile.visit_days.has(day):
			profile.visit_days[day]=[]
	# Existing D7 paid service can be collected on D8 only in this
	# isolated forty-two-day extension, without changing demo7 data.
	profile.erase("carryover_returns")
	profile.visit_days["d8"].append("pickup7")
	for actor:String in ["alpha_pawn_seller","alpha_order_buyer","alpha_escrow","alpha_broker",
		"alpha_merc_a","alpha_merc_b"]:
		if state.wallets.has(actor):
			return {}
		state.wallets[actor]=_cash(0)
		state.inventories[actor+"_grid"]={"owner_id":actor,"width":10,"height":6,"host_item":""}
	state.wallets.alpha_pawn_seller=_cash(60)
	state.wallets.alpha_order_buyer=_cash(175)
	state.wallets.alpha_broker={"VKC":100,"USD":5}
	state.wallets.alpha_merc_a=_cash(400)
	state.wallets.alpha_merc_b=_cash(400)
	state.items["ALPHA_PAWN01"]=Objects.fresh_item("demo_tool","alpha_pawn_seller",
		"alpha_pawn_seller_grid",0,0,"authored_pawn_stock")
	state.items["ALPHA_ORDER01"]=Objects.fresh_item("demo_tool","player",
		"player_stock",0,5,"authored_player_order_stock")
	state.visits["alpha_pawn_offer"]={"scope":{"visit_id":"alpha_pawn_offer","kind":"ordinary",
		"purpose":"purchase","completed":false,"required_ids":[]},
		"seller":"alpha_pawn_seller","buyer":"player",
		"prices":{"ALPHA_PAWN01":_cash(45)},"opens":7*Clock.DAY_MINUTES,
		"expires":7*Clock.DAY_MINUTES+Clock.BUSINESS_MINUTES,
		"allow_inspection":true}
	profile.visit_days["d8"].append("alpha_pawn_offer")
	profile["merchant_contracts"]={"version":1,"escrow_actor":"alpha_escrow",
		"pawns":{"alpha_pawn":{"customer":"alpha_pawn_seller",
			"visit_id":"alpha_pawn_offer","item_id":"ALPHA_PAWN01",
			"principal":_cash(40),"repayment":_cash(45),"repayment_day":9,"due_day":10,
			"placement":{"inventory":"player_stock","x":1,"y":5,"rotated":false}}},
		"orders":{"alpha_order":{"customer":"alpha_order_buyer","def_id":"demo_tool",
			"price":_cash(90),"offer_day":8,"due_day":10}}}
	profile["exchange_market"]={"version":1,"quotes":{
		"alpha_broker_quote":{"counterparty":"alpha_broker",
			"give_currency":"VKC","give_amount":30,
			"receive_currency":"USD","receive_amount":1,
			"first_day":8,"last_day":12}}}
	profile["regional_world"]={"version":1,
		"regions":{"market_quarter":{"status":"ordinary"}},
		"events":{"alpha_market_notice":{"day":10,"region":"market_quarter",
			"topic":"trade_stock_pressure","without_player":"ordinary",
			"with_player":"strained","cause_visit":"g09",
			"source":"local_market_notice"}},"gates":{}}
	profile["market_flow"]={"version":1,"flow_step":1,"max_flow_delta":8,
		"buyers":{},"entries":{}}
	profile["npc_population"]={"version":1,"seed":1729,
		"actors":{"alpha_merc_a":{"kind":"mercenary","region":"market_quarter"},
			"alpha_merc_b":{"kind":"scavenger","region":"market_quarter"}}}
	profile["npc_bargaining"]={"version":1,"traits":{
		"cautious":{"seller_delta":5,"buyer_delta":-5},
		"impatient":{"seller_delta":-5,"buyer_delta":5},
		"methodical":{"seller_delta":0,"buyer_delta":0},
		"reserved":{"seller_delta":2,"buyer_delta":-2}},
		"loyalty_step":2,"max_trades":3}
	var slots:Dictionary={}
	var stock_count:Dictionary={"alpha_merc_a":0,"alpha_merc_b":0}
	for number:int in range(12):
		var day:int=9+number*3
		var id:String="g"+str(day).pad_zeros(2)
		var actor:String="alpha_merc_a" if int(number/2)%2==0 else "alpha_merc_b"
		var candidates:Array=[]
		for choice:int in range(2):
			var serial:int=int(stock_count[actor])
			stock_count[actor]=serial+1
			var item_id:String=id+"_"+str(choice)
			state.items[item_id]=Objects.fresh_item("demo_tool",actor,
				actor+"_grid",serial%8,int(serial/8.0),"authored_finite_merc_supply")
			candidates.append({"actor":actor,"item_id":item_id,
				"price":_cash(42+number),"side":"offer"})
		slots[id]={"day_id":"d"+str(day),"region":"market_quarter",
			"candidates":candidates}
	profile["npc_generated_visits"]={"version":1,"seed":int(config.visit_seed),"slots":slots}
	profile["npc_continuity"]={"version":1,
		"gates":{"g12":{"prior_visit":"g09","outcome":"traded"}}}
	# The finite market indexes the selected *existing object*, not a
	# speculative unnamed candidate, and never funds a new visitor.
	var realized:Dictionary=Generated.expand(state,profile)
	if realized.is_empty():
		return {}
	for id:String in slots:
		var visit:Dictionary=realized.state.visits[id]
		var item:String=str(visit.prices.keys()[0])
		var initial:int=int(visit.prices[item].VKC)
		profile.market_flow.entries[id]={"region":"market_quarter",
			"category":"demo_tools","item_id":item,"def_id":"demo_tool",
			"currency":"VKC","prices":{"ordinary":initial,
			"strained":initial+2,"limited":initial+4}}
	return {"state":state,"profile":profile,"defs":defs}

static func fresh()->RefCounted:
	var source:Dictionary=content()
	if source.is_empty():
		return null
	var session:=Session.new()
	if session.initialize(source.defs,source.state,false,false,source.profile):
		return session
	printerr("ALPHA42_SEED_INVALID "+session.initialization_error())
	return null
