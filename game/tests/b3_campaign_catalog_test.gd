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
	for generation: String in ["b","a"]:
		var path := home.path_join(Slots.KEY+"."+generation+".json")
		var file := FileAccess.open(path,FileAccess.WRITE)
		if not check(file!=null,"write isolated broken generation"): return
		file.store_string("{damaged")
		file.close()
		var summary := Slots.inspect(location,0)
		check(summary.status==("valid" if generation=="b" else "damaged") and FileAccess.get_file_as_string(path)=="{damaged","read-only valid-generation fallback or fail closed")
	check(not disk.save_session(current,Slots.KEY).get("ok",false),"two corrupt revisions cannot be overwritten")

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

func week(seed_value: int) -> void:
	var source := Seed.content(seed_value)
	var s := Play.fresh(source)
	if not check(s!=null,"integrated campaign initializes %d"%seed_value): return
	var start: Dictionary = s.snapshot()
	var report := {"seed":seed_value,"visible":[],"offers":[],"bought":[],"sold":[],"refusals":[],"daily":[],"profit":0}
	for day: int in range(1,8):
		if not check(Play.go(s,"alpha_open"),"real day opens %d"%day): return
		var seen := 0
		while int(s.alpha_view().remaining)>0:
			if not check(Play.next_customer(s),"real customer enters"): return
			seen+=1
			var view: Dictionary = s.alpha_view()
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
		if not check(seen<=10 and Play.sequence(s,["alpha_close","alpha_settle","alpha_next_day"]),"bounded attendance and closing %d"%day): return
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
	check(disk.save_session(s,Slots.KEY).get("ok",false) and disk.load_session(replay,Slots.KEY).get("ok",false) and replay.snapshot()==end,"seven-day save and cold exact replay")
	print("B3_CATALOG_WEEK_JSON ",JSON.stringify(report))

func repair() -> void:
	var target := "CS20"
	var route := Play.trade_witness(target,true)
	if not check(not route.is_empty(),"natural faulty flashlight in the real campaign plan"): return
	var s := Play.fresh(route.source)
	if not check(s!=null and s.restore(route.buy),"exact replay to faulty specimen"): return
	var trade := Play.transfer(s,target)
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
	# A repair changes the authoritative function, not the historic disclosure.
	# Reappraise at the actual later customer visit, never reuse a prior card as current.
	var purchase_id := Catalog.visit_id(target,true)
	var sale_id := Catalog.visit_id(target,false)
	var historic: Dictionary = after.alpha_shop.appraisal.visits[purchase_id].duplicate(true)
	if not check(historic.observed.function_detail.value=="inoperable" and historic.observed.function_detail.version.functional!=after.items[target].field_versions.functional
		and not historic.offers.is_empty(),"repair preserves the earlier faulty observation and its version"): return
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
	var disk := Repo.new("user://zt_rebuild/catalog_reappraisal_%d"%Time.get_ticks_usec())
	var replay := Play.fresh(route.source)
	check(disk.save_session(s,Slots.KEY).get("ok",false) and disk.load_session(replay,Slots.KEY).get("ok",false) and replay.snapshot()==final,"repair and both versioned observations survive cold exact replay")

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var mode: String = arguments[0] if not arguments.is_empty() else "source"
	match mode:
		"source": sources()
		"compat": compat()
		"repair": repair()
		"week":
			if arguments.size()==2 and arguments[1].is_valid_int():
				week(int(arguments[1]))
			else:
				check(false,"week requires a campaign seed")
		_: check(false,"unknown B3 catalog check")
	print("B3_CAMPAIGN_CATALOG: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 and checks>0 else 1)
