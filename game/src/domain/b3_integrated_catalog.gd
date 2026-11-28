extends RefCounted
## Source-bound catalog for the regular first week. Owns no live state.
const Data = preload("res://src/domain/value_rules.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Supply = preload("res://src/domain/b3_civilian_supply.gd")
const PATH := "res://data/alpha_b3/integrated_catalog_v1.json"
const VERSION := 1
const WEEKLY_SELECTION := {"food":3,"essentials":2,"hardware":2}
const GROUP_COUNTS := {"food":10,"essentials":9,"hardware":5}
# Role preferences use existing civilians and their real wallets. Other
# regulars remain eligible when a preferred customer has an appointment.
const INTEREST := {
	"market_food":["G03","G05","G09","G02"],
	"market_medical":["G05","G07","G04","G09"],
	"market_hygiene":["G04","G02","G03","G05"],
	"port_electronics":["G08","G11","G07","G12"],
	"workshop_tools":["G12","G02","G04","G09"],
	"workshop_goods":["G09","G12","G08","G11"]
}
const BUYER_RESERVE := 5
const DAILY_LIMIT := 10
static var _groups: Dictionary = {}
static var _models: Dictionary = {}

static func enabled(profile: Dictionary) -> bool:
	return profile.get("integrated_catalog")==VERSION

static func _load() -> bool:
	if not _groups.is_empty():
		return true
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not Data.keys(document,["version","groups"]) or document.version!=VERSION or not Data.keys(document.groups,GROUP_COUNTS.keys()):
		return false
	var models: Dictionary = {}
	var keys := ["id","model","category","market","width","height","purchase","sale","family","target","wear","functional","repair"]
	for group: String in GROUP_COUNTS:
		var rows: Variant = document.groups[group]
		if not rows is Array or rows.size()!=GROUP_COUNTS[group]:
			return false
		for row: Variant in rows:
			if not Data.keys(row,keys) or not Data.identifier(row.id) or not Data.identifier(row.model) or models.has(row.id):
				return false
			if not INTEREST.has(row.market) or not Data.identifier(row.target) or row.family not in ["","paper","metal","plastic","glass","fabric"]:
				return false
			if not Data.integer(row.purchase,1,100) or not Data.integer(row.sale,int(row.purchase)+1,125) or not Data.integer(row.wear,0,100):
				return false
			if not row.functional is bool or not Data.integer(row.repair,0,20) or (row.repair>0 and not row.functional):
				return false
			if definition(row).is_empty() or models.values().any(func(known: Dictionary)->bool: return known.model==row.model):
				return false
			models[row.id] = row
	_groups = document.groups
	_models = models
	return true

static func models() -> Dictionary:
	return _models.duplicate(true) if _load() else {}

static func definition(row: Dictionary) -> Dictionary:
	var result := Objects.definition({"def_id":row.model,"category":row.category,"localization_key":"item."+str(row.model),"render_key":row.model,"width":row.width,"height":row.height})
	if not result.is_empty() and int(row.repair)>0:
		result.restorable = true
		result.restore_cost = Supply.money(int(row.repair))
	return result

static func selected(seed_value: int) -> Array:
	var result: Array = []
	if not _load():
		return result
	for group: String in WEEKLY_SELECTION:
		var rows: Array = _groups[group]
		var start := posmod(seed_value,rows.size())
		for index: int in range(WEEKLY_SELECTION[group]):
			result.append(rows[(start+index)%rows.size()].duplicate())
	return result

static func origin(item_id: String) -> String:
	return "integrated_catalog_"+item_id

static func visit_id(item_id: String, purchase: bool) -> String:
	return "catalog_"+item_id+("_buy" if purchase else "_sale")

static func retry_id(item_id: String) -> String:
	return "catalog_"+item_id+"_retry_sale"

static func _retry_key(id: String) -> bool:
	return id.begins_with("catalog_") and id.ends_with("_retry_sale")

static func visit_item(profile: Dictionary,id: String) -> String:
	if not enabled(profile) or not id.begins_with("catalog_") or not _load():
		return ""
	if _retry_key(id):
		var retry_item := id.trim_prefix("catalog_").trim_suffix("_retry_sale")
		return retry_item if profile.get("visit_plan_policy")==3 and _models.has(retry_item) and id==retry_id(retry_item) else ""
	var item_id := id.trim_prefix("catalog_").trim_suffix("_buy" if id.ends_with("_buy") else "_sale")
	return item_id if _models.has(item_id) and id in [visit_id(item_id,true),visit_id(item_id,false)] else ""

## A second offer cannot revive an already completed primary sale,
## even if a later system permits the same article to be reacquired.
static func retry_open(state: Dictionary,id: String) -> bool:
	if not _retry_key(id): return true
	var profile: Dictionary = state.alpha_shop.profile
	var item_id := visit_item(profile,id)
	if item_id.is_empty() or not state.visits.has(id): return false
	var primary: Dictionary = state.visits.get(visit_id(item_id,false),{})
	return not primary.is_empty() and not primary.scope.completed and not state.visits[id].scope.completed

static func market_key(profile: Dictionary,item_id: String) -> String:
	if not enabled(profile) or not _load() or not _models.has(item_id):
		return ""
	return _models[item_id].market

static func price_basis(profile: Dictionary,id: String) -> int:
	var item_id := visit_item(profile,id)
	if item_id.is_empty():
		return 0
	return int(_models[item_id].purchase if id.ends_with("_buy") else _models[item_id].sale)

static func _roll(seed_value: int,item_id: String,salt: String) -> int:
	return ("%d/%s/%s"%[seed_value,item_id,salt]).sha256_text().left(8).hex_to_int()

static func starts_functional(seed_value: int,row: Dictionary) -> bool:
	return int(row.repair)==0 or _roll(seed_value,row.id,"function")%4!=0

static func specimen(profile: Dictionary,item_id: String,item: Dictionary) -> Dictionary:
	if market_key(profile,item_id).is_empty():
		return {}
	var row: Dictionary = _models[item_id]
	if item.get("def_id")!=row.model or item.get("provenance_id")!=origin(item_id):
		return {}
	return row

static func wear(profile: Dictionary,row: Dictionary) -> int:
	return clampi(int(row.wear)+_roll(int(profile.visit_random.seed),row.id,"wear")%15-7,0,100)

static func _funded(state: Dictionary,buyer: String,row: Dictionary,reserved: Dictionary) -> bool:
	# Same upper quote bound used by the regional market; no wallet top-ups.
	var upper := floori(float(row.sale)*1.25)
	return int(state.wallets.get(buyer,{}).get("VKC",0))>=upper+BUYER_RESERVE+int(reserved.get(buyer,0))

static func _free(profile: Dictionary,day: int,actor: String) -> bool:
	var slots: Array = profile.days[day-1]
	return slots.size()<DAILY_LIMIT and not slots.any(func(row: Dictionary)->bool: return row.actor_id==actor)

static func _days(profile: Dictionary,first: int,last: int) -> Array:
	var days := range(first,last+1)
	days.sort_custom(func(a: int,b: int)->bool:
		var left: int = profile.days[a-1].size()
		var right: int = profile.days[b-1].size()
		return left<right if left!=right else a<b)
	return days

static func _add_visit(state: Dictionary,profile: Dictionary,row: Dictionary,day: int,actor: String,purchase: bool,retry: bool=false) -> void:
	var id := retry_id(row.id) if retry else visit_id(row.id,purchase)
	state.visits[id] = {
		"scope":{"visit_id":id,"kind":"ordinary","purpose":"purchase" if purchase else "sale","completed":false,"required_ids":[]},
		"seller":actor if purchase else "player","buyer":"player" if purchase else actor,
		"prices":{row.id:Supply.money(int(row.purchase if purchase else row.sale))},
		"opens":(day-1)*1440,"expires":(day-1)*1440+600,"allow_inspection":true
	}
	profile.days[day-1].append({"id":id,"actor_id":actor,"kind":"regular","purpose_key":"alpha.purpose.trade","contact_offer":false})

static func _allocate(state: Dictionary,defs: Dictionary,profile: Dictionary,row: Dictionary,reserved: Dictionary) -> bool:
	var seed_value := int(profile.visit_random.seed)
	var offset := _roll(seed_value,row.id,"actors")
	var buyers: Array = INTEREST[row.market].duplicate()
	for actor: String in Supply.ACTORS:
		if actor not in buyers:
			buyers.append(actor)
	for buy_day: int in _days(profile,1,5):
		for seller_index: int in range(Supply.ACTORS.size()):
			var seller: String = Supply.ACTORS[(offset+seller_index)%Supply.ACTORS.size()]
			if not _free(profile,buy_day,seller):
				continue
			var fit := Supply._fit(state,defs,seller,row)
			if not fit.get("ok",false):
				continue
			for sell_day: int in _days(profile,maxi(3,buy_day+1),7):
				for index: int in range(buyers.size()):
					var buyer: String = buyers[(index+offset%4)%4] if index<4 else buyers[index]
					if buyer==seller or not _free(profile,sell_day,buyer) or not _funded(state,buyer,row,reserved):
						continue
					var item := Objects.fresh_item(row.model,seller,seller+"_grid",fit.x,fit.y,origin(row.id))
					item.functional = starts_functional(seed_value,row)
					state.items[row.id] = item
					_add_visit(state,profile,row,buy_day,seller,true)
					_add_visit(state,profile,row,sell_day,buyer,false)
					reserved[buyer] = int(reserved.get(buyer,0))+floori(float(row.sale)*1.25)
					return true
	return false

static func extend(source: Dictionary) -> Dictionary:
	if source.is_empty() or not _load():
		return {}
	var profile: Dictionary = source.alpha_profile
	if profile.get("f3_composite_trial")!=1 or profile.has("civilian_supply") or profile.has("integrated_catalog"):
		return {}
	for row: Dictionary in _models.values():
		if source.defs.has(row.model) or source.state.items.has(row.id):
			return {}
		source.defs[row.model] = definition(row)
	profile["integrated_catalog"] = VERSION
	var reserved: Dictionary = {}
	for row: Dictionary in selected(int(profile.visit_random.seed)):
		if not _allocate(source.state,source.defs,profile,row,reserved):
			return {}
	return source

## v3 trial: a later opportunity for the same buyer and physical article.
## Never reserve a second purchase price for the same item: there is only
## one transferable article. Actual door eligibility still checks stock,
## display, ownership, prior settlements and current buyer cash.
static func _retry_schedule(state: Dictionary,profile: Dictionary) -> Dictionary:
	var scratch := {"days":[]}
	for day: Variant in profile.days:
		if not day is Array: return {}
		var original: Array = []
		for slot: Variant in day:
			if not slot is Dictionary or not slot.get("id") is String or not slot.get("actor_id") is String:
				return {}
			if not _retry_key(slot.id): original.append(slot.duplicate(true))
		scratch.days.append(original)
	var extra := {"visits":{}}
	var occupied_days: Dictionary = {}
	var candidates: Array = selected(int(profile.visit_random.seed))
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		var left: int = int(state.visits[visit_id(a.id,false)].opens)
		var right: int = int(state.visits[visit_id(b.id,false)].opens)
		return left<right if left!=right else str(a.id)<str(b.id))
	for row: Dictionary in candidates:
		var primary: Dictionary = state.visits[visit_id(row.id,false)]
		var first := int(primary.opens/1440)+2
		# At most one extra candidate per day, and never replace a row.
		for day: int in range(first,8):
			if occupied_days.has(day) or not _free(scratch,day,str(primary.buyer)): continue
			_add_visit(extra,scratch,row,day,str(primary.buyer),false,true)
			occupied_days[day]=true
			break
	return {"days":scratch.days,"visits":extra.visits}

