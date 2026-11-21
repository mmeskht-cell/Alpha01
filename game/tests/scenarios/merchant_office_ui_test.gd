extends SceneTree
## Stage3 native office wiring. A bounded public projection controls
## visible buttons; the button payload is always action+exact revision.
const Office=preload("res://src/presentation/native_office.gd")
var checks:int=0
var failures:int=0
var actions:Array=[]
var office:VBoxContainer

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func money(n:int)->Dictionary:
	return {"VKC":n,"USD":0}

func view()->Dictionary:
	return {"revision":42,"day":2,"phase":"shop","locked":false,"complete":false,
		"locale_epoch":0,"wallet":{"VKC":140,"USD":3},
		"visits":{"active":""},
		"stock":[{"id":"SELL01","label":"item.demo_tool"}],
		"trade_history":{},"obligations":{"contracts":{},"facts":{}},
		"exchange_market":{"quotes":[{"quote_id":"fx1","give_currency":"VKC",
			"give_amount":100,"receive_currency":"USD","receive_amount":2}]},
		"merchant_contracts":{
			"pawns":{"p1":{"status":"pledged","customer":"seller","item_id":"W001",
				"visit_id":"pawn_visit","principal":money(40),"repayment":money(45),
				"repayment_day":2,"repayment_offered":true,"due_day":2}},
			"orders":{"o1":{"status":"accepted","customer":"buyer",
				"def_id":"fictional_watch_p2","price":money(100),"offer_day":1,"due_day":2,
				"delivered_item":"","delivery_options":[{"item_id":"SELL01",
					"placement":{"inventory":"buyer_grid","x":1,"y":0,"rotated":false}}]}},
			"events":[]}}

func tap(name:String)->bool:
	var button:Button=office.find_child(name,true,false) as Button
	if button==null or button.disabled or not button.is_visible_in_tree():
		return false
	button.pressed.emit()
	return true

func _initialize()->void:
	office=Office.new()
	office._tab="contracts"
	office.name="stage3_office"
	root.add_child(office)
	office.visible=true
	office.action_requested.connect(func(k:String,p:Dictionary,r:int)->void:
		actions.append({"type":k,"payload":p,"revision":r}))
	var tr:Callable=func(key:String,arguments:Dictionary={})->String:
		return key
	office.configure(view(),tr,"ko",0)
	check(tap("office_fx_fx1"),"only a real public FX offer has an action")
	check(tap("office_pawn_redeem_p1"),"customer-announced repayment actionable")
	check(tap("office_order_deliver_o1_SELL01"),"real stock and placement create delivery action")
	check(tap("office_order_cancel_o1"),"active paid order can refund")
	check(actions.size()==4,"four independent buttons emit exactly four actions")
	if actions.size()==4:
		check(actions[0].type=="calendar_exchange" and actions[0].payload=={"quote_id":"fx1"} and actions[0].revision==42,
			"exchange uses exact public quote ID and revision")
		check(actions[1].type=="merchant_pawn_redeem" and actions[1].payload=={"contract_id":"p1"} and actions[1].revision==42,
			"pawn repayment cannot invent a new customer wallet")
		check(actions[2].type=="merchant_order_deliver" and actions[2].payload.get("item_id")=="SELL01"
			and actions[2].payload.placement=={"inventory":"buyer_grid","x":1,"y":0,"rotated":false},
			"delivery uses actual physical item and grid-fit placement")
		check(actions[3].type=="merchant_order_cancel" and actions[3].payload=={"contract_id":"o1"},
			"refund cannot substitute new terms")
	var visit:Dictionary=view()
	visit.revision=43
	visit.visits.active="pawn_visit"
	visit.merchant_contracts.pawns.p1.status="offered"
	visit.merchant_contracts.pawns.p1.repayment_offered=false
	office.configure(visit,tr,"en",0)
	check(tap("office_pawn_accept_p1"),"active genuine pawn offer can be accepted")
	check(not tap("office_order_cancel_o1"),"order actions blocked while visitor is active")
	check(tap("office_fx_fx1"),"FX button remains visible but transaction authority rejects while visitor active")
	if actions.size()==6:
		check(actions[4].type=="merchant_pawn_accept" and actions[4].payload=={"contract_id":"p1"}
			and actions[4].revision==43,"pawn visitor offer exact revision")
	office.queue_free()
	print("MERCHANT_OFFICE_UI: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
