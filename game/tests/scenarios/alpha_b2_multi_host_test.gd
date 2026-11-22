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
