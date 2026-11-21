extends SceneTree
## Future Godot runtime evidence; this test is not a claim of execution.
const Scene = preload("res://scenes/app/alpha_b2_trade_slice.tscn")
var host: Control
var checks: int = 0
var failures: int = 0

func check(ok: bool, name: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", name)
	return ok

func click(name: String) -> bool:
	var b := host.find_child(name, true, false) as Button
	if not check(b != null and not b.disabled, "B2 UI " + name):
		return false
	b.pressed.emit()
	return true

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	host = Scene.instantiate()
	host.save_directory_override = "user://zt_rebuild/b2_host_" + str(Time.get_ticks_usec())
	root.add_child(host)
	await process_frame
	if not check(host.session != null and not host._blocked and host.b2_mode, "B2 host boots"):
		quit(1)
		return
	if not click("intro_skip") or not click("alpha_open") or not click("alpha_next_customer") or not click("alpha_ack_entry"):
		quit(1)
		return
	if not click("b2_trade") or not click("alpha_ack_exit") or not click("b2_display_R001"):
		quit(1)
		return
	check(host.session.snapshot().items.R001.inventory == "storefront_grid", "real item moved onto shelf")
	if not click("alpha_next_customer") or not click("alpha_ack_entry") or not click("b2_trade"):
		quit(1)
		return
	check(host.session.snapshot().wallets.player.VKC == 250 and host.session.snapshot().items.R001.owner_id == "G02", "two visitors, real sale")
	if not click("alpha_ack_exit") or not click("alpha_close") or not click("alpha_settle"):
		quit(1)
		return
	check(host.session.snapshot().ledger.size() == 2, "two receipts and no phantom settlement")
	host.queue_free()
	await process_frame
	print("ALPHA_B2_HOST_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
