extends SceneTree
## Exercise actual host controls; headless signals, not a human/device acceptance.
const Scene=preload("res://scenes/app/demo7.tscn")
const Runtime=preload("res://src/application/demo7_runtime.gd")
const Repo=preload("res://src/persistence/checkpoint_repository.gd")
const Seed=preload("res://src/content/demo7_seed.gd")
var checks:int=0
var failures:int=0
var host:Control

func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)
	return ok

func click(id:String)->bool:
	var b:=host.find_child(id,true,false) as Button
	if not check(is_instance_valid(b) and not b.disabled,"button "+id):
		return false
	b.pressed.emit()
	return true

func amount(value:int)->bool:
	var spin:=host.find_child("price_offer_amount",true,false) as SpinBox
	if not check(is_instance_valid(spin) and spin.editable,"price control"):
		return false
	spin.value=value
	return click("price_offer_blank")

func _initialize()->void:
	run.call_deferred()

func run()->void:
	host=Scene.instantiate()
	host.save_directory_override="user://zt_rebuild/demo7/host_"+str(Time.get_ticks_usec())
	root.add_child(host)
	await process_frame
	if not check(host.runtime!=null and not host.runtime.blocked,"new host ready"):
		quit(1)
		return
	var before:Dictionary=host.runtime.snapshot()
	if not click("intro_skip"):
		quit(1)
		return
	check(host.runtime.snapshot()==before,"intro skip no changes")
	var pack_name:String="host_pack_"+str(Time.get_ticks_usec())+".json"
	DirAccess.make_dir_recursive_absolute("user://localization")
	var pack_file:=FileAccess.open("user://localization/"+pack_name,FileAccess.WRITE)
	if not check(pack_file!=null,"isolated host pack fixture"):
		quit(1)
		return
	pack_file.store_string(JSON.stringify({"format_version":1,"content_version":"0.1.0","locale":"en","author":"Test","strings":{"review.basic.open":"Test basic appraisal"}}))
	pack_file.close()
	if not click("language_pack_toggle"):
		quit(1)
		return
	var pack_input:=host.find_child("language_pack_filename",true,false) as LineEdit
	pack_input.text=pack_name
	if not click("language_pack_apply"):
		quit(1)
		return
	check(host.runtime.localization.text("review.basic.open")=="Test basic appraisal" and host.runtime.snapshot()==before,"production language pack applied without domain mutation")
	if not click("language_pack_toggle") or not click("language_pack_clear"):
		quit(1)
		return
	check(host.runtime.localization.current_locale()=="ko" and host.runtime.snapshot()==before,"official language restored without domain mutation")
	DirAccess.remove_absolute("user://localization/"+pack_name)
	if not click("language_pack_toggle"):
		quit(1)
		return
	var volume:=host.find_child("audio_level_music",true,false) as HSlider
	var motion:=host.find_child("motion_toggle",true,false) as CheckButton
	if not check(volume!=null and motion!=null,"settings controls"):
		quit(1)
		return
	volume.value=37
	motion.button_pressed=false
	if not click("language_pack_cancel"):
		quit(1)
		return
	var settings:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(host.save_directory_override.path_join("ui_preferences.json")))
	check(settings.levels.music==37 and not settings.motion and host._feedback_audio.level("music")==37 and not host._feedback_audio.motion_enabled and host.runtime.snapshot()==before,"audio and motion apply and persist without domain change")
	check(ProjectSettings.get_setting("application/run/main_scene")=="res://scenes/app/main_menu.tscn","default scene points to actual menu")
	if not click("language_toggle") or not click("font_toggle") or not click("stock_toggle"):
		quit(1)
		return
	check(host.runtime.snapshot()==before and host.find_child("grid_player_stock",true,false).get_child_count()==60,"preferences and actual grid are read only")
	if not click("stock_toggle") or not click("language_toggle"):
		quit(1)
		return
	if not click("contract_accept") or not click("next_customer") or not click("workspace_toggle") or not amount(100):
		quit(1)
		return
	check(host.runtime.view().appraisal.price_offer.accepted_offer_id==null,"bare low price refused")
	if not amount(110) or not click("place_player_stock_0_0") or not click("confirm_checkout"):
		quit(1)
		return
	check(host.runtime.view().wallet.VKC==70 and host.runtime.snapshot().items.R001.owner_id=="player","paid negotiated amount")
	if not click("next_customer") or not click("decline") or not click("next_customer") or not click("settle_trade") or not click("next_customer") or not click("accept_service") or not click("close_day") or not click("work_W001"):
		quit(1)
		return
	check(host.runtime.view().wallet.VKC==180,"actual wholesale branch with no appraisal discount")
	if not click("next_day"):
		quit(1)
		return
	# Forego all later transactions: no invented income, overdue contract and
	# clinic effect, no G02 return on the different owner. No full campaign test.
	var default_count:int=0
	for day:int in range(2,7):
		var pending:Dictionary=host.runtime.snapshot()
		var contract:Dictionary=pending.calendar.contracts.rows.rad1_first
		if contract.status=="reserved" and int(contract.due_day)==day:
			var pay:=host.find_child("close_day",true,false) as Button
			if not check(is_instance_valid(pay) and pay.disabled,"due payment unavailable after overhead") or not check(host.runtime.snapshot()==pending,"closing choices do not mutate state"):
				quit(1)
				return
			if not click("close_day_without_payment"):
				quit(1)
				return
			var closed:Dictionary=host.runtime.snapshot()
			check(closed.calendar.contracts.rows.rad1_first.status=="defaulted" and closed.calendar.contracts.supplies.rad1_supply_1.status=="available","explicit default releases reservation")
			check(closed.wallets.player.VKC==pending.wallets.player.VKC-15 and closed.wallets.player.USD==pending.wallets.player.USD,"default charges only normal overhead")
			default_count+=1
		else:
			if not check(host.find_child("close_day_without_payment",true,false)==null,"no default choice outside due close") or not click("close_day"):
				quit(1)
				return
		if not click("next_day"):
			quit(1)
			return
	check(default_count==1,"one explicit due default")
	var state:Dictionary=host.runtime.snapshot()
	check(state.items.R001.owner_id=="G03" and not state.visits.has("radio_return") and not state.calendar.dormant.has("R001"),"no forced radio return")
	check(state.calendar.contracts.rows.rad1_first.status=="defaulted","actual insufficient funds default")
	check(host.runtime.view().world_news.news.size()==1 and host.runtime.view().world_news.news[0].cause_refs.size()==1 and not state.calendar.reaction.links.has("clinic_service"),"declined clinic path no positive reaction")
	var slot:=host.find_child("save_slot",true,false) as OptionButton
	slot.select(1)
	if not click("open_slot"):
		quit(1)
		return
	check(host.runtime.snapshot().revision==0 and host.runtime.view().wallet.VKC==180,"separate new game slot")
	slot.select(0)
	if not click("open_slot"):
		quit(1)
		return
	check(host.runtime.snapshot()==state,"resume original slot without overwrite")
	root.remove_child(host)
	host.queue_free()
	await process_frame
	_recovery()
	print("GATE2_DEMO_HOST: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)

func _recovery()->void:
	var dir:String="user://zt_rebuild/demo7/recovery_"+str(Time.get_ticks_usec())
	var r:=Runtime.new()
	if not check(r.open(dir),"fresh recovery runtime"):
		return
	if not check(r.submit("calendar_accept_contract",{"contract_id":"rad1_first"},0).get("persisted",false),"recovery previous generation"):
		r.close()
		return
	var before:Dictionary=r.snapshot()
	if not check(r.submit("calendar_next_visit",{},int(before.revision)).get("persisted",false),"recovery newest generation"):
		r.close()
		return
	var repo:=Repo.new(dir)
	var latest:Dictionary=repo.load_state(Runtime.SLOT,Seed.fresh)
	if not check(latest.ok and latest.state==r.snapshot(),"recoverable A/B pair"):
		r.close()
		return
	r.close()
	var path:String=dir.path_join(Runtime.SLOT+".v4."+latest.generation+".json")
	var damaged:=FileAccess.open(path,FileAccess.WRITE)
	if not check(damaged!=null,"damage isolated test file"):
		return
	damaged.store_string("invalid-test-generation")
	damaged.close()
	var reopened:=Runtime.new()
	if check(reopened.open(dir) and not reopened.blocked,"fallback opens"):
		check(reopened.snapshot()==before,"fallback is exact prior state")
		check(reopened.submit("calendar_next_visit",{},int(before.revision)).get("persisted",false),"continue after recovery")
		check(repo.load_state(Runtime.SLOT,Seed.fresh).get("state",{})==reopened.snapshot(),"recovered and saved exact")
	reopened.close()
