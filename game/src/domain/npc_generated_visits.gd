extends RefCounted
## Data-driven scheduled ordinary NPC visits from a finite, already-owned
## inventory and funded actor pool. No civilian procedural spawning, no
## new wallets or items, and no future-customer reveal before admission.
const Rules=preload("res://src/domain/value_rules.gd")
const Objects=preload("res://src/domain/object_schema.gd")
const Clock=preload("res://src/domain/business_clock.gd")
const VERSION:int=1
const MAX_SLOTS:int=294

static func _choice(seed:int,slot:String,ids:int)->int:
	var digest:String=(str(seed)+":"+slot).sha256_text()
	return digest.substr(0,7).hex_to_int()%ids

static func expand(s:Dictionary,profile:Dictionary)->Dictionary:
	var policy:Variant=profile.get("npc_generated_visits",{})
	if profile.get("id")!="campaign_42" or not Rules.keys(policy,["version","seed","slots"]) or policy.version!=VERSION or not Rules.integer(policy.seed,0,1000000000) or not policy.slots is Dictionary or policy.slots.is_empty() or policy.slots.size()>MAX_SLOTS or not profile.has("npc_population") or not profile.has("regional_world"):
		return {}
	var seen_items:Dictionary={}
	var day_counts:Dictionary={}
	var output_s:Dictionary=s.duplicate(true)
	var output_p:Dictionary=profile.duplicate(true)
	var keys:Array=policy.slots.keys()
	keys.sort()
	for visit_id:String in keys:
		var slot:Variant=policy.slots[visit_id]
		if not Rules.identifier(visit_id) or s.visits.has(visit_id) or not Rules.keys(slot,["day_id","region","candidates"]) or not Rules.identifier(slot.day_id) or slot.day_id not in profile.day_ids or not Rules.identifier(slot.region) or not profile.regional_world.regions.has(slot.region) or not slot.candidates is Array or slot.candidates.size()<2 or slot.candidates.size()>4:
			return {}
		var day_index:int=profile.day_ids.find(slot.day_id)
		day_counts[slot.day_id]=int(day_counts.get(slot.day_id,0))+1
		if day_counts[slot.day_id]>7:
			return {}
		for choice:Variant in slot.candidates:
			if not Rules.keys(choice,["actor","item_id","price","side"]) or not Rules.identifier(choice.actor) or choice.actor=="player" or not Rules.identifier(choice.item_id) or choice.side not in ["offer","request"] or not Objects.money(choice.price,false) or (int(choice.price.VKC)==0 and int(choice.price.USD)==0) or (int(choice.price.VKC)>0 and int(choice.price.USD)>0) or seen_items.has(str(slot.day_id)+":"+str(choice.item_id)):
				return {}
			# Re-offers on later days are allowed, but a physical object may
			# appear only once per day; actual possession is checked at admission.
			seen_items[str(slot.day_id)+":"+str(choice.item_id)]=true
			if not s.wallets.has(choice.actor) or not s.items.has(choice.item_id):
				return {}
			var persona:Dictionary=profile.npc_population.actors.get(choice.actor,{})
			if persona.is_empty() or persona.get("kind") not in ["scavenger","mercenary"] or persona.get("region")!=slot.region:
				return {}
			var buyer:String="player" if choice.side=="offer" else choice.actor
			var seller:String=choice.actor if choice.side=="offer" else "player"
			var item:Dictionary=s.items[choice.item_id]
			if item.owner_id!=seller or item.custodian_id!=seller or item.status!="stock" or item.protected or not item.reservation_id.is_empty() or not item.parent_id.is_empty() or not s.inventories.has(item.inventory) or s.inventories[item.inventory].owner_id!=seller:
				return {}
			if buyer==choice.actor:
				for currency:String in ["VKC","USD"]:
					if int(s.wallets[choice.actor][currency])<int(choice.price[currency]):
						return {}
		var selected:Dictionary=slot.candidates[_choice(int(policy.seed),visit_id,slot.candidates.size())]
		var seller:String=selected.actor if selected.side=="offer" else "player"
		var buyer:String="player" if selected.side=="offer" else selected.actor
		var visit:Dictionary={"scope":{"visit_id":visit_id,"kind":"ordinary",
			"purpose":"purchase" if buyer=="player" else "sale",
			"completed":false,"required_ids":[]},"seller":seller,"buyer":buyer,
			"prices":{selected.item_id:selected.price.duplicate(true)},
			"opens":day_index*Clock.DAY_MINUTES,
			"expires":day_index*Clock.DAY_MINUTES+Clock.BUSINESS_MINUTES,
			"allow_inspection":true}
		output_s.visits[visit_id]=visit
		output_p.visit_days[slot.day_id].append(visit_id)
	# Only one visit per slot exists in the true seed; all other people/items
	# remain genuine but do not become phantom interactions.
	return {"state":output_s,"profile":output_p}
