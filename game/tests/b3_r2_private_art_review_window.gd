extends "res://tests/b3_w20_pointer_window.gd"
## PRIVATE visual review only. Not registered in public CI: the five original
## R2 textures must remain in the private repository until publication approval.
const Review = preload("res://scenes/app/alpha_b3_r2_art_review.tscn")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=1 or DirAccess.make_dir_recursive_absolute(args[0])!=OK:
		quit(2)
		return
	out = args[0]
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		if not await configure_native_window(resolution): break
		if not await install(Review,"r2_private_"+str(resolution.y)): break
		if not check(host.r2_review_mode and host.r2_layers.size()==5,"five original imported R2 textures"): break
		if not await counter_drag(resolution): break
		var before: Dictionary = host.session.snapshot()
		var rear := host.find_child("r2_rear",true,false) as TextureRect
		var visitor := host.find_child("r2_visitor",true,false) as TextureRect
		var counter := host.find_child("r2_counter",true,false) as TextureRect
		var book := host.find_child("r2_book_closed",true,false) as TextureRect
		var lens := host.find_child("r2_lens",true,false) as TextureRect
		if not check(rear!=null and visitor!=null and counter!=null and book!=null and lens!=null,"actual layered art on active counter"): break
		if not check(rear.get_index()<visitor.get_index() and visitor.get_index()<counter.get_index(),"rear actor foreground draw order"): break
		if not check(rear.texture==host.r2_layers.rear and visitor.texture==host.r2_layers.visitor and counter.texture==host.r2_layers.counter and book.texture==host.r2_layers.book_closed and lens.texture==host.r2_layers.lens,"all five live textures match original loaded layers"): break
		if not check(rear.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and visitor.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and counter.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and book.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and lens.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"nearest art filtering"): break
		if not check(host.session.alpha_view().active.actor_id=="G01" and host.session.alpha_view().appraisal.item_id=="R001","real visit and original item identity"): break
		await capture("r2_native_counter_"+str(resolution.y),resolution)
		if not await click_navigation(host,"notes"): break
		await capture("r2_native_reference_"+str(resolution.y),resolution)
		if not await click_navigation(host,"close_drawer"): break
		if not check(host.session.snapshot()==before,"visual navigation preserves authority"): break
		if not await review_negotiation(resolution): break
		await release_host()
	await finish()



# Add the unobserved desk and the actual first observation to the inherited
# pointer route, while retaining its original drag and valuation assertions.
func drag_between(source: Control,target: Control) -> bool:
	var resolution := root.size
	var tool_drag: bool = is_instance_valid(source) and source.name=="tool_wear_detail"
	if tool_drag: await capture("r2_c0_before_observation_"+str(resolution.y),resolution)
	if not await super.drag_between(source,target): return false
	if tool_drag:
		if not check(is_instance_valid(source) and source==host.find_child("tool_wear_detail",true,false),"magnifier keeps its scene identity after the committed observation"): return false
		await capture("r2_c1_actual_observation_"+str(resolution.y),resolution)
	return true

func click(name: String, phase: String) -> bool:
	if name=="exterior_moderate":
		var grade := host.find_child(name,true,false) as Button
		if grade:
			var center := grade.get_global_transform_with_canvas() * (grade.size * 0.5)
			var desk := host.find_child("r2_reference_desk",true,false)
			if not check(is_instance_valid(desk) and Rect2(Vector2.ZERO,desk.scroll.size).has_point(desk.scroll.get_global_transform_with_canvas().affine_inverse()*center),"exterior action is inside the book viewport"): return false
			await capture("r2_c2_judgment_"+str(root.size.y),root.size)
	return await super.click(name,phase)

func review_negotiation(resolution: Vector2i) -> bool:
	var before: Dictionary = host.session.snapshot()
	var hand := host.find_child("fact_wear_detail",true,false) as Control
	var target := host.find_child("attachment_pocket",true,false) as Control
	var editor := host.find_child("ratio_offer_control",true,false) as Control
	var quote := host.find_child("Utterance",true,false) as Label
	if not check(hand!=null and target!=null and editor!=null and quote!=null,"reusable hand, presentation target, price and voice nodes"): return false
	if not await click_navigation(host,"notes"): return false
	var book := host.find_child("r2_reference_desk",true,false) as Control
	if not check(book!=null,"physical reference presentation is open"): return false
	if not await click_navigation(host,"book_surface"): return false
	if not await click_navigation(host,"close_drawer"): return false
	if not await click_navigation(host,"notes"): return false
	if not check(book==host.find_child("r2_reference_desk",true,false),"book and tab strip keep identity across close and reopen"): return false
	if not await click_navigation(host,"close_drawer"): return false
	if not check(host.session.snapshot()==before,"book page navigation keeps authority"): return false
	if not check(editor==host.find_child("ratio_offer_control",true,false) and target==host.find_child("attachment_pocket",true,false),"ratio editor and presentation zone keep identity across book navigation"): return false
	for percent: int in [125,150,100]:
		if not await click_navigation(host,"preferences"): return false
		if not await click_navigation(host,"font_"+str(percent)): return false
		if not await click_navigation(host,"close_drawer"): return false
		if not check(host.reading_scale==percent and host.session.snapshot()==before,"reading size is local"): return false
		if percent!=100:
			if not await click_navigation(host,"notes"): return false
			await capture("r2_c2_reference_"+str(percent)+"_"+str(resolution.y),resolution)
			if not await click_navigation(host,"close_drawer"): return false
	if not await click("offer","CUSTOMER_ACTIVE"): return false
	var refused: Dictionary = host.session.alpha_view()
	var speech := host.find_child("Utterance",true,false) as Label
	if not check(refused.appraisal.offers.back().amount==80 and refused.appraisal.offers.back().response=="declined","real refusal at 80 VKC"): return false
	if not check(refused.npc_context.current_offer.public_slots.has("wear_detail") and speech==quote and not speech.text.is_empty(),"submitted wear evidence is public and persistent speech responds"): return false
	if not check(host.session.snapshot().wallets==before.wallets and host.session.snapshot().ledger==before.ledger,"an offer alone does not settle"): return false
	if not check(hand==host.find_child("fact_wear_detail",true,false),"same recorded card after public disclosure"): return false
	await capture("r2_c3_refused_80_"+str(resolution.y),resolution)
	for id: String in ["ratio_plus_5","ratio_plus_5","ratio_minus_fine"]:
		if not await click_navigation(host,id): return false
	var amount := host.find_child("offer_amount",true,false) as Label
	if not check(amount!=null and amount.text=="95 VKC","proportional offer is 95 VKC with the required wear evidence"): return false
	if not await click("offer","CUSTOMER_ACTIVE"): return false
	var agreed: Dictionary = host.session.alpha_view().appraisal.accepted
	if not check(agreed.get("amount",0)==95 and agreed.get("currency")=="VKC","wear evidence enables the authored 95 VKC agreement"): return false
	await capture("r2_c3_agreed_95_"+str(resolution.y),resolution)
	if not await click("settle_trade","CUSTOMER_EXIT"): return false
	var paid: Dictionary = host.session.snapshot()
	if not check(paid.ledger.size()==before.ledger.size()+1 and paid.items.R001.owner_id=="player" and paid.wallets.player.VKC==before.wallets.player.VKC-95,"one real settlement at the agreed amount"): return false
	await capture("r2_c3_settled_"+str(resolution.y),resolution)
	return true
