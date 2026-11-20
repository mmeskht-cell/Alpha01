extends RefCounted
## Opt-in additive authored candidate. Same campaign authorities; new binding
## and isolated save slot. Never modifies canonical demo7 seed or test fixtures.
const Base=preload("res://src/content/demo7_seed.gd")
const Session=preload("res://src/domain/game_session.gd")
const Objects=preload("res://src/domain/object_schema.gd")
const Catalog=preload("res://src/content/catalog_loader.gd")
const CATALOG="res://data/campaign/gate2/civilian_candidate_catalog.json"

static func _visit(id:String,item:String,seller:String,buyer:String,day:int,price:int)->Dictionary:
	return {"scope":{"visit_id":id,"kind":"ordinary","purpose":"purchase" if buyer=="player" else "sale","completed":false,"required_ids":[]},"seller":seller,"buyer":buyer,"prices":{item:Base.money(price)},"opens":(day-1)*1440,"expires":(day-1)*1440+600,"allow_inspection":true}

static func content(condition_pricing:bool=false,condition_version:int=1)->Dictionary:
	if condition_pricing and condition_version not in [1,2]:
		return {}
	var c:Dictionary=Base.content()
	var catalog:Dictionary=Catalog.load_file(CATALOG)
	if c.is_empty() or not catalog.ok:
		return {}
	for id:String in catalog.definitions:
		if c.defs.has(id):
			return {}
		c.defs[id]=catalog.definitions[id]
	var state:Dictionary=c.state
	var definition_id:String="civil_receiver"
	state.items["CR06"]=Objects.fresh_item(definition_id,"G06","G06_grid",6,4,"civil_receiver_06")
	state.items.CR06.functional=false
	for letter:String in ["a","b","c"]:
		var id:String="CR06_"+letter.to_upper()
		var part:Dictionary=Objects.fresh_item("civil_module_"+letter,"G06","",-1,-1,"civil_receiver_06_"+letter)
		part.parent_id="CR06"
		part.functional=letter!="c"
		state.items[id]=part
	state.items["CM06C"]=Objects.fresh_item("civil_module_c","G06","G06_grid",9,5,"civil_spare_06_c")
	state.visits["civil_receiver_buy"]=_visit("civil_receiver_buy","CR06","G06","player",6,70)
	state.visits["civil_spare_buy"]=_visit("civil_spare_buy","CM06C","G06","player",6,15)
	state.visits["civil_receiver_sale"]=_visit("civil_receiver_sale","CR06","player","G07",7,150)
	state.wallets.G07.VKC+=150
	c.profile.visit_days.d6.append_array(["civil_receiver_buy","civil_spare_buy"])
	c.profile.visit_days.d7.append("civil_receiver_sale")
	if condition_pricing:
		var id:String="civil_receiver_condition_v"+str(condition_version)
		state.visits.erase("civil_receiver_sale")
		state.visits[id]=_visit(id,"CR06","player","G07",7,160)
		state.wallets.G07.VKC+=10
		c.profile.visit_days.d7[-1]=id
	# Keep existing authored demo3 rule selector, including radio/claim bindings.
	# Calendar seed binding includes ALL new data and definitions, not only version.
	return c

static func fresh(condition_pricing:bool=false,condition_version:int=1)->RefCounted:
	var c:Dictionary=content(condition_pricing,condition_version)
	if c.is_empty():
		return null
	var s:=Session.new()
	if s.initialize(c.defs,c.state,false,false,c.profile):
		return s
	print("ZT_CIVILIAN_SEED_DIAGNOSTIC ",s.initialization_error()," ",Objects.validation_error(c.state,c.defs))
	return null
