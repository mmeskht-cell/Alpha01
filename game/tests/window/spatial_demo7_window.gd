extends SceneTree
## Actual rendered candidate; not default startup or human/device acceptance.
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

func button(id:String)->Button:
	for node:Node in host.find_children(id,"Button",true,false):
		if node.is_visible_in_tree() and not node.disabled:
			return node
	return null

func reveal(node:Control)->void:
	var p:Node=node.get_parent()
	while p!=null:
		if p is ScrollContainer:
			p.ensure_control_visible(node)
		p=p.get_parent()
	await frames()

func pointer(point:Vector2,down:bool)->void:
	var e:=InputEventMouseButton.new()
	e.button_index=MOUSE_BUTTON_LEFT
	e.pressed=down
	e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	e.position=point
	e.global_position=point
	root.push_input(e,true)

func motion(point:Vector2,prior:Vector2)->void:
	var e:=InputEventMouseMotion.new()
	e.position=point
	e.global_position=point
	e.relative=point-prior
	e.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(e,true)

func click(id:String)->bool:
	var b:Button=button(id)
	if not check(b!=null,"visible target "+id):
		return false
	await reveal(b)
	var point:Vector2=b.get_global_rect().get_center()
	if not check(root.get_visible_rect().has_point(point),"inside viewport "+id):
		return false
	pointer(point,true)
	pointer(point,false)
	await frames()
	return true

func drag(source_id:String,target_id:String)->bool:
	var from:Button=button(source_id)
	var to:Button=button(target_id)
	if not check(from!=null and to!=null,"drag source and target"):
		return false
	await reveal(from)
	var a:Vector2=from.get_global_rect().get_center()
	var b:Vector2=to.get_global_rect().get_center()
	pointer(a,true)
	motion(a+Vector2(25,-25),a)
	await frames()
	var dragging:bool=root.gui_is_dragging()
	motion(b,a+Vector2(25,-25))
	await frames()
	pointer(b,false)
	await frames()
	return check(dragging and not root.gui_is_dragging(),"actual drag gesture")

func capture(id:String)->void:
	await frames()
	await RenderingServer.frame_post_draw
	var img:Image=root.get_texture().get_image()
	check(img!=null and not img.is_empty() and img.save_png(out.path_join(id+".png"))==OK,"capture "+id)