static func add_retry_opportunities(source: Dictionary) -> Dictionary:
	if source.is_empty() or not seed_valid(source.state,source.alpha_profile) or source.alpha_profile.has("visit_plan_policy"):
		return {}
	var next := source.duplicate(true)
	var schedule := _retry_schedule(next.state,next.alpha_profile)
	if schedule.is_empty(): return {}
	for id: String in schedule.visits:
		if next.state.visits.has(id): return {}
		next.state.visits[id]=schedule.visits[id]
	next.alpha_profile.days=schedule.days
	next.alpha_profile["visit_plan_policy"]=3
	return next if seed_valid(next.state,next.alpha_profile) else {}

static func seed_valid(state: Dictionary,profile: Dictionary) -> bool:
	if not enabled(profile) or profile.has("civilian_supply") or profile.get("f3_composite_trial")!=1 or not profile.get("visit_random") is Dictionary or not profile.get("days") is Array or profile.days.size()!=7 or not _load():
		return false
	if not Data.integer(profile.visit_random.get("seed"),1,Data.LIMIT):
		return false
	var active: Dictionary = {}
	var reserved: Dictionary = {}
	var seed_value := int(profile.visit_random.seed)
	for row: Dictionary in selected(seed_value):
		var id: String = row.id
		active[id] = true
		var item: Dictionary = state.items.get(id,{})
		var buy: Dictionary = state.visits.get(visit_id(id,true),{})
		var sale: Dictionary = state.visits.get(visit_id(id,false),{})
		if item.is_empty() or buy.is_empty() or sale.is_empty():
			return false
		var seller: String = str(item.owner_id)
		var buyer: String = str(sale.buyer)
		if item.def_id!=row.model or item.provenance_id!=origin(id) or item.functional!=starts_functional(seed_value,row) or seller not in Supply.ACTORS or item.custodian_id!=seller or item.inventory!=seller+"_grid" or item.status!="stock" or item.version!=0 or item.parent_id!="":
			return false
		if buyer not in Supply.ACTORS or seller==buyer or not _funded(state,buyer,row,reserved):
			return false
		if buy.seller!=seller or buy.buyer!="player" or sale.seller!="player" or int(buy.opens)>=int(sale.opens):
			return false
		reserved[buyer] = int(reserved.get(buyer,0))+floori(float(row.sale)*1.25)
		for purchase: bool in [true,false]:
			var visit := buy if purchase else sale
			var key := visit_id(id,purchase)
			var day := floori(float(visit.opens)/1440.0)
			var actor := seller if purchase else buyer
			if day<0 or day>=7 or int(visit.opens)!=day*1440 or int(visit.expires)!=day*1440+600:
				return false
			if visit.prices!={id:Supply.money(price_basis(profile,key))} or visit.scope.visit_id!=key or visit.scope.kind!="ordinary" or visit.scope.completed or visit.scope.purpose!=("purchase" if purchase else "sale") or not visit.allow_inspection:
				return false
			if not profile.days[day] is Array or not profile.days[day].any(func(slot: Variant)->bool: return slot is Dictionary and slot.get("id")==key and slot.get("actor_id")==actor and slot.get("kind")=="regular"):
				return false
	for id: String in _models:
		if not active.has(id) and (state.items.has(id) or state.visits.has(visit_id(id,true)) or state.visits.has(visit_id(id,false))):
			return false
	var expected: Dictionary = {}
	if profile.get("visit_plan_policy")==3:
		var schedule := _retry_schedule(state,profile)
		if schedule.is_empty() or schedule.days!=profile.days: return false
		expected=schedule.visits
		for id: String in expected:
			if state.visits.get(id,{})!=expected[id]: return false
	for id: String in state.visits:
		if _retry_key(id) and not expected.has(id): return false
	for day: Variant in profile.days:
		if not day is Array: return false
		for slot: Variant in day:
			if slot is Dictionary and slot.get("id") is String and _retry_key(slot.id) and not expected.has(slot.id): return false
	return true
