extends RefCounted
## B3-M1 nonstory market interest. A buyer only appears when the *existing*
## physical item is actually on the player's shelf and the existing buyer
## wallet can pay. No stock, funds, buyer or provenance is generated.
const Rules = preload("res://src/domain/value_rules.gd")
const FILE: String = "res://data/alpha_b3/market_interest_m1.json"
const CONTENT_VERSION: String = "b3-finite-market-m1"
const CONTENT_VERSION_M2: String = "b3-finite-market-m2"
const CONTENT_VERSION_M3: String = "b3-finite-market-fx-m3"
const VERSIONS: Array = [CONTENT_VERSION, CONTENT_VERSION_M2, CONTENT_VERSION_M3]
const M2_FILE: String = "res://data/alpha_b3/market_interest_m2.json"
const M7_FILE: String = "res://data/alpha_b3/market_interest_m7.json"
const M7_MARKER: String = "b3_m7_finite_interest_1"

static func config(version: String = CONTENT_VERSION, extension: String = "") -> Dictionary:
	if version not in VERSIONS or (not extension.is_empty() and (extension != M7_MARKER or version != CONTENT_VERSION_M3)):
		return {}
	var path: String = M7_FILE if extension == M7_MARKER else (M2_FILE if version in [CONTENT_VERSION_M2,CONTENT_VERSION_M3] else FILE)
	var expected_version: int = 3 if extension == M7_MARKER else (2 if version in [CONTENT_VERSION_M2,CONTENT_VERSION_M3] else 1)
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not Rules.keys(raw,["version","offers"]) or raw.version!=expected_version or not raw.offers is Array:
		return {}
	if raw.offers.is_empty() or raw.offers.size()>16:
		return {}
	if version==CONTENT_VERSION and raw.offers.size()!=1:
		return {}
	return raw

static func _valid_offer(row: Variant, state: Dictionary, profile: Dictionary, materialized: bool) -> bool:
	if not Rules.keys(row,["visit_id","actor_id","day","item_id","quote_source_visit_id","purpose_key"]):
		return false
	for k: String in ["visit_id","actor_id","item_id","quote_source_visit_id","purpose_key"]:
		if not Rules.identifier(row[k]):
			return false
	if not Rules.integer(row.day,1,profile.days.size()) or row.actor_id=="player" or not state.wallets.has(row.actor_id):
		return false
	if not state.items.has(row.item_id) or not state.visits.has(row.quote_source_visit_id):
		return false
	var quoted: Dictionary=state.visits[row.quote_source_visit_id]
	if quoted.seller!="player" or quoted.buyer==row.actor_id or quoted.prices.size()!=1 or not quoted.prices.has(row.item_id):
		return false
	var price: Dictionary=quoted.prices[row.item_id]
	if int(price.get("VKC",0))+int(price.get("USD",0))<=0:
		return false
	# In a finite authored schedule an initially insolvent actor is not a
	# credible buyer. Runtime eligibility rechecks real remaining funds.
	if int(state.wallets[row.actor_id].get("VKC",0))<int(price.VKC) or int(state.wallets[row.actor_id].get("USD",0))<int(price.USD):
		return false
	if row.day>profile.days.size() or profile.days[int(row.day)-1].size()>=10:
		return false if not materialized else _visit_check(row,state,profile,price)
	for visit: Dictionary in profile.days[int(row.day)-1]:
		if visit.actor_id==row.actor_id or visit.id==row.visit_id:
			if not materialized or visit.id!=row.visit_id or visit.actor_id!=row.actor_id:
				return false
			return _visit_check(row,state,profile,price)
	return not materialized

static func _visit_check(row: Dictionary, state: Dictionary, profile: Dictionary, price: Dictionary) -> bool:
	if not state.visits.has(row.visit_id):
		return false
	var visit: Dictionary=state.visits[row.visit_id]
	if not Rules.keys(visit,["scope","seller","buyer","prices","opens","expires","allow_inspection"]):
		return false
	return visit.seller=="player" and visit.buyer==row.actor_id and visit.scope.kind=="ordinary" and visit.scope.purpose=="sale" and not visit.scope.completed and visit.prices.size()==1 and visit.prices.has(row.item_id) and Rules.canonical(visit.prices[row.item_id])==Rules.canonical(price) and int(visit.opens)==(int(row.day)-1)*1440 and int(visit.expires)==int(visit.opens)+600

