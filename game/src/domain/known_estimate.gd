extends RefCounted
## Pure projection of player-visible, dated, individual completed sales.
## No session, hidden item truth, private NPC terms, or exchange conversion.
## Historical sample bounds are not a current market forecast.

static func evaluate(history: Dictionary, appraisal: Dictionary, selected_model: String, day: int) -> Dictionary:
	var result: Dictionary = {"reference": {}, "estimate": {}, "market": {}, "omitted": int(history.get("omitted",0))}
	if str(history.get("item_id","")).is_empty() or history.get("item_id")!=appraisal.get("item_id") or day<1:
		return result
	var facts: Dictionary = {}
	var unavailable_surface := false
	for card: Dictionary in appraisal.get("cards",[]):
		var slot: String = str(card.slot)
		var value: String = str(card.value)
		# The surface view currently masks numerical readings. Do not let a
		# price band reveal their hidden equality while real assets are absent.
		if slot in ["wear_detail","display_damage_detail"] and value.is_valid_int():
			unavailable_surface = true
			continue
		facts[slot] = value
	var judgments: Dictionary = appraisal.get("surface_judgments",{})
	var comparable: Dictionary = {}
	var seen: Dictionary = {}
	for row: Dictionary in history.get("records",[]):
		var event_id: String = str(row.get("event_id",""))
		if event_id.is_empty() or seen.has(event_id) or row.get("direction")!="sale":
			continue
		var minute: int = int(row.get("minute",-1))
		if minute<0 or int(minute/1440)+1>day or not row.get("amounts") is Dictionary:
			continue
		var amounts: Dictionary = row.amounts
		var currency: String = ""
		if int(amounts.get("VKC",0))>0 and int(amounts.get("USD",0))==0:
			currency = "VKC"
		elif int(amounts.get("USD",0))>0 and int(amounts.get("VKC",0))==0:
			currency = "USD"
		if currency.is_empty():
			continue
		seen[event_id] = true
		var source_day: int = int(minute/1440)+1
		_add_sample(result.reference,currency,int(amounts[currency]),source_day)
		if not unavailable_surface and _matches(row.get("offer_reference",{}),facts,judgments,selected_model,str(appraisal.get("def_id",""))):
			_add_sample(comparable,currency,int(amounts[currency]),source_day)
	for currency: String in comparable:
		var band: Dictionary = comparable[currency]
		# One trade (or only one date) is a reference, not an appraisal range.
		if band.count>=2 and band.first_day<band.last_day:
			result.estimate[currency] = band
	return result

static func _matches(offer: Dictionary, facts: Dictionary, judgments: Dictionary, selected_model: String, public_model: String) -> bool:
	if selected_model.is_empty() or selected_model!=public_model or facts.is_empty() or offer.is_empty():
		return false
	var previous: Dictionary = offer.get("assessment",{})
	for group: String in ["material","exterior"]:
		var guess: String = str(judgments.get(group,"unknown"))
		var allowed: Array = ["metal","plastic","paper","fabric","glass"] if group=="material" else ["minimal","moderate","severe"]
		if guess not in allowed or previous.get(group,"unknown")!=guess:
			return false
	var slots: Array = offer.get("observed_slots",[])
	var disclosed: Dictionary = {}
	for fact: Dictionary in offer.get("facts",[]):
		disclosed[str(fact.slot)] = str(fact.value)
	if slots.size()!=facts.size() or disclosed.size()!=facts.size():
		return false
	for slot: String in facts:
		if slot not in slots or not disclosed.has(slot) or disclosed[slot]!=facts[slot]:
			return false
	return true

static func _add_sample(bands: Dictionary, currency: String, amount: int, day: int) -> void:
	if not bands.has(currency):
		bands[currency] = {"low":amount,"high":amount,"count":1,"first_day":day,"last_day":day}
		return
	var band: Dictionary = bands[currency]
	band.low = mini(int(band.low),amount)
	band.high = maxi(int(band.high),amount)
	band.count = int(band.count)+1
	band.first_day = mini(int(band.first_day),day)
	band.last_day = maxi(int(band.last_day),day)
