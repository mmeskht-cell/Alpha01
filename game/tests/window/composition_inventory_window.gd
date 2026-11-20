extends SceneTree
const Session=preload("res://src/domain/game_session.gd")
const Fixture=preload("res://tests/fixtures/gate0_c_state.gd")
const Objects=preload("res://src/domain/object_schema.gd")
const Management=preload("res://src/presentation/spatial_management.gd")
const EN=preload("res://locales/en/core.po")
var authority:RefCounted
var panel:Control
var defs:Dictionary={}
var checks:int=0
var failures:int=0
var committed:Dictionary={}
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
func find_button(id:String)->Button:
	for node:Node in panel.find_children(id,"Button",true,false):
		if node.is_visible_in_tree() and not node.disabled:
			return node
	return null
func pointer(p:Vector2,down:bool)->void:
	var e:=InputEventMouseButton.new()
	e.button_index=MOUSE_BUTTON_LEFT
	e.pressed=down
	e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	e.position=p
	e.global_position=p
	root.push_input(e,true)
func motion(p:Vector2,prior:Vector2)->void:
	var e:=InputEventMouseMotion.new()
	e.position=p
	e.global_position=p
	e.relative=p-prior
	e.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(e,true)
func reveal(node:Control)->void:
	var p:Node=node.get_parent()
	while p!=null:
		if p is ScrollContainer:
			p.ensure_control_visible(node)
		p=p.get_parent()
	await frames()
func click(id:String)->bool:
	var b:Button=find_button(id)
	if not check(b!=null,"visible control "+id):
		return false
	await reveal(b)
	var p:Vector2=b.get_global_rect().get_center()
	if not check(root.get_visible_rect().has_point(p),"visible viewport "+id):
		return false
	pointer(p,true)
	pointer(p,false)
	await frames()
	return true
func drag(a_id:String,b_id:String)->bool:
	var a:Button=find_button(a_id)
	var b:Button=find_button(b_id)
	if not check(a!=null and b!=null,"drag controls "+a_id+" "+b_id):
		return false
	await reveal(b)
	await reveal(a)
	var start:Vector2=a.get_global_rect().get_center()
	var end:Vector2=b.get_global_rect().get_center()
	if not check(root.get_visible_rect().has_point(start) and root.get_visible_rect().has_point(end),"drag endpoints in viewport"):
		return false
	pointer(start,true)
	motion(start+Vector2(25,-25),start)
	await frames()
	var dragging:bool=root.gui_is_dragging()
	motion(end,start+Vector2(25,-25))
	await frames()
	pointer(end,false)
	await frames()
	return check(dragging and not root.gui_is_dragging(),"actual pointer drag")
func refresh()->void:
	var s:Dictionary=authority.snapshot()
	var stock:Array=[]
	var work:Array=[]
	for id:String in s.items:
		var row:Dictionary=s.items[id]
		if row.custodian_id!="player" or not row.parent_id.is_empty():
			continue
		var size:Array=Objects.footprint(s,defs,id)
		if row.rotated:
			size=[size[1],size[0]]
		stock.append({"id":id,"label":defs[row.def_id].localization_key,"inventory":row.inventory,"owned":row.owner_id=="player","basis":row.basis,"x":row.x,"y":row.y,"width":size[0],"height":size[1],"rotated":row.rotated})
		var d:Dictionary=defs[row.def_id]
		if d.category=="civilian_electronics" and s.phase=="workshop" and row.owner_id=="player" and not row.functional and d.restorable:
			work.append({"id":id,"cost":d.restore_cost.duplicate(true)})
	panel.configure({"revision":s.revision,"phase":s.phase,"wallet":s.wallets.player,"stock":stock,"stock_inventory_id":"player_grid","stock_grids":[{"id":"player_grid","width":10,"height":6}],"work":work,"locked":false,"complete":false},"inventory",func(key:String,arguments:Dictionary={})->String: return str(EN.get_message(key)).format(arguments),"en",0)
func submit(kind:String,p:Dictionary,revision:int)->void:
	committed=authority.execute({"action_id":"inventory_probe_"+str(revision+1),"expected_revision":revision,"type":kind,"payload":p})
	check(committed.ok,"authority commit "+kind+" "+str(committed.get("error","")))
	refresh()
