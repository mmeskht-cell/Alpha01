extends SceneTree
const Scene = preload("res://scenes/app/alpha_b1.tscn")
var checks: int = 0
var failures: int = 0
var host: Control

func check(ok: bool, name: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", name)
	return ok

func click(name: String) -> bool:
	var button := host.find_child(name, true, false) as Button
	if not check(button != null and not button.disabled, "B1 control " + name):
		return false
	button.pressed.emit()
	return true

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	host = Scene.instantiate()
	host.save_directory_override = "user://zt_rebuild/alpha_b1_host_" + str(Time.get_ticks_usec())
	root.add_child(host)
	await process_frame
	if not check(host.session != null and not host._blocked, "B1 host boots"):
		quit(1)
		return
	var first: Dictionary = host.session.snapshot()
	check(host._intro, "intro initially visible")
	if not click("intro_skip"):
		quit(1)
		return
	check(host.session.snapshot() == first, "skip has no domain effects")
	if not click("alpha_open") or not click("alpha_next_customer") or not click("alpha_ack_entry"):
		quit(1)
		return
	check(host.find_child("alpha_speech", true, false) != null, "unified Korean bubble")
	if not click("alpha_exchange_contact") or not click("alpha_finish_customer") or not click("alpha_ack_exit") or not click("alpha_close") or not click("alpha_settle"):
		quit(1)
		return
	check(host.session.snapshot().alpha_shop.phase == "EVENING_WORK" and host.session.snapshot().alpha_shop.contacts.has("G01"), "contact in evening only")
	if not click("alpha_next_day") or not click("alpha_prepare_day"):
		quit(1)
		return
	check(host.session.snapshot().alpha_shop.day == 2, "real day 2")
	var next_host: Control = Scene.instantiate()
	next_host.save_directory_override = "user://zt_rebuild/alpha_b1_host_finish_" + str(Time.get_ticks_usec())
	root.add_child(next_host)
	await process_frame
	check(next_host._intro, "independent new game intro")
	next_host.intro_next()
	next_host.intro_next()
	check(not next_host._intro and next_host.session.snapshot() == first, "intro fully viewed has identical Day1")
	next_host.queue_free()
	host.queue_free()
	await process_frame
	print("ALPHA_B1_HOST_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
