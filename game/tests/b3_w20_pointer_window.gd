extends "res://tests/window/b3_spatial_week_window.gd"
## Supplemental pointer path. Existing full campaign and W17-W19 routes remain independent.
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=1 or DirAccess.make_dir_recursive_absolute(args[0])!=OK:
		quit(2)
		return
	out=args[0]
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=resolution
		if not await install(Spatial,"w20_pointer_"+str(resolution.y)): break
		if not await counter_drag(resolution): break
		await release_host()
	await finish()

func drag_between(source: Control,target: Control) -> bool:
	if not check(is_instance_valid(source) and is_instance_valid(target),"drag endpoints exist"): return false
	var start := source.get_global_transform_with_canvas()*(source.size*0.5)
	var end := target.get_global_transform_with_canvas()*(target.size*0.5)
	var prior := start
	for step in range(11):
		var point := start.lerp(end,float(step)/10)
		var move := InputEventMouseMotion.new()
		move.position=point
		move.global_position=point
		move.relative=point-prior
		move.button_mask=0 if step==0 else MOUSE_BUTTON_MASK_LEFT
		root.push_input(move,true)
		if step==0 or step==10:
			var press := InputEventMouseButton.new()
			press.position=point
			press.global_position=point
			press.button_index=MOUSE_BUTTON_LEFT
			press.pressed=step==0
			press.button_mask=MOUSE_BUTTON_MASK_LEFT if step==0 else 0
			root.push_input(press,true)
		prior=point
		await process_frame
	await frames()
	return true

func counter_drag(resolution: Vector2i) -> bool:
	for step: Array in [["intro_skip","DAY_PREP"],["alpha_open","OPEN_IDLE"],["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"],["alpha_contract_decline","CUSTOMER_ACTIVE"],["alpha_finish_customer","CUSTOMER_EXIT"],["alpha_ack_exit","OPEN_IDLE"],["alpha_next_customer","CUSTOMER_ENTER"],["alpha_ack_entry","CUSTOMER_ACTIVE"]]:
		if not await click(step[0],step[1]): return false
	var before: int = host.session.snapshot().revision
	if not await drag_between(host.find_child("tool_wear_detail",true,false),host.find_child("specimen",true,false)): return false
	if not check(host.session.snapshot().revision==before+1,"one real drag inspection"): return false
	if not await drag_between(host.find_child("fact_wear_detail",true,false),host.find_child("attachment_pocket",true,false)): return false
	if not check(host.session.snapshot().revision==before+2,"one attachment change"): return false
	var found := false
	for card: Dictionary in host.session.alpha_view().appraisal.cards:
		if card.slot=="wear_detail": found=card.selected and not card.public_active
	if not check(found,"attached evidence remains private before offer"): return false
	await capture("w20_attached_"+str(resolution.y),resolution)
	if not await click_navigation(host,"notes"): return false
	await capture("w20_surface_"+str(resolution.y),resolution)
	return check(host.session.snapshot().revision==before+2,"opening reference has no authority effect")
