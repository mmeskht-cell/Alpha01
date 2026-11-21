extends RefCounted
## Opt-in lossless in-save history partition for campaign_42. Existing v4
## receipts and the sole authoritative command replay remain unchanged.
## No historical observation, price basis, revision or item ID is discarded.
const Rules=preload("res://src/domain/value_rules.gd")
const Receipt=preload("res://src/domain/receipt_primitives.gd")
const CONTRACT:String="lossless_v1"
const MAX_ACTIVE:int=128
const MAX_TOTAL:int=2048

static func enabled(s:Dictionary)->bool:
	return s.get("calendar",{}).get("profile",{}).get("observation_retention","")==CONTRACT

static func records(s:Dictionary)->Dictionary:
	var calendar:Dictionary=s.get("calendar",{})
	var active:Dictionary=calendar.get("appraisal_observations",s.get("appraisal_observations",{}))
	if not enabled(s):
		return active
	var combined:Dictionary=calendar.get("appraisal_observation_archive",{}).duplicate()
	combined.merge(active)
	return combined

static func valid(s:Dictionary)->bool:
	var calendar:Dictionary=s.get("calendar",{})
	if not calendar.has("appraisal_profile"):
		return not calendar.has("appraisal_observation_archive")
	var active:Variant=calendar.get("appraisal_observations",{})
	if not active is Dictionary or active.size()>MAX_ACTIVE:
		return false
	if not enabled(s):
		return not calendar.has("appraisal_observation_archive")
	var archive:Variant=calendar.get("appraisal_observation_archive")
	if not archive is Dictionary or archive.size()+active.size()>MAX_TOTAL:
		return false
	for id:Variant in archive:
		if not Rules.identifier(id) or active.has(id):
			return false
		var row:Variant=archive[id]
		if not row is Dictionary or not row.has("record") or not row.get("visit_id") is String:
			return false
	return true

## Called on a detached GameSession candidate AFTER observation preparation.
## Move an entire historical record (never just a digest), only from a
## completed/declined/missed visit. Existing references use records() union.
## A/B saves and replay still validate the unmodified full contents.
static func make_room(s:Dictionary)->bool:
	if not enabled(s) or not valid(s):
		return false
	var active:Dictionary=s.calendar.appraisal_observations
	var archive:Dictionary=s.calendar.appraisal_observation_archive
	if active.size()<MAX_ACTIVE:
		return true
	if archive.size()+active.size()>=MAX_TOTAL:
		return false
	var queue:Dictionary=s.calendar.get("queue",{})
	var outcomes:Dictionary=queue.get("outcomes",{})
	var current:String=str(queue.get("active",""))
	var selected:String=""
	var earliest:int=2147483647
	for id:String in active:
		var row:Dictionary=active[id]
		var visit:String=str(row.get("visit_id",""))
		if visit==current or not outcomes.has(visit):
			continue
		var revision:int=Receipt.receipt_revision(s,id)
		if revision<1:
			return false
		if revision<earliest or (revision==earliest and (selected.is_empty() or id<selected)):
			earliest=revision
			selected=id
	if selected.is_empty():
		return false
	archive[selected]=active[selected].duplicate(true)
	active.erase(selected)
	return true
