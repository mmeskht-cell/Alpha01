extends RefCounted
## Read-only permission helpers over the validated session. No physical operations.
## Visit-specific grants remain with the caller. A general visit flag never
## overrides a restricted customer preview or the opening's frozen tool list.
const Objects = preload("res://src/domain/object_schema.gd")
const Visits = preload("res://src/domain/visit_primitives.gd")
const Clock = preload("res://src/domain/business_clock.gd")

static func root_for(state: Dictionary, id: String) -> String:
	if not state.items.has(id):
		return ""
	var parent: String = state.items[id].parent_id
	if parent.is_empty():
		return id
	return parent if state.items.has(parent) and state.items[parent].parent_id.is_empty() else ""

static func stock_access(state: Dictionary, id: String, actor: String, detached_only: bool = false) -> bool:
	var root_id: String = root_for(state, id)
	if root_id.is_empty() or (detached_only and root_id != id):
		return false
	var root: Dictionary = state.items[root_id]
	var item: Dictionary = state.items[id]
	for row: Dictionary in [root, item]:
		if row.owner_id != actor or row.custodian_id != actor or row.status != "stock" or row.protected or not row.reservation_id.is_empty():
			return false
	return Objects.destination_accessible(state, root.inventory, actor, actor)

## A reader may review known facts for property in their custody. This does
## not grant a new inspection, disposition, or a read into a locked container.
static func custody_read(state: Dictionary, id: String, actor: String) -> bool:
	var root_id: String = root_for(state, id)
	if root_id.is_empty():
		return false
	var root: Dictionary = state.items[root_id]
	return root.custodian_id == actor and state.items[id].custodian_id == actor and Objects.destination_accessible(state, root.inventory, root.owner_id, actor)

## Generic non-campaign fixture permits explicitly offered roots. The caller
## selects a stricter per-tool grant for temporary internal observations.
static func external_until(state: Dictionary, id: String, actor: String) -> int:
	var root_id: String = root_for(state, id)
	if actor != "player" or root_id.is_empty():
		return -1
	var root: Dictionary = state.items[root_id]
	if not stock_access(state, id, root.owner_id):
		return -1
	var expires: int = -1
	var queue: Variant = state.get("calendar", {}).get("queue")
	if queue is Dictionary and root_id != id:
		return -1 # No implicit internal grant for queued customer goods.
	for v: Dictionary in state.visits.values():
		if queue is Dictionary and v.scope.visit_id != queue.active:
			continue
		if Visits.purchase_open(state, v.scope.visit_id, root_id, root.owner_id, true):
			expires = maxi(expires, int(v.expires))
	return expires

static func generic_read(state: Dictionary, id: String, actor: String) -> bool:
	return actor == "player" and (custody_read(state, id, actor) or external_until(state, id, actor) >= 0)

## No new observation of protected/reserved/custody-only stock without explicit
## work/inspection authority. Keep old zero-duration fixture definitions valid.
static func generic_end(state: Dictionary, id: String, actor: String, duration: int) -> int:
	if actor != "player" or state.phase != "shop":
		return -1
	var minute: int = int(state.game_minutes)
	var end: int = minute + duration
	var owned: bool = stock_access(state, id, actor)
	var expires: int = Clock.CAMPAIGN_END if owned else external_until(state, id, actor)
	if expires < end or end > Clock.CAMPAIGN_END or duration < 0 or not Clock.business_at(minute, state.phase, false):
		return -1
	if duration > 0 and not Clock.inspection_at(minute, duration, true).ok:
		return -1
	return end
