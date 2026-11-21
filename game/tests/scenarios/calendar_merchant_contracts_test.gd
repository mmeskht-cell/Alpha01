extends SceneTree
## Paired real asset/finite-money demonstrations and cold replay:
## 1) paid pawn loan + repayment, 2) automatic forfeiture,
## 3) fully escrowed order delivery, 4) cancel/refund, 5) forged saves.
const Watch=preload("res://tests/fixtures/p2_watch_state.gd")
const Objects=preload("res://src/domain/object_schema.gd")
const Session=preload("res://src/domain/game_session.gd")
const Merchant=preload("res://src/domain/calendar_merchant_contracts.gd")
var checks:int=0
var failures:int=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func money(n:int)->Dictionary:
	return {"VKC":n,"USD":0}

func fixture()->Dictionary:
	var src:RefCounted=Watch.fresh(false)
	if src==null:
		return {}
	var s:Dictionary=src.snapshot()
	var p:Dictionary=s.calendar.profile.duplicate(true)
	s.erase("calendar")
	# Existing funded seller with real W001; a separate customer reserves
	# actual cash in a dedicated, unreachable-by-visits escrow wallet.
	s.wallets.seller.VKC=10
	s.wallets["order_buyer"]=money(150)
	s.wallets["order_escrow"]=money(0)
	s.inventories["order_buyer_grid"]={"owner_id":"order_buyer","width":4,"height":3,"host_item":""}
	s.items["SELL01"]=Objects.fresh_item("fictional_watch_p2","player","player_grid",2,0,"owned_before_order")
	p.id="campaign_42"
	p.day_ids=[]
	p.visit_days={}
	for day:int in range(1,43):
		var name:String="d"+str(day)
		p.day_ids.append(name)
		p.visit_days[name]=["watch_a","watch_b"] if day==1 else []
	p["merchant_contracts"]={"version":1,"escrow_actor":"order_escrow",
		"pawns":{"pawn_a":{"customer":"seller","visit_id":"watch_a","item_id":"W001",
			"principal":money(40),"repayment":money(45),"repayment_day":2,"due_day":2,
			"placement":{"inventory":"player_grid","x":0,"y":0,"rotated":false}}},
		"orders":{"order_a":{"customer":"order_buyer","def_id":"fictional_watch_p2",
			"price":money(100),"offer_day":1,"due_day":2}}}
	var defs:Dictionary={"fictional_watch_p2":{"def_id":"fictional_watch_p2","category":"fixture",
		"localization_key":"p2.watch.meridian12","render_key":"placeholder_none",
		"width":1,"height":1}}
	return {"seed":s,"profile":p,"defs":defs}

func cmd(s:RefCounted,kind:String,id:String,p:Dictionary={})->Dictionary:
	return s.execute({"action_id":id,"expected_revision":s.snapshot().revision,"type":kind,"payload":p})

func open(f:Dictionary)->RefCounted:
	var s:=Session.new()
	if s.initialize(f.defs,f.seed,false,false,f.profile):
		return s
	printerr("MERCHANT_INIT ",s.initialization_error())
	return null

