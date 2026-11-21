extends SceneTree
## True Godot Window + actual GameSession integration of the native office.
## No test-invented DTO price, item ownership, contract or cash balance.
const Cross=preload("res://tests/scenarios/alpha_cross_system_42day_test.gd")
const Session=preload("res://src/domain/game_session.gd")
const Office=preload("res://src/presentation/native_office.gd")
var checks:int=0
var failures:int=0
var office:VBoxContainer
var session:RefCounted
var actions:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: "+label)
func cmd(kind:String,id:String,p:Dictionary={})->bool:
	var r:Dictionary=session.execute({"action_id":id,"expected_revision":session.snapshot().revision,
		"type":kind,"payload":p})
	if not r.get("ok",false):
		printerr("OFFICE_REAL_REJECT "+id+" "+str(r.get("error","")))
	return bool(r.get("ok",false))
func office_view()->Dictionary:
	var data:Dictionary=session.calendar_view()
	var state:Dictionary=session.snapshot()
	data["revision"]=state.revision
	data["wallet"]=state.wallets.player.duplicate(true)
	data["locked"]=false
	data["locale_epoch"]=0
	data["stock"]=[]
	data["trade_history"]=session.calendar_history_index()
	for id:String in state.items:
		if state.items[id].owner_id=="player" and state.items[id].parent_id=="":
			data.stock.append({"id":id,"label":"p2.watch.meridian12"})
	return data
func render()->void:
	var tr:Callable=func(key:String,args:Dictionary={})->String: return key
	office.configure(office_view(),tr,"ko",0)
func tap(name:String)->bool:
	var button:Button=office.find_child(name,true,false) as Button
	if button==null or button.disabled or not button.is_visible_in_tree():
		printerr("OFFICE_REAL_NOT_CLICKABLE "+name)
		return false
	button.pressed.emit()
	return true
func _initialize()->void:
	var f:Dictionary=Cross.fixture()
	check(not f.is_empty(),"real seeded finite campaign profile")
	if f.is_empty():
		quit(1)
		return
	session=Session.new()
	check(session.initialize(f.defs,f.state,false,false,f.profile),"same 42-day GameSession, not a mocked office")
	if session.snapshot().is_empty():
		quit(1)
		return
	root.visible=true
	office=Office.new()
	office._tab="contracts"
	office.name="real_office"
	office.visible=true
	root.add_child(office)
	office.action_requested.connect(func(kind:String,p:Dictionary,revision:int)->void:
		var response:Dictionary=session.execute({"action_id":"real_office_"+str(revision+1),
			"expected_revision":revision,"type":kind,"payload":p})
		if response.get("ok",false):
			actions.append(kind)
		else:
			printerr("FAIL: OFFICE_REAL_ACTION "+kind+" "+str(response.get("error","")))
			failures+=1)
	await process_frame
	render()
	check(tap("office_order_accept_o1"),"real order acceptance via visible office button")
	check(session.snapshot().wallets.escrow.VKC==100 and actions.has("merchant_order_accept"),
		"only actual customer cash is deposited")
	render()
	check(tap("office_fx_fx"),"real FX quote through visible office control")
	check(session.snapshot().wallets.player.USD==1 and session.snapshot().wallets.broker.USD==2,
		"real player/broker FX settlement, no fake currency")
	check(cmd("calendar_next_visit","arrive"),"shop queue admits real pawn customer")
	render()
	check(tap("office_pawn_accept_p1"),"actual pawn button appears for active customer")
	check(session.snapshot().items.W001.status=="custody_pawn"
		and session.snapshot().items.W001.owner_id=="seller"
		and session.snapshot().wallets.seller.VKC==140,
		"pledge changes physical custody and actual lender/borrower wallets")
	check(cmd("calendar_close","d1_close") and cmd("calendar_morning","d2_morning"),
		"authored repayment day begins with same authority")
	render()
	check(tap("office_pawn_redeem_p1"),"real customer's D2 repayment button")
	check(session.snapshot().items.W001.owner_id=="seller" and
		session.snapshot().items.W001.custodian_id=="seller",
		"actual returned collateral ownership and custody")
	render()
	check(tap("office_order_deliver_o1_SELL01"),"real selected item delivered via visible office button")
	check(session.snapshot().wallets.escrow.VKC==0 and
		session.snapshot().items.SELL01.owner_id=="order_buyer",
		"funded order settles exact physical ID and no escrow residual")
	office._tab="ledger"
	render()
	check(office.find_child("history_item_SELL01",true,false)!=null
		and office.find_child("history_item_W001",true,false)!=null,
		"same real office shows both paid order sale and separately classified pawn custody")
	var cold:=Session.new()
	var state:Dictionary=session.snapshot()
	check(cold.initialize(f.defs,f.state,false,false,f.profile)
		and cold.restore(state) and cold.snapshot()==state,
		"actual office button actions have deterministic cold-replay receipts")
	office.queue_free()
	print("ALPHA_42DAY_REAL_OFFICE: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
