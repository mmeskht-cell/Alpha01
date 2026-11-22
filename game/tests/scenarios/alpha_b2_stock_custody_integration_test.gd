extends SceneTree
## Integrated B2 shelf / accepted commission / two distinct customer custody
## objects on the real source seed. No fixture mint or new story commitment.
const Multi = preload("res://src/content/alpha_b2_service_multi_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
	return ok

func new_session() -> RefCounted:
	var src: Dictionary = Multi.content()
	var s := Session.new()
	if src.is_empty() or not s.initialize(src.defs,src.state,false,false,{},src.alpha_profile):
		printerr("B2_STOCK_CUSTODY_INIT: ",s.initialization_error())
		return null
	return s

func go(s: RefCounted, kind: String, payload: Dictionary={}) -> bool:
	var before: Dictionary=s.snapshot()
	var result: Dictionary=s.execute({"action_id":"cross_"+str(before.revision+1),"expected_revision":before.revision,"type":kind,"payload":payload})
	if not result.ok:
		printerr("B2_STOCK_CUSTODY_ACTION: ",kind," -> ",result)
	return bool(result.ok)

func deny(s: RefCounted, kind: String, payload: Dictionary={}) -> bool:
	var before: Dictionary=s.snapshot()
	var result: Dictionary=s.execute({"action_id":"cross_"+str(before.revision+1),"expected_revision":before.revision,"type":kind,"payload":payload})
	return not result.ok and s.snapshot()==before

func active(s: RefCounted, actor: String) -> bool:
	return go(s,"alpha_next_customer") and go(s,"alpha_ack_entry") and s.alpha_view().active.actor_id==actor

func leave(s: RefCounted) -> bool:
	return go(s,"alpha_finish_customer") and go(s,"alpha_ack_exit")

func next_open(s: RefCounted) -> bool:
	return go(s,"alpha_close") and go(s,"alpha_settle") and go(s,"alpha_next_day") and go(s,"alpha_prepare_day") and go(s,"alpha_open")

func find(options: Array, item_id: String) -> Dictionary:
	for option: Dictionary in options:
		if option.item_id==item_id:
			return option
	return {}

func display(s: RefCounted, p: Dictionary, withdrawal: bool=false) -> bool:
	return not p.is_empty() and go(s,"alpha_withdraw_display" if withdrawal else "alpha_display",
		{"item_id":p.item_id,"x":p.x,"y":p.y,"rotated":p.rotated})

func _initialize() -> void:
	var src: Dictionary=Multi.content()
	var s: RefCounted=new_session()
	if not check(s!=null and not src.is_empty(),"source-unchanged real multi-service and dual commission profile"):
		quit(1)
		return
	var original: Dictionary=s.snapshot()
	check(original.items.W001.owner_id=="G02" and original.items.W002S.owner_id=="G04"
		and original.items.TL04.owner_id=="G01" and original.items.R001.owner_id=="G01","all four specimens are actual finite actor-owned goods")
	if not check(go(s,"alpha_open") and active(s,"G01"),"D1 G01 original first shop visit"):
		quit(1)
		return
	# The same published wear inspection/counter price path used by B2 cards.
	var radio: Dictionary={"visit_id":"visit_g01","item_id":"R001","seller":"G01","buyer":"player",
		"currency":"VKC","amount":95,"inventory":"player_stock","x":0,"y":0,"rotated":false}
	if not check(go(s,"alpha_inspect",{"slot":"wear_detail"})
		and go(s,"alpha_card_toggle",{"slot":"wear_detail","selected":true})
		and go(s,"alpha_price_offer",{"amount":95})
		and go(s,"alpha_trade",radio) and go(s,"alpha_ack_exit"),"G01 actually sells R001 for agreed 95 VKC, not starter stock"):
		quit(1)
		return
	var shelf: Dictionary=find(s.alpha_shelf_options().display,"R001")
	if not check(display(s,shelf),"move real radio to physical shop shelf before customer custody"):
		quit(1)
		return
	if not check(active(s,"G02") and go(s,"alpha_service_accept",{"job_id":"service_w001"}),"G02 actually entrusts W001 without transferring title"):
		quit(1)
		return
	var first: Dictionary=s.snapshot()
	check(first.items.W001.owner_id=="G02" and first.items.W001.custodian_id=="player"
		and find(s.alpha_shelf_options().withdraw,"W001").is_empty(),"customer-held W001 cannot be withdrawn as player stock")
	check(deny(s,"alpha_display",{"item_id":"W001","x":1,"y":0,"rotated":false}),"forged public listing of G02 customer-owned W001 denied with rollback")
	if not check(leave(s) and active(s,"G03") and go(s,"alpha_commission_accept",{"request_id":"tool_for_g03"}),"real G03 offer accepted with no advance"):
		quit(1)
		return
	check(s.snapshot().alpha_shop.commissions.entries.tool_for_g03.status=="accepted"
		and s.snapshot().wallets.player.VKC==85,"G03 acceptance neither creates commission stock nor transfer income")
	if not check(leave(s) and next_open(s),"D1 closes after two genuine obligations and D2 opens"):
		quit(1)
		return
	if not check(active(s,"G03") and leave(s) and active(s,"G04") and go(s,"alpha_service_accept",{"job_id":"service_w002s"}),"D2 G04 actually entrusts distinct W002S item"):
		quit(1)
		return
	var held: Dictionary=s.snapshot()
	check(held.items.W001.owner_id=="G02" and held.items.W002S.owner_id=="G04"
		and held.items.W001.inventory=="service_grid" and held.items.W002S.inventory=="service_grid"
		and held.items.W001.y != held.items.W002S.y and held.alpha_shop.displayed==["R001"],
		"two customer assets in distinct custody slots coexist with the real listed shop radio")
	check(find(s.alpha_shelf_options().display,"W001").is_empty() and find(s.alpha_shelf_options().display,"W002S").is_empty()
		and find(s.alpha_shelf_options().withdraw,"R001").item_id=="R001",
		"read-only shelf options exclude two entrusted assets but retain owner-stock withdrawal")
	check(deny(s,"alpha_display",{"item_id":"W002S","x":2,"y":0,"rotated":false})
		and deny(s,"alpha_withdraw_display",{"item_id":"W001","x":0,"y":0,"rotated":false}),
		"direct display/withdraw commands cannot steal customer-held goods")
	if not check(leave(s) and next_open(s) and next_open(s),"D2 and D3 settle unattended returns without silent title transfer; D4 open"):
		quit(1)
		return
	var overdue: Dictionary=s.snapshot()
	check(overdue.alpha_shop.services.jobs.service_w001.status=="overdue_custody"
		and overdue.alpha_shop.services.jobs.service_w002s.status=="overdue_custody"
		and overdue.items.W001.owner_id=="G02" and overdue.items.W002S.owner_id=="G04"
		and overdue.alpha_shop.services.settlements.is_empty(),"missed service pickups preserve both owners, no fictitious fees")
	if not check(active(s,"G12") and leave(s) and active(s,"G01"),"D4 original G01 tool seller, no synthetic procurement"):
		quit(1)
		return
	var tool: Dictionary={"visit_id":"tool_buy","item_id":"TL04","seller":"G01","buyer":"player",
		"currency":"VKC","amount":60,"inventory":"player_stock","x":0,"y":0,"rotated":false}
	if not check(go(s,"alpha_price_offer",{"amount":60}) and go(s,"alpha_trade",tool) and go(s,"alpha_ack_exit"),"real TL04 purchased for 60 VKC while custody remains unchanged"):
		quit(1)
		return
	var options: Dictionary=s.alpha_shelf_options()
	var tool_fit: Dictionary=find(options.display,"TL04")
	check(not tool_fit.is_empty() and not find(options.withdraw,"R001").is_empty()
		and find(options.display,"W001").is_empty() and find(options.display,"W002S").is_empty(),
		"free acquired TL04 can list; both customer custody objects remain non-sellable")
	if not check(display(s,tool_fit),"temporarily list newly owned TL04 on multi-item shelf"):
		quit(1)
		return
	check(deny(s,"alpha_commission_reserve",{"request_id":"tool_for_g03","item_id":"TL04"}),
		"accepted G03 obligation cannot secretly reserve a currently displayed retail item")
	var unlist: Dictionary=find(s.alpha_shelf_options().withdraw,"TL04")
	if not check(display(s,unlist,true),"physically withdraw TL04 before earmarking for G03"):
		quit(1)
		return
	if not check(go(s,"alpha_commission_reserve",{"request_id":"tool_for_g03","item_id":"TL04"}),"reserve only genuine player-owned TL04 after free-stock withdrawal"):
		quit(1)
		return
	var reserved: Dictionary=s.snapshot()
	check(reserved.items.TL04.reservation_id=="tool_for_g03" and reserved.items.TL04.inventory=="player_stock"
		and reserved.items.R001.inventory=="storefront_grid" and reserved.items.W001.custodian_id=="player"
		and reserved.items.W002S.custodian_id=="player","one reserved, one listed, two customer-held physical goods coexist without copies")
	check(find(s.alpha_shelf_options().display,"TL04").is_empty()
		and not find(s.alpha_shelf_options().withdraw,"R001").is_empty(),
		"reserved contract stock is removed from public display options but unrelated radio remains removable")
	check(deny(s,"alpha_display",{"item_id":"TL04","x":2,"y":0,"rotated":false})
		and deny(s,"alpha_withdraw_display",{"item_id":"TL04","x":0,"y":0,"rotated":false}),
		"malicious direct shelf commands cannot bypass reservation or claim reserved item is listed")
	if not check(active(s,"G04"),"original D4 G04 attempted retail buyer is present"):
		quit(1)
		return
	var spoof: Dictionary={"visit_id":"tool_sale","item_id":"TL04","seller":"player","buyer":"G04",
		"currency":"VKC","amount":95,"inventory":"G04_grid","x":5,"y":4,"rotated":false}
	check(deny(s,"alpha_trade",spoof),"reserved TL04 cannot be sold to different ordinary customer despite actual D4 buyer")
	if not check(leave(s),"real G04 leaves without buying reserved tool"):
		quit(1)
		return
	var before_cancel: Dictionary=s.snapshot()
	check(deny(s,"alpha_close"),"pending G03 pickup prevents discarding promised appointment by early close")
	if not check(go(s,"alpha_commission_cancel",{"request_id":"tool_for_g03"}),"explicitly cancel unfulfilled order with physical reservation release"):
		quit(1)
		return
	var after_cancel: Dictionary=s.snapshot()
	check(after_cancel.items.TL04.reservation_id.is_empty() and find(s.alpha_shelf_options().display,"TL04")!={}
		and after_cancel.wallets==before_cancel.wallets and after_cancel.ledger==before_cancel.ledger,
		"only cancelled item returns to shelf choices; no refund/fee or provenance mutation")
	check(find(s.alpha_shelf_options().display,"W001").is_empty() and find(s.alpha_shelf_options().display,"W002S").is_empty(),
		"customer custody never leaks into freely listed inventory after unrelated commission cancellation")
	var storage:=Repo.new("user://zt_rebuild/b2_integrated_stock_custody_"+str(Time.get_ticks_usec()))
	check(storage.save_session(s,"cross").ok,"cross-system real ownership A/B save")
	var cold: RefCounted=new_session()
	check(cold!=null and storage.load_session(cold,"cross").ok and cold.snapshot()==after_cancel,
		"cross-system reservation release / custody / shelf cold restore byte-identical")
	check(cold!=null and cold.alpha_shelf_options()==s.alpha_shelf_options(),
		"restored client recomputes the same read-only shelf actions")
	print("B2_STOCK_CUSTODY_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
