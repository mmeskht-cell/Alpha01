extends RefCounted
## A1 technical calendar pilot, optional finite medicine. No content generation or ending.
## Mutates only the GameSession candidate; trusted profile bound to seed.
const Rules = preload("res://src/domain/value_rules.gd")
const Clock = preload("res://src/domain/business_clock.gd")
const Medicine = preload("res://src/domain/campaign_medicine.gd")
const Queue = preload("res://src/domain/campaign_visit_queue.gd")
const Service = preload("res://src/domain/campaign_service.gd")
const Contract = preload("res://src/domain/campaign_contract.gd")
const VisitObservation = preload("res://src/domain/visit_appraisal_observation.gd")
const CalendarLife = preload("res://src/domain/calendar_lifecycle.gd")
const Selection = preload("res://src/domain/calendar_tracking.gd")
const Reaction = preload("res://src/domain/calendar_reaction.gd")
const Retention=preload("res://src/domain/appraisal_history_retention.gd")
const Regional=preload("res://src/domain/regional_world_state.gd")
const Npc=preload("res://src/domain/npc_continuity.gd")
const Market=preload("res://src/domain/regional_market_flow.gd")
const Population=preload("res://src/domain/npc_population.gd")
const Finance=preload("res://src/domain/calendar_exchange_market.gd")
const ACTIONS: Array = ["calendar_close", "calendar_morning", "calendar_pay_overhead"]
const COMMON: Array = ["trade", "deliver", "move", "observe", "restore_item", "attach", "detach", "discard", "replace_component","clean_exterior"]
const OVERHEAD: int = 15
const LIFECYCLE_VERSION: String = "calendar-lifecycle-1"

static func profile_valid(p: Variant) -> bool:
	if p is Dictionary and p.has("exchange_market"):
		if p.get("id")!="campaign_42" or not p.get("exchange_market") is Dictionary or not p.has("visit_days"):
			return false
		var base:Dictionary=p.duplicate(true)
		base.erase("exchange_market")
		return profile_valid(base)
	if p is Dictionary and p.has("npc_population"):
		if p.get("id")!="campaign_42" or not p.get("npc_population") is Dictionary or not p.has("market_flow") or not p.has("visit_days"):
			return false
		var base:Dictionary=p.duplicate(true)
		base.erase("npc_population")
		return profile_valid(base)
	if p is Dictionary and p.has("market_flow"):
		if p.get("id")!="campaign_42" or not p.get("market_flow") is Dictionary or not p.has("regional_world") or not p.has("visit_days"):
			return false
		var base:Dictionary=p.duplicate(true)
		base.erase("market_flow")
		return profile_valid(base)
	if p is Dictionary and p.has("npc_continuity"):
		if not p.npc_continuity is Dictionary or not p.has("visit_days"):
			return false
		var base:Dictionary=p.duplicate(true)
		base.erase("npc_continuity")
		return profile_valid(base)
	if p is Dictionary and p.has("regional_world"):
		if not p.regional_world is Dictionary or not p.has("visit_days"):
			return false
		var base:Dictionary=p.duplicate(true)
		base.erase("regional_world")
		return profile_valid(base)
	if p is Dictionary and p.has("observation_retention"):
		if p.observation_retention!=Retention.CONTRACT or p.get("id")!="campaign_42" or p.get("appraisal_profile")!="watch_p2_v1":
			return false
		var base:Dictionary=p.duplicate(true)
		base.erase("observation_retention")
		return profile_valid(base)
	if p is Dictionary and p.has("carryover_returns"):
		if p.get("id")!="demo_7" or p.get("content_version") not in ["demo7-integrated-1","demo7-integrated-2","demo7-integrated-3"] or not p.has("services") or not p.has("visit_days") or not p.carryover_returns is Dictionary or p.carryover_returns.is_empty() or p.carryover_returns.size()>8:
			return false
		var base:Dictionary=p.duplicate(true)
		base.erase("carryover_returns")
		return profile_valid(base)
	if p is Dictionary and p.get("content_version") in ["demo7-integrated-1","demo7-integrated-2","demo7-integrated-3"] and p.has("appraisal_profile") and p.has("services") and p.has("contracts"):
		var base:Dictionary=p.duplicate(true)
		base.erase("appraisal_profile")
		return profile_valid(base)
	if p is Dictionary and p.has("reaction_rules"):
		if not p.reaction_rules is Dictionary or p.reaction_rules.is_empty() or p.reaction_rules.size()>Reaction.MAX_RULES or not p.has("services") or not p.has("visit_days"):
			return false
		var base:Dictionary=p.duplicate(true)
		base.erase("reaction_rules")
		return profile_valid(base)
	if p is Dictionary and p.has("lifecycle_version"):
		if p.lifecycle_version != LIFECYCLE_VERSION or not p.has("visit_days"):
			return false
		var base: Dictionary = p.duplicate(true)
		base.erase("lifecycle_version")
		if base.has("tracking_candidates"):
			base.erase("tracking_candidates")
		if base.has("reentry_rules"):
			if not base.reentry_rules is Dictionary or base.reentry_rules.is_empty() or base.reentry_rules.size()>CalendarLife.MAX_RETURN_RULES:
				return false
			base.erase("reentry_rules")
		return profile_valid(base)
	if not Rules.keys(p, ["id", "content_version", "day_ids"]) and not Rules.keys(p, ["id", "content_version", "day_ids", "medicine"]) and not Rules.keys(p, ["id", "content_version", "day_ids", "visit_days"]) and not Rules.keys(p, ["id", "content_version", "day_ids", "visit_days", "services"]) and not Rules.keys(p, ["id", "content_version", "day_ids", "visit_days", "contracts", "story_rules"]) and not Rules.keys(p, ["id", "content_version", "day_ids", "visit_days", "services", "contracts", "story_rules"]) and not Rules.keys(p,["id","content_version","day_ids","visit_days","appraisal_profile"]):
		return false
	if p.id not in ["demo_7", "campaign_42"] or not Rules.identifier(p.content_version) or not p.day_ids is Array:
		return false
	var days: int = 7 if p.id == "demo_7" else 42
	if p.day_ids.size() != days:
		return false
	var seen: Dictionary = {}
	for id: Variant in p.day_ids:
		if not Rules.identifier(id) or seen.has(id):
			return false
		seen[id] = true
	return true

