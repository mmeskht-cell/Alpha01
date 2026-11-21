extends SceneTree
## Production 42-day alpha seed and the exact source-backed saved GameSession
## runtime, never a test fixture or a second economy authority.
const Seed=preload("res://src/content/alpha42_mechanics_seed.gd")
const Runtime=preload("res://src/application/campaign42_alpha_runtime.gd")
const Session=preload("res://src/domain/game_session.gd")
const Clock=preload("res://src/domain/business_clock.gd")
var checked:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
	checked+=1
	if not ok:
		failed+=1
		printerr("FAIL: "+label)
func command(s:RefCounted,t:String,p:Dictionary={})->bool:
	var r:Dictionary=s.execute({"type":t,"payload":p,"action_id":"production_"+str(s.snapshot().revision+1),"expected_revision":s.snapshot().revision})
	if not r.get("ok",false):
		printerr("ALPHA42_COMMAND_REJECT "+t+": "+str(r.get("error","")))
	return bool(r.get("ok",false))
func _initialize()->void:
	var f:Dictionary=Seed.content()
	check(not f.is_empty(),"separate authored finite production alpha42 content resolves")
	if f.is_empty():
		quit(1)
		return
	check(f.profile.id=="campaign_42" and f.profile.day_ids.size()==42
		and f.profile.visit_days.d8.has("pickup7"),
		"original D7 pickup travels into D8 without changing seven-day baseline")
	check(f.profile.merchant_contracts.pawns.size()==1 and
		f.profile.merchant_contracts.orders.size()==1 and
		f.profile.npc_generated_visits.slots.size()==209,
		"publicly authored finite merchant and NPC model is actual launch content")
	var s:=Seed.fresh()
	check(s!=null,"fresh source-backed campaign initialized by standard GameSession")
	if s==null:
		quit(1)
		return
	check(s.snapshot().calendar.profile.id=="campaign_42" and
		s.snapshot().visits.has("g09_0") and
		s.snapshot().items.has("ALPHA_ORDER01"),
		"real physical contract inventory and selected merchant supply materialized")
	check(not s.calendar_view().has("npc_visitor"),"future actor secrets absent from public runtime")
	for n:int in range(1,8):
		check(command(s,"calendar_close") and command(s,"calendar_morning"),"canonical first-week calendar day "+str(n))
	check(s.calendar_view().day==8 and not s.calendar_view().complete,
		"isolated 42-day runtime continues after the unchanged demo seven")
	check(command(s,"merchant_order_accept",{"contract_id":"alpha_order"}),
		"real D8 merchant order reserves actual buyer funds")
	check(command(s,"calendar_exchange",{"quote_id":"alpha_broker_quote"}),
		"D8 actual broker exchange of finite VKC/USD")
	var d8:Dictionary=s.calendar_view()
	check(s.snapshot().wallets.player.USD==1 and s.snapshot().wallets.alpha_broker.USD==4,
		"real broker holds previous USD and player receives exactly one")
	check(command(s,"calendar_next_visit"),"D8 collateral seller enters real shop queue")
	check(command(s,"merchant_pawn_accept",{"contract_id":"alpha_pawn"}),
		"player can lend against exact original physical goods")
	check(s.snapshot().items.ALPHA_PAWN01.owner_id=="alpha_pawn_seller" and
		s.snapshot().items.ALPHA_PAWN01.custodian_id=="player",
		"pledge preserves original owner and transfers only custody")
	check(command(s,"calendar_close") and command(s,"calendar_morning"),
		"D9 opens with repayment due at authored time")
	check(command(s,"merchant_pawn_redeem",{"contract_id":"alpha_pawn"}),
		"actual D9 loan repayment transfers currency and returns exact goods")
	check(command(s,"calendar_next_visit"),"D9 financed named mercenary offers real stock")
	var visited:Dictionary=s.calendar_view()
	check(visited.npc_visitor.has("alias") and
		not visited.npc_visitor.has("private_trait"),
		"one current real NPC visible with hidden bargaining behavior")
	var initial:Dictionary=s.snapshot()
	check(JSON.stringify(initial).to_utf8_buffer().size()<1048576,
		"authoritative production 42-day seed and several-day commands under one MiB")
	var restored:=Session.new()
	check(restored.initialize(f.defs,f.state,false,false,f.profile) and
		restored.restore(initial) and restored.snapshot()==initial,
		"fresh production content replays exact long-alpha commands")
	var tampered:Dictionary=initial.duplicate(true)
	tampered.wallets.alpha_broker.USD+=1
	check(not restored.restore(tampered) and restored.snapshot()==initial,
		"actual alpha broker cannot mint or forge foreign currency")
	var runtime:=Runtime.new()
	var path:String=Runtime.PREFIX+"/slot_3"
	check(runtime.open(path),"actual production save/load adapter opens isolated 42-day slot")
	if runtime.localization!=null:
		runtime.close()
	print("ALPHA42_PRODUCTION_RUNTIME: ",checked," checks, ",failed," failures")
	quit(0 if failed==0 else 1)