func run()->void:
	root.size=Vector2i(1280,900)
	defs=Fixture.definitions()
	authority=Session.new()
	if not check(authority.initialize(defs,Fixture.make()),"fixture initialize "+authority.initialization_error()):
		await finish()
		return
	var bought:Dictionary=authority.execute(Fixture.purchase())
	if not check(bought.ok,"fixture purchase "+str(bought.get("error",""))):
		await finish()
		return
	panel=Management.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.size=Vector2(root.size)
	panel.composition_query=func(id:String)->Dictionary: return authority.composition_options(id,"player_grid")
	panel.action_requested.connect(submit)
	refresh()
	await frames()
	if not await click("stock_cell_player_grid_0_0"):
		await finish()
		return
	check(find_button("component_detach_sample_insert_a")==null,"day component removal disabled")
	var evening:Dictionary=authority.snapshot()
	evening.phase="workshop"
	if not check(authority.restore(evening),"trusted evening fixture"):
		await finish()
		return
	refresh()
	await frames()
	if not await click("stock_cell_player_grid_0_0"):
		await finish()
		return
	var before:Dictionary=authority.snapshot()
	if not await drag("component_detach_sample_insert_a","stock_cell_player_grid_0_0"):
		await finish()
		return
	check(panel._prepared_composition.is_empty() and authority.snapshot()==before,"occupied/root collision rejects drop")
	if not await drag("component_detach_sample_insert_a","stock_cell_player_grid_6_2"):
		await finish()
		return
	check(panel._prepared_kind=="detach" and panel._prepared_composition.get("x")==6 and panel._prepared_composition.get("y")==2 and authority.snapshot()==before,"valid chosen location previews only")
	if not await click("stock_cell_player_grid_8_4"):
		await finish()
		return
	check(panel._prepared_composition.is_empty() and panel._destination==Vector2i(8,4) and authority.snapshot()==before,"stock relocation replaces composition preview without mutation")
	if not await drag("component_detach_sample_insert_a","stock_cell_player_grid_6_2"):
		await finish()
		return
	check(panel._destination==Vector2i(-1,-1) and panel._prepared_kind=="detach","composition preview replaces stock move")
	if not await click("component_cancel"):
		await finish()
		return
	check(authority.snapshot()==before and panel._prepared_composition.is_empty(),"cancel no mutation")
	if not await drag("component_detach_sample_insert_a","stock_cell_player_grid_6_2") or not await click("component_confirm"):
		await finish()
		return
	var detached:Dictionary=authority.snapshot()
	check(detached.items.X01_A.parent_id=="" and detached.items.X01_A.inventory=="player_grid" and detached.items.X01_A.x==6 and detached.items.X01_A.y==2,"exact detached location and ID")
	check(detached.wallets==before.wallets and detached.game_minutes==before.game_minutes and Objects.basis(detached,detached.items.keys()).basis.VKC==70,"cost time and basis conserved")
	if not await click("stock_cell_player_grid_0_0") or not await drag("stock_cell_player_grid_6_2","component_attach_X01_A"):
		await finish()
		return
	check(panel._prepared_kind=="attach" and authority.snapshot()==detached,"attach drag previews only")
	if not await click("component_confirm"):
		await finish()
		return
	var final:Dictionary=authority.snapshot()
	check(final.items.X01_A.parent_id=="X01" and final.items.X01_A.inventory=="" and final.items.size()==4,"same component reattached without duplication")
	check(Objects.basis(final,final.items.keys()).basis.VKC==70 and final.wallets==before.wallets and final.game_minutes==before.game_minutes,"roundtrip economic invariants")
	var exchange_seed:Dictionary=final.duplicate(true)
	exchange_seed.items["SPARE_A"]=Objects.fresh_item("sample_insert_a","player","player_grid",6,2,"fixture_spare_a")
	exchange_seed.items.SPARE_A.basis={"VKC":15,"USD":0}
	if not check(authority.restore(exchange_seed),"isolated spare abstract component"):
		await finish()
		return
	refresh()
	await frames()
	if not await click("stock_cell_player_grid_0_0") or not await drag("stock_cell_player_grid_6_2","component_replace_SPARE_A"):
		await finish()
		return
	var exchange_before:Dictionary=authority.snapshot()
	check(panel._prepared_kind=="replace_component" and exchange_before==exchange_seed,"exchange drag is only a preview")
	if not await click("component_confirm"):
		await finish()
		return
	var exchanged:Dictionary=authority.snapshot()
	check(exchanged.items.SPARE_A.parent_id=="X01" and exchanged.items.X01_A.parent_id=="" and exchanged.items.X01_A.x==6 and exchanged.items.X01_A.y==2,"atomic exchange uses freed spare cell")
	check(exchanged.revision==exchange_before.revision+1 and exchanged.wallets==exchange_before.wallets and Objects.basis(exchanged,exchanged.items.keys()).basis.VKC==85,"one exchange event and conserved basis")
	await civilian_route()
	await finish()
