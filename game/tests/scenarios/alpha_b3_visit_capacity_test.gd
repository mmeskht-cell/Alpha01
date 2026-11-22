extends SceneTree
## B3-M1: audit real 7-day B2 source, never compensate for a schedule gap
## by adding an imaginary visit, item, buyer or currency unit.
const Source = preload("res://src/content/alpha_b2_service_multi_seed.gd")
const Capacity = preload("res://src/domain/alpha_b3_visit_capacity.gd")
var checks: int=0
var failures: int=0

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func _initialize() -> void:
	var source: Dictionary=Source.content()
	check(not source.is_empty(),"same finite source as the accepted B2 multi-customer shop")
	if source.is_empty():
		quit(1)
		return
	var before: Dictionary=source.duplicate(true)
	var review: Dictionary=Capacity.audit(source)
	check(review.get("ok",false) and not review.get("ready",true),
		"existing B2 scenario cannot claim B3 7-10 visitors every day")
	check(review.get("total_authored",-1)==26
		and review.get("total_guaranteed",-1)==20
		and review.get("total_conditional",-1)==6,
		"source-based 26 real authored slots with six acceptance-dependent returns")
	var counts: Array=[]
	var guaranteed: Array=[]
	for day: Dictionary in review.get("days",[]):
		counts.append(int(day.authored))
		guaranteed.append(int(day.guaranteed))
	check(counts==[5,6,6,4,3,2,0] and guaranteed==[5,5,4,3,1,2,0],
		"D1-D7 authored/guaranteed visitors are not simulated from empty legacy service IDs")
	check(review.days[6].minimum_shortfall==7 and review.days[6].maximum_free_slots==10,
		"Day7 is an open B3 scheduling shortfall, not an invented completed campaign")
	check(source==before and review.days[1].conditional==1 and review.days[4].conditional==2,
		"pure audit preserves real source and distinguishes G02/Ian/G04 dependent appointments")
	var tampered: Dictionary=source.duplicate(true)
	tampered.alpha_profile.days[0].append({
		"id":"b3_unfunded_visit","actor_id":"phantom_buyer","kind":"regular",
		"purpose_key":"alpha.purpose.trade","contact_offer":false
	})
	check(not Capacity.audit(tampered).get("ok",false),
		"actor without seeded wallet is rejected rather than materialized")
	tampered=source.duplicate(true)
	tampered.alpha_profile.days[0].append({
		"id":"b3_duplicate_actor","actor_id":"G01","kind":"named",
		"purpose_key":"alpha.purpose.trade","contact_offer":false
	})
	check(not Capacity.audit(tampered).get("ok",false),
		"same actor cannot appear twice on one finite day")
	tampered=source.duplicate(true)
	tampered.alpha_profile.days.append([])
	check(not Capacity.audit(tampered).get("ok",false),
		"seven-day B3 acceptance requires exactly seven explicit day rows")
	print("ALPHA_B3_CAPACITY_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
