extends RefCounted
const Retention=preload("res://src/domain/appraisal_history_retention.gd")
## Authored customer knowledge only, never specimen truth or player private assessment.
## Versioned opt-in for the isolated watch campaign. Keep old replay semantics.
const Rules = preload("res://src/domain/value_rules.gd")
const Documents = preload("res://src/content/packaged_documents.gd")
const DEMO_POLICY_PATH:String="res://data/campaign/gate2/demo_customer_policy_v1.json"
const VERSION: String = "p2-watch-claims-1"
const BEATS: Dictionary = {
	"watch_a":{
		"appearance_id":{"id":"a_wear_claim","candidate_id":"light_wear","label_key":"catalog.radio.wear.light","basis":"seller_recollection"},
		"model_id":{"id":"a_model_claim","candidate_id":"meridian_12a","label_key":"p2.watch.meridian12a","basis":"seller_recollection"}
	},
	"watch_b":{
		"appearance_id":{"id":"b_wear_claim","candidate_id":"visible_wear","label_key":"catalog.radio.wear.visible","basis":"seller_recollection"},
		"model_id":{"id":"b_model_claim","candidate_id":"meridian_12","label_key":"p2.watch.meridian12","basis":"seller_recollection"}
	}
}

# Radio sellers have their own public recollections, not omniscient answers.
const DEMO_BEATS:Dictionary={
	"visit_g01":{"appearance_id":{"id":"g01_wear","candidate_id":"light_wear","label_key":"catalog.radio.wear.light","basis":"seller_recollection"},"model_id":{"id":"g01_model","candidate_id":"selvar_r18","label_key":"catalog.radio.r18.name","basis":"seller_recollection"}},
	"radio3_buy":{"appearance_id":{"id":"g10_wear","candidate_id":"visible_wear","label_key":"catalog.radio.wear.visible","basis":"seller_recollection"}},
	"radio_return":{"appearance_id":{"id":"g02_return_wear","candidate_id":"visible_wear","label_key":"catalog.radio.wear.visible","basis":"seller_recollection"}}
}
# Provisional visit-specific settlement bands; the normal route remains unchanged.
# No floor is projected to the UI. Only supported, relevant public arguments qualify.
const DEMO_TERMS:Dictionary={
	"visit_g01":{"ask":125,"floor":110,"discount":10},
	"watch_a":{"ask":95,"floor":80,"discount":5},
	"radio3_buy":{"ask":50,"floor":40,"discount":5},
	"radio_return":{"ask":110,"floor":95,"discount":5}
}

static func demo3(state:Dictionary)->bool:
	return state.get("calendar",{}).get("profile",{}).get("content_version")=="demo7-integrated-3"

static func binding(version:String="") -> String:
	if version=="demo7-integrated-3":
		return Rules.canonical({"version":version,"beats":BEATS,"radio_beats":DEMO_BEATS,"terms":DEMO_TERMS,"wear_policy":"public-index-v1"}).sha256_text()
	return Rules.canonical({"version":VERSION,"beats":BEATS}).sha256_text()

# Demo3's immutable packaged policy must reproduce the exact old binding.
# Constants above remain the historical compatibility anchor, never a newly
# configurable fallback for malformed data. A new policy requires a new version.
static func validated_demo_policy(raw:Dictionary)->Dictionary:
	if not Rules.keys(raw,["version","beats","radio_beats","terms","wear_policy"]) or raw.get("version")!="demo7-integrated-3":
		return {}
	if Rules.canonical(raw).sha256_text()!=binding("demo7-integrated-3"):
		return {}
	return raw.duplicate(true)

static func demo_policy()->Dictionary:
	return validated_demo_policy(Documents.read_object(DEMO_POLICY_PATH))

static func settlement(visit_id:String)->Dictionary:
	return demo_policy().get("terms",{}).get(visit_id,{})

