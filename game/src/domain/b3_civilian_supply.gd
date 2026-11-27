extends RefCounted
## Opt-in civilian content. Four of eight model types per seeded first week.
## Only initial finite stock and ordinary visits; no new wallets or money.
const Objects = preload("res://src/domain/object_schema.gd")
const Grid = preload("res://src/domain/grid_primitives.gd")
const Rules = preload("res://src/domain/value_rules.gd")
const PATH := "res://data/alpha_b3/civilian_supply_v1.json"
const PATH_V2 := "res://data/alpha_b3/civilian_supply_v2.json"
const ACTORS := ["G01","G02","G03","G04","G05","G06","G07","G08","G09","G10","G11","G12"]

static func config(version: int = 1) -> Array:
	if version not in [1,2]: return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH if version==1 else PATH_V2))
	if not data is Dictionary or data.get("version")!=version or not data.get("items") is Array or data.items.size()!=(8 if version==1 else 14): return []
	return data.items

static func selected(seed_value: int,version: int = 1) -> Array:
	var all := config(version)
	if all.is_empty(): return []
	var index := posmod(seed_value,4)
	if version==1:
		return [all[index],all[(index+1)%4],all[4+index],all[4+(index+1)%4]]
	var food: Array = all.filter(func(row:Dictionary)->bool:return row.category=="food")
	var other: Array = all.filter(func(row:Dictionary)->bool:return row.category!="food")
	if food.size()!=10 or other.size()!=4: return []
	var f := posmod(seed_value,10)
	return [food[f],food[(f+1)%10],other[index],other[(index+1)%4]]

static func money(amount: int) -> Dictionary:
	return {"VKC":amount,"USD":0}

static func _free_actor(profile: Dictionary,day: int,actor: String) -> bool:
	var slots: Array = profile.days[day-1]
	return slots.size()<10 and not slots.any(func(row:Dictionary)->bool:return row.actor_id==actor)

static func _fit(state: Dictionary,defs: Dictionary,actor: String,row: Dictionary) -> Dictionary:
	var inventory: String = actor+"_grid"
	if not state.inventories.has(inventory): return {}
	var placements: Array = []
	for id: String in state.items:
		var item: Dictionary = state.items[id]
		if item.inventory!=inventory or not item.parent_id.is_empty(): continue
		var shape := Objects.footprint(state,defs,id)
		placements.append({"item_id":id,"width":shape[0],"height":shape[1],"x":item.x,"y":item.y,"rotated":item.rotated})
	var grid: Dictionary = state.inventories[inventory]
	return Grid.first_fit(grid.width,grid.height,placements,{"item_id":row.id,"width":row.width,"height":row.height,"rotated":false},false)

static func _add_visit(state: Dictionary,profile: Dictionary,row: Dictionary,day: int,actor: String,buy: bool) -> void:
	var id: String = "civilian_"+str(row.id)+("_buy" if buy else "_sale")
	state.visits[id] = {"scope":{"visit_id":id,"kind":"ordinary","purpose":"purchase" if buy else "sale","completed":false,"required_ids":[]},
		"seller":actor if buy else "player","buyer":"player" if buy else actor,"prices":{row.id:money(int(row.purchase if buy else row.sale))},
		"opens":(day-1)*1440,"expires":(day-1)*1440+600,"allow_inspection":true}
	profile.days[day-1].append({"id":id,"actor_id":actor,"kind":"regular","purpose_key":"alpha.purpose.trade","contact_offer":false})

