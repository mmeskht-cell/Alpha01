extends SceneTree
const Play = preload("res://tests/fixtures/b3_campaign_play.gd")
const Catalog = preload("res://src/domain/b3_integrated_catalog.gd")
const Seed = preload("res://src/content/b3_integrated_campaign_seed.gd")
const Legacy = preload("res://src/content/b3_f3_composite_seed.gd")
const V1 = preload("res://src/content/b3_civilian_supply_seed.gd")
const V2 = preload("res://src/content/b3_civilian_supply_v2_seed.gd")
const Slots = preload("res://src/content/b3_campaign_slots.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const Art = preload("res://src/presentation/native_v23_art.gd")
const Market = preload("res://src/domain/b3_f2_market.gd")
const Surface = preload("res://src/domain/appraisal_surface_profiles.gd")
const EXISTING := {
	"medical_06_soap":["HY05","demo_hygiene",["hygiene_buy","hygiene_sale"]],
	"utility_01_field_radio":["F3R01","f3_receiver_v1",["f3_receiver_buy","f3_receiver_sale","f3_receiver_return"]],
	"utility_03_aa_batteries":["BAT02","battery",["battery_buy","battery_sale"]],
	"utility_05_wrench":["TL04","demo_tool",["tool_buy","tool_sale"]],
	"utility_08_multimeter":["EL06","demo_electronics",["electronics_buy","electronics_sale"]],
	"utility_10_control_module":["F3S01","f3_module_b",["f3_spare_buy"]]
}
var checks := 0
var failures := 0

func check(condition: bool,message: String) -> bool:
	checks+=1
	if not condition:
		failures+=1
		printerr("FAIL: ",message)
	return condition

func subset(expected: Dictionary,actual: Dictionary) -> bool:
	for id: Variant in expected:
		if not actual.has(id) or actual[id]!=expected[id]: return false
	return true

func asset_map() -> Dictionary:
	var expected := {}
	for folder: String in ["preserved_food_v03","approved_civilian_v01"]:
		var path := "res://assets/art/items/"+folder+"/asset_manifest.json"
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		for item: Dictionary in manifest.items:
			var key: String = str(item.get("art_key",item.get("key","")))
			expected[key] = folder
	return expected

func exact_art(model: String,id: String,art_key: String,folder: String) -> bool:
	for role: String in ["stock","counter","inspection"]:
		var texture: Texture2D = Art.ITEMS.model_texture(model,role,id)
		var suffix := "_128.png" if role=="stock" else "_256.png"
		if texture==null or not texture.resource_path.ends_with(folder+"/"+art_key+suffix):
			return false
	return true

func sources() -> void:
	var models := Catalog.models()
	var expected := asset_map()
	if not check(models.size()==24 and expected.size()==30,"24 catalog additions and 30 approved manifest art keys"):
		return
	var traced := {}
	var witnessed_stock := {}
	for row: Dictionary in models.values():
		traced[row.model] = true
		check(expected.has(row.model) and exact_art(row.model,row.id,row.model,str(expected.get(row.model,""))),"exact stock, counter and inspection art "+str(row.id))
	for seed_value: int in range(101,125):
		var src := Seed.content(seed_value)
		var base := Legacy.content(seed_value)
		if not check(not src.is_empty() and not base.is_empty() and src==Seed.content(seed_value),"deterministic complete source %d"%seed_value):
			continue
		check(src.state.wallets==base.state.wallets and int(src.state.wallets.player.VKC)==180 and src.state.ledger==base.state.ledger,"initial wallets and ledger %d"%seed_value)
		check(subset(base.defs,src.defs) and subset(base.state.items,src.state.items) and subset(base.state.visits,src.state.visits),"preserve legacy objects, visits and definitions %d"%seed_value)
		check(src.state.items.size()==base.state.items.size()+7 and src.state.visits.size()==base.state.visits.size()+14,"seven finite parcels plus their ordinary routes")
		check(src.alpha_profile.contracts==base.alpha_profile.contracts and src.alpha_profile.story_rules==base.alpha_profile.story_rules and src.alpha_profile.visit_random==base.alpha_profile.visit_random,"same inherited first-week story constraints")
		for index: int in range(7):
			var rows: Array = src.alpha_profile.days[index]
			check(rows.size()<=10 and rows.slice(0,base.alpha_profile.days[index].size())==base.alpha_profile.days[index],"no displaced appointment on day %d"%(index+1))
		var s := Play.fresh(src)
		if not check(s!=null,"source passes actual game authority %d"%seed_value): continue
		for id: String in models:
			if not src.state.items.has(id): continue
			var row: Dictionary = models[id]
			var stock: Dictionary = src.state.items[id]
			witnessed_stock[id] = true
			check(s.spatial_dimensions(id)==[int(row.width),int(row.height)] and stock.provenance_id==Catalog.origin(id),"real physical root with exact footprint "+id)
			check(src.state.visits.has(Catalog.visit_id(id,true)) and src.state.visits.has(Catalog.visit_id(id,false)),"finite purchase and resale visits "+id)
			check(Surface.project(id,stock,{},src.alpha_profile).is_empty(),"no actual appearance in an unread observation "+id)
	check(witnessed_stock.size()==models.size(),"at least one initial physical source for every added model")
	var source := Seed.content(101)
	if source.is_empty(): return
	for key: String in EXISTING:
		var row: Array = EXISTING[key]
		traced[key] = true
		check(source.state.items.get(row[0],{}).get("def_id")==row[1] and exact_art(row[1],row[0],key,str(expected.get(key,""))),"existing real SKU and exact art "+key)
		for id: String in row[2]:
			check(source.state.visits.get(id,{}).get("prices",{}).has(row[0]),"existing real visit "+id)
	check(traced.size()==expected.size() and expected.keys().all(func(key: String)->bool: return traced.has(key)),"all 30 manifest art keys trace to gameplay")
	check(source.state.items.F3R01_B.parent_id=="F3R01" and source.state.items.F3S01.parent_id=="","module B remains two distinct objects with the same model")
	var extra := {"R001":"r001_pixel_front_candidate.png","R003":"civilian_radio_r003.png","WAT02":"meridian_watch_front.png","GE03":"protective_case.png","F3R01_A":"receiver_module_a.png"}
	for id: String in extra:
		var texture: Texture2D = Art.ITEMS.model_texture(source.state.items[id].def_id,"stock",id)
		check(texture!=null and texture.resource_path.ends_with(extra[id]),"additional approved article or attached component "+id)

func compat() -> void:
	var location := "user://zt_rebuild/catalog_compat_"+str(Time.get_ticks_usec())
	var home := Slots.directory(location,0)
	var current := Play.fresh(Seed.content(109))
	if not check(current!=null and Slots.inspect(location,0).status=="empty","product slot starts empty"): return
	var old_slots := {"b3_f5_counter_v1":Legacy.content(109),"b3_civilian_supply_v1":V1.content(109),"b3_civilian_supply_v2":V2.content(109)}
	var disk := Repo.new(home)
	var preserved := {}
	for key: String in old_slots:
		var old := Play.fresh(old_slots[key])
		if not check(old!=null and disk.save_session(old,key).get("ok",false),"existing compatible source saved "+key): return
		preserved[key] = FileAccess.get_file_as_string(home.path_join(key+".a.json"))
	check(Slots.inspect(location,0).status=="empty","legacy versions are invisible to the product slots")
	check(disk.save_session(current,Slots.KEY).get("ok",false),"first new generation")
	check(Play.go(current,"alpha_open") and disk.save_session(current,Slots.KEY).get("ok",false),"second new generation")
	check(Slots.inspect(location,0).status=="valid","verified playable save")
	var recovered := Play.fresh(Seed.content(109))
	check(disk.load_session(recovered,Slots.KEY).get("ok",false) and recovered.snapshot()==current.snapshot(),"same source and journal replay")
	var wrong := Play.fresh(Seed.content(110))
	check(wrong!=null and not disk.load_session(wrong,Slots.KEY).get("ok",false),"same content version with different seed cannot load")
	var legacy := Play.fresh(old_slots.b3_f5_counter_v1)
	check(not disk.load_session(legacy,Slots.KEY).get("ok",false),"F5 source cannot validate new snapshot")
	for key: String in preserved:
		check(FileAccess.get_file_as_string(home.path_join(key+".a.json"))==preserved[key],"old generation stays byte-identical "+key)
		var old := Play.fresh(old_slots[key])
		check(disk.load_session(old,key).get("ok",false),"legacy slot remains readable "+key)
	# Structurally valid JSON with an invalid envelope revision must not
	# influence bootstrap or throw before the valid A generation is loaded.
	var newest_path := home.path_join(Slots.KEY+".b.json")
	var newest: Variant = JSON.parse_string(FileAccess.get_file_as_string(newest_path))
	if not check(newest is Dictionary,"two-generation fixture includes new envelope"): return
	for bad_revision: Variant in [{"invalid":1},-1,int(newest.revision)+1]:
		var damaged: Dictionary = newest.duplicate(true)
		damaged.revision = bad_revision
		var encoded := JSON.stringify(damaged)
		var output := FileAccess.open(newest_path,FileAccess.WRITE)
		if not check(output!=null,"write malformed revision fixture"): return
		output.store_string(encoded)
		output.close()
		var selection := preload("res://src/content/alpha_b3_seed_authority.gd").select_seed(home,Slots.KEY)
		var fallback := Play.fresh(Seed.content(109))
		if not check(selection.get("ok",false) and selection.seed==109 and Slots.inspect(location,0).status=="valid"
			and disk.load_session(fallback,Slots.KEY).get("ok",false) and int(fallback.snapshot().revision)==0
			and FileAccess.get_file_as_string(newest_path)==encoded,"bad revision ignored; genuine older generation stays readable"): return
	for generation: String in ["b","a"]:
		var path := home.path_join(Slots.KEY+"."+generation+".json")
		var file := FileAccess.open(path,FileAccess.WRITE)
		if not check(file!=null,"write isolated broken generation"): return
		file.store_string("{damaged")
		file.close()
		var summary := Slots.inspect(location,0)
		check(summary.status==("valid" if generation=="b" else "damaged") and FileAccess.get_file_as_string(path)=="{damaged","read-only valid-generation fallback or fail closed")
	check(not disk.save_session(current,Slots.KEY).get("ok",false),"two corrupt revisions cannot be overwritten")
	# Explicit fixture only: the same product slot contract can read the
	# next source without changing default New Game or old slot bytes.
	var v2_home := Slots.directory(location,1)
	var v2_disk := Repo.new(v2_home)
	var v2 := Play.fresh(Seed.content(109,2))
	if not check(v2!=null and v2_disk.save_session(v2,Slots.KEY).get("ok",false)
		and Play.go(v2,"alpha_open") and v2_disk.save_session(v2,Slots.KEY).get("ok",false),"versioned product-slot fixture"): return
	var v2_selection := preload("res://src/content/alpha_b3_seed_authority.gd").select_seed(v2_home,Slots.KEY)
	var v2_cold := Play.fresh(Seed.content(109,2))
	check(v2_selection.get("campaign_version",0)==2 and Slots.inspect(location,1).status=="valid"
		and v2_disk.load_session(v2_cold,Slots.KEY).get("ok",false) and v2_cold.snapshot()==v2.snapshot(),"product slot resolves actual versioned source")
	var v1 := Play.fresh(Seed.content(109))
	check(not v2_disk.load_session(v1,Slots.KEY).get("ok",false),"old source cannot load new profile")
	var v1_home := Slots.directory(location,2)
	var v1_disk := Repo.new(v1_home)
	var old_initial: Dictionary = v1.snapshot()
	check(v1_disk.save_session(v1,Slots.KEY).get("ok",false)
		and Slots.inspect(location,2).status=="valid","v1 remains a valid product slot")
	var old_selection := preload("res://src/content/alpha_b3_seed_authority.gd").select_seed(v1_home,Slots.KEY)
	check(old_selection.get("campaign_version",0)==1 and v1.snapshot()==old_initial,"implicit original source resolves to v1 without migration")
	# Two individually valid generations with incompatible sources must
	# never be interpreted as a single campaign, even with the same seed.
	var conflicting := v2_home.path_join(Slots.KEY+".a.json")
	var old_bytes := FileAccess.get_file_as_string(v1_home.path_join(Slots.KEY+".a.json"))
	var output := FileAccess.open(conflicting,FileAccess.WRITE)
	if not check(output!=null,"write isolated mixed-source fixture"): return
	output.store_string(old_bytes)
	output.close()
	var conflict := preload("res://src/content/alpha_b3_seed_authority.gd").select_seed(v2_home,Slots.KEY)
	check(not conflict.get("ok",false) and conflict.get("error")=="campaign_source_conflict"
		and Slots.inspect(location,1).status=="damaged" and FileAccess.get_file_as_string(conflicting)==old_bytes,"mixed valid sources fail closed without rewriting")
	output = FileAccess.open(conflicting,FileAccess.WRITE)
	if not check(output!=null,"isolated corrupt versioned generation fixture"): return
	output.store_string("{damaged")
	output.close()
	var recovered_v2 := Play.fresh(Seed.content(109,2))
	var recovered_slot := Slots.inspect(location,1)
	check(recovered_slot.status=="valid" and v2_disk.load_session(recovered_v2,Slots.KEY).get("ok",false)
		and recovered_v2.snapshot()==v2.snapshot() and FileAccess.get_file_as_string(conflicting)=="{damaged","valid v2 generation survives corrupted sibling without migration")
	check(recovered_slot.get("generation")=="b" and recovered_slot.get("recovered")==true
		and recovered_slot.get("stamp")==int(FileAccess.get_modified_time(v2_home.path_join(Slots.KEY+".b.json")))
		and recovered_slot.get("revision")==v2.snapshot().revision and recovered_slot.get("day")==v2.snapshot().alpha_shop.day,
		"slot metadata derives from restored generation, not recently modified corrupt sibling")

func wallet_total(wallets: Dictionary,currency: String) -> int:
	var total := 0
	for wallet: Dictionary in wallets.values(): total+=int(wallet[currency])
	return total

func visit_trade(s: RefCounted,id: String,report: Dictionary) -> bool:
	var start: Dictionary = s.snapshot()
	var trade := Play.transfer(s,id)
	if trade.is_empty(): return false
	var purchase: bool = trade.buyer=="player"
	var appraisal: Dictionary = s.alpha_view().appraisal
	var model: Dictionary = Catalog.specimen(start.alpha_shop.profile,id,start.items[id])
	var quote: int = int(s.alpha_view().get("customer_ask_vkc" if purchase else "customer_bid_vkc",0))
	if not check(quote==trade.amount and appraisal.cards.is_empty() and appraisal.surface_profiles.is_empty(),"public price and private facts start separate "+id): return false
	if not check(appraisal.tools.any(func(tool: Dictionary)->bool: return tool.id=="function_detail")==model.functional,"packaging and functional tool permissions "+id): return false
	if not purchase:
		var unlisted := start.duplicate(true)
		unlisted.alpha_shop.displayed.erase(id)
		var gate := preload("res://src/domain/alpha_shop_cycle.gd").trade_gate(unlisted,trade)
		if not check(gate=="alpha_trade_not_displayed","unlisted goods cannot settle "+id): return false
		var unfunded := start.duplicate(true)
		unfunded.wallets[trade.buyer].VKC = quote-1
		if not check(not Market.eligible(unfunded,trade.visit_id),"actual buyer reserve depends on cash "+id): return false
	if not Play.go(s,"alpha_inspect",{"slot":"identity"}): return false
	var slot := "function_detail" if model.functional else ("wear_detail" if not str(model.family).is_empty() else "")
	if not slot.is_empty():
		if not Play.go(s,"alpha_inspect",{"slot":slot}): return false
		var updated: Dictionary = s.alpha_view().appraisal
		var surface: Dictionary = updated.surface_profiles
		if not check(updated.cards.size()==2 and updated.cards.all(func(card: Dictionary)->bool: return not card.public_active),"observations are private until offered "+id): return false
		if slot=="wear_detail" and not check(surface.get(slot,{}).get("family")==model.family,"observed live surface has exact material "+id): return false
		if slot=="function_detail" and not check(updated.cards.any(func(card: Dictionary)->bool: return card.slot==slot and card.value==("serviceable" if start.items[id].functional else "inoperable")),"explicit fictional function reading "+id): return false
	if int(start.wallets[trade.buyer].VKC)<quote:
		if not Play.go(s,"alpha_price_offer",{"amount":quote}): return false
		report.refusals.append(id)
		if not check(s.alpha_view().appraisal.accepted.is_empty() and s.snapshot().ledger==start.ledger and s.snapshot().wallets==start.wallets,"unfunded offer leaves ownership and money untouched"): return false
		return Play.leave(s)
	if not Play.go(s,"alpha_price_offer",{"amount":quote}): return false
	var payment := Play.command(s,"alpha_trade",trade)
	if not s.execute(payment).get("ok",false): return false
	var paid: Dictionary = s.snapshot()
	if not check(paid.items[id].owner_id==trade.buyer and paid.items[id].custodian_id==trade.buyer and paid.items[id].provenance_id==start.items[id].provenance_id and paid.ledger.size()==start.ledger.size()+1,"one ownership and ledger movement "+id): return false
	if not check(paid.items[id].basis.VKC==(quote if purchase else start.items[id].basis.VKC),"purchase basis survives resale "+id): return false
	if not check(s.execute(payment).get("ok",false) and s.snapshot()==paid,"same receipt is idempotent "+id): return false
	if not Play.go(s,"alpha_ack_exit"): return false
	report["bought" if purchase else "sold"].append(id)
	return not purchase or Play.display(s,id)

func week(seed_value: int,version: int=1) -> void:
	var source := Seed.content(seed_value,version)
	var s := Play.fresh(source)
	if not check(s!=null,"integrated campaign initializes %d"%seed_value): return
	var start: Dictionary = s.snapshot()
	var report := {"seed":seed_value,"planner_version":version,"visible":[],"offers":[],"bought":[],"sold":[],"refusals":[],"daily":[],"attendance":[],"profit":0}
	for day: int in range(1,8):
		if not check(Play.go(s,"alpha_open"),"real day opens %d"%day): return
		var seen := 0
		var opening: Dictionary = s.snapshot()
		var opened: Dictionary = s.alpha_view().attendance.duplicate(true)
		var arrived: Array = []
		var regular := 0
		var named := 0
		var anchors := 0
		var anchor_ids: Array = ["alpha_marcus_intro","alpha_ian_hygiene_offer_d1"]
		while int(s.alpha_view().remaining)>0:
			if not check(Play.next_customer(s),"real customer enters"): return
			seen+=1
			var view: Dictionary = s.alpha_view()
			arrived.append(str(view.active.id))
			if str(view.active.kind)=="regular": regular+=1
			elif str(view.active.kind)=="named": named+=1
			if str(view.active.id) in anchor_ids: anchors+=1
			var id := Catalog.visit_item(source.alpha_profile,str(view.active.id))
			if id.is_empty():
				if not check(Play.leave(s),"inherited customer can be served or declined"): return
			else:
				if view.appraisal.we_buy:
					report.visible.append(id)
				else:
					report.offers.append(id)
				if not check(visit_trade(s,id,report),"real trade route "+id): return
		report.daily.append(seen)
		var planned: Array = opening.alpha_shop.random_visits.plan.duplicate()
		var not_planned: Array = []
		for candidate: Dictionary in source.alpha_profile.days[day-1]:
			if candidate.id not in planned: not_planned.append(candidate.id)
		var not_arrived: Array = planned.filter(func(id: String)->bool: return id not in arrived)
		report.attendance.append({"day":day,"opening":opened,"planned_ids":planned,"arrived_ids":arrived,"unplanned_ids":not_planned,"unarrived_planned_ids":not_arrived,"regular_count":regular,"named_count":named,"opening_story_anchor_count":anchors,"other_count":seen-regular-named,"cash_open":opening.wallets.player.duplicate(),"cash_close":s.snapshot().wallets.player.duplicate(),"displayed_open":opening.alpha_shop.displayed.duplicate(),"displayed_close":s.snapshot().alpha_shop.displayed.duplicate()})
		if not check(arrived.size()==seen and seen<=planned.size() and seen<=10 and anchors<=named
			and (day!=1 or anchors==2) and Play.sequence(s,["alpha_close","alpha_settle","alpha_next_day"]),"bounded attendance, opening story anchors and closing %d"%day): return
		if day<7 and not check(Play.go(s,"alpha_prepare_day"),"prepare following day"): return
	var end: Dictionary = s.snapshot()
	report.profit = int(end.wallets.player.VKC)-int(start.wallets.player.VKC)
	check(end.alpha_shop.phase=="COMPLETE" and end.items.size()==start.items.size(),"seven days and finite identity count")
	check(end.ledger.size()==report.bought.size()+report.sold.size(),"ledger equals actual catalog transactions")
	check(wallet_total(end.wallets,"VKC")==wallet_total(start.wallets,"VKC") and wallet_total(end.wallets,"USD")==wallet_total(start.wallets,"USD"),"no currency added during trade")
	var tallies := 0
	for count: int in Market.market_history(end,8).counts.values(): tallies+=count
	check(tallies==end.ledger.size(),"regional activity arises from settled catalog trades")
	var disk := Repo.new("user://zt_rebuild/catalog_week_%d_%d"%[seed_value,Time.get_ticks_usec()])
	var replay := Play.fresh(source)
	var key: String = Seed.PLANNER_TRIAL_KEY if version==2 else Slots.KEY
	check(disk.save_session(s,key).get("ok",false) and disk.load_session(replay,key).get("ok",false) and replay.snapshot()==end,"seven-day save and cold exact replay")
	if version==2:
		var legacy := Play.fresh(Seed.content(seed_value))
		check(legacy!=null and not disk.load_session(legacy,key).get("ok",false),"v1 cannot reinterpret v2 planner journal")
		check(start.wallets==Seed.content(seed_value).state.wallets,"v2 initial wallets unchanged")
	print("B3_CATALOG_WEEK_JSON ",JSON.stringify(report))

# Supplement, not a replacement for the 24-model matrix. Exercise a real
# ordinary-trade strategy including old and new inventory, retaining limits.
const MIXED_ITEMS := ["HY05","F3R01","BAT02","TL04","EL06","F3S01","R001","R003","WAT02","GE03"]
const Cycle = preload("res://src/domain/alpha_shop_cycle.gd")

func mixed(seed_value: int,version: int=1) -> void:
	var source := Seed.content(seed_value,version)
	var s := Play.fresh(source)
	if not check(s!=null,"mixed integrated source"): return
	var start: Dictionary = s.snapshot()
	var report := {"seed":seed_value,"planner_version":version,"bought":[],"sold":[],"skips":[],"daily":[],"cash_delta":{},"stock_basis_vkc":0}
	for day: int in range(1,8):
		if not check(Play.go(s,"alpha_open"),"mixed open"): return
		var count := 0
		var daily: Dictionary = s.alpha_view().attendance.duplicate(true)
		var planned: Array = s.snapshot().alpha_shop.random_visits.plan.duplicate()
		var arrived: Array = []
		var regular := 0
		while int(s.alpha_view().remaining)>0:
			if not check(Play.next_customer(s),"mixed customer enters"): return
			count+=1
			var view: Dictionary = s.alpha_view()
			var state: Dictionary = s.snapshot()
			var visit_id: String = str(view.active.id)
			arrived.append(visit_id)
			if view.active.kind=="regular": regular+=1
			var visit: Dictionary = state.visits.get(visit_id,{})
			var item_id: String = str(view.appraisal.get("item_id",""))
			var relevant: bool = item_id in MIXED_ITEMS or not Catalog.visit_item(source.alpha_profile,visit_id).is_empty()
			var reason := "nonordinary_or_unselected"
			var completed := false
			if relevant and visit.get("scope",{}).get("kind")=="ordinary" and visit.get("prices",{}).has(item_id):
				var price: Dictionary = visit.prices[item_id]
				var currency := "VKC" if int(price.VKC)>0 and int(price.USD)==0 else ("USD" if int(price.USD)>0 and int(price.VKC)==0 else "")
				var dest: String = "player_stock" if visit.buyer=="player" else str(visit.buyer)+"_grid"
				var fit: Dictionary = s.spatial_fit(item_id,dest)
				reason = "currency_or_space"
				if not currency.is_empty() and fit.get("ok",false):
					var amount := int(price[currency])
					var trade := {"visit_id":visit_id,"item_id":item_id,"seller":visit.seller,"buyer":visit.buyer,"currency":currency,"amount":amount,"inventory":dest,"x":fit.x,"y":fit.y,"rotated":fit.rotated}
					reason = Cycle.trade_gate(state,trade)
					if reason.is_empty():
						if int(state.wallets[visit.buyer][currency])<amount:
							reason = "buyer_cash"
						elif visit.buyer=="player" and not s.spatial_fit(item_id,"storefront_grid").get("ok",false):
							reason = "shelf_capacity"
						else:
							if not check(Play.go(s,"alpha_price_offer",{"amount":amount}),"mixed ordinary quote "+visit_id): return
							if s.alpha_view().appraisal.accepted.is_empty():
								reason = "offer_declined"
							else:
								if not check(Play.go(s,"alpha_trade",trade),"mixed actual settlement "+visit_id): return
								var paid: Dictionary = s.snapshot()
								if not check(paid.items[item_id].owner_id==visit.buyer and paid.items[item_id].provenance_id==state.items[item_id].provenance_id and paid.ledger.size()==state.ledger.size()+1,"mixed ledger and same identity "+item_id): return
								if not check(Play.go(s,"alpha_ack_exit"),"mixed exit"): return
								completed = true
								report["bought" if visit.buyer=="player" else "sold"].append({"item":item_id,"visit":visit_id,"day":day,"currency":currency,"amount":amount})
								if visit.buyer=="player" and not check(Play.display(s,item_id),"mixed real shelf "+item_id): return
			if not completed:
				if relevant: report.skips.append({"visit":visit_id,"item":item_id,"day":day,"reason":reason})
				if not check(Play.leave(s),"mixed declined or unrelated visit "+visit_id): return
		daily["actual"] = count
		daily["regular_count"] = regular
		daily["planned_ids"] = planned
		daily["arrived_ids"] = arrived
		daily["unarrived_planned_ids"] = planned.filter(func(id:String)->bool:return id not in arrived)
		report.daily.append(daily)
		if not check(count<=planned.size() and count<=10 and Play.sequence(s,["alpha_close","alpha_settle","alpha_next_day"]),"mixed closing"): return
		if day<7 and not check(Play.go(s,"alpha_prepare_day"),"mixed next preparation"): return
	var end: Dictionary = s.snapshot()
	for currency: String in ["VKC","USD"]:
		report.cash_delta[currency] = int(end.wallets.player[currency])-int(start.wallets.player[currency])
		check(wallet_total(end.wallets,currency)==wallet_total(start.wallets,currency),"mixed finite currency "+currency)
	for item: Dictionary in end.items.values():
		if item.owner_id=="player" and item.custodian_id=="player" and item.status=="stock":
			report.stock_basis_vkc+=int(item.basis.VKC)
	check(end.alpha_shop.phase=="COMPLETE" and end.ledger.size()==report.bought.size()+report.sold.size(),"mixed actual week ledger")
	print("B3_MIXED_WEEK_JSON ",JSON.stringify(report))

func repair() -> void:
	var target := "CS20"
	var route := Play.trade_witness(target,true)
	if not check(not route.is_empty(),"natural faulty flashlight in the real campaign plan"): return
	var s := Play.fresh(route.source)
	if not check(s!=null and s.restore(route.buy),"exact replay to faulty specimen"): return
	var trade := Play.transfer(s,target)
	var forbidden := {"actor":"player","item_id":target,"confirmed_ids":[target]}
	var customer_state: Dictionary = s.snapshot()
	if not check(s.alpha_discard_preview(target).is_empty()
		and not s.execute(Play.command(s,"spatial_discard",forbidden)).get("ok",false)
		and s.snapshot()==customer_state,"customer-owned article cannot be disposed at counter"): return
	if not check(not trade.is_empty() and Play.go(s,"alpha_inspect",{"slot":"function_detail"})
		and Play.go(s,"alpha_card_toggle",{"slot":"function_detail","selected":true}),"explicitly test and disclose the failed function"): return
	var discount := clampi(roundi(int(trade.amount)*0.10),1,3)
	trade.amount -= discount
	if not check(Play.go(s,"alpha_price_offer",{"amount":trade.amount}) and s.alpha_view().appraisal.accepted.get("amount")==trade.amount
		and Play.go(s,"alpha_trade",trade) and Play.sequence(s,["alpha_ack_exit","alpha_close","alpha_settle"]),"verified fault can affect genuine terms before workshop"): return
	var before: Dictionary = s.snapshot()
	var cost: Dictionary = s.alpha_stock_restore_cost(target)
	var request := {"actor":"player","item_id":target}
	var draft: Dictionary = s.spatial_action_preview("spatial_restore_item",request)
	if not check(cost.VKC==5 and draft.get("ok",false) and int(draft.VKC)==-int(cost.VKC) and s.snapshot()==before,"evening quote is read-only"): return
	if not check(Play.go(s,"spatial_restore_item",request),"perform authorized evening repair"): return
	var after: Dictionary = s.snapshot()
	check(after.items[target].functional and after.items[target].provenance_id==before.items[target].provenance_id
		and after.items[target].basis.VKC==before.items[target].basis.VKC+cost.VKC
		and after.wallets.player.VKC==before.wallets.player.VKC-cost.VKC
		and after.ledger==before.ledger and after.object_events.back().expenses==cost,"paid repair updates same article, basis and work record")
	if not check(not s.execute(Play.command(s,"spatial_restore_item",request)).get("ok",false) and s.snapshot()==after,"repair cannot be collected twice"): return
	# Independent genuine branch: disposal of ordinary owned catalog stock.
	# The original repair/resale path below remains intact.
	var disposal := Play.fresh(route.source)
	if not check(disposal!=null and disposal.restore(after),"disposal branch replays real paid repair"): return
	var preview: Dictionary = disposal.alpha_discard_preview(target)
	if not check(not preview.is_empty() and preview.payload.confirmed_ids==[target]
		and preview.basis==after.items[target].basis and disposal.snapshot()==after,"owned catalog root has read-only evening disposal quote"): return
	var wrong: Dictionary = preview.payload.duplicate(true)
	wrong.confirmed_ids=[]
	if not check(not disposal.execute(Play.command(disposal,"spatial_discard",wrong)).get("ok",false)
		and disposal.snapshot()==after,"incorrect family confirmation cannot dispose"): return
	if not check(Play.go(disposal,"spatial_discard",preview.payload),"authorized catalog disposal"): return
	var discarded: Dictionary = disposal.snapshot()
	if not check(not discarded.items.has(target) and discarded.tombstones.has(target)
		and discarded.tombstones[target].provenance_id==after.items[target].provenance_id
		and discarded.object_events.back().basis==after.items[target].basis
		and discarded.object_events.back().expenses=={"VKC":0,"USD":0}
		and discarded.wallets==after.wallets and discarded.ledger==after.ledger,"terminal same identity and basis; no invented cash flow"): return
	if not check(disposal.alpha_discard_preview(target).is_empty()
		and not disposal.execute(Play.command(disposal,"spatial_discard",preview.payload)).get("ok",false)
		and disposal.snapshot()==discarded,"cannot dispose twice"): return
	var disposed_history: Dictionary = disposal.alpha_item_history(target)
	if not check(disposed_history.work_records.any(func(row:Dictionary)->bool:return row.kind=="discard" and row.loss==preview.basis)
		and disposed_history.prior_offers.size()==1
		and disposed_history.prior_offers[0].facts.all(func(fact:Dictionary)->bool:return fact.get("current",true)==false),"terminal history retains offers as past facts only"): return
	var disposal_disk := Repo.new("user://zt_rebuild/catalog_disposal_%d"%Time.get_ticks_usec())
	var disposal_cold := Play.fresh(route.source)
	if not check(disposal_disk.save_session(disposal,Slots.KEY).get("ok",false)
		and disposal_disk.load_session(disposal_cold,Slots.KEY).get("ok",false)
		and disposal_cold.snapshot()==discarded and disposal_cold.alpha_item_history(target)==disposed_history,"terminal history survives cold replay"): return
	if not check(Play.sequence(disposal,["alpha_next_day","alpha_prepare_day","alpha_open"]),"open after disposal"): return
	for day: int in range(int(after.alpha_shop.day)+1,int(route.sale_day)):
		if not check(Play.advance(disposal),"advance to disposed item buyer day"): return
	if not check(Catalog.visit_id(target,false) not in disposal.snapshot().alpha_shop.random_visits.plan
		and not disposal.snapshot().items.has(target),"disposed item cannot reappear in subsequent sale plan"): return
	# A repair changes the authoritative function, not the historic disclosure.
	# Reappraise at the actual later customer visit, never reuse a prior card as current.
	var purchase_id := Catalog.visit_id(target,true)
	var sale_id := Catalog.visit_id(target,false)
	var historic: Dictionary = after.alpha_shop.appraisal.visits[purchase_id].duplicate(true)
	if not check(historic.observed.function_detail.value=="inoperable" and historic.observed.function_detail.version.functional!=after.items[target].field_versions.functional
		and not historic.offers.is_empty(),"repair preserves the earlier faulty observation and its version"): return
	var history_after: Dictionary = s.alpha_item_history(target)
	if not check(history_after.prior_offers.size()==1 and history_after.prior_offers[0].facts.any(func(fact:Dictionary)->bool:return fact.slot=="function_detail" and fact.value=="inoperable" and fact.get("current",true)==false)
		and s.snapshot()==after,"history flags the previous disclosed fault as stale without changing it"): return
	if not check(Play.display(s,target),"repaired physical item goes on the finite shelf"): return
	var first_day := int(after.alpha_shop.day)
	var sale_day := int(route.sale_day)
	if not check(sale_day>first_day and Play.sequence(s,["alpha_next_day","alpha_prepare_day","alpha_open"]),"real following day opens after repair"): return
	for day: int in range(first_day+1,sale_day):
		if not check(Play.advance(s),"advance toward actual resale day %d"%day): return
	if not check(Play.reach(s,sale_id),"funded later buyer enters for the repaired item"): return
	var projected: Dictionary = s.alpha_view().appraisal
	if not check(projected.item_id==target and projected.cards.is_empty() and projected.tools.any(func(tool:Dictionary)->bool:return tool.id=="function_detail"),"new visit requires a new private function observation"): return
	if not check(Play.go(s,"alpha_inspect",{"slot":"function_detail"}),"explicitly reappraise the repaired specimen"): return
	var renewed: Dictionary = s.snapshot()
	var current: Dictionary = renewed.alpha_shop.appraisal.visits[sale_id].observed.function_detail
	if not check(current.value=="serviceable" and current.version.functional==renewed.items[target].field_versions.functional
		and renewed.alpha_shop.appraisal.visits[purchase_id]==historic
		and s.alpha_view().appraisal.cards.any(func(card:Dictionary)->bool:return card.slot=="function_detail" and card.value=="serviceable" and not card.public_active),"current function differs while earlier private/public history is unchanged"): return
	trade = Play.transfer(s,target)
	if not check(not trade.is_empty() and Play.go(s,"alpha_card_toggle",{"slot":"function_detail","selected":true})
		and Play.go(s,"alpha_price_offer",{"amount":trade.amount}) and Play.go(s,"alpha_trade",trade) and Play.go(s,"alpha_ack_exit"),"reappraised repaired item settles with the real buyer"): return
	var final: Dictionary = s.snapshot()
	if not check(final.items[target].owner_id==trade.buyer and final.items[target].provenance_id==before.items[target].provenance_id
		and final.alpha_shop.appraisal.visits[purchase_id]==historic and final.ledger.size()==after.ledger.size()+1,"same identity and immutable historic appraisal survive resale"): return
	var history_final: Dictionary = s.alpha_item_history(target)
	if not check(history_final.prior_offers.size()==2 and int(history_final.prior_offers[0].revision)<int(history_final.prior_offers[1].revision)
		and history_final.prior_offers[0].facts.any(func(fact:Dictionary)->bool:return fact.slot=="function_detail" and fact.value=="inoperable" and fact.get("current",true)==false)
		and history_final.prior_offers[1].facts.any(func(fact:Dictionary)->bool:return fact.slot=="function_detail" and fact.value=="serviceable" and fact.get("current",false)==true)
		and s.snapshot()==final,"ordered public history distinguishes old and newly verified function"): return
	var disk := Repo.new("user://zt_rebuild/catalog_reappraisal_%d"%Time.get_ticks_usec())
	var replay := Play.fresh(route.source)
	check(disk.save_session(s,Slots.KEY).get("ok",false) and disk.load_session(replay,Slots.KEY).get("ok",false) and replay.snapshot()==final and replay.alpha_item_history(target)==history_final,"repair and both versioned observations survive cold exact replay")

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var mode: String = arguments[0] if not arguments.is_empty() else "source"
	match mode:
		"source": sources()
		"compat": compat()
		"repair": repair()
		"mixed","mixed_v2":
			if arguments.size()==2 and arguments[1].is_valid_int(): mixed(int(arguments[1]),2 if mode=="mixed_v2" else 1)
			else: check(false,"mixed requires a campaign seed")
		"week","week_v2":
			if arguments.size()==2 and arguments[1].is_valid_int():
				week(int(arguments[1]),2 if mode=="week_v2" else 1)
			else:
				check(false,"week requires a campaign seed")
		_: check(false,"unknown B3 catalog check")
	print("B3_CAMPAIGN_CATALOG: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 and checks>0 else 1)
