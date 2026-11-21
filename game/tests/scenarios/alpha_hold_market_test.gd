extends SceneTree
## Budget-safe seven-day delayed-buyer alpha: modifies ONLY time slots in a
## dedicated save/seed. No canonical merchandise, prices or money edited.
const Candidate=preload("res://src/content/civilian_candidate_seed.gd")
const Runtime=preload("res://src/application/demo7_runtime.gd")
const Session=preload("res://src/domain/game_session.gd")
var checks:int=0
var failures:int=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: "+label)
func _initialize()->void:
	var normal:Dictionary=Candidate.content(true,3)
	var hold:Dictionary=Candidate.content(true,3,true)
	check(not normal.is_empty() and not hold.is_empty(),
		"existing fixed alpha and isolated holding-market variant both load")
	if normal.is_empty() or hold.is_empty():
		quit(1)
		return
	check(normal.state.items==hold.state.items and normal.state.wallets==hold.state.wallets
		and normal.defs==hold.defs,
		"no new money, changed prices, extra items or definition modifications")
	check(normal.profile.contracts==hold.profile.contracts and normal.profile.story_rules==hold.profile.story_rules
		and normal.profile.services==hold.profile.services
		and normal.profile.reentry_rules==hold.profile.reentry_rules,
		"RAD-1 dates, clinic story branch and all service/return contracts untouched")
	var changes:Array=[
		["watch_sale",2,3],["battery_sale",2,3],
		["gear_sale",3,4],["radio3_sale",3,4],
		["tool_sale",4,6],["electronics_sale",6,7]]
	for move:Array in changes:
		var id:String=move[0]
		var initial_day:String="d"+str(move[1])
		var later:String="d"+str(move[2])
		check(normal.profile.visit_days[initial_day].has(id)
			and not hold.profile.visit_days[initial_day].has(id)
			and hold.profile.visit_days[later].has(id),
			"unchanged offer moved to a genuinely later day: "+id)
		check(normal.state.visits[id].prices==hold.state.visits[id].prices
			and normal.state.visits[id].seller==hold.state.visits[id].seller
			and normal.state.visits[id].buyer==hold.state.visits[id].buyer,
			"real buyer, actor cash and quote unchanged: "+id)
		check(hold.state.visits[id].opens==(int(move[2])-1)*1440
			and hold.state.visits[id].expires==hold.state.visits[id].opens+600,
			"postponed offer really opens and expires on new day: "+id)
	check(hold.profile.visit_days.d5.has("hygiene_sale") and
		hold.profile.story_rules.clinic_supply_confirmed.day==6,
		"clinic stock trade remains D5, actual resulting event remains D6")
	check(hold.profile.visit_days.d3.has("battery_sale") and
		hold.profile.visit_days.d3.has("watch_sale") and
		hold.profile.visit_days.d4.has("gear_sale") and
		hold.profile.visit_days.d4.has("radio3_sale"),
		"four real pre-deadline cash-recovery opportunities have correct D3/D4 schedules")
	var alpha3:=Session.new()
	var holding:=Session.new()
	check(alpha3.initialize(normal.defs,normal.state,false,false,normal.profile),
		"previous alpha3 session still runs its exact original profile")
	check(holding.initialize(hold.defs,hold.state,false,false,hold.profile),
		"new mode reuses GameSession authority with moved timing-only seed")
	if alpha3.snapshot().is_empty() or holding.snapshot().is_empty():
		printerr("HOLD_INIT_DIAG ",alpha3.initialization_error()," ",holding.initialization_error())
		quit(1)
		return
	check(alpha3.snapshot().calendar.binding!=holding.snapshot().calendar.binding,
		"separate seed hash prevents cross-mode save spoofing or silent migration")
	var forged:=Session.new()
	check(forged.initialize(hold.defs,hold.state,false,false,hold.profile)
		and not forged.restore(alpha3.snapshot()),
		"original-alpha persisted state forbidden in deferred-market mode")
	check(holding.calendar_view().visits.remaining==alpha3.calendar_view().visits.remaining,
		"untouched opening day still has original number of real customer appointments")
	var app:=Runtime.new()
	check(app.open("user://zt_rebuild/demo7/hold_market_alpha",true,true,3,true)
		and app.view().hold_market_alpha,
		"isolated production runtime and dedicated alpha-market save slot launch")
	if app.localization!=null:
		app.close()
	var old:=Runtime.new()
	check(old.open("user://zt_rebuild/demo7/alpha_playtest",true,true,3)
		and not old.view().hold_market_alpha,
		"existing alpha3 save remains independent and unmodified")
	if old.localization!=null:
		old.close()
	print("ALPHA_HOLD_MARKET: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
