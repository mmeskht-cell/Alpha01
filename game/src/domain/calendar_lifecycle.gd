extends RefCounted
## Single calendar replay authority. No second runtime or public dormant DTO.
const Rules=preload("res://src/domain/value_rules.gd")
const Directory=preload("res://src/domain/campaign_identity_directory.gd")
const Objects=preload("res://src/domain/object_schema.gd")
const Clock=preload("res://src/domain/business_clock.gd")
const Receipt=preload("res://src/domain/receipt_primitives.gd")
const Selection=preload("res://src/domain/calendar_tracking.gd")
const ACTIONS:Array=["world_sleep_family","world_wake_family","world_open_visit","world_track_promote","world_track_reference","world_track_suspend"]
const MAX_RETURN_RULES:int=10
const VERSION:String="calendar-lifecycle-1"

static func enabled(s:Dictionary)->bool:
	var c:Variant=s.get("calendar")
	return c is Dictionary and c.get("profile") is Dictionary and c.profile.get("lifecycle_version")==VERSION and c.get("dormant") is Dictionary

static func partition(s:Dictionary)->Dictionary:
	return {"state":s,"dormant":s.calendar.dormant,"tracking":{}}

static func read_history(s:Dictionary)->Dictionary:
	var history:Dictionary=s.duplicate()
	history.items=s.items.duplicate()
	for family:Dictionary in s.calendar.dormant.values():
		history.items.merge(family)
	return history

static func valid(s:Dictionary,defs:Dictionary)->bool:
	if not enabled(s):
		return false
	var result:Dictionary=Directory.audit(partition(s),defs)
	if not result.ok or not Selection.valid(s):
		return false
	# Services use their own visit table, not ordinary visit prices.
	var services:Variant=s.calendar.get("services",{})
	if not services is Dictionary or not services.get("jobs",{}) is Dictionary:
		return false
	for job:Variant in services.get("jobs",{}).values():
		if not job is Dictionary or not job.get("terms") is Dictionary:
			return false
		var id:Variant=job.terms.get("item_id")
		if not Rules.identifier(id) or not result.index.has(id):
			return false
		if job.get("status") in ["offered","accepted","complete"] and result.index[id]!="active":
			return false
	# Other calendar refs and exact historical values are enforced by seed replay.
	return true

static func apply(s:Dictionary,defs:Dictionary,command:Dictionary)->String:
	if not valid(s,defs):
		return "calendar_lifecycle_directory"
	var p:Dictionary=command.payload
	if command.type in Selection.ACTIONS:
		return Selection.apply(s,command)
	if command.type=="world_open_visit":
		return _open_return(s,defs,p)
	var next:Dictionary={}
	match command.type:
		"world_sleep_family":
			if not Rules.keys(p,["root_id"]) or not Rules.identifier(p.root_id):
				return "calendar_sleep_shape"
			next=Directory.sleep_candidate(partition(s),defs,p.root_id)
		"world_wake_family":
			if not Rules.keys(p,["root_id","inventory","x","y","rotated"]) or not Rules.identifier(p.root_id) or not Rules.identifier(p.inventory) or not Rules.integer(p.x,0,9) or not Rules.integer(p.y,0,9) or not p.rotated is bool:
				return "calendar_wake_shape"
			next=Directory.wake_candidate(partition(s),defs,p.root_id,p.inventory,int(p.x),int(p.y),p.rotated)
		_:
			return "calendar_world_permission"
	if next.is_empty():
		return "calendar_lifecycle_transition"
	var candidate:Dictionary=next.state
	candidate.calendar.dormant=next.dormant
	if not valid(candidate,defs):
		return "calendar_lifecycle_protection"
	# Nothing outside active placement and dormant family registry changes.
	s.items=candidate.items
	s.calendar.dormant=candidate.calendar.dormant
	return ""