static func extend(source: Dictionary,version: int = 1) -> Dictionary:
	if source.is_empty(): return {}
	var next := source.duplicate(true)
	var state: Dictionary = next.state
	var profile: Dictionary = next.alpha_profile
	if profile.get("f3_composite_trial")!=1 or profile.has("civilian_supply"): return {}
	var all := config(version)
	if all.is_empty(): return {}
	for row: Dictionary in all:
		if next.defs.has(row.model): return {}
		var def := Objects.definition({"def_id":row.model,"category":row.category,"localization_key":"item."+str(row.model),"render_key":row.model,"width":row.width,"height":row.height})
		if def.is_empty(): return {}
		next.defs[row.model] = def
	var reserved := {}
	var new_counts := {}
	for row: Dictionary in selected(int(profile.visit_random.seed),version):
		var allocated := false
		for buy_day: int in range(1,7):
			if allocated: break
			if int(new_counts.get(buy_day,0))>=2: continue
			for seller: String in ACTORS:
				if allocated: break
				if not _free_actor(profile,buy_day,seller): continue
				var fit := _fit(state,next.defs,seller,row)
				if not fit.get("ok",false): continue
				for sell_day: int in range(7,buy_day,-1):
					if allocated: break
					if int(new_counts.get(sell_day,0))>=2: continue
					for buyer: String in ACTORS:
						if buyer==seller or not _free_actor(profile,sell_day,buyer): continue
						if int(state.wallets[buyer].VKC)-int(reserved.get(buyer,0))<int(row.sale): continue
						state.items[row.id] = Objects.fresh_item(row.model,seller,seller+"_grid",fit.x,fit.y,"civilian_supply_"+str(row.id))
						_add_visit(state,profile,row,buy_day,seller,true)
						_add_visit(state,profile,row,sell_day,buyer,false)
						reserved[buyer] = int(reserved.get(buyer,0))+int(row.sale)
						new_counts[buy_day] = int(new_counts.get(buy_day,0))+1
						new_counts[sell_day] = int(new_counts.get(sell_day,0))+1
						allocated = true
						break
		if not allocated: return {}
	profile["civilian_supply"] = version
	return next if seed_valid(state,profile) else {}

static func seed_valid(state: Dictionary,profile: Dictionary) -> bool:
	if profile.get("civilian_supply") not in [1,2] or profile.get("f3_composite_trial")!=1 or not profile.get("visit_random") is Dictionary: return false
	var version := int(profile.civilian_supply)
	var active := selected(int(profile.visit_random.seed),version)
	if active.size()!=4: return false
	var active_ids: Array = []
	var reserved := {}
	var daily := {}
	for row: Dictionary in active:
		active_ids.append(row.id)
		var item: Dictionary = state.items.get(row.id,{})
		var buy_id := "civilian_"+str(row.id)+"_buy"
		var sell_id := "civilian_"+str(row.id)+"_sale"
		var purchase: Dictionary = state.visits.get(buy_id,{})
		var sale: Dictionary = state.visits.get(sell_id,{})
		if purchase.is_empty() or sale.is_empty() or item.is_empty(): return false
		if item.def_id!=row.model or item.provenance_id!="civilian_supply_"+str(row.id) or item.owner_id not in ACTORS or item.custodian_id!=item.owner_id or item.inventory!=str(item.owner_id)+"_grid" or item.status!="stock" or item.version!=0: return false
		if purchase.seller!=item.owner_id or purchase.buyer!="player" or sale.seller!="player" or sale.buyer not in ACTORS or sale.buyer==item.owner_id: return false
		if purchase.prices!={row.id:money(int(row.purchase))} or sale.prices!={row.id:money(int(row.sale))} or int(purchase.opens)>=int(sale.opens): return false
		reserved[sale.buyer] = int(reserved.get(sale.buyer,0))+int(row.sale)
		if int(state.wallets.get(sale.buyer,{}).get("VKC",0))<int(reserved[sale.buyer]): return false
		for id: String in [buy_id,sell_id]:
			var visit: Dictionary = state.visits[id]
			var day := floori(float(visit.opens)/1440.0)
			var actor: String = str(visit.seller if id==buy_id else visit.buyer)
			if day<0 or day>=profile.days.size() or int(visit.opens)!=day*1440 or int(visit.expires)!=day*1440+600: return false
			if visit.scope.visit_id!=id or visit.scope.kind!="ordinary" or visit.scope.completed or visit.scope.purpose!=("purchase" if id==buy_id else "sale") or not visit.allow_inspection: return false
			if not profile.days[day].any(func(slot:Dictionary)->bool:return slot.id==id and slot.actor_id==actor and slot.kind=="regular"): return false
			daily[day] = int(daily.get(day,0))+1
			if daily[day]>2: return false
	for row: Dictionary in config(version):
		if row.id not in active_ids and (state.items.has(row.id) or state.visits.has("civilian_"+str(row.id)+"_buy") or state.visits.has("civilian_"+str(row.id)+"_sale")): return false
	return true
