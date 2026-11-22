extends SceneTree
## Same B2 counter and UI controller, original customers G02 and G04.
## No separate quest menus, invented funds, or virtual repair inventory.
const Scene = preload("res://scenes/app/alpha_b2_service_multi.tscn")
var host: Control
var checks: int = 0
var failures: int = 0

func check(ok: bool, name: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",name)
	return ok

func press(id: String) -> bool:
	var button := host.find_child(id,true,false) as Button
	if not check(button != null and button.is_visible_in_tree() and not button.disabled,"available B2 button "+id):
		return false
	button.pressed.emit()
	return true

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	host = Scene.instantiate()
	host.save_directory_override = "user://zt_rebuild/b2_multi_host_" + str(Time.get_ticks_usec())
	root.add_child(host)
	await process_frame
	if not check(host.session != null and not host._blocked and host._slot() == "alpha_b2_service_custody_multi_v3","independent two-owner B2 counter boots"):
		quit(1)
		return
	for action: String in ["intro_skip","alpha_open","alpha_next_customer","alpha_ack_entry","alpha_finish_customer","alpha_ack_exit","alpha_next_customer","alpha_ack_entry","b2_service_accept"]:
		if not press(action):
			quit(1)
			return
	check(host.session.snapshot().items.W001.owner_id == "G02" and host.session.snapshot().items.W001.custodian_id == "player","first customer's title retained")
	var first_custody := host.find_child("b2_board_custody",true,false) as Label
	check(first_custody!=null and first_custody.text.contains("1건") and first_custody.text.contains("상점 재고 아님"),"same counter notebook separates first customer custody from shop stock")
	var first_entry := host.find_child("b2_board_custody_W001",true,false) as Label
	check(first_entry!=null and first_entry.text.contains("G02") and first_entry.text.contains("판매 불가")
		and host.find_child("b2_board_custody_W002S",true,false)==null,"notebook names actual first owner without inventing an unaccepted second object")
	for action: String in ["alpha_finish_customer","alpha_ack_exit","alpha_close","alpha_settle","b2_service_repair","alpha_next_day","alpha_prepare_day","alpha_open"]:
		if not press(action):
			quit(1)
			return
	for action: String in ["alpha_next_customer","alpha_ack_entry","alpha_finish_customer","alpha_ack_exit","alpha_next_customer","alpha_ack_entry"]:
		if not press(action):
			quit(1)
			return
	check(host.session.alpha_view().active.actor_id == "G04","G04's original D2 counter is reused for job2")
	check(host.find_child("b2_service_status_service_w001",true,false) == null and host.find_child("b2_service_status_service_w002s",true,false) != null,"customer sees only their own service consent at shared counter")
	if not press("b2_service_accept"):
		quit(1)
		return
	var held: Dictionary = host.session.snapshot()
	check(held.items.W001.owner_id == "G02" and held.items.W002S.owner_id == "G04" and held.items.W001.inventory == "service_grid" and held.items.W002S.inventory == "service_grid" and held.items.W001.y != held.items.W002S.y,"two separately held customer objects without phantom ownership")
	check(held.wallets.player.VKC == 170 and held.ledger.is_empty(),"second acceptance does not create cash or retail sale")
	var both_custody := host.find_child("b2_board_custody",true,false) as Label
	check(both_custody!=null and both_custody.text.contains("2건"),"second separately owned custody item is counted without becoming storefront inventory")
	var owner_one := host.find_child("b2_board_custody_W001",true,false) as Label
	var owner_two := host.find_child("b2_board_custody_W002S",true,false) as Label
	check(owner_one!=null and owner_two!=null and owner_one.text.contains("G02") and owner_two.text.contains("G04")
		and owner_one.text.contains("판매 불가") and owner_two.text.contains("판매 불가"),"separate customer owner rows remain attached to the two real held objects")
	check(host.find_child("b2_display_W001",true,false)==null and host.find_child("b2_display_W002S",true,false)==null,"customer property never receives player-shelf listing buttons")
	for action: String in ["alpha_finish_customer","alpha_ack_exit","alpha_close","alpha_settle","b2_service_repair"]:
		if not press(action):
			quit(1)
			return
	check(host.session.snapshot().wallets.player.VKC == 160 and host.session.snapshot().items.W002S.functional,"second real workshop charge only for W002S")
	for action: String in ["alpha_next_day","alpha_prepare_day","alpha_open"]:
		if not press(action):
			quit(1)
			return
	for actor: String in ["G08","G09","G10","G11","G02","G04"]:
		for action: String in ["alpha_next_customer","alpha_ack_entry"]:
			if not press(action):
				quit(1)
				return
		check(host.session.alpha_view().active.actor_id == actor,"finite D3 visitor "+actor)
		if actor in ["G02","G04"]:
			check(host.find_child("b2_service_deliver",true,false) != null,"only current customer can collect actual work")
			if not press("b2_service_deliver") or not press("alpha_ack_exit"):
				quit(1)
				return
			# Refresh must follow actual title return, not the earlier custody tally.
			var remaining_custody := host.find_child("b2_board_custody",true,false) as Label
			var held_g02 := host.find_child("b2_board_custody_W001",true,false) as Label
			var held_g04 := host.find_child("b2_board_custody_W002S",true,false) as Label
			if actor == "G02":
				check(remaining_custody!=null and remaining_custody.text.contains("1건")
					and held_g02==null and held_g04!=null and held_g04.text.contains("G04"),
					"after G02 real return, only G04 customer title remains in shop notebook")
			else:
				check(remaining_custody==null and held_g02==null and held_g04==null,
					"after both real returns, no customer property remains in shop notebook")
		elif not press("alpha_finish_customer") or not press("alpha_ack_exit"):
			quit(1)
			return
	var result: Dictionary = host.session.snapshot()
	check(result.wallets.player.VKC == 230 and result.alpha_shop.services.settlements.size() == 2 and result.ledger.is_empty(),"real 30+40 service receipts minus two work costs")
	check(result.items.W001.owner_id == "G02" and result.items.W001.custodian_id == "G02" and result.items.W002S.owner_id == "G04" and result.items.W002S.custodian_id == "G04","both physical owners receive exactly their own object")
	host.queue_free()
	await process_frame
	print("ALPHA_B2_MULTI_HOST_CHECKS=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