## Authored candidates, not a generated price or a promise to the player.
## Each pilot rule is one future opportunity for a unique initial root.
static func rules_valid(s:Dictionary,profile:Dictionary)->bool:
	var rules:Variant=profile.get("reentry_rules",{})
	if not rules is Dictionary or rules.size()>MAX_RETURN_RULES:
		return false
	if not profile.has("reentry_rules"):
		return true
	if rules.is_empty() or profile.get("lifecycle_version")!=VERSION:
		return false
	var seen:Dictionary={}
	var services:Dictionary=s.calendar.get("services",{}).get("visits",{})
	for id:Variant in rules:
		var row:Variant=rules[id]
		var fields:Array=["item_id","prior_sale","seller","day","price","placement"]
		if profile.get("content_version") in ["demo7-integrated-2","demo7-integrated-3"] and row is Dictionary and row.has("resale"):
			fields.append_array(["resale","functional_after"])
		if not Rules.identifier(id) or s.visits.has(id) or services.has(id) or not Rules.keys(row,fields):
			return false
		if not Rules.identifier(row.item_id) or seen.has(row.item_id) or not s.items.has(row.item_id) or not s.items[row.item_id].parent_id.is_empty() or not Rules.identifier(row.prior_sale) or not s.visits.has(row.prior_sale) or not Rules.identifier(row.seller) or row.seller=="player" or not s.wallets.has(row.seller):
			return false
		var prior:Dictionary=s.visits[row.prior_sale]
		if prior.scope.purpose!="sale" or prior.seller!="player" or prior.buyer!=row.seller or not prior.prices.has(row.item_id) or not Rules.integer(row.day,2,profile.day_ids.size()) or (int(row.day)-1)*Clock.DAY_MINUTES<=int(prior.expires):
			return false
		if not Objects.money(row.price,false) or (row.price.VKC>0)==(row.price.USD>0):
			return false
		var p:Variant=row.placement
		if not Rules.keys(p,["inventory","x","y","rotated"]) or not Rules.identifier(p.inventory) or not s.inventories.has(p.inventory) or not Rules.integer(p.x,0,9) or not Rules.integer(p.y,0,9) or not p.rotated is bool:
			return false
		var grid:Dictionary=s.inventories[p.inventory]
		if grid.owner_id!=row.seller or not grid.host_item.is_empty() or p.x>=grid.width or p.y>=grid.height:
			return false
		if row.has("resale"):
			var resale:Variant=row.resale
			if not Rules.keys(resale,["id","buyer","price"]) or not Rules.identifier(resale.id) or s.visits.has(resale.id) or services.has(resale.id) or rules.has(resale.id) or not Rules.identifier(resale.buyer) or resale.buyer=="player" or resale.buyer==row.seller or not s.wallets.has(resale.buyer) or not Objects.money(resale.price,false) or (resale.price.VKC>0)==(resale.price.USD>0) or not row.functional_after is bool:
				return false
		seen[row.item_id]=true
	return true

static func _open_return(s:Dictionary,defs:Dictionary,p:Dictionary)->String:
	if not Rules.keys(p,["rule_id"]) or not Rules.identifier(p.rule_id):
		return "return_shape"
	var row:Dictionary=s.calendar.profile.get("reentry_rules",{}).get(p.rule_id,{})
	if row.is_empty() or s.visits.has(p.rule_id) or not s.calendar.get("queue",{}).get("active","").is_empty() or Clock.day_index(int(s.game_minutes))!=row.day or not Clock.business_at(int(s.game_minutes),s.phase,false):
		return "return_window"
	var family:Dictionary=s.calendar.dormant.get(row.item_id,{})
	if not family.has(row.item_id) or family[row.item_id].owner_id!=row.seller or family[row.item_id].custodian_id!=row.seller:
		return "return_owner"
	var sale:Dictionary={}
	for e:Dictionary in s.ledger:
		if e.visit_id==row.prior_sale and e.from==row.seller and e.to=="player" and row.item_id in e.root_ids:
			sale=e
			break
	if sale.is_empty() or Receipt.receipt_type(s,sale.event_id)!="trade" or Receipt.receipt_revision(s,sale.event_id)!=sale.revision or not s.visits[row.prior_sale].scope.completed:
		return "return_sale"
	# Wake first on the detached candidate; only then create the ordinary visit.
	# A pending visit must never reference dormant stock.
	var place:Dictionary=row.placement
	var next:Dictionary=Directory.wake_candidate(partition(s),defs,row.item_id,place.inventory,int(place.x),int(place.y),place.rotated)
	if next.is_empty():
		return "return_placement"
	var candidate:Dictionary=next.state
	candidate.calendar.dormant=next.dormant
	var start:int=(int(row.day)-1)*Clock.DAY_MINUTES
	var prices:Dictionary={}
	prices[row.item_id]=row.price.duplicate(true)
	candidate.visits[p.rule_id]={"scope":{"visit_id":p.rule_id,"kind":"ordinary","purpose":"purchase","completed":false,"required_ids":[]},"seller":row.seller,"buyer":"player","prices":prices,"opens":start,"expires":start+Clock.BUSINESS_MINUTES,"allow_inspection":true}
	if row.has("resale"):
		var resale:Dictionary=row.resale
		if candidate.visits.has(resale.id):
			return "return_resale_collision"
		var item:Dictionary=candidate.items[row.item_id]
		if item.functional!=row.functional_after:
			item.functional=row.functional_after
			item.version+=1
			item.field_versions.functional+=1
		var resale_prices:Dictionary={}
		resale_prices[row.item_id]=resale.price.duplicate(true)
		candidate.visits[resale.id]={"scope":{"visit_id":resale.id,"kind":"ordinary","purpose":"sale","completed":false,"required_ids":[]},"seller":"player","buyer":resale.buyer,"prices":resale_prices,"opens":start,"expires":start+Clock.BUSINESS_MINUTES,"allow_inspection":false}
	if not valid(candidate,defs):
		return "return_invariant"
	s.items=candidate.items
	s.calendar.dormant=candidate.calendar.dormant
	s.visits=candidate.visits
	return ""