func _initialize()->void:
	var f:Dictionary=fixture()
	check(not f.is_empty(),"real funded pawn and order fixture")
	var normalized_defs:Dictionary={"fictional_watch_p2":Objects.definition(f.defs.fictional_watch_p2)}
	check(not Merchant.seed(f.seed,normalized_defs,f.profile).is_empty(),"seed validates real item and escrow")
	var invalid:Dictionary=f.duplicate(true)
	invalid.seed.wallets.order_escrow.VKC=1
	check(Merchant.seed(invalid.seed,normalized_defs,invalid.profile).is_empty(),"no prefilled magic escrow")
	invalid=f.duplicate(true)
	invalid.profile.merchant_contracts.pawns.pawn_a.principal.VKC=-1
	check(Merchant.seed(invalid.seed,normalized_defs,invalid.profile).is_empty(),"negative loan rejected")
	invalid=f.duplicate(true)
	invalid.profile.merchant_contracts.orders.order_a.customer="unknown"
	check(Merchant.seed(invalid.seed,normalized_defs,invalid.profile).is_empty(),"unfinanced fictional order denied")
	var redeemed:RefCounted=open(f)
	var forfeited:RefCounted=open(f)
	var cancelled:RefCounted=open(f)
	check(redeemed!=null and forfeited!=null and cancelled!=null,"three independent common-GameSession profiles")
	if redeemed==null or forfeited==null or cancelled==null:
		quit(1)
		return
	for pair:Array in [[redeemed,"a"],[forfeited,"b"],[cancelled,"c"]]:
		var s:RefCounted=pair[0]
		var suf:String=pair[1]
		check(cmd(s,"calendar_next_visit","arrive_"+suf).get("ok",false),"offer visit uses real shop queue "+suf)
		check(cmd(s,"merchant_pawn_accept","loan_"+suf,{"contract_id":"pawn_a"}).get("ok",false),
			"pawn transfers custody plus actual loan "+suf)
		var state:Dictionary=s.snapshot()
		check(state.items.W001.owner_id=="seller" and state.items.W001.custodian_id=="player"
			and state.items.W001.status=="custody_pawn" and state.wallets.player.VKC==140
			and state.wallets.seller.VKC==50,"custody/loan ledger reality "+suf)
		check(not cmd(s,"merchant_pawn_accept","duplicate_loan_"+suf,{"contract_id":"pawn_a"}).get("ok",false)
			and s.snapshot()==state,"one pledge, no duplicate disbursement "+suf)
	var before_early:Dictionary=redeemed.snapshot()
	check(not cmd(redeemed,"merchant_pawn_redeem","early_repay",{"contract_id":"pawn_a"}).get("ok",false)
		and redeemed.snapshot()==before_early,
		"player cannot debit a borrower before authored repayment offer")
	check(cmd(redeemed,"merchant_order_accept","escrow_order",{"contract_id":"order_a"}).get("ok",false),
		"real buyer funds segregated escrow once")
	var a:Dictionary=redeemed.snapshot()
	check(a.wallets.order_buyer.VKC==50 and a.wallets.order_escrow.VKC==100
		and a.wallets.player.VKC==140,"no phantom prepaid sales revenue")
	check(not cmd(redeemed,"merchant_order_accept","second_order",{"contract_id":"order_a"}).get("ok",false)
		and redeemed.snapshot()==a,"duplicate order cannot collect twice")
	check(cmd(redeemed,"merchant_order_deliver","deliver_real",{"contract_id":"order_a",
		"item_id":"SELL01","placement":{"inventory":"order_buyer_grid","x":0,"y":0,
			"rotated":false}}).get("ok",false),"real owned item fulfils actual funded order")
	a=redeemed.snapshot()
	check(a.items.SELL01.owner_id=="order_buyer" and a.items.SELL01.custodian_id=="order_buyer"
		and a.items.SELL01.inventory=="order_buyer_grid" and a.wallets.player.VKC==240
		and a.wallets.order_escrow.VKC==0,"physical shipment and escrow settlement conserve money")
	check(not cmd(redeemed,"merchant_order_deliver","double_sell",{"contract_id":"order_a",
		"item_id":"SELL01","placement":{"inventory":"order_buyer_grid","x":0,"y":0,
			"rotated":false}}).get("ok",false) and redeemed.snapshot()==a,
		"same shipment cannot be invoiced twice")
	check(cmd(redeemed,"calendar_close","redeem_d1_close").get("ok",false)
		and cmd(redeemed,"calendar_morning","redeem_d2_open").get("ok",false),
		"customer offers repayment on the authored second-day window")
	check(redeemed.calendar_view().merchant_contracts.pawns.pawn_a.repayment_offered,
		"only actual customer redemption day is an actionable offer")
	check(cmd(redeemed,"merchant_pawn_redeem","redeem_a",{"contract_id":"pawn_a"}).get("ok",false),
		"repayment by customer in agreed window returns original item")
	a=redeemed.snapshot()
	check(a.items.W001.owner_id=="seller" and a.items.W001.custodian_id=="seller"
		and a.items.W001.status=="stock" and a.items.W001.inventory=="seller_grid"
		and a.wallets.player.VKC==270 and a.wallets.seller.VKC==5,
		"repayment transfers 45 after actual D1 operating cost")
	var history_order:Dictionary=redeemed.calendar_item_history("SELL01")
	check(history_order.records.size()==1 and history_order.records[0].get("contract_kind")=="order"
		and history_order.records[0].amounts.VKC==100,
		"real order sale appears in verified unified item history, never a fictitious visit")
	var pawn_entries:Array=redeemed.calendar_item_history("W001").get("contract_records",[])
	check(pawn_entries.size()==2 and pawn_entries[0].kind=="pawn_repayment"
		and pawn_entries[1].kind=="pawn_loan" and pawn_entries[1].amounts.VKC==40,
		"pledge and redemption recorded separately from purchases/sales")
	var contract_index:Array=redeemed.calendar_history_index().items
	var indexed:Dictionary={}
	for row:Dictionary in contract_index:
		indexed[row.item_id]=true
	check(indexed.has("W001") and indexed.has("SELL01"),
		"office ledger index includes real contract-only physical items")
	check(redeemed.calendar_view().merchant_contracts.pawns.pawn_a.status=="redeemed",
		"office contract projection exposes final redeem status")
	var cold:RefCounted=open(f)
	check(cold!=null and cold.restore(a) and cold.snapshot()==a,
		"pawn/order and customer redemption replay survive cold restore")
	var forged:Dictionary=a.duplicate(true)
	forged.calendar.merchant_contracts.events[0].amount.VKC+=1
	check(not cold.restore(forged) and cold.snapshot()==a,
		"counterfeit contract ledger rejected")
	check(cmd(cancelled,"merchant_order_accept","escrow_cancel",{"contract_id":"order_a"}).get("ok",false)
		and cmd(cancelled,"merchant_order_cancel","refund_cancel",{"contract_id":"order_a"}).get("ok",false),
		"order cancellation refunds exact original buyer")
	var c:Dictionary=cancelled.snapshot()
	check(c.wallets.order_buyer.VKC==150 and c.wallets.order_escrow.VKC==0
		and c.items.SELL01.owner_id=="player","cancelled buyer never receives merchandise or generates new money")
	check(cmd(forfeited,"calendar_close","day1_close").get("ok",false)
		and cmd(forfeited,"calendar_morning","day2_open").get("ok",false)
		and cmd(forfeited,"calendar_close","day2_close").get("ok",false),
		"unredeemed physical pawn reaches actual deadline")
	var b:Dictionary=forfeited.snapshot()
	check(b.items.W001.owner_id=="player" and b.items.W001.custodian_id=="player"
		and b.items.W001.status=="stock" and b.items.W001.basis.VKC==40
		and forfeited.calendar_view().merchant_contracts.pawns.pawn_a.status=="forfeited",
		"forfeit is the original asset, single loan basis, not a minted commodity")
	check(forfeited.calendar_view().merchant_contracts.orders.order_a.status=="missed",
		"unaccepted order does not issue phantom payment")
	var cold_f:RefCounted=open(f)
	check(cold_f!=null and cold_f.restore(b) and cold_f.snapshot()==b,
		"automatic deadline change fully deterministic and cold replayable")
	# Legacy pawn remains unchanged. Opt-in extension requires an authored
	# later due day, a borrower-funded fee and a new repayment window.
	var proposal:Dictionary=fixture()
	proposal.profile.merchant_contracts.pawns.pawn_a["extension_day"]=4
	proposal.profile.merchant_contracts.pawns.pawn_a["extension_repayment_day"]=3
	proposal.profile.merchant_contracts.pawns.pawn_a["extension_fee"]=money(5)
	var ex:RefCounted=open(proposal)
	check(ex!=null,"optional finite pawn amendment terms seed separately")
	if ex!=null:
		check(cmd(ex,"calendar_next_visit","ex_arrive").get("ok",false) and
			cmd(ex,"merchant_pawn_accept","ex_loan",{"contract_id":"pawn_a"}).get("ok",false),
			"real collateral loan precedes amendment")
		check(cmd(ex,"calendar_close","ex_close1").get("ok",false) and
			cmd(ex,"calendar_morning","ex_open2").get("ok",false),
			"original D2 deadline opens")
		check(ex.calendar_view().merchant_contracts.pawns.pawn_a.can_extend and
			cmd(ex,"merchant_pawn_extend","ex_extend",{"contract_id":"pawn_a"}).get("ok",false),
			"genuine authored deadline extension executed on borrower funds")
		var x:Dictionary=ex.snapshot()
		check(x.calendar.merchant_contracts.pawns.pawn_a.extended and
			x.calendar.merchant_contracts.pawns.pawn_a.effective_due_day==4 and
			x.wallets.seller.VKC==45 and x.items.W001.status=="custody_pawn",
			"extension charges five exactly without a phantom goods transfer")
		check(not cmd(ex,"merchant_pawn_extend","ex_double",{"contract_id":"pawn_a"}).get("ok",false)
			and ex.snapshot()==x,"cannot double collect real fee")
		check(cmd(ex,"calendar_close","ex_close2").get("ok",false) and
			cmd(ex,"calendar_morning","ex_open3").get("ok",false) and
			cmd(ex,"merchant_pawn_redeem","ex_repay",{"contract_id":"pawn_a"}).get("ok",false),
			"genuine D3 agreed new repayment returns original collateral")
		var now:Dictionary=ex.snapshot()
		check(now.items.W001.owner_id=="seller" and now.items.W001.custodian_id=="seller"
			and now.wallets.seller.VKC==0,
			"no invented cash, borrower pays original principal+fee+interest")
		var history:Array=ex.calendar_item_history("W001").get("contract_records",[])
		check(history.size()==3 and history[1].kind=="pawn_extension"
			and history[1].amounts.VKC==5,"signed amendment fee appears in same item ledger")
		var replay:RefCounted=open(proposal)
		check(replay!=null and replay.restore(now) and replay.snapshot()==now,
			"authoritative extension and rescheduled repayment cold replay")
		var defaulted:RefCounted=open(proposal)
		check(cmd(defaulted,"calendar_next_visit","df_arrive").get("ok",false) and
			cmd(defaulted,"merchant_pawn_accept","df_loan",{"contract_id":"pawn_a"}).get("ok",false)
			and cmd(defaulted,"calendar_close","df_close1").get("ok",false)
			and cmd(defaulted,"calendar_morning","df_open2").get("ok",false)
			and cmd(defaulted,"merchant_pawn_extend","df_extend",{"contract_id":"pawn_a"}).get("ok",false),
			"alternative real pledged path granted same extension")
		check(cmd(defaulted,"calendar_close","df_close2").get("ok",false)
			and cmd(defaulted,"calendar_morning","df_open3").get("ok",false)
			and cmd(defaulted,"calendar_close","df_close3").get("ok",false)
			and cmd(defaulted,"calendar_morning","df_open4").get("ok",false)
			and cmd(defaulted,"calendar_close","df_close4").get("ok",false),
			"unredeemed collateral forfeit on new D4 expiry, not original D2")
		check(defaulted.snapshot().items.W001.owner_id=="player" and
			defaulted.snapshot().items.W001.basis.VKC==40,
			"physical collateral becomes original principal-basis player stock")
	print("CALENDAR_MERCHANT_CONTRACTS: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
