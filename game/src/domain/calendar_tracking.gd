extends RefCounted
## Private tracking policy for calendar lifecycle only. No second event journal.
const Rules=preload("res://src/domain/value_rules.gd")
const Tracking=preload("res://src/domain/selective_tracking.gd")
const Receipt=preload("res://src/domain/receipt_primitives.gd")
const Clock=preload("res://src/domain/business_clock.gd")
const ACTIONS:Array=["world_track_promote","world_track_reference","world_track_suspend"]

static func seed_valid(s:Dictionary,p:Dictionary)->bool:
	if not p.has("tracking_candidates"):
		return true
	var rows:Variant=p.tracking_candidates
	if not rows is Dictionary or rows.is_empty() or rows.size()>Tracking.MAX_RECORDS or p.get("lifecycle_version")!="calendar-lifecycle-1":
		return false
	for id:Variant in rows:
		var row:Variant=rows[id]
		if not Rules.identifier(id) or not s.items.has(id) or not Rules.keys(row,["tier","pinned"]) or row.tier not in ["tracked","narrative"] or not row.pinned is bool:
			return false
	return true

static func index(s:Dictionary)->Dictionary:
	var result:Dictionary={}
	for id:String in s.items:
		result[id]="active"
	for id:String in s.tombstones:
		result[id]="terminal"
	for family:Dictionary in s.calendar.dormant.values():
		for id:String in family:
			result[id]="dormant"
	return result

static func _ref(s:Dictionary,id:String,event:String)->bool:
	if Receipt.receipt_revision(s,event)<1:
		return false
	# Only existing player-observed or actual transaction/work references.
	if s.knowledge.has(event):
		return s.knowledge[event].item_id==id and s.knowledge[event].observer_id=="player"
	for row:Dictionary in s.ledger:
		if row.event_id==event:
			return id in row.item_ids and "player" in [row.from,row.to]
	for row:Dictionary in s.object_events:
		if row.event_id==event:
			var revision:int=int(row.revision)
			if revision<1 or revision>s.calendar.commands.size():
				return false
			var command:Dictionary=s.calendar.commands[revision-1]
			return id in row.item_ids and command.payload.get("actor")=="player" and command.action_id==event
	var observation:Dictionary=s.calendar.get("appraisal_observations",{}).get(event,{})
	if not observation.is_empty():
		return observation.record.item_id==id and observation.record.observer_id=="player" and Receipt.receipt_type(s,event)=="inspect_subject"
	for entry:Dictionary in s.calendar.get("appraisal_decks",{}).values():
		if entry.item_id==id:
			for speech:Dictionary in entry.deck.presented:
				if speech.presentation_id==event:
					return Receipt.receipt_type(s,event)=="subject_deck_action"
	for offers:Array in s.calendar.get("appraisal_offers",{}).values():
		for offer:Dictionary in offers:
			if offer.offer_id==event and offer.item_id==id:
				return Receipt.receipt_type(s,event)=="subject_price_offer"
	return false

static func valid(s:Dictionary)->bool:
	var allowed:Dictionary=s.calendar.profile.get("tracking_candidates",{})
	if not s.calendar.has("tracking"):
		return allowed.is_empty()
	var rows:Variant=s.calendar.tracking
	if allowed.is_empty() or not rows is Dictionary or rows.size()>Tracking.MAX_RECORDS:
		return false
	var ids:Dictionary=index(s)
	var enabled_count:int=0
	var authored:int=0
	for id:Variant in rows:
		var row:Variant=rows[id]
		if not Rules.identifier(id) or not ids.has(id) or not allowed.has(id) or not Rules.keys(row,["tier","enabled","pinned","refs"]) or row.tier!=allowed[id].tier or row.pinned!=allowed[id].pinned or not row.enabled is bool or not row.refs is Array or row.refs.size()>Tracking.MAX_REFS or (row.pinned and not row.enabled):
			return false
		if row.enabled:
			if ids[id]=="terminal":
				return false
			enabled_count+=1
			authored+=1 if row.tier=="narrative" else 0
		var seen:Dictionary={}
		for ref:Variant in row.refs:
			if not Rules.identifier(ref) or seen.has(ref) or not _ref(s,id,ref):
				return false
			seen[ref]=true
	return enabled_count<=Tracking.MAX_TRACKED and authored<=Tracking.MAX_AUTHORED

static func _can_suspend(s:Dictionary,id:String)->bool:
	var found:Dictionary={}
	var root:String=""
	for root_id:String in s.calendar.dormant:
		if s.calendar.dormant[root_id].has(id):
			found=s.calendar.dormant[root_id]
			root=root_id
			break
	if found.is_empty():
		return false
	var history:Dictionary=s.duplicate()
	history.items=s.items.duplicate()
	history.items.merge(found)
	for member:String in found:
		if not Tracking.can_suspend(history,member):
			return false
	for job:Dictionary in s.calendar.get("services",{}).get("jobs",{}).values():
		if job.terms.item_id in found and job.status in ["offered","accepted","complete"]:
			return false
	for rule:Dictionary in s.calendar.profile.get("reentry_rules",{}).values():
		if rule.item_id==root and Clock.day_index(int(s.game_minutes))<=rule.day:
			return false
	return true

static func apply(s:Dictionary,command:Dictionary)->String:
	if not s.calendar.has("tracking") or not valid(s):
		return "tracking_disabled"
	var p:Dictionary=command.payload
	var keys:Array=["item_id","event_id"] if command.type=="world_track_reference" else ["item_id"]
	if not Rules.keys(p,keys) or not Rules.identifier(p.item_id):
		return "tracking_shape"
	var id:String=p.item_id
	var rows:Dictionary=s.calendar.tracking
	var row:Dictionary=rows.get(id,{})
	match command.type:
		"world_track_promote":
			var rule:Dictionary=s.calendar.profile.tracking_candidates.get(id,{})
			if rule.is_empty() or index(s).get(id) not in ["active","dormant"] or row.get("enabled",false):
				return "tracking_candidate"
			rows[id]={"tier":rule.tier,"pinned":rule.pinned,"enabled":true,"refs":row.get("refs",[]).duplicate()}
		"world_track_reference":
			if not row.get("enabled",false) or not Rules.identifier(p.event_id) or p.event_id in row.refs or row.refs.size()>=Tracking.MAX_REFS or not _ref(s,id,p.event_id):
				return "tracking_reference"
			row.refs.append(p.event_id)
		"world_track_suspend":
			if not row.get("enabled",false) or row.pinned or not _can_suspend(s,id):
				return "tracking_protected"
			row.enabled=false
		_:
			return "tracking_command"
	return "" if valid(s) else "tracking_budget"

## Called after a real disposal on the candidate; rejection rolls it all back.
## Retained history is never deleted. Authored pins require separate resolution.
static func reconcile_terminal(s:Dictionary)->String:
	for id:String in s.calendar.get("tracking",{}):
		var row:Dictionary=s.calendar.tracking[id]
		if s.tombstones.has(id) and row.enabled:
			if row.pinned:
				return "tracking_pinned_disposal"
			row.enabled=false
	return ""