func finish()->void:
	if is_instance_valid(host):
		host._feedback_audio.shutdown_audio()
		await create_timer(0.25).timeout
		root.remove_child(host)
		host.queue_free()
		await frames()
	print("GATE2_SPATIAL_WINDOW: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(2)
		return
	out=args[0]
	root.size=Vector2i(1280,720)
	host=preload("res://scenes/app/spatial_demo7.tscn").instantiate()
	host.save_directory_override="user://zt_rebuild/demo7/spatial_"+str(Time.get_ticks_usec())
	root.add_child(host)
	await frames()
	if not await click("intro_skip") or not await click("contract_accept") or not await click("next_customer"):
		await finish()
		return
	var before:Dictionary=host.runtime.snapshot()
	check(host._spatial.visible and not host._counter.visible and not host._app.visible,"no dual panels in active spatial visit")
	await capture("spatial-inspection-empty-ko")
	if not await click("select_tool_wear_detail") or not await click("region_function_detail"):
		await finish()
		return
	check(host.runtime.snapshot()==before,"tool selection and wrong region are free")
	if not await click("region_wear_detail"):
		await finish()
		return
	check(host.runtime.view().minute==5,"tool target samples actual authority")
	if not await click("flip_item") or not await drag("select_tool_casing_detail","region_casing_detail"):
		await finish()
		return
	check(host.runtime.view().minute==15,"back surface drag samples actual authority")
	await capture("spatial-inspection-back-ko")
	if not await click("flip_item") or not await click("open_book"):
		await finish()
		return
	var app:Dictionary=host.runtime.view().appraisal
	var evidence:String=app.evidence[0].evidence_id
	if not await click("pick_model_id_selvar_r18") or not await click("pick_appearance_id_visible_wear") or not await click("link_appearance_id_"+evidence):
		await finish()
		return
	check(host.runtime.view().minute==15 and host.runtime.view().appraisal.deck.direct_ready.size()==2 and host.runtime.view().appraisal.deck.ready.is_empty() and host.runtime.view().appraisal.deck.presented.is_empty(),"two private cards without deck preparation or speech")
	check(host._spatial.find_child("prepare_model_id",true,false)==null and host._spatial.find_child("prepare_appearance_id",true,false)==null,"production book has no prepare actions")
	await capture("spatial-open-book-ko")
	before=host.runtime.snapshot()
	if not await click("workspace_toggle"):
		await finish()
		return
	await create_timer(0.40).timeout
	check(host.runtime.snapshot()==before and host._spatial._gaze==0.0,"shared scene gaze free")
	var speech:=host._spatial.find_child("spatial_speech_background",true,false) as Control
	check(speech!=null and not speech.get_global_rect().intersects(host._spatial._item.get_global_rect()),"speech does not obscure physical item")
	await capture("spatial-customer-hand-ko")
	var ready:Array=host.runtime.view().appraisal.deck.direct_ready
	var wear:String=""
	var model:String=""
	for card:Dictionary in ready:
		if card.argument.slot_id=="appearance_id":
			wear=card.card_id
		else:
			model=card.card_id
	if not await drag("spatial_card_"+wear,"spatial_customer_drop"):
		await finish()
		return
	app=host.runtime.view().appraisal
	check(app.deck.presented.size()==1 and app.deck.presented[0].customer_response.relation=="disagrees","first card produces actual counterclaim")
	await capture("spatial-customer-response-ko")
	if not await click("spatial_card_"+model) or not await click("spatial_customer_drop"):
		await finish()
		return
	check(host.runtime.view().appraisal.deck.presented.size()==2 and host.runtime.view().minute==15,"tap alternative presents exactly one card")
	if not await click("spatial_history"):
		await finish()
		return
	if not await click("withdraw_model_id"):
		await finish()
		return
	check(host.runtime.view().appraisal.deck.presented.size()==3 and host.runtime.view().appraisal.deck.public_basis_ids.size()==1,"public withdrawal from actual sheet")
	if host._spatial._statements_open and not await click("close_overlay"):
		await finish()
		return
	if not await click("spatial_card_"+model) or not await click("spatial_customer_drop"):
		await finish()
		return
	check(host.runtime.view().appraisal.deck.presented.size()==4 and host.runtime.view().appraisal.deck.public_basis_ids.size()==2 and host.runtime.view().minute==15,"actual reaffirmation without extra time")
	var spin:=host._spatial.find_child("spatial_price_amount",true,false) as SpinBox
	if not check(spin!=null,"actual price field"):
		await finish()
		return
	spin.value=100
	if not await click("spatial_offer"):
		await finish()
		return
	check(host.runtime.view().appraisal.has("checkout"),"qualified offer accepted")
	var empty:=host._spatial.find_child("spatial_empty_hand",true,false) as Label
	check(empty!=null and empty.size.x>=300 and empty.autowrap_mode==TextServer.AUTOWRAP_OFF,"empty hand has readable horizontal layout")
	speech=host._spatial.find_child("spatial_speech_background",true,false) as Control
	check(speech!=null and not speech.get_global_rect().intersects(host._spatial._item.get_global_rect()),"agreed price dialogue leaves item visible")
	await capture("spatial-price-agreed-ko")
	if not await click("spatial_checkout"):
		await finish()
		return
	var checkout_before:Dictionary=host.runtime.snapshot()
	if not await drag("checkout_drag_item","place_player_stock_0_0"):
		await finish()
		return
	check(host.runtime.snapshot()==checkout_before,"checkout drop previews without settlement")
	if not await click("confirm_checkout"):
		await finish()
		return
	check(host.runtime.view().wallet.VKC==80 and host.runtime.snapshot().items.R001.owner_id=="player","actual purchase, canonical balance")
	var stock_before:Dictionary=host.runtime.snapshot()
	if not await click("stock_toggle") or not await click("stock_cell_player_stock_0_0") or not await click("stock_cell_player_stock_4_2"):
		await finish()
		return
	check(host.runtime.snapshot()==stock_before,"stock preview is free")
	var locked_work:=host._management.find_child("work_confirm",true,false) as Button
	check(locked_work!=null and locked_work.disabled,"day inventory uses same details but restoration disabled")
	await capture("spatial-stock-preview-ko")
	if not await click("stock_cancel"):
		await finish()
		return
	check(host.runtime.snapshot()==stock_before,"stock cancel is free")
	if not await drag("stock_cell_player_stock_0_0","stock_cell_player_stock_9_5"):
		await finish()
		return
	check(host.runtime.snapshot()==stock_before and host._management._destination==Vector2i(-1,-1),"out of bounds drag rejected without mutation")
	if not await drag("stock_cell_player_stock_1_0","stock_cell_player_stock_5_2"):
		await finish()
		return
	check(host.runtime.snapshot()==stock_before and host._management._destination==Vector2i(4,2),"drag preserves grab anchor and stages preview")
	await capture("spatial-stock-drag-preview-ko")
	if not await click("stock_confirm"):
		await finish()
		return
	check(host.runtime.snapshot().items.R001.x==4 and host.runtime.snapshot().items.R001.y==2 and host.runtime.view().wallet.VKC==80 and host.runtime.view().minute==15,"owned stock placement persists with no cost/time")
	await capture("spatial-stock-placed-ko")
	if not await click("stock_cell_player_stock_4_2") or not await click("stock_rotate") or not await click("stock_cell_player_stock_4_2") or not await click("stock_confirm"):
		await finish()
		return
	var rotated:Dictionary={}
	for row:Dictionary in host.runtime.view().stock:
		if row.id=="R001":
			rotated=row
	check(rotated.get("rotated",false) and rotated.get("width",0)==1 and rotated.get("height",0)==2,"rotated DTO matches occupied footprint")
	if not await drag("stock_cell_player_stock_4_3","stock_cell_player_stock_6_4") or not await click("stock_confirm"):
		await finish()
		return
	check(host.runtime.snapshot().items.R001.x==6 and host.runtime.snapshot().items.R001.y==3 and host.runtime.snapshot().items.R001.rotated,"rotated lower cell drag preserves anchor")
	if not await click("stock_cell_player_stock_6_3") or not await click("detail_history_toggle"):
		await finish()
		return
	check(host._management.find_child("history_item_R001",true,false)!=null,"selected item history accessible from inventory")
	if not await click("stock_toggle"):
		await finish()
		return
	await watch_route()
	await finish()

# Reach the actual D2 appointment through normal authority commands. This
# setup is not counted as pointer coverage of other visits or workshop.
func command(kind:String,p:Dictionary={})->bool:
	var v:Dictionary=host.runtime.view()
	var r:Dictionary=host.runtime.submit(kind,p,v.revision)
	return check(r.ok and r.get("persisted",false),"setup D"+str(v.day)+" "+str(v.visits.active)+" "+kind+" "+str(r.get("error","")))

func watch_route()->void:
	var seen:int=0
	while host.runtime.view().visits.can_next and seen<10:
		seen+=1
		if not command("calendar_next_visit"):
			return
		var v:Dictionary=host.runtime.view()
		if not v.trade.is_empty():
			var p:Dictionary=v.trade.duplicate()
			p.erase("label")
			p.erase("placement")
			p.merge(v.trade.placement)
			if v.trade.visit_id=="visit_g02_buy":
				host.refresh()
				await frames()
				if not check(host._spatial.visible and not host._counter.visible and not host._workspace_button.visible,"fixed-price sale has spatial scene, no false appraisal"):
					return
				await capture("spatial-radio-sale-ko")
				if not await click("spatial_fixed_confirm"):
					return
				check(host.runtime.snapshot().items.R001.owner_id=="G02" and host.runtime.view().wallet.VKC==250,"actual fixed-price sale")
			elif not command("trade",p):
				return
		else:
			var terms:Dictionary=v.visits.terms
			if terms.kind=="service_offer":
				host.refresh()
				await frames()
				if not check(host._spatial.visible and not host._workspace_button.visible and not host._counter.visible,"service offer uses shared stage"):
					return
				await capture("spatial-service-offer-ko")
				var cash:int=host.runtime.view().wallet.VKC
				if not await click("spatial_service_accept"):
					return
				var item:Dictionary=host.runtime.snapshot().items[terms.item_id]
				check(item.owner_id==terms.customer and item.custodian_id=="player" and host.runtime.view().wallet.VKC==cash,"accept service transfers custody not ownership or fee")
			elif not command("calendar_deliver_service",{"visit_id":v.visits.active,"job_id":terms.job_id}):
				return
	if not command("calendar_close"):
		return
	host.refresh()
	await frames()
	if not check(host._management.visible and not host._counter.visible,"evening unified inventory candidate"):
		return
	for work:Dictionary in host.runtime.view().work:
		var prior:Dictionary=host.runtime.snapshot()
		var source:String=inventory_cell(work.id)
		if not check(not source.is_empty(),"service item in shared custody grid") or not await drag(source,"inventory_detail_drop"):
			return
		check(host.runtime.snapshot()==prior and host._management._selected==work.id,"inventory detail drop selects only, no cost or time")
		await capture("spatial-workbench-cost-ko")
		if not await click("work_confirm"):
			return
		check(host.runtime.snapshot().items[work.id].functional and host.runtime.view().wallet.VKC==int(prior.wallets.player.VKC)-int(work.cost.VKC),"restore authority charges exact cost")
		if not await click(inventory_cell(work.id)):
			return
		await capture("spatial-workbench-complete-ko")
	if not await click("work_next_day"):
		return
	for i:int in range(4):
		if not command("calendar_next_visit"):
			return
		var v:Dictionary=host.runtime.view()
		if v.visits.active=="watch_a":
			break
		if v.trade.is_empty():
			var terms:Dictionary=v.visits.terms
			host.refresh()
			await frames()
			if not check(host._spatial.visible and terms.status=="complete","completed service return on shared stage"):
				return
			await capture("spatial-service-return-ko")
			var cash:int=host.runtime.view().wallet.VKC
			if not await click("spatial_service_deliver"):
				return
			var item:Dictionary=host.runtime.snapshot().items[terms.item_id]
			check(item.owner_id==terms.customer and item.custodian_id==terms.customer and host.runtime.view().wallet.VKC==cash+int(terms.fee.VKC),"paid return restores custody and credits exact fee")
		elif not command("calendar_decline_visit",{"visit_id":v.visits.active}):
			return
	if not check(host.runtime.view().visits.active=="watch_a","reached actual second-day watch"):
		return
	host._compact_appraisal=true
	host.refresh()
	await frames()
	if not check(host._spatial.visible and not host._app.visible and not host._counter.visible,"shared spatial watch scene"):
		return
	check(host._spatial._npc.texture.resource_path.ends_with("g04.png"),"watch customer is distinct")
	check(host._spatial._item.texture.resource_path.ends_with("meridian_watch_front.png"),"neutral watch front art")
	var prior:Dictionary=host.runtime.snapshot()
	await capture("spatial-watch-front-ko")
	if not await click("select_tool_wear_detail") or not await click("region_wear_detail"):
		return
	check(host.runtime.view().minute==int(prior.game_minutes)+5,"watch face observation authority")
	if not await click("flip_item") or not await drag("select_tool_batch_detail","region_batch_detail"):
		return
	check(host._spatial._item.texture.resource_path.ends_with("meridian_watch_back.png"),"physical flip shows the matching Meridian caseback")
	check(host.runtime.view().minute==int(prior.game_minutes)+10,"watch back observation authority")
	await capture("spatial-watch-back-ko")
	prior=host.runtime.snapshot()
	if not await click("workspace_toggle"):
		return
	await create_timer(0.40).timeout
	check(host.runtime.snapshot()==prior and host._spatial._gaze==0.0,"watch gaze preserves state")
	await capture("spatial-watch-customer-ko")
	var spin:=host._spatial.find_child("spatial_price_amount",true,false) as SpinBox
	if not check(spin!=null,"watch price control"):
		return
	spin.value=80
	if not await click("spatial_offer"):
		return
	check(host.runtime.view().appraisal.has("checkout"),"watch accepted canonical price")
	await capture("spatial-watch-price-ko")
	if not await click("spatial_checkout") or not await click("place_player_stock_0_0") or not await click("confirm_checkout"):
		return
	check(host.runtime.snapshot().items.WAT02.owner_id=="player","watch placed and purchased by pointer")
	for expected:String in ["watch_sale","battery_buy","battery_sale"]:
		host.refresh()
		await frames()
		if not await click("next_customer"):
			return
		var v:Dictionary=host.runtime.view()
		if not check(v.visits.active==expected and host._spatial.visible and not host._workspace_button.visible,"fixed trade scene "+expected):
			return
		await capture("spatial-"+expected+"-ko")
		if expected=="watch_sale":
			check(host._spatial._item.texture.resource_path.ends_with("meridian_watch_front.png"),"watch resale uses the same Meridian face as purchase")
		if expected=="battery_buy":
			var basic_before:Dictionary=host.runtime.snapshot()
			if not await click("spatial_basic_review"):
				return
			check(host.runtime.snapshot()==basic_before and host._app.visible,"opt-in basic appraisal changes no game state")
			if not await click("tool_basic_function_v1"):
				return
			var basic:Dictionary=host.runtime.view().appraisal
			check(basic.evidence.size()==1 and basic.evidence[0].observed_value=="serviceable" and host.runtime.snapshot().game_minutes==basic_before.game_minutes+5 and host.runtime.snapshot().wallets==basic_before.wallets,"actual basic functional observation, existing time cost")
			if not await click("pick_function_id_working") or not await click("workspace_toggle"):
				return
			if not await click("disclose_observation_"+str(basic.evidence[0].evidence_id)) or not await click("price_offer_public"):
				return
			check(host.runtime.view().appraisal.checkout.amount==40 and host.runtime.view().appraisal.reference.estimate==null,"same fixed price and no invented estimate")
			if not await click("place_player_stock_0_0") or not await click("confirm_checkout"):
				return
			var record:Dictionary=host.runtime.item_history("BAT02").items[0].history.records[0]
			check(record.appraisal_sheet.statements[0].argument.statement_kind=="observation","basic disclosed observation in actual transaction history")
		elif expected=="battery_sale":
			var quality:Dictionary=v.get("basic_sale_quality",{})
			if not check(quality.get("observed_value")=="serviceable","purchase observation reused for current sale term"):
				return
			var before_sale:Dictionary=host.runtime.snapshot()
			var forged:Dictionary=v.trade.duplicate(true)
			forged.erase("label")
			forged.erase("placement")
			forged.merge(v.trade.placement)
			forged["sale_quality_evidence_id"]="forged_sale_evidence"
			var rejected:Dictionary=host.runtime.submit("trade",forged,v.revision)
			check(not rejected.ok and host.runtime.snapshot()==before_sale,"unbound sale term rejected atomically")
			if not await click("spatial_sale_quality_confirm"):
				return
			var sale_record:Dictionary=host.runtime.item_history("BAT02").items[0].history.records[0]
			check(sale_record.appraisal_sheet.quality_condition==quality and sale_record.amounts.VKC==60 and host.runtime.snapshot().wallets.player.VKC==before_sale.wallets.player.VKC+60,"explicit sale condition bound to actual 60 VKC transaction")
		elif not await click("spatial_fixed_confirm"):
			return
		check(host.runtime.snapshot().items[v.trade.item_id].owner_id==v.trade.buyer,"trade changes ownership "+expected)

	await return_route()



# Advance the already tested daily schedule using the public commands only.
# This setup is not a substitute for actual D7 pointer coverage.
func return_route()->void:
	for day:int in range(2,7):
		print("ZT_SPATIAL_SETUP_DAY ",day," revision ",host.runtime.view().revision)
		var seen:int=0
		while host.runtime.view().visits.can_next and seen<10:
			seen+=1
			if not command("calendar_next_visit"):
				return
			var v:Dictionary=host.runtime.view()
			var terms:Dictionary=v.visits.terms
			if v.trade.is_empty():
				if not command("calendar_accept_service" if terms.kind=="service_offer" else "calendar_deliver_service",{"visit_id":v.visits.active,"job_id":terms.job_id}):
					return
			elif v.trade.visit_id=="radio3_buy":
				# This purchase requires its own appraisal and accepted offer.
				if not await radio3_route():
					return
			else:
				var payload:Dictionary=v.trade.duplicate(true)
				payload.erase("label")
				payload.erase("placement")
				payload.merge(v.trade.placement)
				if not command("trade",payload):
					return
		if not check(seen<10,"bounded setup day "+str(day)) or not command("calendar_close"):
			return
		for work:Dictionary in host.runtime.view().work:
			if not command("restore_item",{"actor":"player","item_id":work.id}):
				return
		if not command("calendar_morning"):
			return
	if not check(host.runtime.view().day==7 and host.runtime.snapshot().items.R001.owner_id=="G02","same radio returns on D7"):
		return
	print("ZT_SPATIAL_D7_POINTER")
	host.refresh()
	await frames()
	for i:int in range(8):
		if not await click("next_customer"):
			return
		var v:Dictionary=host.runtime.view()
		if v.visits.active=="radio_return":
			break
		if v.trade.is_empty():
			if not await click("spatial_service_accept" if v.visits.terms.kind=="service_offer" else "spatial_service_deliver"):
				return
		else:
			if not await click("spatial_fixed_confirm"):
				return
	if not check(host.runtime.view().visits.active=="radio_return" and host._spatial.visible,"D7 returning radio spatial stage"):
		return
	check(host._spatial._customer_id()=="G02" and host.runtime.view().appraisal.item_id=="R001","returning customer and same item")
	var prior:Dictionary=host.runtime.snapshot()
	if not await click("history_toggle"):
		return
	check(host._history.visible and host._history.find_child("history_item_R001",true,false)!=null and host.runtime.snapshot()==prior,"returning item historical ledger read only, independent of recent index")
	if not await click("history_toggle"):
		return
	if not await click("select_tool_wear_detail") or not await click("region_wear_detail") or not await drag("select_tool_function_detail","region_function_detail"):
		return
	check(host.runtime.view().appraisal.evidence.size()>=2 and host.runtime.view().minute>int(prior.game_minutes),"D7 fresh observations not historical inference")
	if not await click("workspace_toggle"):
		return
	await create_timer(0.40).timeout
	var spin:=host._spatial.find_child("spatial_price_amount",true,false) as SpinBox
	if not check(spin!=null,"D7 price control"):
		return
	spin.value=95
	if not await click("spatial_offer"):
		return
	check(host.runtime.view().appraisal.has("checkout"),"D7 accepted offer")
	if not await click("spatial_checkout") or not await click("place_player_stock_0_0") or not await click("confirm_checkout"):
		return
	check(host.runtime.snapshot().items.R001.owner_id=="player","D7 same radio repurchased")
	var seen:int=0
	while host.runtime.view().visits.can_next and seen<8:
		seen+=1
		if not await click("next_customer"):
			return
		var v:Dictionary=host.runtime.view()
		if v.trade.is_empty():
			if not await click("spatial_service_accept" if v.visits.terms.kind=="service_offer" else "spatial_service_deliver"):
				return
		else:
			if not await click("spatial_fixed_confirm"):
				return
	if not check(seen<8,"finite final-day visits") or not await click("close_day"):
		return
	for work:Dictionary in host.runtime.view().work:
		if not await click(inventory_cell(work.id)) or not await click("work_confirm"):
			return
	if not await click("work_next_day"):
		return
	var final:Dictionary=host.runtime.view()
	var snapshot:Dictionary=host.runtime.snapshot()
	check(final.complete and final.minute==10080 and final.wallet.VKC==260,"actual week completion and expected final balance")
	check(snapshot.items.R001.owner_id=="G08" and snapshot.calendar.tracking.R001.refs.size()==4,"same radio lineage after final sale")
	check(snapshot.calendar.services.jobs.job7.status=="complete" and snapshot.items.W007S.custodian_id=="player" and not final.visits.can_next,"final custody remains and no D8 visits")

func radio3_route()->bool:
	print("ZT_SPATIAL_D3_POINTER")
	# Set inspection before the first refresh of this new visit, not during a gaze tween.
	host._compact_appraisal=true
	host.refresh()
	await frames()
	if host._spatial.transitioning:
		await create_timer(0.40).timeout
	if not check(host._spatial.visible and host._spatial._customer_id()=="G10" and host._spatial._inspect and not host._spatial.transitioning,"D3 second radio has active inspection stage"):
		return false
	if not await click("select_tool_wear_detail") or not await click("region_wear_detail") or not await click("workspace_toggle"):
		return false
	await create_timer(0.40).timeout
	var spin:=host._spatial.find_child("spatial_price_amount",true,false) as SpinBox
	if not check(spin!=null,"D3 radio has price control"):
		return false
	spin.value=40
	if not await click("spatial_offer"):
		return false
	if not check(host.runtime.view().appraisal.has("checkout"),"D3 radio accepted offer"):
		return false
	if not await click("spatial_checkout") or not await click("place_player_stock_0_0") or not await click("confirm_checkout"):
		return false
	return check(host.runtime.snapshot().items.R003.owner_id=="player","D3 radio purchased using pointer and offer")


func inventory_cell(id:String)->String:
	for row:Dictionary in host.runtime.view().stock:
		if row.id==id:
			return "stock_cell_"+str(row.inventory)+"_"+str(row.x)+"_"+str(row.y)
	return ""
