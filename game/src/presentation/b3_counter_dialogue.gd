extends RefCounted
## Select speech from the public projection only; text is independent of game rules.
const PATH = "res://data/alpha_b3/dialogue_ko.json"
const Rules = preload("res://src/domain/value_rules.gd")
const REQUIRED = ["challenge_topic","challenge_plain","withdraw_topic","withdraw_plain","reaffirm_topic","reaffirm_plain","accept_buy","accept_sell","decline_remembered","decline_topic","decline_withdrawn","decline_buy","decline_sell","return_traded","return_commission","return_service","return_declined","return_accepted","opening_buy","opening_sell","bid_return","bid_open"]
const TOPIC_KEYS = ["challenge_topic","withdraw_topic","reaffirm_topic","decline_remembered","decline_topic"]
const AMOUNT_KEYS = ["bid_return","bid_open"]
static var _catalog: Dictionary = {}
static var _loaded: bool = false

static func validate(raw: Variant) -> bool:
	if not Rules.keys(raw,["version","subjects","voices","lines","actor_lines"]) or raw.version!=1:
		return false
	if not raw.subjects is Dictionary or not raw.voices is Dictionary or not raw.lines is Dictionary or not raw.actor_lines is Dictionary:
		return false
	for key: Variant in raw.subjects:
		var label: Variant = raw.subjects[key]
		if not Rules.identifier(key) or not label is String or label.is_empty() or label.length()>120 or "{" in label or "}" in label:
			return false
	for key: Variant in raw.voices:
		if not Rules.identifier(key) or not Rules.integer(raw.voices[key],0,63):
			return false
	for key: String in REQUIRED:
		if not raw.lines.has(key): return false
	for key: Variant in raw.lines:
		if not Rules.identifier(key) or not _valid_rows(str(key),raw.lines[key]): return false
	for actor: Variant in raw.actor_lines:
		if not Rules.identifier(actor) or not raw.actor_lines[actor] is Dictionary: return false
		for key: Variant in raw.actor_lines[actor]:
			if key not in REQUIRED or not _valid_rows(str(key),raw.actor_lines[actor][key]): return false
	return true

static func _valid_rows(key: String, rows: Variant) -> bool:
	if not rows is Array or rows.is_empty() or rows.size()>64: return false
	var token: String = "{topic}" if key in TOPIC_KEYS else ("{amount}" if key in AMOUNT_KEYS else "")
	for row: Variant in rows:
		if not row is String or row.strip_edges().is_empty() or row.length()>512: return false
		var rest: String = row
		if not token.is_empty():
			if row.count(token)!=1: return false
			rest = row.replace(token,"")
		if "{" in rest or "}" in rest: return false
	return true

static func _data() -> Dictionary:
	if not _loaded:
		_loaded = true
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if validate(raw):
			_catalog = raw
		else:
			push_error("Invalid B3 dialogue catalog: "+PATH)
	return _catalog

static func subject(slot: String) -> String:
	return str(_data().get("subjects",{}).get(slot,""))

## Stable variants; no economic or NPC state change. Existing three-way selection is preserved.
static func voice(actor_id: String, count: int = 3) -> int:
	if count<=1 or actor_id.is_empty(): return 0
	var overrides: Dictionary = _data().get("voices",{})
	if overrides.has(actor_id): return int(overrides[actor_id])%count
	return actor_id.sha256_text().left(6).hex_to_int()%count

static func _rows(key: String, actor_id: String) -> Array:
	var catalog := _data()
	return catalog.get("actor_lines",{}).get(actor_id,{}).get(key,catalog.get("lines",{}).get(key,[]))

static func _say(key: String, actor_id: String, topic: String = "") -> String:
	var rows: Array = _rows(key,actor_id)
	if rows.is_empty(): return ""
	return str(rows[voice(actor_id,rows.size())]).replace("{topic}",topic)

static func bid(key: String, amount: int, actor_id: String = "") -> String:
	if key not in AMOUNT_KEYS: return ""
	var rows: Array = _rows(key,actor_id)
	if rows.is_empty(): return ""
	return str(rows[voice(actor_id,rows.size())]).replace("{amount}",str(amount))

static func line(context: Dictionary, we_buy: bool, actor_id: String = "") -> String:
	var latest: Dictionary = context.get("latest_spoken",{})
	var offer: Dictionary = context.get("current_offer",{})
	var topic := subject(str(latest.get("slot","")))
	match str(latest.get("kind","")):
		"challenge":
			return _say("challenge_topic",actor_id,topic) if not topic.is_empty() else _say("challenge_plain",actor_id)
		"withdraw":
			return _say("withdraw_topic",actor_id,topic) if not topic.is_empty() else _say("withdraw_plain",actor_id)
		"reaffirm":
			return _say("reaffirm_topic",actor_id,topic) if not topic.is_empty() else _say("reaffirm_plain",actor_id)
	if not offer.is_empty():
		if offer.get("response")=="accepted":
			return _say("accept_buy",actor_id) if we_buy else _say("accept_sell",actor_id)
		if offer.get("response")!="declined": return ""
		var evidence: Array = offer.get("public_slots",[])
		var remembered := false
		if evidence.is_empty():
			evidence = offer.get("active_slots",[])
			remembered = not evidence.is_empty()
		for slot: Variant in evidence:
			topic = subject(str(slot))
			if topic.is_empty(): continue
			if remembered: return _say("decline_remembered",actor_id,topic)
			return _say("decline_topic",actor_id,topic)
		if not offer.get("withdrawn_slots",[]).is_empty():
			return _say("decline_withdrawn",actor_id)
		return _say("decline_buy",actor_id) if we_buy else _say("decline_sell",actor_id)
	var prior: Dictionary = context.get("prior",{})
	match str(prior.get("outcome","")):
		"traded": return _say("return_traded",actor_id)
		"commission_delivered": return _say("return_commission",actor_id)
		"service_delivered": return _say("return_service",actor_id)
	var old: Dictionary = prior.get("offer",{})
	if old.get("response")=="declined": return _say("return_declined",actor_id)
	if old.get("response")=="accepted": return _say("return_accepted",actor_id)
	return _say("opening_buy",actor_id) if we_buy else _say("opening_sell",actor_id)
