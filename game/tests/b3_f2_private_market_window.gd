extends "res://tests/b3_r2_product_integration_window.gd"
## Private V2 native acceptance. Preparation uses genuine authoritative
## commands, not injected wallets/items/quotes. All post-load counter actions
## are native UI pointers. Do not register this private scene in public CI.
const F2Scene = preload("res://scenes/app/alpha_b3_f2_regional_v2.tscn")
const F2Source = preload("res://src/content/b3_spatial_week_seed.gd")
const F2Session = preload("res://src/domain/game_session.gd")
const F2Repo = preload("res://src/persistence/save_repository.gd")
const F2_SLOT := "b3_f2_regional_late_v2"
const F2_BUYER := "alpha_b3_g11_battery_d4"

func f2_command(s:RefCounted, kind:String, p:Dictionary={}) -> bool:
	var rev:int=int(s.snapshot().revision)
	var result:Dictionary=s.execute({"action_id":"f2_native_"+str(rev+1),"expected_revision":rev,"type":kind,"payload":p})
	if not result.get("ok",false): printerr("F2_SETUP ",kind," ",result)
	return bool(result.get("ok",false))

func f2_morning(s:RefCounted)->bool:
	for kind:String in ["alpha_close","alpha_settle","alpha_next_day","alpha_prepare_day","alpha_open"]:
		if not f2_command(s,kind): return false
	return true

func f2_enter(s:RefCounted,id:String)->bool:
	while int(s.alpha_view().remaining)>0:
		if not f2_command(s,"alpha_next_customer") or not f2_command(s,"alpha_ack_entry"): return false
		if s.alpha_view().active.id==id: return true
		if not f2_command(s,"alpha_finish_customer") or not f2_command(s,"alpha_ack_exit"): return false
	return false

func f2_fixture()->RefCounted:
	for seed_value:int in range(101,125):
		var src:Dictionary=F2Source.content(seed_value)
		src.alpha_profile["battery_market"]="regional_late_v2"
		var s:=F2Session.new()
		if not s.initialize(src.defs,src.state,false,false,{},src.alpha_profile): return null
		if not f2_command(s,"alpha_open") or not f2_morning(s): return null
		if not f2_enter(s,"battery_buy"): continue
		var fit:Dictionary=s.spatial_fit("BAT02","player_stock")
		if not fit.get("ok",false): return null
		if not f2_command(s,"alpha_price_offer",{"amount":40}) or not f2_command(s,"alpha_trade",{"visit_id":"battery_buy","item_id":"BAT02","seller":"G06","buyer":"player","currency":"VKC","amount":40,"inventory":"player_stock","x":fit.x,"y":fit.y,"rotated":fit.rotated}) or not f2_command(s,"alpha_ack_exit"): return null
		fit=s.spatial_fit("BAT02","storefront_grid")
		if not fit.get("ok",false) or not f2_command(s,"alpha_display",{"item_id":"BAT02","x":fit.x,"y":fit.y,"rotated":fit.rotated}): return null
		if not f2_morning(s) or not f2_morning(s): return null
		if F2_BUYER not in s.snapshot().alpha_shop.random_visits.plan: continue
		if not f2_enter(s,F2_BUYER): return null
		if int(s.alpha_view().get("customer_bid_vkc",0))>0:
			print("F2_NATIVE_SETUP_SEED ",seed_value)
			return s
	return null

func f2_install(location:String)->bool:
	host=F2Scene.instantiate()
	host.save_directory_override=location
	root.add_child(host)
	await frames()
	if not check(host.session!=null and not host._blocked and not host._intro,"private V2 cold scene resumes actual saved session"): return false
	return check(host.r2_review_mode and host.r2_layers.size()==5 and host.theme!=null and host.theme.default_font!=null and host.theme.default_font.has_char(0xD55C),"real R2 layers and Korean UI font")