static func boundary(p: Dictionary) -> int:
	return p.day_ids.size() * Clock.DAY_MINUTES

static func seed(state: Dictionary, defs: Dictionary, profile: Dictionary) -> Dictionary:
	if not profile_valid(profile) or state.get("revision") != 0 or state.get("game_minutes") != 0 or state.get("phase") != "shop" or not state.get("wallets") is Dictionary or not state.wallets.has("player") or not state.get("visits") is Dictionary:
		return {}
	for visit: Variant in state.visits.values():
		if not visit is Dictionary or "player" not in [visit.get("seller"), visit.get("buyer")]:
			return {}
	var result: Dictionary = state.duplicate(true)
	result["calendar"] = {"version": 1, "profile": profile.duplicate(true), "binding": Rules.canonical({"seed": state, "definitions": defs, "profile": profile}).sha256_text(), "debt": 0, "commands": []}
	if profile.get("lifecycle_version") == LIFECYCLE_VERSION:
		result.calendar["dormant"] = {}
		if profile.has("tracking_candidates"):
			if not Selection.seed_valid(result,profile):
				return {}
			result.calendar["tracking"] = {}
	if profile.has("medicine"):
		var m: Dictionary = Medicine.seed(state, profile)
		if m.is_empty():
			return {}
		result.calendar["medicine"] = m
	if profile.has("services"):
		var jobs: Dictionary = Service.seed(state, defs, profile)
		if jobs.is_empty():
			return {}
		result.calendar["services"] = jobs
	if profile.has("visit_days"):
		var q: Dictionary = Queue.seed(state, profile, result.calendar.get("services", {}).get("visits", {}))
		if q.is_empty():
			return {}
		result.calendar["queue"] = q
	if profile.has("contracts"):
		var contracts: Dictionary = Contract.seed(state, profile)
		if contracts.is_empty():
			return {}
		result.calendar["contracts"] = contracts
		Contract.morning(result, "opening")
	if profile.has("appraisal_profile"):
		var observation_profile: Dictionary = VisitObservation.seed(state,profile)
		if observation_profile.is_empty():
			return {}
		result.calendar["appraisal_profile"] = observation_profile
		result.calendar["appraisal_observations"] = {}
		if profile.get("observation_retention","")==Retention.CONTRACT:
			result.calendar["appraisal_observation_archive"]={}
		result.calendar["appraisal_assessments"] = {}
	if profile.has("reaction_rules"):
		var reaction:Dictionary=Reaction.seed(result,profile)
		if reaction.is_empty():
			return {}
		result.calendar["reaction"]=reaction
	if profile.has("npc_continuity") and not Npc.seed_valid(result,profile):
		return {}
	if profile.has("regional_world"):
		var region_seed:Dictionary=Regional.seed(result,profile)
		if region_seed.is_empty():
			return {}
		result.calendar["regional_world"]=region_seed
	if profile.has("market_flow") and not Market.seed_valid(result,profile):
		return {}
	if profile.has("npc_population"):
		var generated:Dictionary=Population.seed(result,profile)
		if generated.is_empty():
			return {}
		result.calendar["npc_population"]=generated
	if profile.has("exchange_market"):
		var exchange:Dictionary=Finance.seed(result,profile)
		if exchange.is_empty():
			return {}
		result.calendar["exchange_market"]=exchange
	if not CalendarLife.rules_valid(result,profile):
		return {}
	return Rules.normalized(result)

