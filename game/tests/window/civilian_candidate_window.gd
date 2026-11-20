extends SceneTree
## Bounded actual candidate host pointer route; original visits skipped in setup.
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
	if not check(from!=null and to!=null,"drag source and target: "+source_id+" -> "+target_id):
		return false
	await reveal(to)
	await reveal(from)
	var a:Vector2=from.get_global_rect().get_center()
	var b:Vector2=to.get_global_rect().get_center()
	if not check(root.get_visible_rect().has_point(a) and root.get_visible_rect().has_point(b),"both drag endpoints simultaneously inside viewport"):
		return false
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

var directory:String=""
func open_host()->void:
	host=preload("res://scenes/app/integrated_b_candidate.tscn").instantiate()
	host.save_directory_override=directory
	root.add_child(host)
	await frames()

func close_host()->void:
	if is_instance_valid(host):
		if is_instance_valid(host._feedback_audio):
			host._feedback_audio.shutdown_audio()
			await create_timer(0.25).timeout
		root.remove_child(host)
		host.queue_free()
		await frames()
	host=null

func finish()->void:
	await close_host()
	print("GATE2_CIVILIAN_HOST_WINDOW: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)

func command(kind:String,p:Dictionary={})->bool:
	var result:Dictionary=host.runtime.submit(kind,p,host.runtime.view().revision)
	return check(result.ok and result.get("persisted",false),"setup "+kind+" "+str(result.get("error","")))

func inventory_cell(id:String)->String:
	for row:Dictionary in host.runtime.view().stock:
		if row.id==id:
			return "stock_cell_"+str(row.inventory)+"_"+str(row.x)+"_"+str(row.y)
	return ""

func label_text(id:String)->String:
	var node:Label=host._management.find_child(id,true,false) as Label
	return node.text if node!=null else ""

func check_assessment_layout(id:String,keys:Array)->void:
	for key:String in keys:
		var fact:Label=host._management.find_child("appraisal_fact_"+id+"_"+key,true,false) as Label
		var inspect:Button=host._management.find_child("inventory_observe_"+id+"_"+key,true,false) as Button
		var row:Control=host._management.find_child("appraisal_row_"+id+"_"+key,true,false) as Control
		if not check(fact!=null and inspect!=null and row!=null,"all assessment geometry controls "+key):
			continue
		check(fact.size.x>=120 and inspect.size.y>=48 and inspect.size.y<=64 and row.size.y<=100 and not fact.get_global_rect().intersects(inspect.get_global_rect()),"bounded readable assessment row "+id+" "+key)
		check(row.get_global_rect().encloses(fact.get_global_rect()) and row.get_global_rect().encloses(inspect.get_global_rect()),"controls enclosed by appraisal row "+key)
		var limit_key:String={"functional":"inventory.assessment.limit_function","complete":"inventory.assessment.limit_completeness","restored":"inventory.assessment.limit_restoration"}.get(key,"")
		if not limit_key.is_empty():
			check(fact.tooltip_text==host.tr_key(limit_key) and inspect.tooltip_text.contains(host.tr_key(limit_key)),"public fact limits explained without altering observation "+key)

func check_grid_codes()->void:
	var found:Dictionary={}
	var legend:Label=host._management.find_child("inventory_legend_player_stock",true,false) as Label
	for id:String in ["CR06","CM06C"]:
		var node:Button=host._management.find_child(inventory_cell(id),true,false) as Button
		if not check(node!=null and legend!=null,"grid legend and anchor "+id):
			continue
		var code:String=str(node.get_meta("display_code",""))
		var font:Font=node.get_theme_font("font")
		var fsize:int=node.get_theme_font_size("font_size")
		var width:float=font.get_string_size(code,HORIZONTAL_ALIGNMENT_LEFT,-1,fsize).x
		var style:StyleBox=node.get_theme_stylebox("normal")
		var available:float=node.size.x-style.get_minimum_size().x
		check(not code.is_empty() and node.text==code and not found.has(code) and width<=available and node.size.x>=48 and node.size.y>=48,"unique fitting touch-safe grid code "+id)
		check(str(node.get_meta("item_id",""))==id and node.tooltip_text.contains(id) and legend.text.contains(code+" · "+id),"full identity linked to grid code "+id)
		found[code]=true

func setup_day6()->bool:
	for day:int in range(1,6):
		if not command("calendar_close") or not command("calendar_morning"):
			return false
	# Skip unrelated appointments without replaying a second full campaign.
	for i:int in range(8):
		var v:Dictionary=host.runtime.view()
		if not v.visits.can_next:
			return check(false,"civilian purchase must be available")
		if not command("calendar_next_visit"):
			return false
		v=host.runtime.view()
		if v.visits.active=="civil_receiver_buy":
			return true
		if not command("calendar_decline_visit",{"visit_id":v.visits.active}):
			return false
	return check(false,"bounded D6 setup")

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(2)
		return
	out=args[0]
	root.size=Vector2i(1440,1000)
	directory="user://zt_rebuild/demo7/civilian_host_"+str(Time.get_ticks_usec())
	await open_host()
	if not check(host.runtime!=null and not host.runtime.blocked and host.runtime.view().civilian_candidate and host.preview_native_v23 and host.runtime.view().condition_version==2,"same integrated candidate scene and isolated runtime"):
		await finish()
		return
	if not await click("intro_skip") or not setup_day6():
		await finish()
		return
	host.refresh()
	await frames()
	var v:Dictionary=host.runtime.view()
	check(v.day==6 and v.wallet.VKC==105 and host._spatial.visible and v.trade.item_id=="CR06","actual D6 offer at counter, no extra player funds")
	await capture("civilian-counter-buy-ko")
	if not await click("spatial_fixed_confirm") or not await click("next_customer"):
		await finish()
		return
	check(host.runtime.view().visits.active=="civil_spare_buy" and host.runtime.view().trade.item_id=="CM06C","actual spare visit")
	if not await click("spatial_fixed_confirm"):
		await finish()
		return
	check(host.runtime.view().wallet.VKC==20 and host.runtime.snapshot().items.CR06.owner_id=="player","both actual purchases settled")
	if not await click("stock_toggle") or not await click(inventory_cell("CR06")):
		await finish()
		return
	if not await detail_page("appraisal"):
		await finish()
		return
	check(host._management.visible and label_text("appraisal_basis_CR06").contains("70 VKC"),"owned assembly detail")
	check_assessment_layout("CR06",["functional","complete","restored"])
	if not await detail_page("plan"):
		await finish()
		return
	check(label_text("disposition_basis").contains("70 VKC") and label_text("disposition_sale").contains("문의 없음") and label_text("disposition_opportunity").contains("미확인"),"disposition actual basis and unknown sale without buyer")
	check_grid_codes()
	if not await detail_page("appraisal"):
		await finish()
		return
	var prior:Dictionary=host.runtime.snapshot()
	if not await click("inventory_observe_CR06_functional"):
		await finish()
		return
	check(host.runtime.view().minute==int(prior.game_minutes) and label_text("appraisal_fact_CR06_functional").contains("아니오"),"owned whole observation free from actual host")
	if not await detail_page("components") or not await select_component_slot("CR06_C") or not await click("component_appraisal_CR06_C") or not await click("inventory_observe_CR06_C_functional"):
		await finish()
		return
	check(label_text("appraisal_fact_CR06_C_functional").contains("아니오"),"owned component observation from actual host")
	check_assessment_layout("CR06_C",["functional","restored"])
	var stock_pane:ScrollContainer=host._management._stock_scroll
	var detail_pane:ScrollContainer=host._management._detail_scroll
	check(stock_pane!=detail_pane and not stock_pane.get_global_rect().intersects(detail_pane.get_global_rect()),"independent stock and detail panes")
	await capture("civilian-component-assessment-ko")
	if not await click("stock_toggle") or not await click("close_day"):
		await finish()
		return
	root.size=Vector2i(1280,720)
	await frames()
	if not await click(inventory_cell("CR06")):
		await finish()
		return
	var grid:ScrollContainer=host._management._stock_scroll
	var details:ScrollContainer=host._management._detail_scroll
	var stock_position:Vector2=grid.get_global_rect().position
	var stock_offset:int=grid.scroll_vertical
	details.scroll_vertical=int(details.get_v_scroll_bar().max_value)
	await frames()
	check(grid.get_global_rect().position==stock_position and grid.scroll_vertical==stock_offset,"detail scrolling never moves stock")
	prior=host.runtime.snapshot()
	var old_epoch: int = host._management._epoch
	# The detail pane deliberately remains at its bottom. Care must be a
	# fixed action and must not depend on a test-driven scroll to the button.
	var care_button: Button=button("care_exterior")
	var work_footer: Control=host._management.find_child("inventory_fixed_footer",true,false) as Control
	if not check(care_button!=null and work_footer!=null and work_footer.is_ancestor_of(care_button) and not details.is_ancestor_of(care_button),"care action belongs to fixed work footer"):
		await finish()
		return
	var care_rect: Rect2=care_button.get_global_rect()
	var pane_bounds: Rect2=host._management.get_global_rect()
	var body: Control=host._management.find_child("inventory_bounded_body",true,false) as Control
	var toolbar: Control=host._management.find_child("inventory_fixed_actions",true,false) as Control
	var viewport: Rect2=root.get_visible_rect()
	# Log geometry even on a failed run so minimum-size propagation can be
	# distinguished from resize/scroll timing without guessing.
	print("ZT_INVENTORY_COMPACT_GEOMETRY viewport=",viewport," shell=",pane_bounds," body=",body.get_global_rect() if body!=null else Rect2()," footer=",work_footer.get_global_rect()," care=",care_rect," stock=",grid.get_global_rect()," detail=",details.get_global_rect())
	var shell_ok: bool=body!=null and toolbar!=null and viewport.encloses(pane_bounds) and pane_bounds.encloses(work_footer.get_global_rect()) and pane_bounds.encloses(grid.get_global_rect()) and pane_bounds.encloses(details.get_global_rect()) and not work_footer.get_global_rect().intersects(grid.get_global_rect()) and not work_footer.get_global_rect().intersects(details.get_global_rect())
	if not check(shell_ok,"bounded inventory shell, distinct panes and fixed footer inside compact viewport"):
		await capture("civilian-compact-layout-failure")
		await finish()
		return
	if not check(viewport.encloses(care_rect) and work_footer.get_global_rect().encloses(care_rect) and care_rect.size.y>=48,"care fully inside compact viewport and fixed footer"):
		await capture("civilian-compact-care-failure")
		await finish()
		return
	for child: Node in toolbar.get_children():
		if child is Button and child.is_visible_in_tree():
			var bounds: Rect2=child.get_global_rect()
			check(viewport.encloses(bounds) and toolbar.get_global_rect().encloses(bounds) and bounds.size.x>=48 and bounds.size.y>=48,"bounded fixed action "+str(child.name))
	if not await click("discard_preview"):
		await finish()
		return
	check(host.runtime.snapshot()==prior and button("discard_confirm")!=null and button("discard_cancel")!=null,"disposal preview is free and explicitly confirmed")
	if not await click("discard_cancel"):
		await finish()
		return
	check(host.runtime.snapshot()==prior and button("discard_confirm")==null,"disposal cancel leaves actual family untouched")
	var before_care_art: TextureRect=host._management.find_child("native_selected_art",true,false) as TextureRect
	check(before_care_art!=null and not before_care_art.get_meta("exterior_cleaned",true) and before_care_art.modulate!=Color.WHITE,"uncared item tint before explicit action")
	if not await click("care_exterior"):
		await finish()
		return
	var cared: Dictionary=host.runtime.snapshot()
	check(cared.items==prior.items and cared.wallets==prior.wallets and cared.game_minutes==prior.game_minutes and cared.ledger==prior.ledger,"exterior care no functional, price, money or clock changes")
	check(cared.revision==prior.revision+1 and cared.object_events.size()==prior.object_events.size()+1 and cared.object_events.back().type=="clean_exterior" and button("care_exterior")==null,"care recorded exactly once, no repeat button")
	var illustration: TextureRect=host._management.find_child("native_selected_art",true,false) as TextureRect
	check(illustration!=null and illustration.get_meta("exterior_cleaned",false) and illustration.modulate==Color.WHITE,"cosmetic visible care feedback without economic change")
	check(host._management._selected=="CR06" and host._management._revision==cared.revision and host._management._epoch>old_epoch and host._management._prepared_composition.is_empty(),"care refresh keeps selected root, invalidates old interaction previews")
	if not await detail_page("components") or not await select_component_slot("CR06_C"):
		await finish()
		return
	check(button("component_replace_CM06C")!=null and button(inventory_cell("CM06C"))!=null,"exchange endpoints available on direct component page")
	check(not host.runtime.item_history("CR06").items[0].history.work_records.is_empty(),"care in actual item lineage")
	prior=cared
	check_component_visible("component_replace_CM06C")
	if not await drag(inventory_cell("CM06C"),"component_replace_CM06C"):
		await finish()
		return
	check(host._management._prepared_kind=="replace_component" and host.runtime.snapshot()==prior,"real exchange drag preview only")
	var allocation: Dictionary=host.runtime.composition_options("CR06")
	check(allocation.family_basis.VKC==70 and allocation.material_basis.CM06C.VKC==15 and allocation.restore_cost.VKC==5,"actual incoming material and work cost projected")
	var confirm:Button=button("component_confirm")
	var cancel:Button=button("component_cancel")
	var footer:Control=host._management.find_child("inventory_fixed_footer",true,false) as Control
	check(confirm!=null and cancel!=null and footer!=null and footer.is_ancestor_of(confirm) and footer.is_ancestor_of(cancel) and root.get_visible_rect().encloses(confirm.get_global_rect()) and root.get_visible_rect().encloses(cancel.get_global_rect()) and footer.get_global_rect().encloses(confirm.get_global_rect()) and footer.get_global_rect().encloses(cancel.get_global_rect()),"confirm and cancel fully fixed within compact viewport")
	check_component_visible("component_projected_basis")
	check_component_visible("component_restore_cost")
	check_component_visible("component_cash_notice")
	check(label_text("component_projected_basis").contains("75 VKC") and label_text("component_restore_cost").contains("5 VKC"),"projected basis and separate restoration charge in preview")
	check(button("work_confirm")==null,"restoration cannot bypass pending composition")
	await capture("civilian-exchange-preview-720-ko")
	if not await click("component_cancel"):
		await finish()
		return
	check(host.runtime.snapshot()==prior,"compact exchange cancel free")
	if not await drag(inventory_cell("CM06C"),"component_replace_CM06C"):
		await finish()
		return
	await capture("civilian-exchange-preview-ko")
	if not await click("component_confirm") or not await click(inventory_cell("CR06")):
		await finish()
		return
	if not await detail_page("appraisal"):
		await finish()
		return
	check(label_text("appraisal_fact_CR06_functional").contains("재확인") and label_text("appraisal_basis_CR06").contains("75 VKC"),"stale aggregate evidence and current cost displayed")
	check_assessment_layout("CR06",["functional","complete","restored"])
	var stale_work:Button=button("work_confirm")
	check(stale_work==null or stale_work.disabled or not stale_work.is_visible_in_tree(),"stale whole evidence does not expose restoration")
	var before_review:Dictionary=host.runtime.snapshot()
	if not await click("inventory_observe_CR06_functional"):
		await finish()
		return
	check(host.runtime.snapshot().game_minutes==before_review.game_minutes and host.runtime.snapshot().wallets==before_review.wallets and label_text("appraisal_fact_CR06_functional").contains("아니오"),"free current evening defect review")
	if not await click("work_confirm") or not await click("work_next_day"):
		await finish()
		return
	root.size=Vector2i(1440,1000)
	await frames()
	var checkpoint:Dictionary=host.runtime.snapshot()
	check(host.runtime.view().day==7 and checkpoint.wallets.player.VKC==0 and checkpoint.items.CM06C.parent_id=="CR06" and not host.runtime.pending,"actual save after paid restoration")
	await close_host()
	await open_host()
	if not check(not host.runtime.blocked and host.runtime.snapshot()==checkpoint and not host._intro,"relaunch restores same D7 state and scene"):
		await finish()
		return
	# Advance unrelated authored visitors; the target resale is pointer-driven.
	for i:int in range(8):
		if not command("calendar_next_visit"):
			await finish()
			return
		if host.runtime.view().visits.active=="civil_receiver_condition_v2":
			break
		if not command("calendar_decline_visit",{"visit_id":host.runtime.view().visits.active}):
			await finish()
			return
	host.refresh()
	await frames()
	if not check(host.runtime.view().visits.active=="civil_receiver_condition_v2" and host._spatial.visible,"actual D7 resale at counter"):
		await finish()
		return
	check(host.runtime.view().condition_version==2 and host.runtime.view().condition_quote.tier=="verify_complete" and host.runtime.view().trade.amount==40 and button("spatial_fixed_confirm")==null,"counter rejects stale completeness")
	var slip:Label=host._spatial.find_child("spatial_fixed_price_label",true,false) as Label
	check(slip!=null and slip.text.contains("가격 미확정") and not slip.text.contains("40"),"blocked sale displays no confirmed price")
	root.size=Vector2i(1280,720)
	await frames()
	await capture("civilian-condition-unverified-ko")
	var unchanged:Dictionary=host.runtime.snapshot()
	if not await click("spatial_condition_inspect"):
		await finish()
		return
	check(host._management.visible and host._management._selected=="CR06" and host.runtime.snapshot()==unchanged,"direct inspection route selects owned item free")
	if not await click("inventory_return_counter"):
		await finish()
		return
	check(host._spatial.visible and host.runtime.snapshot()==unchanged,"return to same offer free")
	if not await click("spatial_condition_inspect"):
		await finish()
		return
	root.size=Vector2i(1440,1000)
	await frames()
	for key:String in ["complete","functional","restored"]:
		if not await click("inventory_observe_CR06_"+key):
			await finish()
			return
		var expect:Dictionary={"complete":40,"functional":110,"restored":150}
		check(host.runtime.view().trade.amount==expect[key],"evidence-driven quote stage "+key)
	check(label_text("appraisal_quality_CR06").contains("정비품") and label_text("appraisal_basis_CR06").contains("80 VKC"),"fresh host assessment and full basis")
	if not await detail_page("plan"):
		await finish()
		return
	check(label_text("disposition_sale").contains("150 VKC") and label_text("disposition_opportunity").contains("150 VKC") and label_text("disposition_basis").contains("80 VKC"),"actual quote and opportunity distinct from basis")
	if not await detail_page("appraisal"):
		await finish()
		return
	check_assessment_layout("CR06",["functional","complete","restored"])
	await capture("civilian-restored-assessment-ko")
	# Verify compact landscape, English, and larger UI font without changing game state.
	var observed:Dictionary=host.runtime.snapshot()
	root.size=Vector2i(1280,720)
	await frames()
	if not await click("language_pack_toggle") or not await click("language_toggle") or not await click("font_toggle") or not await click("language_pack_cancel"):
		await finish()
		return
	check(host.runtime.snapshot()==observed,"language/font presentation only")
	check_native_locale_navigation("en")
	if not await detail_page("plan"):
		await finish()
		return
	check(label_text("disposition_sale").contains("Current sale offer") and label_text("disposition_sale").contains("150 VKC"),"translated disposition actual quote")
	if not await detail_page("appraisal"):
		await finish()
		return
	check_assessment_layout("CR06",["functional","complete","restored"])
	await capture("civilian-restored-assessment-720-en")
	if not await click("language_pack_toggle") or not await click("font_toggle") or not await click("language_pack_cancel"):
		await finish()
		return
	check(host._prefs.font_size==24 and host.runtime.snapshot()==observed,"150 percent English review preserves authority")
	await responsive_assessment_review()
	if not await click("language_pack_toggle") or not await click("font_toggle") or not await click("language_toggle") or not await click("language_pack_cancel"):
		await finish()
		return
	check_native_locale_navigation("ko")
	root.size=Vector2i(1440,1000)
	await frames()
	if not await click("inventory_return_counter"):
		await finish()
		return
	check(host.runtime.view().condition_quote.tier=="refurbished" and host.runtime.view().trade.amount==150 and button("spatial_fixed_confirm")!=null,"counter refreshed public evidence quote")
	await capture("civilian-condition-refurbished-ko")
	if not await click("spatial_fixed_confirm"):
		await finish()
		return
	check(host.runtime.snapshot().items.CR06.owner_id=="G07" and host.runtime.snapshot().items.CR06_C.owner_id=="player" and host.runtime.view().wallet.VKC==150,"sale settlement with residual component")
	if not await click("history_toggle"):
		await finish()
		return
	var history_before:Dictionary=host.runtime.snapshot()
	check(host._history.find_child("history_item_CR06",true,false)!=null,"transaction history is available")
	if not await click("history_item_CR06"):
		await finish()
		return
	check(host._history.find_children("history_trade_*_CR06","Label",true,false).size()>0 and host.runtime.snapshot()==history_before,"direct history detail retains actual sale records")
	await capture("civilian-resale-history-ko")
	var ledger_back:=button("office_ledger_back")
	check(ledger_back!=null and ledger_back.text==host.tr_key("menu.back"),"history back is navigation not card reverse")
	if not await click("office_ledger_back"):
		await finish()
		return
	if not await click("history_toggle") or not await click("close_day") or not await click("work_next_day"):
		await finish()
		return
	var final:Dictionary=host.runtime.snapshot()
	check(host.runtime.view().complete and final.wallets.player.VKC==135 and final.game_minutes==10080,"candidate week complete")
	await close_host()
	await open_host()
	check(not host.runtime.blocked and host.runtime.snapshot()==final and host.runtime.view().complete,"completed candidate reload exact")
	await finish()

# A real fixed tab, not an artificial scroll or authority command.
func detail_page(page:String)->bool:
	var before:Dictionary=host.runtime.snapshot()
	if host._management._detail_page!=page:
		if not await click("inventory_detail_"+page):
			return false
	var tabs:=host._management.find_child("inventory_detail_tabs",true,false) as Control
	check(tabs!=null and root.get_visible_rect().encloses(tabs.get_global_rect()),"detail tabs remain in viewport")
	check(host._management._detail_page==page and host.runtime.snapshot()==before,"detail page preserves state "+page)
	var section:=host._management.find_child("inventory_section_"+page,true,false) as Control
	check(section!=null and section.is_visible_in_tree(),"selected detail page visible "+page)
	for other:String in ["overview","appraisal","components","plan","history"]:
		if other==page:
			continue
		var hidden:=host._management.find_child("inventory_section_"+other,true,false) as Control
		check(hidden==null or not hidden.is_visible_in_tree(),"unselected detail page not stacked "+other)
	return true

func select_component_slot(item_id:String)->bool:
	var data:Dictionary=host.runtime.composition_options(host._management._selected)
	var index:int=-1
	for i:int in range(data.get("slots",[]).size()):
		if data.slots[i].item_id==item_id:
			index=i
			break
	if not check(index>=0,"public component slot exists"):
		return false
	var before:Dictionary=host.runtime.snapshot()
	while host._management._component_page!=index:
		if not await click("component_slot_next" if host._management._component_page<index else "component_slot_previous"):
			return false
	check(host.runtime.snapshot()==before,"slot paging is read-only")
	check(host._management.find_children("component_slot_card","PanelContainer",true,false).size()==1,"one visible slot card")
	return true

func check_component_visible(id:String)->void:
	var node:=host._management.find_child(id,true,false) as Control
	var pane:Control=host._management._detail_scroll
	check(node!=null and node.is_visible_in_tree() and pane.get_global_rect().encloses(node.get_global_rect()) and root.get_visible_rect().encloses(node.get_global_rect()),"component control visible without scrolling "+id)


func responsive_assessment_review()->void:
	var snapshot:Dictionary=host.runtime.snapshot()
	var previous_size:Vector2i=root.size
	var previous_scale:Vector2i=root.content_scale_size
	for dimensions:Vector2i in [Vector2i(1280,720),Vector2i(960,720)]:
		root.content_scale_size=dimensions
		root.size=dimensions
		await frames()
		var tag:String=str(dimensions.x)+"x"+str(dimensions.y)
		print("ZT_RESPONSIVE_ASSESSMENT EN150 ",tag," viewport=",root.get_visible_rect())
		check(root.get_visible_rect().size==Vector2(dimensions),"explicit assessment viewport "+tag)
		check(host._management._detail_page=="appraisal" and host._management._selected=="CR06","resize/font preserves assessment context "+tag)
		for key:String in ["functional","complete","restored"]:
			var row:=host._management.find_child("appraisal_row_CR06_"+key,true,false) as Control
			check(row!=null and host._management._detail_scroll.get_global_rect().encloses(row.get_global_rect()) and root.get_visible_rect().encloses(row.get_global_rect()),"150 percent assessment row visible without reveal "+key+" "+tag)
		var return_button:=button("inventory_return_counter")
		check(return_button!=null and root.get_visible_rect().encloses(return_button.get_global_rect()),"150 percent fixed return "+tag)
		check(host.runtime.snapshot()==snapshot,"resize read-only "+tag)
		var status:=host.find_child("native_hud_status",true,false) as Label
		check(status!=null and status.is_visible_in_tree() and not host._feedback.is_visible_in_tree() and status.text==host.tr_key("ui.copy.completed_12ead41e"),"generic feedback shares HUD without losing translated text "+tag)
		check(status!=null and root.get_visible_rect().encloses(status.get_global_rect()),"compact status within viewport "+tag)
		await capture("responsive-assessment-en150-"+tag)
		if dimensions.x==960:
			var grid_column:=host._management.find_child("inventory_grid_column",true,false) as Control
			var grid_back:=button("inventory_detail_grid")
			check(grid_column!=null and not grid_column.is_visible_in_tree() and grid_back!=null and root.get_visible_rect().encloses(grid_back.get_global_rect()),"compact appraisal has explicit grid return")
			for action_id:String in ["stock_rotate","stock_confirm","stock_cancel"]:
				var action:=host._management.find_child(action_id,true,false) as Button
				check(action!=null and not action.is_visible_in_tree(),"compact appraisal hides placement action "+action_id)
			if not await click("inventory_detail_grid"):
				return
			var grid:=host._management.find_child("spatial_grid_player_stock",true,false) as Control
			check(grid!=null and grid.is_visible_in_tree() and host._management._stock_scroll.get_global_rect().encloses(grid.get_global_rect()) and host._management._selected=="CR06" and host.runtime.snapshot()==snapshot,"return to full grid keeps item and evidence")
			var rotate:=host._management.find_child("stock_rotate",true,false) as Button
			check(rotate!=null and rotate.is_visible_in_tree(),"grid return restores eligible placement actions")
			if not await detail_page("appraisal"):
				return
			for key:String in ["functional","complete","restored"]:
				var row:=host._management.find_child("appraisal_row_CR06_"+key,true,false) as Control
				check(row!=null and host._management._detail_scroll.get_global_rect().encloses(row.get_global_rect()) and root.get_visible_rect().encloses(row.get_global_rect()),"reopened compact assessment row "+key)
			check(host.runtime.snapshot()==snapshot,"compact grid/detail navigation read-only")
			if not await detail_page("plan"):
				return
			grid_column=host._management.find_child("inventory_grid_column",true,false) as Control
			check(grid_column!=null and not grid_column.is_visible_in_tree(),"compact plan uses full reading width")
			for field:String in ["disposition_basis","disposition_sale","disposition_hold","disposition_opportunity","disposition_recover","disposition_recover_count","disposition_restore","disposition_demand","disposition_basis_notice"]:
				var label:=host._management.find_child(field,true,false) as Label
				check(label!=null and host._management._detail_scroll.get_global_rect().encloses(label.get_global_rect()),"compact plan primary field visible "+field)
			check(label_text("disposition_sale").contains("150 VKC") and label_text("disposition_basis").contains("80 VKC"),"compact plan retains actual offer and basis")
			var comparison:=host._management.find_child("disposition_comparison",true,false) as GridContainer
			check(comparison!=null and comparison.columns==2 and comparison.get_child_count()==4,"compact plan has four alternatives in two columns")
			var details:=host._management.find_child("disposition_details",true,false) as Control
			check(details!=null and not details.is_visible_in_tree(),"long plan details optional by default")
			var plan_toggle:=button("disposition_details_toggle")
			check(plan_toggle!=null and host._management._detail_scroll.get_global_rect().encloses(plan_toggle.get_global_rect()),"compact plan details toggle visible without reveal")
			var compact_header:=host._management.find_child("native_work_light",true,false) as Control
			check(compact_header!=null and not compact_header.is_visible_in_tree(),"compact plan prioritizes decision content over decorative header")
			await capture("responsive-plan-en150-960x720")
			if not await click("disposition_details_toggle"):
				return
			check(details!=null and details.is_visible_in_tree() and host.runtime.snapshot()==snapshot,"plan details expansion is read-only")
			if not await click("disposition_details_toggle"):
				return
			check(details!=null and not details.is_visible_in_tree() and host.runtime.snapshot()==snapshot,"plan details collapse is read-only")
			if not await detail_page("history"):
				return
			var records:=host._management.find_child("inventory_history_records",true,false) as ScrollContainer
			check(records!=null and records.is_visible_in_tree() and host._management._detail_scroll.get_global_rect().encloses(records.get_global_rect()),"compact history reader fully inside viewport pane")
			check(host._management._detail_scroll.vertical_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED and records!=null and records.size.y>=160,"history owns one expanded scroll region")
			check(records!=null and records.find_children("history_trade_*_CR06","Label",true,false).size()>0,"compact history retains actual transaction records")
			check(host.runtime.snapshot()==snapshot,"plan/history navigation preserves authority")
			var history_header:=host._management.find_child("native_work_light",true,false) as Control
			check(history_header!=null and not history_header.is_visible_in_tree(),"compact history prioritizes records over lighting vignette")
			await capture("responsive-history-en150-960x720")
			# Inject a presentation-only diagnostic, not a game command: ensure
			# the compact HUD never hides a non-generic or suffixed message.
			host._set_feedback("ui.copy.unavailable_e8505c55"," [fixture diagnostic]")
			await frames()
			check(host._feedback.is_visible_in_tree() and host._feedback.text.ends_with(" [fixture diagnostic]") and not status.is_visible_in_tree(),"diagnostic feedback keeps full-width row and suffix")
			check(root.get_visible_rect().encloses(host._feedback.get_global_rect()) and host.runtime.snapshot()==snapshot,"diagnostic presentation is visible and read-only")
			host._set_feedback("ui.copy.completed_12ead41e")
			await frames()
			check(status.is_visible_in_tree() and not host._feedback.is_visible_in_tree(),"generic feedback returns to shared HUD")
			if not await detail_page("appraisal"):
				return
	root.content_scale_size=previous_scale
	root.size=previous_size
	await frames()
	var restored_grid:=host._management.find_child("inventory_grid_column",true,false) as Control
	check(restored_grid!=null and restored_grid.is_visible_in_tree() and host._management._detail_page=="appraisal" and host.runtime.snapshot()==snapshot,"wide resize restores split with same item/evidence")
	var wide_rotate:=host._management.find_child("stock_rotate",true,false) as Button
	check(wide_rotate!=null and wide_rotate.is_visible_in_tree(),"wide split restores eligible placement actions")
	var wide_header:=host._management.find_child("native_work_light",true,false) as Control
	check(wide_header!=null and wide_header.is_visible_in_tree(),"wide workspace retains lighting vignette")

# Actual locale switch with a previously completed operation: the status is
# translated again from its stable key without clearing failure information.
func check_native_locale_navigation(locale:String)->void:
	check(host.runtime.localization.current_locale()==locale,"expected native locale "+locale)
	check(host._history_button.text==host.tr_key("ui.location.history") and host._stock_button.text==host.tr_key("ui.location.inventory"),"localized HUD navigation "+locale)
	check(host._slot_open.text==host.tr_key("ui.copy.open_fc52508") and host._slot.get_item_text(0)==host.tr_key("menu.slot")+" 1","localized slot controls "+locale)
	check(host._feedback_key=="ui.copy.completed_12ead41e" and host._feedback.text==host.tr_key(host._feedback_key),"previous operation feedback retranslated "+locale)