func finish()->void:
	if is_instance_valid(panel):
		root.remove_child(panel)
		panel.queue_free()
		await frames()
	authority=null
	print("GATE2_COMPOSITION_WINDOW: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)

func fact_text(id:String,key:String)->String:
	var node:Label=panel.find_child("appraisal_fact_"+id+"_"+key,true,false) as Label
	return node.text if node!=null else ""

func label_text(id:String)->String:
	var node:Label=panel.find_child(id,true,false) as Label
	return node.text if node!=null else ""

func trusted_command(kind:String,p:Dictionary)->bool:
	var revision:int=authority.snapshot().revision
	var result:Dictionary=authority.execute({"action_id":"civilian_pointer_"+str(revision+1),"expected_revision":revision,"type":kind,"payload":p})
	return check(result.ok,"civilian fixture setup "+kind+" "+str(result.get("error","")))

func civilian_route()->void:
	# Independent synthetic calendar; original seven-day scenario and save IDs untouched.
	root.remove_child(panel)
	panel.queue_free()
	await frames()
	authority=Session.new()
	defs=Fixture.definitions()
	for id:String in ["sample_device","sample_insert_a","sample_insert_b","sample_insert_c"]:
		defs[id].category="civilian_electronics"
	var seed:Dictionary=Fixture.make()
	seed.wallets.player.USD=3
	seed.items["SPARE_C"]=Objects.fresh_item("sample_insert_c","seller","seller_grid",6,2,"civilian_spare_c")
	seed.visits["buy_spare"]=Fixture.visit("buy_spare","seller","player",{"SPARE_C":{"VKC":15,"USD":0}})
	seed.visits["resell_device"]=Fixture.visit("resell_device","player","buyer",{"X01":{"VKC":150,"USD":0}})
	seed.visits.resell_device.opens=1440
	var profile:Dictionary={"id":"demo_7","content_version":"civilian_assessment_pointer_1","day_ids":["d1","d2","d3","d4","d5","d6","d7"]}
	if not check(authority.initialize(defs,seed,false,false,profile),"civilian pointer initialize "+authority.initialization_error()):
		return
	if not check(authority.execute(Fixture.purchase()).ok,"civilian pointer purchase") or not trusted_command("trade",{"visit_id":"buy_spare","item_id":"SPARE_C","seller":"seller","buyer":"player","currency":"VKC","amount":15,"inventory":"player_grid","x":6,"y":2,"rotated":false}):
		return
	panel=Management.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.size=Vector2(root.size)
	panel.composition_query=func(id:String)->Dictionary: return authority.composition_options(id,"player_grid")
	panel.appraisal_query=func(id:String)->Dictionary: return authority.inventory_appraisal(id)
	panel.action_requested.connect(submit)
	refresh()
	await frames()
	var before:Dictionary=authority.snapshot()
	if not await click("stock_cell_player_grid_0_0"):
		return
	check(fact_text("X01","functional").contains("Unknown") and label_text("appraisal_basis_X01").contains("70 VKC") and authority.snapshot()==before,"unknown condition and actual basis only")
	if not await click("inventory_observe_X01_functional"):
		return
	check(fact_text("X01","functional").contains("Known: No") and authority.snapshot().game_minutes==before.game_minutes and authority.snapshot().wallets==before.wallets and panel._selected=="X01","whole observation updates in place")
	if not await click("component_appraisal_X01_C"):
		return
	check(fact_text("X01_C","functional").contains("Unknown"),"individual part still unknown")
	if not await click("inventory_observe_X01_C_functional"):
		return
	check(fact_text("X01_C","functional").contains("Known: No") and authority.snapshot().game_minutes==before.game_minutes and authority.snapshot().wallets==before.wallets and panel._appraisal_target=="X01_C","component observation retains target")
	if not trusted_command("calendar_close",{}):
		return
	refresh()
	await frames()
	if not await click("stock_cell_player_grid_0_0") or not await click("component_replace_SPARE_C"):
		return
	var pre:Dictionary=authority.snapshot()
	check(panel._prepared_kind=="replace_component","exchange selected")
	if not await click("component_confirm"):
		return
	check(authority.snapshot().revision==pre.revision+1,"exchange single command")
	if not await click("stock_cell_player_grid_0_0"):
		return
	check(fact_text("X01","functional").contains("Historical") and label_text("appraisal_basis_X01").contains("75 VKC"),"stale whole observation and new family basis visible")
	var evening_before:Dictionary=authority.snapshot()
	var evening_review:Button=find_button("inventory_observe_X01_functional")
	check(evening_review!=null and not evening_review.disabled,"owned evening inspection enabled")
	if not await click("inventory_observe_X01_functional"):
		return
	check(authority.snapshot().game_minutes==evening_before.game_minutes and authority.snapshot().wallets==evening_before.wallets and fact_text("X01","functional").contains("Known: No"),"evening review samples actual state at no clock or cash cost")
	if not await click("work_confirm"):
		return
	if not await click("stock_cell_player_grid_0_0"):
		return
	check(label_text("appraisal_basis_X01").contains("80 VKC"),"actual restoration expense reflected in basis")
	if not await click("work_next_day") or not await click("stock_cell_player_grid_0_0"):
		return
	for key:String in ["functional","complete","restored"]:
		if not await click("inventory_observe_X01_"+key):
			return
	check(fact_text("X01","functional").contains("Known: Yes") and label_text("appraisal_quality_X01").contains("Refurbished"),"fresh assessment confirms restored assembly")
	if not trusted_command("trade",{"visit_id":"resell_device","item_id":"X01","seller":"player","buyer":"buyer","currency":"VKC","amount":150,"inventory":"buyer_grid","x":0,"y":0,"rotated":false}):
		return
	refresh()
	await frames()
	var final:Dictionary=authority.snapshot()
	check(final.wallets.player.VKC==225 and final.wallets.player.USD==1 and final.items.X01_C.owner_id=="player" and authority.inventory_appraisal("X01").is_empty(),"resale settlement and residual stock exact")
	print("ZT_CIVILIAN_ASSESSMENT_POINTER_DONE")