func f2_counter(resolution:Vector2i,fixture:RefCounted)->bool:
	var before:Dictionary=fixture.snapshot()
	var location:String="user://zt_rebuild/f2_native_"+str(resolution.y)+"_"+str(Time.get_ticks_usec())
	var db:=F2Repo.new(location)
	if not check(db.save_session(fixture,F2_SLOT).get("ok",false),"genuine D4 purchase/display state saved to isolated slot"): return false
	if not await f2_install(location): return false
	if not check(host.session.snapshot()==before,"cold host state equals genuine command history"): return false
	var view:Dictionary=host.session.alpha_view()
	var bid:int=int(view.get("customer_bid_vkc",0))
	if not check(view.active.id==F2_BUYER and view.appraisal.item_id=="BAT02" and bid>0,"active matching physical battery and real public bid"): return false
	var speech:=host.find_child("Utterance",true,false) as Label
	if not check(speech!=null and speech.is_visible_in_tree() and ("%d VKC"%bid) in speech.text,"actual counter speech reveals only current bid"): return false
	await capture("f2_v2_counter_"+str(resolution.y),resolution)
	if not await click_navigation(host,"news"): return false
	if not check(host.drawer=="news" and host.session.snapshot()==before,"bulletin opens during actual active visit without changing authority"): return false
	await capture("f2_v2_news_"+str(resolution.y),resolution)
	if not await click_navigation(host,"close_drawer"): return false
	if not check(host.drawer.is_empty() and host.session.snapshot()==before,"return to identical counter and customer"): return false
	if not await click_navigation(host,"counter_offer"): return false
	var notice:=host.find_child("market_notice",true,false) as Label
	if not check(notice!=null and "항구 · 전지" in notice.text and "공방 구역 · 공구" in notice.text and "거래 자료 부족" in notice.text,"seven-group dated public bulletin on actual offer page"): return false
	await reveal_action("customer_bid")
	var basis:=host.find_child("customer_bid",true,false) as Button
	if not check(basis!=null and ("%d VKC"%bid) in basis.text,"explicit current customer price basis"): return false
	await capture("f2_v2_public_basis_"+str(resolution.y),resolution)
	if not await click_navigation(host,"customer_bid"): return false
	if not await click_navigation(host,"close_drawer"): return false
	var amount:=host.find_child("offer_amount",true,false) as Label
	if not check(amount!=null and amount.text==("%d VKC"%bid) and host.session.snapshot()==before,"explicit ratio basis remains read-only at 100 percent"): return false
	var selected_basis: Dictionary = host.offer_basis.duplicate(true)
	var selected_ratio: int = host.offer_ratio
	if not await click_navigation(host,"news"): return false
	if not await click_navigation(host,"close_drawer"): return false
	amount = host.find_child("offer_amount",true,false) as Label
	if not check(host.offer_basis==selected_basis and host.offer_ratio==selected_ratio and amount!=null and amount.text==("%d VKC"%bid) and host.session.snapshot()==before,"bulletin round trip retains selected offer basis, ratio, amount and authoritative state"): return false
	if not await click("offer","CUSTOMER_ACTIVE"): return false
	var agreed:Dictionary=host.session.snapshot()
	if not check(host.session.alpha_view().appraisal.accepted.get("amount")==bid and agreed.wallets==before.wallets and agreed.items==before.items and agreed.ledger==before.ledger,"real agreement does not settle assets"): return false
	await capture("f2_v2_agreed_"+str(resolution.y),resolution)
	if not await click("settle_trade","CUSTOMER_EXIT"): return false
	var paid:Dictionary=host.session.snapshot()
	if not check(paid.items.BAT02.owner_id=="G11" and paid.items.BAT02.basis.VKC==40 and paid.wallets.player.VKC==before.wallets.player.VKC+bid and paid.wallets.G11.VKC==before.wallets.G11.VKC-bid and paid.ledger.size()==before.ledger.size()+1,"one actual UI sale with real cost basis and finite balances"): return false
	if not check(not host.session.alpha_view().has("customer_bid_vkc"),"completed visit no longer projects a bid"): return false
	await capture("f2_v2_settled_"+str(resolution.y),resolution)
	if not await click("alpha_ack_exit","OPEN_IDLE"): return false
	var final:Dictionary=host.session.snapshot()
	# Use host's normal autosave path: no manual save of the result here.
	await release_host()
	if not await f2_install(location): return false
	if not check(host.session.snapshot()==final and not host.session.alpha_view().has("customer_bid_vkc"),"normal host autosave cold resume keeps paid item and idle counter"): return false
	await capture("f2_v2_resumed_"+str(resolution.y),resolution)
	return true

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1 or DirAccess.make_dir_recursive_absolute(args[0])!=OK:
		quit(2)
		return
	out=args[0]
	var fixture:RefCounted=f2_fixture()
	if check(fixture!=null,"real V2 native preparation witness"):
		for resolution:Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
			if not await configure_native_window(resolution): break
			if not await f2_counter(resolution,fixture):
				check(false,"complete V2 market native route "+str(resolution.y))
				break
			await release_host()
	await release_host()
	print("B3_F2_PRIVATE_MARKET_WINDOW: ",checks," checks, ",failures," failures")
	Node.print_orphan_nodes()
	call_deferred("quit",0 if failures==0 and checks>0 else 1)
