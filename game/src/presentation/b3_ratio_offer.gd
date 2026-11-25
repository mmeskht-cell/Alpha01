extends RefCounted
## Presentation-only quote arithmetic. No session, catalog truth, NPC prices,
## exchange rates or wallet access. Only caller-provided visible references.
## Ratio unit = 0.1 percentage point; 1000 represents 100%.
const MAX_AMOUNT: int = 999999999
const MAX_RATIO: int = 100000 # candidate input safety ceiling, not economic policy

static func basis(known: Dictionary, currency: String, public_reference: Dictionary = {}) -> Dictionary:
	if currency not in ["VKC","USD"]: return {}
	var band: Dictionary = known.get("estimate",{}).get(currency,{})
	var low: int = int(band.get("low",0))
	var high: int = int(band.get("high",0))
	if low>0 and high>=low and high<=MAX_AMOUNT:
		return {"amount":low+roundi(float(high-low)/2.0),"currency":currency,"source":"appraisal_range","low":low,"high":high}
	# A separately labelled player-selected public reference, never a hidden
	# visit quote or silently substituted estimate.
	if public_reference.get("currency")!=currency or str(public_reference.get("source","")).is_empty(): return {}
	var value: int = int(public_reference.get("amount",0))
	if value<1 or value>MAX_AMOUNT: return {}
	if public_reference.get("kind") not in ["catalog_reference","posted_ask","public_quote","personal_provisional"]: return {}
	return {"amount":value,"currency":currency,"source":public_reference.kind,"reference_source":public_reference.source}

## Optional public catalogue appearance rule: player judgment only, no truth.
static func catalog_basis(catalog: Dictionary, model: Dictionary, judgment: String, currency: String) -> Dictionary:
	if catalog.get("currency")!=currency: return {}
	var base: int = int(model.get("value",0))
	if base<1 or base>MAX_AMOUNT: return {}
	var matched := false
	var factor: int = 100
	var appearance: String = {"minimal":"light_wear","moderate":"visible_wear","severe":"heavy_wear"}.get(judgment,"")
	for slot: Dictionary in catalog.get("slots",[]):
		if slot.get("effect")=="base":
			for row: Dictionary in slot.get("candidates",[]):
				if row.get("id")==model.get("id") and row.get("value")==model.get("value"): matched=true
		elif slot.get("id")=="appearance_id" and slot.get("effect")=="percent" and not appearance.is_empty():
			for row: Dictionary in slot.get("candidates",[]):
				if row.get("id")==appearance and int(row.get("value",0))>0 and int(row.value)<=100:
					factor=int(row.value)
	if not matched: return {}
	var result := basis({},currency,{"kind":"catalog_reference","source":catalog.get("source_key",""),"amount":maxi(1,roundi(float(base)*factor/100.0)),"currency":currency})
	if not result.is_empty():
		result["model"]=str(model.get("id",""))
		result["catalog_amount"]=base
		result["appearance_percent"]=factor
		result["judgment"]=judgment if not appearance.is_empty() else "unknown"
	return result

static func amount(base: Dictionary, ratio: int) -> int:
	var value: int = int(base.get("amount",0))
	if base.get("currency") not in ["VKC","USD"] or value<1 or value>MAX_AMOUNT or ratio<1 or ratio>MAX_RATIO: return 0
	var result: int = maxi(1,roundi(float(value)*float(ratio)/1000.0))
	return result if result<=MAX_AMOUNT else 0

static func shift(base: Dictionary, ratio: int, delta: int) -> int:
	# Skip repeated rounded amounts on low-denomination goods, without
	# changing the effective meaning of a displayed ratio.
	if delta==0 or amount(base,ratio)==0: return ratio
	var direction: int = 1 if delta>0 else -1
	var next: int = clampi(ratio+delta,1,MAX_RATIO)
	var old: int = amount(base,ratio)
	while next>1 and next<MAX_RATIO and amount(base,next)==old:
		next += direction
	return next if amount(base,next)>0 and amount(base,next)!=old else ratio
