extends SceneTree
## B2 physical multi-stock listing and withdrawal, original finite actors.
## Placement is a preview, authoritative moves still validate full grids.
const Seed = preload("res://src/content/alpha_b2_seed.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
var checks: int=0
var failures: int=0

func check(ok: bool, label: String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)
	return ok

func fresh() -> RefCounted:
	var data: Dictionary=Seed.content()
	var s:=Session.new()
	if data.is_empty() or not s.initialize(data.defs,data.state,false,false,{},data.alpha_profile):
		printerr("B2_SHELF_INIT: ",s.initialization_error())
		return null
	return s

func go(s: RefCounted, kind: String, p: Dictionary={}) -> bool:
	var b: Dictionary=s.snapshot()
	return bool(s.execute({"type":kind,"payload":p,"expected_revision":b.revision,"action_id":"shelf_"+str(b.revision+1)}).ok)

func deny(s: RefCounted, kind: String, p: Dictionary={}) -> bool:
	var before: Dictionary=s.snapshot()
	return not go(s,kind,p) and s.snapshot()==before

func option(options: Array, id: String) -> Dictionary:
	for entry: Dictionary in options:
		if entry.item_id == id:
			return entry
	return {}

func _initialize() -> void:
	var s: RefCounted=fresh()
	if not check(s != null,"original finite B2 trade seed initializes"):
		quit(1)
		return
	check(s.alpha_shelf_options().display.is_empty() and s.alpha_shelf_options().withdraw.is_empty(),"no display actions without actual player-owned items")
	if not check(go(s,"alpha_open") and go(s,"alpha_next_customer") and go(s,"alpha_ack_entry"),"real first G01 comes to same counter"):
		quit(1)
		return
	var radio: Dictionary={"visit_id":"visit_g01","item_id":"R001","seller":"G01","buyer":"player","currency":"VKC","amount":100,"inventory":"player_stock","x":0,"y":0,"rotated":false}
	if not check(go(s,"alpha_trade",radio) and go(s,"alpha_ack_exit"),"real R001 100 VKC buy and same-customer exit"):
		quit(1)
		return
	var open_stock: Dictionary=s.snapshot()
	var found: Dictionary=option(s.alpha_shelf_options().display,"R001")
	check(not found.is_empty() and found.x==0 and found.y==0,"first physical object previews first-fit shelf origin")
	check(s.snapshot()==open_stock,"preview never moves goods or spends funds")
	if not check(go(s,"alpha_display",{"item_id":"R001","x":found.x,"y":found.y,"rotated":found.rotated}),"list actual R001 at previewed free cell"):
		quit(1)
		return
	check(s.alpha_shelf_options().display.is_empty() and not option(s.alpha_shelf_options().withdraw,"R001").is_empty(),"listed item has withdrawal, not double-list action")
	check(go(s,"alpha_close") and go(s,"alpha_settle") and go(s,"alpha_next_day") and go(s,"alpha_prepare_day") and go(s,"alpha_open"),"D1 early close to original D2 finite market")
	check(go(s,"alpha_next_customer") and go(s,"alpha_ack_entry") and s.alpha_view().active.actor_id=="G03" and go(s,"alpha_finish_customer") and go(s,"alpha_ack_exit"),"D2 G03 actual customer skipped without fabricated commerce")
	if not check(go(s,"alpha_next_customer") and go(s,"alpha_ack_entry") and s.alpha_view().active.actor_id=="G04","G04 actually owns D2 watch"):
		quit(1)
		return
	var watch: Dictionary={"visit_id":"watch_a","item_id":"WAT02","seller":"G04","buyer":"player","currency":"VKC","amount":80,"inventory":"player_stock","x":0,"y":0,"rotated":false}
	if not check(go(s,"alpha_trade",watch) and go(s,"alpha_ack_exit"),"second real WAT02 purchase uses remaining 80 VKC and no new stock"):
		quit(1)
		return
	var original: Dictionary=s.snapshot()
	var opportunities: Dictionary=s.alpha_shelf_options()
	var watch_placement: Dictionary=option(opportunities.display,"WAT02")
	check(not watch_placement.is_empty() and not option(opportunities.withdraw,"R001").is_empty(),"second stock item and first listed item each have distinct visible actions")
	check(deny(s,"alpha_display",{"item_id":"WAT02","x":0,"y":0,"rotated":false}),"cannot place watch on top of already displayed radio")
	check(s.snapshot()==original and original.wallets.player.VKC==0 and original.ledger.size()==2,"collision rejected atomically without balance/receipt mutation")
	if not check(not watch_placement.is_empty() and go(s,"alpha_display",{"item_id":"WAT02","x":watch_placement.x,"y":watch_placement.y,"rotated":watch_placement.rotated}),"second real item fits a separate shelf cell"):
		quit(1)
		return
	var both: Dictionary=s.snapshot()
	check(both.alpha_shop.displayed.size()==2 and both.items.R001.inventory=="storefront_grid" and both.items.WAT02.inventory=="storefront_grid","multi-item shelf holds two different real item IDs")
	var withdrawal: Dictionary=option(s.alpha_shelf_options().withdraw,"R001")
	check(not withdrawal.is_empty() and option(s.alpha_shelf_options().withdraw,"WAT02")!={} and withdrawal.item_id=="R001","both listed items have valid independent re-storage choices")
	if not check(go(s,"alpha_withdraw_display",{"item_id":"R001","x":withdrawal.x,"y":withdrawal.y,"rotated":withdrawal.rotated}),"real R001 physical withdrawal from two-item shelf"):
		quit(1)
		return
	var one: Dictionary=s.snapshot()
	check(one.alpha_shop.displayed==["WAT02"] and one.items.R001.inventory=="player_stock" and one.items.WAT02.inventory=="storefront_grid","withdraw one without removing or selling other")
	check(one.ledger==both.ledger and one.wallets==both.wallets and one.items.R001.basis==both.items.R001.basis,"display/withdraw preserves cost basis, physical ownership and money")
	var relist: Dictionary=option(s.alpha_shelf_options().display,"R001")
	check(not relist.is_empty() and go(s,"alpha_display",{"item_id":"R001","x":relist.x,"y":relist.y,"rotated":relist.rotated}),"relisting uses a fresh geometric preview instead of fixed x0")
	var final_state: Dictionary=s.snapshot()
	check(final_state.items.R001.owner_id=="player" and final_state.items.WAT02.owner_id=="player" and final_state.ledger.size()==2,"relisted items remain player-owned with exactly two actual purchases")
	var repo:=Repo.new("user://zt_rebuild/b2_multi_shelf_"+str(Time.get_ticks_usec()))
	check(repo.save_session(s,"shelf").ok,"multi-shelf A/B save complete")
	var cold: RefCounted=fresh()
	check(cold!=null and repo.load_session(cold,"shelf").ok and cold.snapshot()==final_state,"multi-shelf cold restore with exact placements, no duplicate stock")
	check(cold!=null and cold.alpha_shelf_options().withdraw.size()==2,"restored session deterministically projects both physical withdrawal actions")
	print("B2_SHELF_OPTIONS_CHECKS=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
