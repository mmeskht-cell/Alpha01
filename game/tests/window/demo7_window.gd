extends SceneTree
## Bounded actual default scene and real pointer test; not a human/device test.
var host:Control
var out:String
var checks:int=0
var failures:int=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)
	return ok

func frames()->void:
	await process_frame
	await process_frame
	await process_frame

func click(id:String)->bool:
	var node:=host.find_child(id,true,false) as Button
	if not check(node!=null and node.is_visible_in_tree() and not node.disabled,"visible pointer target "+id):
		return false
	var parent:Node=node.get_parent()
	while parent!=null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(node)
		parent=parent.get_parent()
	await frames()
	var point:Vector2=node.get_global_transform_with_canvas()* (node.size*0.5)
	if not check(root.get_visible_rect().has_point(point),"pointer inside viewport "+id):
		return false
	for down:bool in [true,false]:
		var e:=InputEventMouseButton.new()
		e.button_index=MOUSE_BUTTON_LEFT
		e.pressed=down
		e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
		e.position=point
		e.global_position=point
		root.push_input(e,true)
	await frames()
	return true

func capture(id:String)->void:
	await frames()
	await RenderingServer.frame_post_draw
	var img:Image=root.get_texture().get_image()
	check(img!=null and not img.is_empty() and img.save_png(out.path_join(id+".png"))==OK,"capture "+id)

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(2)
		return
	out=args[0]
	root.size=Vector2i(1280,720)
	var path:String=ProjectSettings.get_setting("application/run/main_scene")
	if not check(path=="res://scenes/app/main_menu.tscn","actual default menu"):
		quit(1)
		return
	var compatibility_path := "res://scenes/app/legacy_development_menu.tscn"
	if not check(ResourceLoader.exists(compatibility_path),"legacy slot and settings route stays available for development"):
		quit(1)
		return
	var shell:Control=(load(compatibility_path) as PackedScene).instantiate()
	shell.save_directory_override="user://zt_rebuild/demo7/menu_window_"+str(Time.get_ticks_usec())
	host=shell
	root.add_child(shell)
	await frames()
	if not check(shell.game!=null and shell.menu.visible and not shell.game.visible,"menu starts before entering shop"):
		quit(1)
		return
	var menu_before:Dictionary=shell.game.runtime.snapshot()
	await capture("menu-street-ko")
	for dimensions:Vector2i in [Vector2i(960,720),Vector2i(1280,800)]:
		root.size=dimensions
		await frames()
		verify_menu_bounds(shell)
		await capture("menu-responsive-"+str(dimensions.x)+"x"+str(dimensions.y))
	root.size=Vector2i(1280,720)
	await frames()
	if not await click("menu_settings"):
		quit(1)
		return
	check(shell.game._pack_panel.is_visible_in_tree() and not shell.game._gameplay_margin.is_visible_in_tree(),"separate settings screen")
	verify_settings_bounds(shell.game,"general",["language_toggle","font_toggle","sound_toggle"])
	await capture("menu-settings-ko")
	if not await click("settings_category_audio"):
		quit(1)
		return
	verify_settings_bounds(shell.game,"audio",["audio_level_music","audio_level_ambience","audio_level_sfx","audio_level_ui","motion_toggle"])
	await capture("menu-settings-audio-ko")
	if not await click("settings_category_pack"):
		quit(1)
		return
	verify_settings_bounds(shell.game,"pack",["language_pack_filename","language_pack_apply","language_pack_clear"])
	await capture("menu-settings-pack-ko")
	if not await click("settings_category_general") or not await click("language_toggle") or not await click("font_toggle") or not await click("font_toggle"):
		quit(1)
		return
	root.size=Vector2i(960,720)
	await frames()
	verify_settings_bounds(shell.game,"general",["language_toggle","font_toggle","sound_toggle"])
	await capture("menu-settings-general-150-en")
	if not await click("settings_category_audio"):
		quit(1)
		return
	verify_settings_bounds(shell.game,"audio",["audio_level_music","audio_level_ambience","audio_level_sfx","audio_level_ui","motion_toggle"])
	if not await click("settings_category_pack"):
		quit(1)
		return
	verify_settings_bounds(shell.game,"pack",["language_pack_filename","language_pack_apply","language_pack_clear"])
	if not await click("settings_category_general") or not await click("font_toggle"):
		quit(1)
		return
	root.size=Vector2i(1280,720)
	await frames()
	if not check(shell.game.runtime.snapshot()==menu_before,"category navigation and font changes preserve game"):
		quit(1)
		return
	check(shell.game.runtime.snapshot()==menu_before and shell.game.runtime.localization.current_locale()=="en","menu settings do not change campaign")
	if not await click("language_pack_cancel"):
		quit(1)
		return
	check(shell.menu.visible and not shell.game.visible,"back to title")
	await capture("menu-street-en")
	if not await click("menu_new"):
		quit(1)
		return
	check(shell.game.visible and not shell.menu.visible and shell.game.runtime.snapshot()==menu_before,"new empty slot enters actual candidate")
	if not await click("return_main_menu"):
		quit(1)
		return
	check(shell.menu.visible and shell.game.runtime.snapshot()==menu_before,"back preserves session")
	if not await click("menu_new") or not await click("intro_skip") or not await click("next_customer"):
		quit(1)
		return
	var saved:Dictionary=shell.game.runtime.snapshot()
	check(saved.revision>0 and not shell.game.runtime.pending,"real first action stored")
	if not await click("return_main_menu") or not await click("menu_continue"):
		quit(1)
		return
	check(shell.game.visible and shell.game.runtime.snapshot()==saved,"continue restores same saved session")
	if not await click("return_main_menu") or not await click("menu_new"):
		quit(1)
		return
	check(shell.game._slot_index==1 and shell.game.runtime.snapshot().revision==0,"new game chooses empty slot without replacing save")
	if not await click("return_main_menu") or not await click("menu_load"):
		quit(1)
		return
	await capture("menu-load-en")
	if not await click("menu_slot_1"):
		quit(1)
		return
	check(shell.game._slot_index==0 and shell.game.runtime.snapshot()==saved,"load existing slot preserves authority")
	shell.game._feedback_audio.shutdown_audio()
	root.remove_child(shell)
	shell.queue_free()
	await frames()
	# Keep the existing legacy host regression route intact.
	host=preload("res://scenes/app/demo7.tscn").instantiate()
	host.save_directory_override="user://zt_rebuild/demo7/window_"+str(Time.get_ticks_usec())
	root.add_child(host)
	await frames()
	if not check(host.runtime!=null and not host.runtime.blocked,"actual runtime"):
		quit(1)
		return
	var pristine:Dictionary=host.runtime.snapshot()
	await capture("demo-intro-ko")
	if not await click("intro_skip"):
		quit(1)
		return
	check(host.runtime.snapshot()==pristine,"skip is presentation only")
	if not await click("next_customer"):
		quit(1)
		return
	check(host.runtime.view().visits.active=="visit_g01","real admitted visitor")
	if not await click("tool_wear_detail"):
		quit(1)
		return
	check(host.runtime.view().minute==5,"real observation time")
	await capture("demo-appraisal-ko")
	var snapshot:Dictionary=host.runtime.snapshot()
	if not await click("workspace_toggle"):
		quit(1)
		return
	check(host.runtime.snapshot()==snapshot and host.find_child("price_offer_amount",true,false).is_visible_in_tree(),"customer perspective no state change")
	await capture("demo-customer-ko")
	if not await click("workspace_toggle"):
		quit(1)
		return
	if not await click("language_toggle"):
		quit(1)
		return
	check(host.runtime.snapshot()==snapshot and host.runtime.localization.current_locale()=="en","language no world mutation")
	await capture("demo-appraisal-en")
	for i:int in range(10):
		var key:=InputEventKey.new()
		key.keycode=KEY_SPACE
		key.pressed=true
		root.push_input(key,true)
		key=InputEventKey.new()
		key.keycode=KEY_SPACE
		key.pressed=false
		root.push_input(key,true)
		await frames()
	check(host.runtime.snapshot()==snapshot and host.find_child("tool_wear_detail",true,false)!=null,"ten SPACE switches preserve authority and perspective")
	root.content_scale_size=Vector2i(900,720)
	root.size=Vector2i(900,720)
	await frames()
	if check(host.find_child("workspace_toggle",true,false).is_visible_in_tree(),"compact workspace switch"):
		if not await click("workspace_toggle"):
			quit(1)
			return
		check(host.runtime.snapshot()==snapshot,"compact view no world mutation")
		await capture("demo-compact-counter")
	if not await click("stock_toggle"):
		quit(1)
		return
	check(host.runtime.snapshot()==snapshot and host.find_child("grid_player_stock",true,false).get_child_count()==60,"stock public geometry")
	await capture("demo-stock-compact")
	if not await click("history_toggle"):
		quit(1)
		return
	check(host.runtime.snapshot()==snapshot,"history read only")
	await capture("demo-history-compact")
	host._feedback_audio.shutdown_audio()
	await create_timer(0.25).timeout
	root.remove_child(host)
	host.queue_free()
	await frames()
	print("GATE2_DEMO_WINDOW: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)

func verify_menu_bounds(shell:Control)->void:
	for id:String in ["menu_new","menu_continue","menu_load","menu_settings","menu_quit"]:
		var node:=shell.menu.find_child(id,true,false) as Button
		check(node!=null and root.get_visible_rect().encloses(node.get_global_rect()) and node.size.y>=48,"title button fits "+id)

func verify_settings_bounds(game:Control,page:String,controls:Array)->void:
	var shell:Control=game._pack_panel.find_child("settings_fixed_shell",true,false) as Control
	var back:=game._pack_panel.find_child("language_pack_cancel",true,false) as Button
	check(shell!=null and back!=null and shell.get_global_rect().encloses(back.get_global_rect()) and root.get_visible_rect().encloses(back.get_global_rect()) and back.size.y>=48,"fixed settings back "+page)
	check(game._settings_page==page and game._pack_panel.find_children("*","ScrollContainer",true,false).is_empty(),"settings category without scroll "+page)
	for id:String in controls:
		var control:=game._pack_panel.find_child(id,true,false) as Control
		check(control!=null and control.is_visible_in_tree() and root.get_visible_rect().encloses(control.get_global_rect()) and not control.get_global_rect().intersects(back.get_global_rect()),"settings control visible "+id)