# Evaluate the customer's ability to accept a claim using ONLY observations
# disclosed in the argument. No comparison with hidden specimen truth.
static func supported_wear(state:Dictionary,visit:String,item:String,references:Array)->bool:
	var latest:Dictionary={}
	var ids:Array=[]
	for speech:Dictionary in references:
		ids.append(speech.presentation_id)
	for speech:Dictionary in state.calendar.get("appraisal_decks",{}).get(visit,{}).get("deck",{}).get("presented",[]):
		if speech.argument.slot_id=="appearance_id" and speech.presentation_id in ids:
			latest=speech
	if latest.is_empty():
		return false
	for id:String in latest.argument.evidence_ids:
		var entry:Dictionary=Retention.records(state).get(id,{})
		var record:Dictionary=entry.get("record",{})
		if entry.get("visit_id")!=visit or record.get("item_id")!=item or record.get("observation_key") not in ["R001.wear","dial_wear"] or not Rules.integer(record.get("observed_value"),0,100):
			continue
		var reading:int=int(record.observed_value)
		var candidate:String="light_wear" if reading<25 else ("visible_wear" if reading<60 else "heavy_wear")
		if candidate==latest.argument.candidate_id and candidate!="light_wear":
			return true
	return false

static func enabled(state: Dictionary) -> bool:
	var calendar: Dictionary = state.get("calendar",{})
	var version:String=calendar.get("profile",{}).get("content_version","")
	return version in [VERSION,"demo7-integrated-1","demo7-integrated-2","demo7-integrated-3"] and calendar.get("appraisal_profile",{}).get("customer_claims_sha") == binding(version) and (version!="demo7-integrated-3" or not demo_policy().is_empty())

## Public argument only. A seller can disagree without being correct.
## Each authored beat is disclosed once in a visit, attached to its causal presentation.
static func respond(state: Dictionary,visit_id: String,item_id: String,argument: Dictionary,presentation_id: String,presented: Array) -> Dictionary:
	if not enabled(state):
		return {}
	var beats:Dictionary=BEATS
	if demo3(state):
		var policy:Dictionary=demo_policy()
		beats=policy.get("radio_beats",{}) if policy.get("radio_beats",{}).has(visit_id) else policy.get("beats",{})
	var beat: Dictionary = beats.get(visit_id,{}).get(argument.slot_id,{})
	if beat.is_empty():
		return {}
	for entry: Dictionary in presented:
		if entry.get("customer_response",{}).get("beat_id") == beat.id:
			return {}
	return {
		"beat_id":beat.id,"presentation_id":presentation_id,"visit_id":visit_id,"item_id":item_id,
		"slot_id":argument.slot_id,"candidate_id":beat.candidate_id,"label_key":beat.label_key,
		"statement_kind":"customer_claim","basis":beat.basis,"source":"customer",
		"relation":"agrees" if beat.candidate_id == argument.candidate_id else "disagrees",
		"verified":false,"is_claim":true
	}

## Explicit rebuttal is a hypothesis, not an adjudication. The new linked
## observation must not already have been used for this claim's initial speech
## or an earlier rebuttal. Caller validates current evidence and card scope.
static func rebuttal(visit_id: String,item_id: String,argument: Dictionary,claim_id: String,presented: Array) -> Dictionary:
	var target: Dictionary = {}
	var original: Dictionary = {}
	var used: Array = []
	for speech: Dictionary in presented:
		var response: Dictionary = speech.get("customer_response",{})
		if response.get("beat_id") == claim_id and response.get("visit_id") == visit_id and response.get("item_id") == item_id:
			target = response
			original = speech
			for id: String in speech.argument.evidence_ids:
				if id not in used:
					used.append(id)
		var previous: Dictionary = speech.get("rebuttal",{})
		if previous.get("claim_id") == claim_id:
			for id: String in speech.argument.evidence_ids:
				if id not in used:
					used.append(id)
	if target.is_empty() or target.slot_id != argument.slot_id or target.candidate_id == argument.candidate_id:
		return {}
	var added: Array = []
	for id: String in argument.evidence_ids:
		if id not in used:
			added.append(id)
	if added.is_empty():
		return {}
	return {"claim_id":claim_id,"claim_presentation_id":original.presentation_id,"claim_label_key":target.label_key,"new_evidence_ids":added,"statement_kind":"rebuttal_hypothesis","verified":false}

static func rebuttal_options(visit_id: String,item_id: String,argument: Dictionary,presented: Array) -> Array:
	var result: Array = []
	for speech: Dictionary in presented:
		var response: Dictionary = speech.get("customer_response",{})
		if response.is_empty():
			continue
		var candidate: Dictionary = rebuttal(visit_id,item_id,argument,response.beat_id,presented)
		if not candidate.is_empty():
			result.append(candidate)
	return result