## Build a *different* content-bound profile. It only adds a dated purchase
## opportunity quoting an already-written economic amount.
static func extend(source: Dictionary, version: String = CONTENT_VERSION) -> Dictionary:
	var c: Dictionary=config(version)
	if c.is_empty() or not source.has("alpha_profile") or not source.has("state"):
		return {}
	var next: Dictionary=source.duplicate(true)
	if next.alpha_profile.get("content_version")!="b2-cards-commission-service-multi-3":
		return {}
	for offer: Dictionary in c.offers:
		if not _valid_offer(offer,next.state,next.alpha_profile,false) or next.state.visits.has(offer.visit_id):
			return {}
		var price: Dictionary=next.state.visits[offer.quote_source_visit_id].prices[offer.item_id].duplicate(true)
		next.state.visits[offer.visit_id]={
			"scope":{"visit_id":offer.visit_id,"kind":"ordinary","purpose":"sale","completed":false,"required_ids":[]},
			"seller":"player","buyer":offer.actor_id,
			"prices":{offer.item_id:price},
			"opens":(int(offer.day)-1)*1440,"expires":(int(offer.day)-1)*1440+600,
			"allow_inspection":true
		}
		next.alpha_profile.days[int(offer.day)-1].append({
			"id":offer.visit_id,"actor_id":offer.actor_id,"kind":"regular",
			"purpose_key":offer.purpose_key,"contact_offer":false
		})
	next.alpha_profile.content_version=version
	next.alpha_profile["market_interest"]=c.duplicate(true)
	return next

## Separate opt-in M7: add only four proven new purchase opportunities.
## The original M2/M3 source schedule, items, wallets, and prices stay intact.
## This function never clones goods or funds; it binds each extra visit to an
## existing seller-side quote and an independently funded other buyer.
static func extend_m7(source: Dictionary) -> Dictionary:
	if not source.has("state") or not source.has("alpha_profile"):
		return {}
	var original: Dictionary = config(CONTENT_VERSION_M3)
	var expanded: Dictionary = config(CONTENT_VERSION_M3, M7_MARKER)
	var profile: Dictionary = source.alpha_profile
	if original.is_empty() or expanded.is_empty() or profile.get("content_version") != CONTENT_VERSION_M3 or profile.has("market_extension") or not profile.has("visit_random"):
		return {}
	if Rules.canonical(profile.get("market_interest", {})) != Rules.canonical(original) or expanded.offers.size() != original.offers.size() + 4:
		return {}
	for i: int in range(original.offers.size()):
		if Rules.canonical(expanded.offers[i]) != Rules.canonical(original.offers[i]):
			return {}
	var next: Dictionary = source.duplicate(true)
	for i: int in range(original.offers.size(), expanded.offers.size()):
		var offer: Dictionary = expanded.offers[i]
		if not _valid_offer(offer, next.state, next.alpha_profile, false) or next.state.visits.has(offer.visit_id):
			return {}
		var price: Dictionary = next.state.visits[offer.quote_source_visit_id].prices[offer.item_id].duplicate(true)
		next.state.visits[offer.visit_id] = {
			"scope": {"visit_id": offer.visit_id, "kind": "ordinary", "purpose": "sale", "completed": false, "required_ids": []},
			"seller": "player", "buyer": offer.actor_id,
			"prices": {offer.item_id: price},
			"opens": (int(offer.day) - 1) * 1440,
			"expires": (int(offer.day) - 1) * 1440 + 600,
			"allow_inspection": true
		}
		next.alpha_profile.days[int(offer.day) - 1].append({
			"id": offer.visit_id, "actor_id": offer.actor_id,
			"kind": "regular", "purpose_key": offer.purpose_key, "contact_offer": false
		})
	next.alpha_profile.market_interest = expanded.duplicate(true)
	next.alpha_profile["market_extension"] = M7_MARKER
	return next

static func profile_valid(profile: Dictionary, state: Dictionary) -> bool:
	if profile.get("content_version") not in VERSIONS or not profile.has("market_interest"):
		return false
	var c: Dictionary = config(str(profile.content_version), str(profile.get("market_extension", "")))
	if c.is_empty() or Rules.canonical(profile.market_interest)!=Rules.canonical(c):
		return false
	for offer: Dictionary in c.offers:
		# The physical source and price remain bound to the original economic
		# fixture. A forged new buyer, quote or extra item fails seed validation.
		if not _valid_offer(offer,state,profile,true):
			return false
	return true

static func interest_status(state: Dictionary, visit_id: String) -> String:
	var a: Dictionary=state.alpha_shop
	var policy: Dictionary=a.profile.get("market_interest",{})
	if policy.is_empty():
		return "ordinary"
	for offer: Dictionary in policy.get("offers",[]):
		if offer.visit_id!=visit_id:
			continue
		if not state.visits.has(visit_id) or not state.items.has(offer.item_id):
			return "missing_source"
		var visit: Dictionary=state.visits[visit_id]
		var item: Dictionary=state.items[offer.item_id]
		if visit.scope.completed or item.owner_id!="player" or item.custodian_id!="player" or item.inventory!="storefront_grid" or item.status!="stock" or item.protected or not item.parent_id.is_empty() or not item.reservation_id.is_empty() or offer.item_id not in a.get("displayed",[]):
			return "unavailable_stock"
		var wallet: Dictionary=state.wallets.get(offer.actor_id,{})
		var price: Dictionary=visit.prices[offer.item_id]
		if int(wallet.get("VKC",0)) < int(price.VKC) or int(wallet.get("USD",0)) < int(price.USD):
			return "insufficient_budget"
		return "eligible"
	return "ordinary"

static func eligible(state: Dictionary, visit_id: String) -> bool:
	return interest_status(state, visit_id) in ["ordinary", "eligible"]
