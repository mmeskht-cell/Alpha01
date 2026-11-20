extends RefCounted
## Actual demo content; no test fixture dependency. All money and stock created once in seed.
const Session=preload("res://src/domain/game_session.gd")
const Objects=preload("res://src/domain/object_schema.gd")
const Rules=preload("res://src/domain/value_rules.gd")
const Catalog=preload("res://src/content/catalog_loader.gd")
const DATA="res://data/campaign/gate2/demo7.json"

static func money(n:int)->Dictionary:
	return {"VKC":n,"USD":0}

static func definition(id:String,key:String,w:int=1,h:int=1)->Dictionary:
	return {"def_id":id,"category":"demo","localization_key":key,"render_key":"placeholder_none","width":w,"height":h}

static func content()->Dictionary:
	var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not raw is Dictionary or raw.get("version")!=1:
		return {}
	var loaded:Dictionary=Catalog.load_file("res://data/campaign/gate1_day_one/catalog.json")
	if not loaded.ok:
		return {}
	var defs:Dictionary=loaded.definitions.duplicate(true)
	for row:Array in [["fictional_watch_p2","p2.watch.meridian12"],["demo_tool","item.demo_tool"],["demo_hygiene","item.demo_hygiene"],["demo_electronics","item.demo_electronics"]]:
		defs[row[0]]=Objects.definition(definition(row[0],row[1]))
	for cost:int in [5,10]:
		var id:String="demo_service_"+str(cost)
		var d:Dictionary=Objects.definition(definition(id,"item.fictional_gear",2,1))
		d.restorable=true
		d.restore_cost=money(cost)
		defs[id]=d
	var state:Dictionary={"object_schema":3,"revision":0,"game_minutes":0,"phase":"shop","wallets":{"player":money(180)},"inventories":{"player_stock":{"owner_id":"player","width":10,"height":6,"host_item":""},"service_grid":{"owner_id":"player","width":4,"height":3,"host_item":""}},"items":{},"visits":{},"ledger":[],"receipts":{},"receipt_archive":{},"tombstones":{},"object_events":[],"knowledge":{}}
	var counters:Dictionary={}
	for actor:String in raw.actors:
		state.wallets[actor]=money(0)
		state.inventories[actor+"_grid"]={"owner_id":actor,"width":10,"height":6,"host_item":""}
		counters[actor]=0
	var day_ids:Array=[]
	var schedule:Dictionary={}
	for i:int in range(7):
		var day:String="d"+str(i+1)
		day_ids.append(day)
		schedule[day]=raw.schedule[i]
	for row:Array in raw.trades:
		var id:String=row[0]
		var day:int=int(row[1])
		var item:String=row[2]
		var seller:String=row[4]
		var buyer:String=row[5]
		var price:int=int(row[6])
		if not state.items.has(item):
			if seller=="player":
				return {}
			var n:int=counters[seller]
			var row_y:int=int(n/3.0)*2
			state.items[item]=Objects.fresh_item(row[3],seller,seller+"_grid",(n%3)*3,row_y,"p2_watch_a" if item=="WAT02" else "demo_"+item)
			counters[seller]+=1
		if buyer!="player":
			state.wallets[buyer].VKC+=price
		var prices:Dictionary={}
		prices[item]=money(price)
		state.visits[id]={"scope":{"visit_id":id,"kind":"ordinary","purpose":"purchase" if buyer=="player" else "sale","completed":false,"required_ids":[]},"seller":seller,"buyer":buyer,"prices":prices,"opens":(day-1)*1440,"expires":(day-1)*1440+600,"allow_inspection":true}
	var services:Dictionary={}
	for row:Array in raw.services:
		var id:String=row[0]
		var item:String=row[1]
		var customer:String=row[2]
		var day:int=int(row[3])
		var fee:int=int(row[4])
		var cost:int=int(row[5])
		var n:int=counters[customer]
		state.items[item]=Objects.fresh_item("demo_service_"+str(cost),customer,customer+"_grid",(n%3)*3,int(n/3.0)*2,"demo_"+item)
		state.items[item].functional=false
		counters[customer]+=1
		state.wallets[customer].VKC+=fee
		services[id]={"offer_id":"clinic_service" if day==6 else "service"+str(day),"return_ids":["pickup"+str(day)],"item_id":item,"customer":customer,"fee":money(fee),"placement":{"inventory":"service_grid","x":0,"y":0,"rotated":false}}
	# Dynamic return is authored separately; no future pending visit pins R001 active.
	state.wallets.G08.VKC+=140
	var profile:Dictionary={"id":"demo_7","content_version":"demo7-integrated-3","day_ids":day_ids,"visit_days":schedule,"services":services,"contracts":{"rad1_first":{"supplier":"marcus","supply_id":"rad1_supply_1","offer_day":1,"due_day":4,"delivery_day":5,"extension_day":5,"price":money(300),"label_key":"day1.marcus.offer"}},"story_rules":{"clinic_supply_confirmed":{"day":6,"source":"trade","source_id":"hygiene_sale","outcome":"traded","text_key":"clinic_supply_confirmed"},"rad1_delivered":{"day":6,"source":"contract","source_id":"rad1_first","outcome":"delivered","text_key":"rad1_delivered"},"rad1_defaulted":{"day":6,"source":"contract","source_id":"rad1_first","outcome":"defaulted","text_key":"rad1_defaulted"}},"carryover_returns":{"pickup7":8},"appraisal_profile":"watch_p2_v1","lifecycle_version":"calendar-lifecycle-1","tracking_candidates":{"R001":{"tier":"narrative","pinned":false},"WAT02":{"tier":"tracked","pinned":false}}}
	profile["reentry_rules"]={"radio_return":{"item_id":"R001","prior_sale":"visit_g02_buy","seller":"G02","day":7,"price":money(95),"placement":{"inventory":"G02_grid","x":6,"y":4,"rotated":false},"resale":{"id":"radio_return_sale","buyer":"G08","price":money(140)},"functional_after":false}}
	profile["reaction_rules"]={"clinic_d6":{"day":6,"trade_visit":"hygiene_sale","opportunity_id":"clinic_service","local_public":true,"organization_id":""}}
	return {"defs":defs,"state":state,"profile":profile}

static func fresh()->RefCounted:
	var c:Dictionary=content()
	if c.is_empty():
		return null
	var s:=Session.new()
	if s.initialize(c.defs,c.state,false,false,c.profile):
		return s
	print("ZT_DEMO_SEED_DIAGNOSTIC stage=",s.initialization_error()," object=",Objects.validation_error(c.state,c.defs))
	return null
