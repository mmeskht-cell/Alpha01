extends SceneTree
## Standalone, synthetic read-model regression. Not a live economy fixture.
const Estimate = preload("res://src/domain/known_estimate.gd")
var failures: int = 0
var checks: int = 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error(label)

func sale(event_id: String, day: int, vkc: int, usd: int, offer: Dictionary) -> Dictionary:
	return {"event_id":event_id,"minute":(day-1)*1440,"direction":"sale","amounts":{"VKC":vkc,"USD":usd},"offer_reference":offer.duplicate(true)}

func _initialize() -> void:
	var offer: Dictionary = {"assessment":{"material":"metal","exterior":"moderate"},"observed_slots":["function_detail"],"facts":[{"slot":"function_detail","value":"serviceable"}]}
	var appraisal: Dictionary = {"item_id":"TEST1","def_id":"test_radio","surface_judgments":offer.assessment.duplicate(true),"cards":offer.facts.duplicate(true)}
	var history: Dictionary = {"item_id":"TEST1","records":[sale("A",1,100,0,offer),sale("B",2,120,0,offer),sale("C",2,0,2,offer),sale("D",3,900,0,offer),sale("B",2,120,0,offer),sale("E",2,10,1,offer)],"omitted":0}
	var original_history: Dictionary = history.duplicate(true)
	var original_appraisal: Dictionary = appraisal.duplicate(true)
	var result: Dictionary = Estimate.evaluate(history,appraisal,"test_radio",2)
	check("only dated individual single-currency sales",result.reference.get("VKC",{}).get("count")==2 and result.reference.get("USD",{}).get("count")==1)
	check("historical sample band",result.estimate.get("VKC",{}).get("low")==100 and result.estimate.get("VKC",{}).get("high")==120)
	check("one sample is not an estimate",not result.estimate.has("USD"))
	check("no synthetic market forecast",result.market.is_empty())
	check("read model leaves inputs unchanged",history==original_history and appraisal==original_appraisal)
	check("unselected model has no estimate",Estimate.evaluate(history,appraisal,"",2).estimate.is_empty())
	check("unrelated item rejected",Estimate.evaluate(history,{"item_id":"OTHER"},"test_radio",2).reference.is_empty())
	var different: Dictionary = appraisal.duplicate(true)
	different.surface_judgments.exterior = "severe"
	check("different private judgment rejects comparable",Estimate.evaluate(history,different,"test_radio",2).estimate.is_empty())
	different = appraisal.duplicate(true)
	different.cards.append({"slot":"wear_detail","value":"38"})
	check("masked surface value cannot produce estimate",Estimate.evaluate(history,different,"test_radio",2).estimate.is_empty())
	check("no future transactions",Estimate.evaluate(history,appraisal,"test_radio",1).reference.get("VKC",{}).get("count")==1)
	print("B3 KnownEstimate: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)
