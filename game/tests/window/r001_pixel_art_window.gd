extends "res://tests/window/spatial_demo7_window.gd"
## Real existing runtime and pointer path; only the R001 visual candidate differs.
func finish()->void:
	print("GATE2_R001_PIXEL_WINDOW: ",checks," checks, ",failures," failures")
	await super.finish()

func verify_face(face:String)->void:
	var art:TextureRect=host._spatial._item
	check(art.texture.resource_path.ends_with("r001_pixel_"+face+"_candidate.png"),"correct "+face+" imported texture")
	check(art.texture.get_size()==Vector2(320,240),"exact source dimensions")
	check(art.size.y>0 and absf(art.size.x/art.size.y-4.0/3.0)<0.01,"texture rect fits actual aspect")
	for id:String in host._spatial._regions:
		var target:Control=host._spatial._regions[id]
		var expected:Rect2=host._spatial._face_regions()[id]
		var actual:Rect2=target.get_global_rect()
		var photo:Rect2=art.get_global_rect()
		check(actual.position.distance_to(photo.position+expected.position*photo.size)<2.0 and actual.size.distance_to(expected.size*photo.size)<2.0,"sprite-local "+face+" region "+id)

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(2)
		return
	out=args[0]
	root.size=Vector2i(1280,720)
	host=preload("res://scenes/app/r001_pixel_art_candidate.tscn").instantiate()
	host.save_directory_override="user://zt_rebuild/demo7/r001_pixel_test_"+str(Time.get_ticks_usec())
	root.add_child(host)
	await frames()
	if not await click("intro_skip") or not await click("contract_accept") or not await click("next_customer"):
		await finish()
		return
	check(host._spatial.visible and host._spatial._uses_r001_pixel_art(),"opt-in actual first visitor")
	var before:Dictionary=host.runtime.snapshot()
	verify_face("front")
	await capture("r001-pixel-front")
	if not await click("select_tool_wear_detail") or not await click("region_function_detail"):
		await finish()
		return
	check(host.runtime.snapshot()==before,"incorrect region does not charge time or reveal evidence")
	if not await click("region_wear_detail"):
		await finish()
		return
	check(host.runtime.view().minute==5,"wear samples authority")
	if not await click("flip_item"):
		await finish()
		return
	verify_face("back")
	await capture("r001-pixel-back")
	if not await drag("select_tool_casing_detail","region_casing_detail"):
		await finish()
		return
	check(host.runtime.view().minute==15 and host.runtime.view().wallet.VKC==180,"back tool samples authority, money preserved")
	var after:Dictionary=host.runtime.snapshot()
	if not await click("flip_item") or not await click("workspace_toggle"):
		await finish()
		return
	await create_timer(0.40).timeout
	check(host.runtime.snapshot()==after and host._spatial._gaze==0.0,"gaze change free")
	await capture("r001-pixel-counter")
	await finish()