static func complete(s: Dictionary) -> bool:
	return s.game_minutes == boundary(s.calendar.profile)

static func apply(s: Dictionary, kind: String, payload: Dictionary, action: String) -> String:
	var explicit:bool=kind=="calendar_close" and Rules.keys(payload,["contract_choices"])
	if (not payload.is_empty() and not explicit) or complete(s):
		return "calendar_boundary_or_payload"
	if explicit and not Contract.close_choices_valid(s,payload.contract_choices):
		return "contract_close_choice"
	var c: Dictionary = s.calendar
	match kind:
		"calendar_close":
			if not Clock.business_at(int(s.game_minutes), s.phase):
				return "calendar_close_phase"
			if c.has("queue"):
				Queue.close(s)
			var paid: int = mini(OVERHEAD, int(s.wallets.player.VKC))
			s.wallets.player.VKC -= paid
			c.debt += OVERHEAD - paid
			s.game_minutes = (Clock.day_index(int(s.game_minutes)) - 1) * Clock.DAY_MINUTES + Clock.BUSINESS_MINUTES
			if c.has("medicine"):
				Medicine.close(s, action)
			var contract_error:String=Contract.close(s,action,payload.get("contract_choices",{}),explicit)
			if not contract_error.is_empty():
				return contract_error
			s.phase = "workshop"
		"calendar_morning":
			if s.phase != "workshop" or int(s.game_minutes) % Clock.DAY_MINUTES != Clock.BUSINESS_MINUTES:
				return "calendar_morning_phase"
			s.game_minutes += Clock.DAY_MINUTES - Clock.BUSINESS_MINUTES
			if not complete(s):
				s.phase = "shop"
				if c.has("medicine"):
					Medicine.morning(s, action)
				Contract.morning(s, action)
				Reaction.morning(s,action)
				Regional.morning(s,action)
		"calendar_pay_overhead":
			if not Clock.business_at(int(s.game_minutes), s.phase) or c.debt <= 0 or s.wallets.player.VKC < c.debt:
				return "calendar_debt"
			s.wallets.player.VKC -= c.debt
			c.debt = 0
		_:
			return "calendar_command"
	return ""

static func view(s: Dictionary) -> Dictionary:
	var done: bool = complete(s)
	var day: int = mini(Clock.day_index(int(s.game_minutes)), s.calendar.profile.day_ids.size())
	return {"profile": s.calendar.profile.id, "day": day, "day_id": s.calendar.profile.day_ids[day - 1], "minute": s.game_minutes, "phase": "complete" if done else s.phase, "complete": done, "overhead_debt": s.calendar.debt}
