extends RefCounted
## B3-M1 read-only finite visit feasibility gate. It never creates visitors,
## buys stock, replenishes wallets or modifies a single source-bound save.
## A scheduled service/commission return is conditional, not guaranteed.
const Alpha = preload("res://src/domain/alpha_shop_cycle.gd")
const Commission = preload("res://src/domain/alpha_commission.gd")
const Service = preload("res://src/domain/alpha_service_custody.gd")
const TARGET_MIN: int = 7
const TARGET_MAX: int = 10

static func audit(source: Dictionary) -> Dictionary:
	if not source.has("state") or not source.has("alpha_profile"):
		return {"ok":false,"error":"b3_source_shape"}
	var state: Variant=source.state
	var profile: Variant=source.alpha_profile
	if not state is Dictionary or not profile is Dictionary:
		return {"ok":false,"error":"b3_source_type"}
	if not profile.get("days") is Array or profile.days.size()!=7:
		return {"ok":false,"error":"b3_seven_day_plan"}
	if not Alpha.profile_valid(profile,state):
		return {"ok":false,"error":"b3_invalid_authority"}
	var days: Array=[]
	var total_authored: int=0
	var total_guaranteed: int=0
	var total_conditional: int=0
	var all_ready: bool=true
	for day_index: int in range(7):
		var rows: Array=profile.days[day_index]
		var guaranteed: int=0
		var conditional: int=0
		var authored: int=rows.size()
		var witnesses: Array=[]
		for row: Dictionary in rows:
			var id: String=str(row.id)
			var actor_id: String=str(row.actor_id)
			var is_commission_return: bool=profile.has("commission_profile_id") and Commission.is_return_visit(id,str(profile.commission_profile_id))
			var is_service_return: bool=profile.has("service_profile_id") and Service.is_return_visit(id,str(profile.service_profile_id))
			# Returning appointments require earlier acceptance and an actual
			# customer revisit. The authored slot alone is not a real visitor.
			if is_commission_return or is_service_return:
				conditional+=1
				witnesses.append({"visit_id":id,"actor_id":actor_id,"kind":"conditional_return"})
				continue
			var kind: String="transaction" if state.visits.has(id) else "named_contact"
			guaranteed+=1
			witnesses.append({"visit_id":id,"actor_id":actor_id,"kind":kind})
		var shortage: int=maxi(0,TARGET_MIN-guaranteed)
		var room: int=TARGET_MAX-authored
		# Never call conditional appointments actual arrivals or pad an
		# empty day with unfinanced simulated purchases.
		var ready: bool=guaranteed>=TARGET_MIN and authored<=TARGET_MAX
		all_ready=all_ready and ready
		total_authored+=authored
		total_guaranteed+=guaranteed
		total_conditional+=conditional
		days.append({
			"day":day_index+1,"authored":authored,"guaranteed":guaranteed,
			"conditional":conditional,"minimum_shortfall":shortage,
			"maximum_free_slots":room,"ready":ready,"witnesses":witnesses
		})
	return {"ok":true,"ready":all_ready,"min":TARGET_MIN,"max":TARGET_MAX,
		"days":days,"total_authored":total_authored,
		"total_guaranteed":total_guaranteed,"total_conditional":total_conditional}
