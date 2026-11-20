extends "res://tests/window/spatial_demo7_window.gd"
## Real runtime and pointer path at both representative physical resolutions.
var _expected_pixels:Vector2i=Vector2i(1280,720)
var _wholesale:bool=false

func capture(id:String)->void:
	await frames()
	await RenderingServer.frame_post_draw
	var img:Image=root.get_texture().get_image()
	if not check(img!=null and not img.is_empty(),"actual rendered image "+id):
		return
	check(img.get_size()==_expected_pixels,"actual capture dimensions "+id+" "+str(img.get_size()))
	check(img.save_png(out.path_join(id+".png"))==OK,"capture "+id)
func finish()->void:
	print("GATE2_NATIVE_V23_WINDOW: ",checks," checks, ",failures," failures")
	await super.finish()

func verify_single_view()->void:
	var art:TextureRect=host._spatial._item
	check(art.texture.resource_path.ends_with("native_v23/radio_front.png"),"fixed representative imported texture")
	check(art.texture.get_size()==Vector2(192,144),"exact source dimensions")
	check(art.size.y>0 and absf(art.size.x/art.size.y-4.0/3.0)<0.01,"texture rect fits actual aspect")
	for id:String in host._spatial._regions:
		var target:Control=host._spatial._regions[id]
		var expected:Rect2=host._spatial._face_regions()[id]
		var actual:Rect2=target.get_global_rect()
		var photo:Rect2=art.get_global_rect()
		check(actual.position.distance_to(photo.position+expected.position*photo.size)<2.0 and actual.size.distance_to(expected.size*photo.size)<2.0,"sprite-local single view region "+id)

# Exercise every authored room/time combination before the real pointer route.
func verify_space_layers()->void:
	var profile=preload("res://src/presentation/native_v23_art.gd")
	for kind:String in ["office","stock"]:
		for i:int in range(6):
			var scene:Control=profile.space_preview(kind,{"minute":i*120,"phase":"shop"},Vector2(320,180))
			if not check(scene!=null,"construct room "+kind+" time "+str(i)):
				continue
			check(scene.get_child_count()==5 and scene.get_meta("time_index")==i and scene.mouse_filter==Control.MOUSE_FILTER_IGNORE,"five passive layers "+kind+" time "+str(i))
			for j:int in range(scene.get_child_count()):
				var image:=scene.get_child(j) as TextureRect
				check(image!=null and image.texture!=null and image.texture.get_size()==Vector2(640,360) and image.mouse_filter==Control.MOUSE_FILTER_IGNORE and image.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"room layer imported and passive "+kind+" "+str(i)+" "+str(j))
			scene.free()

func verify_public_reference_guide()->void:
	var guide=preload("res://src/presentation/public_reference_guide.gd")
	var docs=preload("res://src/content/packaged_documents.gd")
	var visual=preload("res://src/presentation/public_appraisal_visuals.gd")
	for path:String in ["res://data/campaign/gate2/demo_radio_catalog.json","res://data/campaign/gate2/watch_public_catalog.json"]:
		var catalog:Dictionary=docs.read_object(path)
		check(not catalog.is_empty(),"public guide catalog loaded")
		if catalog.def_id=="portable_radio":
			check(guide.related_chapters(catalog,"R001.casing_detail")==[0,1,3],"mark topic navigates all related chapters, not a single answer")
			check(guide.related_chapters(catalog,"R001.function").is_empty(),"no invented radio function judgment slot")
		else:
			check(guide.related_chapters(catalog,"back_mark")==[0,4],"watch mark connects model and special topics")
		check(guide.related_chapters(catalog,"unknown").is_empty(),"unknown observation topic adds no relation")
		for slot:Dictionary in catalog.get("slots",[]):
			for candidate:Dictionary in slot.candidates:
				check(not guide.description_key(candidate).is_empty(),"public candidate has explanatory reference "+str(candidate.id))
			if catalog.def_id=="fictional_watch_p2" and slot.id in ["material_id","function_id","mark_id"]:
				var text_row:Dictionary=guide.comparison(catalog,slot)
				check(text_row.get("kind")=="text" and text_row.get("entries",[]).size()==2,"both public watch alternatives "+str(slot.id))
				if text_row.get("entries",[]).size()==2:
					check(text_row.entries[0].sample!=text_row.entries[1].sample,"distinct public comparison "+str(slot.id))
			if slot.id=="model_id":
				var comparison:Dictionary=guide.comparison(catalog,slot)
				check(comparison.get("entries",[]).size()==2,"both public models represented "+str(catalog.def_id))
				var incomplete:Dictionary=slot.duplicate(true)
				incomplete.candidates.pop_back()
				check(guide.comparison(catalog,incomplete).is_empty(),"incomplete guide no inferred answer")
			if slot.id=="appearance_id":
				var wear_examples:Dictionary=guide.comparison(catalog,slot)
				check(wear_examples.get("kind")=="wear" and wear_examples.get("entries",[]).size()==3,"three public cosmetic examples "+str(catalog.def_id))
	check(visual.wear_reference("unmapped")==null,"unsupported wear example has no image")
	var light:Texture2D=visual.wear_reference("light")
	var heavy:Texture2D=visual.wear_reference("heavy")
	check(light!=null and heavy!=null and light.get_image().get_data()!=heavy.get_image().get_data(),"distinct public wear example drawings")
	check(visual.acquired_display({"current":false,"is_claim":false,"evidence_id":"fixture","observation_key":"back_mark","observed_value":"M12"},Callable())==null,"stale mark has no acquired image")
	check(visual.acquired_display({"current":true,"is_claim":true,"evidence_id":"fixture","observation_key":"back_mark","observed_value":"M12"},Callable())==null,"customer claim has no acquired image")

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()<1 or args.size()>2 or (args.size()==2 and args[1] not in ["1920x1080","wholesale"]):
		quit(2)
		return
	out=args[0]
	if args.size()==2:
		if args[1]=="1920x1080":
			_expected_pixels=Vector2i(1920,1080)
		else:
			_wholesale=true
	root.size=_expected_pixels
	host=preload("res://scenes/app/integrated_b_candidate.tscn").instantiate()
	host.save_directory_override="user://zt_rebuild/demo7/native_v23_test_"+str(Time.get_ticks_usec())
	root.add_child(host)
	await frames()
	verify_space_layers()
	verify_public_reference_guide()
	check(host.runtime.view().civilian_candidate and host.runtime.view().condition_version==2 and host.preview_native_v23,"same integrated evaluation scene and additive profile")
	if failures>0:
		await finish()
		return
	if not await click("intro_skip"):
		await finish()
		return
	var opening:Dictionary=host.runtime.snapshot()
	check(host.theme.get_color("font_color","Label")==Color("#D5D0C3"),"approved native palette")
	check(host._native_location.get_meta("mode")=="counter","opening counter location")
	check(host._head.get_parent()==host._native_location.get_parent() and not host._head.text.contains("EXIT NOT INCLUDED"),"single compact header without development branding")
	check(button("language_toggle")==null and button("font_toggle")==null and button("open_slot")==null,"settings controls removed from gameplay toolbar")
	if not await click("office_toggle") or not await click("office_tab_news"):
		await finish()
		return
	check(host._office.visible and host._office.find_child("office_news_heading",true,false)!=null and host.runtime.snapshot()==opening,"office news free and public")
	check(host._native_location.get_meta("mode")=="office","office navigation status")
	var office_art:=host._office.find_child("office_room_layer",true,false) as TextureRect
	check(office_art!=null and office_art.texture.resource_path.ends_with("/rooms/office_room.png") and office_art.mouse_filter==Control.MOUSE_FILTER_IGNORE,"independent office room art")
	var office_scene:=host._office.find_child("office_art_scene",true,false) as Control
	check(office_scene!=null and office_scene.get_meta("time_index")==0,"office clock at opening")
	await capture("native-v24-terminal")
	if not await click("office_tab_contracts"):
		await finish()
		return
	check(host.runtime.snapshot()==opening,"contract browsing free")
	var paper_title:=host._office.find_child("office_contract_rad1_first",true,false) as Label
	check(paper_title!=null and paper_title.get_theme_color("font_color")==Color("#252A2D"),"readable paper document ink")
	await capture("native-v24-contract")
	if not await click("office_contract_accept_rad1_first"):
		await finish()
		return
	check(host.runtime.view().obligations.contracts.rad1_first.status=="reserved" and host.runtime.view().wallet.VKC==180 and host.runtime.view().minute==0,"same authority contract accepted")
	if not await click("office_toggle") or not await click("next_customer"):
		await finish()
		return
	check(host._spatial.visible and host._spatial._uses_native_r001(),"opt-in actual first visitor")
	check(host._native_location.get_meta("mode")=="inspection","inspection navigation status")
	var before:Dictionary=host.runtime.snapshot()
	var profile=preload("res://src/presentation/native_v23_art.gd")
	check(host._spatial._native_index==profile.time_index(host.runtime.view()),"live DTO clock drives light index")
	check(host._spatial._native_window.visible and host._spatial._native_lamp.visible,"independent room and lamp layers")
	for i:int in range(6):
		check(profile.time_index({"minute":i*120,"phase":"shop"})==i,"clock projection anchor "+str(i))
	check(profile.time_index({"minute":600,"phase":"workshop"})==5 and profile.time_index({"minute":1440,"phase":"shop"})==0,"actual workshop phase and next-day mapping (pure projection)")
	check(host.runtime.snapshot()==before,"read-only light projection")
	verify_single_view()
	verify_art_swap()
	verify_shared_item_profiles()
	verify_scene_art_swap()
	var wear_target:=button("region_wear_detail")
	check(wear_target!=null and wear_target.modulate.a==1.0 and wear_target.get_theme_stylebox("normal") is StyleBoxFlat,"clear native target outline")
	check(button("flip_item")==null,"no face rotation action")
	check(button("region_casing_detail")!=null and not host._spatial._regions.has("casing_detail"),"off-image casing target exists without fake hotspot")
	await capture("native-v23-single-view")
	if not await click("select_tool_wear_detail") or not await click("region_function_detail"):
		await finish()
		return
	check(host.runtime.snapshot()==before,"incorrect region does not charge time or reveal evidence")
	var unobserved:=host._spatial.find_child("inspection_review_result",true,false) as Label
	check(unobserved!=null and not unobserved.has_meta("evidence_id"),"visible preview has no unearned reading")
	check(host._spatial.find_child("inspection_acquired_visual",true,false)==null,"no acquired graphic before actual tool action")
	if not await click("region_wear_detail"):
		await finish()
		return
	check(host.runtime.view().minute==5,"wear samples authority")
	verify_single_view()
	await capture("native-v23-observed")
	var sampled:=host._spatial.find_child("inspection_review_result",true,false) as Label
	var crop:=host._spatial.find_child("inspection_visible_crop",true,false) as TextureRect
	check(sampled!=null and sampled.get_meta("evidence_id","")==host.runtime.view().appraisal.evidence[0].evidence_id,"viewer shows acquired evidence only")
	check(crop!=null and crop.texture is AtlasTexture and crop.texture.atlas==host._spatial._item.texture,"magnifier crops actual displayed sprite")
	verify_review_bounds()
	if not await drag_native_tool("casing_detail"):
		await finish()
		return
	check(host.runtime.view().minute==15 and host.runtime.view().wallet.VKC==180,"detail tool samples authority, money preserved")
	verify_single_view()
	check(button("flip_item")==null,"still no face rotation after observation")
	check(host._spatial.find_child("inspection_visible_crop",true,false)==null,"off-image marking has no fabricated image")
	var mark_display:=host._spatial.find_child("inspection_acquired_visual",true,false) as Control
	check(mark_display!=null and mark_display.get_meta("evidence_id","")==host.runtime.view().appraisal.evidence.back().evidence_id,"mark display bound to acquired record")
	var transcript:=mark_display.find_child("transcribed_mark",true,false) as Label if mark_display!=null else null
	check(transcript!=null and transcript.text==str(host.runtime.view().appraisal.evidence.back().observed_value),"mark transcript preserves uncertainty and literal acquired characters")
	await capture("native-inspection-mark-readout")
	verify_review_bounds()
	var review_before:Dictionary=host.runtime.snapshot()
	if not await click("select_tool_wear_detail"):
		await finish()
		return
	check(host.runtime.snapshot()==review_before,"reviewing acquired tool record is free")
	var free_tool:=button("select_tool_wear_detail")
	check(free_tool!=null and free_tool.text.ends_with("\n0"+host.tr_key("ui.copy.min_a419b7d")),"known tool visibly costs zero time to review")
	var reviewed:=host._spatial.find_child("inspection_review_result",true,false) as Label
	check(reviewed!=null and reviewed.get_meta("evidence_id","")==host.runtime.view().appraisal.evidence[0].evidence_id,"earlier observation accessible without repeat inspection")
	await capture("native-inspection-review")
	verify_review_bounds()
	await responsive_review("inspection")
	var after:Dictionary=host.runtime.snapshot()
	if not await click("workspace_toggle"):
		await finish()
		return
	await create_timer(0.40).timeout
	check(host.runtime.snapshot()==after and host._spatial._gaze==0.0,"gaze change free")
	check(host._spatial._item.texture.resource_path.ends_with("native_v23/radio_counter.png"),"small counter sprite independent of close-up")
	check(host._spatial._native_index==profile.time_index(host.runtime.view()),"live light remains in sync after inspections and gaze")
	check(host._spatial._native_window.mouse_filter==Control.MOUSE_FILTER_IGNORE and host._spatial._native_cold.mouse_filter==Control.MOUSE_FILTER_IGNORE,"lighting does not capture pointer")
	var speech:=host._spatial.find_child("spatial_speech_background",true,false) as Control
	check(speech!=null and not speech.get_global_rect().intersects(host._spatial._npc.get_global_rect()),"dialogue leaves native customer visible")
	check(host._native_location.get_meta("mode")=="counter","counter navigation status")
	var drop:=host._spatial.find_child("spatial_customer_drop",true,false) as Control
	check(drop!=null and not drop.get_global_rect().intersects(host._spatial._npc.get_global_rect()) and not drop.get_global_rect().intersects(host._spatial._item.get_global_rect()),"card target does not cover customer or item")
	var hand:=host._spatial.find_child("spatial_hand",true,false) as Control
	check(hand!=null and not hand.get_global_rect().intersects(host._spatial._item.get_global_rect()),"entire radio clear of hand panel")
	await capture("native-v23-counter")
	await inventory_route()
	await finish()

func check_grid_icon(id:String)->void:
	var node:=host._management.find_child("native_item_"+id,true,false) as TextureRect
	check(node!=null,"actual item sprite "+id)
	if node==null:
		return
	var row:Dictionary={}
	for entry:Dictionary in host.runtime.view().stock:
		if entry.id==id:
			row=entry
	if not check(not row.is_empty(),"sprite public stock row"):
		return
	var first:=host._management.find_child("stock_cell_"+str(row.inventory)+"_"+str(row.x)+"_"+str(row.y),true,false) as Control
	var last:=host._management.find_child("stock_cell_"+str(row.inventory)+"_"+str(int(row.x)+int(row.width)-1)+"_"+str(int(row.y)+int(row.height)-1),true,false) as Control
	if not check(first!=null and last!=null,"real occupied cells"):
		return
	var bounds:Rect2=first.get_global_rect().merge(last.get_global_rect())
	check(bounds.encloses(node.get_global_rect()) and node.get_global_rect().size.distance_to(bounds.size-Vector2(6,6))<2.0,"sprite matches committed footprint")
	check(node.mouse_filter==Control.MOUSE_FILTER_IGNORE and node.get_meta("owned")==row.owned and node.get_meta("rotated")==row.rotated,"sprite is noninteractive public metadata")

func inventory_route()->void:
	if not await click("workspace_toggle"):
		return
	await create_timer(0.40).timeout
	if not await click("open_book"):
		return
	var app:Dictionary=host.runtime.view().appraisal
	var evidence:String=app.evidence[0].evidence_id
	check(host._spatial._notebook.vertical_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED,"private book is paged")
	var book_before:Dictionary=host.runtime.snapshot()
	if not await click("book_reference"):
		return
	check(host.runtime.snapshot()==book_before,"reference page is free")
	var guide_title:=host._spatial._notebook.find_child("book_reference_heading",true,false) as Label
	var page_style:=host._spatial._notebook.get_theme_stylebox("panel") as StyleBoxFlat
	check(guide_title!=null and guide_title.text.contains("200 VKC") and guide_title.get_theme_color("font_color")==Color("#302D27") and page_style!=null and page_style.bg_color==Color("#D5CCB6"),"public model reference price printed on private paper book, not item truth")
	await capture("native-book-reference")
	verify_book_bounds()
	var models:=host._spatial._notebook.find_child("book_radio_model_comparison",true,false) as Control
	check(models!=null and models.get_child_count()==2 and host.runtime.snapshot()==book_before,"two public model illustrations, no hidden identity or game cost")
	if models!=null:
		check(host._spatial._notebook.get_global_rect().encloses(models.get_global_rect()),"model drawings fit book")
	var model_sample:=button("reference_sample_selvar_r18s")
	check(model_sample!=null and model_sample.size.y>=84 and host._spatial._notebook.get_global_rect().encloses(model_sample.get_global_rect()),"larger illustrated reference remains fully inside handbook")
	if not await click("reference_sample_selvar_r18s"):
		return
	var alternate:=host._spatial._notebook.find_child("book_reference_heading",true,false) as Label
	check(alternate!=null and alternate.text.contains("240 VKC") and host._spatial._notebook._book_entry==1 and host.runtime.snapshot()==book_before,"click public alternative illustration, no hypothesis or authority change")
	if not await click("reference_sample_selvar_r18"):
		return
	check(host._spatial._notebook._book_entry==0 and host.runtime.snapshot()==book_before,"return to first example without game state change")
	if not await click("select_tool_casing_detail"):
		return
	var clue:=host._spatial.find_child("book_observation_sample",true,false) as Control
	var transcript:=clue.find_child("transcribed_mark",true,false) as Label if clue!=null else null
	check(host._spatial._book_open and host._spatial._notebook._book_section=="reference" and host.runtime.snapshot()==book_before,"existing reference page and state preserved when reviewing another tool")
	check(clue!=null and transcript!=null and transcript.text==str(app.evidence[1].observed_value) and clue.get_meta("evidence_id","")==app.evidence[1].evidence_id,"literal acquired mark beside public model alternatives")
	verify_book_clue_bounds()
	var related_index:=host._spatial._notebook.find_child("book_slot_index",true,false) as OptionButton
	check(related_index!=null and related_index.get_meta("related_chapters",[])==[0,1,3] and related_index.selected==0,"selected mark flags all related public chapters without changing page")
	await capture("native-book-direct-mark-comparison")
	if not await click("select_tool_wear_detail"):
		return
	clue=host._spatial.find_child("book_observation_sample",true,false) as Control
	check(clue is TextureRect and clue.get_meta("evidence_id","")==evidence and host.runtime.snapshot()==book_before,"actual accessible crop replaces mark without new inspection")
	verify_book_clue_bounds()
	# Compare cosmetic examples against the acquired crop without a grade.
	if not await click("book_slot_next") or not await click("book_reference"):
		return
	var wear_examples:=host._spatial._notebook.find_child("book_radio_wear_comparison",true,false) as Control
	check(wear_examples!=null and wear_examples.get_child_count()==3 and host.runtime.snapshot()==book_before,"public cosmetic examples beside acquired crop")
	if wear_examples!=null:
		check(host._spatial._notebook.get_global_rect().encloses(wear_examples.get_global_rect()),"wear comparison row fits book")
	await capture("native-book-wear-comparison")
	if not await click("reference_sample_heavy_wear"):
		return
	check(host._spatial._notebook._book_entry==2 and host.runtime.snapshot()==book_before,"wear reference browsing is not an appraisal")
	# Public comparison samples are available before material inspection.
	if not await click("book_slot_next") or not await click("book_reference"):
		return
	var comparisons:=host._spatial._notebook.find_child("book_material_comparison",true,false) as Control
	check(comparisons!=null and comparisons.get_child_count()==3,"all three public texture references side by side")
	check(host.runtime.snapshot()==book_before,"reference comparisons spend no time and acquire no evidence")
	if not await click("select_tool_material_detail"):
		return
	var visible_preview:=host._spatial.find_child("book_visible_preview",true,false) as TextureRect
	check(visible_preview!=null and visible_preview.texture is AtlasTexture and visible_preview.texture.atlas==host._spatial._item.texture and not visible_preview.has_meta("evidence_id") and host._spatial.find_child("book_observation_sample",true,false)==null and host.runtime.snapshot()==book_before,"unacquired tool compares existing visible pixels only, no evidence or time")
	if visible_preview!=null:
		check(not visible_preview.get_global_rect().intersects(host._spatial._item.get_global_rect()) and not visible_preview.get_global_rect().intersects(host._spatial._notebook.get_global_rect()),"unacquired crop fits between physical item and reference")
		var surface:Rect2=visible_preview.texture.region
		check(surface.position.y<52 and surface.end.y<=52 and surface.size.x>60 and not host._spatial._regions.has("material_detail") and button("region_material_detail")!=null,"small visible casing crop independent of accessible detail target, not speaker grille")
	await capture("native-book-unacquired-preview")
	if not await click("select_tool_function_detail"):
		return
	var topic:=host._spatial.find_child("book_observation_caption",true,false) as Label
	var no_relation:=host._spatial._notebook.find_child("book_slot_index",true,false) as OptionButton
	check(topic!=null and topic.text.contains(host.tr_key("inspection.not_observed")) and topic.text.contains(host.tr_key("ui.tool.function_detail")) and no_relation!=null and no_relation.get_meta("related_chapters",[]).is_empty() and host.runtime.snapshot()==book_before,"unobserved function topic does not repeat previous reading or infer a chapter")
	if not await click("select_tool_wear_detail") or not await click("zoom_in") or not await click("zoom_in"):
		return
	verify_book_clue_bounds()
	verify_book_bounds()
	check(host.runtime.snapshot()==book_before,"maximum book comparison zoom remains free")
	if not await click("zoom_out") or not await click("zoom_out"):
		return
	await capture("native-book-material-comparison")
	verify_book_bounds()
	if comparisons!=null:
		check(host._spatial._notebook.get_global_rect().encloses(comparisons.get_global_rect()),"comparison samples fit book")
	if not await click("book_slot_next") or not await click("book_reference"):
		return
	var batch:=host._spatial._notebook.find_child("book_batch_comparison",true,false) as Control
	check(batch!=null and batch.get_child_count()==3 and host.runtime.snapshot()==book_before,"all public batch alternatives before inspection, read-only")
	if batch!=null:
		check(host._spatial._notebook.get_global_rect().encloses(batch.get_global_rect()),"batch reference samples fit book")
	await capture("native-book-batch-comparison")
	var chapter:=host._spatial._notebook.find_child("book_slot_index",true,false) as OptionButton
	check(chapter!=null and chapter.item_count==app.catalog.slots.size() and chapter.selected==3 and host._spatial._notebook.get_global_rect().encloses(chapter.get_global_rect()),"index exposes every public chapter within the book")
	if chapter==null:
		return
	# Direct selection event is a local UI-only probe. Existing pointer
	# next/previous tests remain elsewhere; popup input needs real review.
	chapter.select(0)
	chapter.item_selected.emit(0)
	await frames()
	check(host._spatial._notebook._book_slot==0 and host._spatial._notebook._book_section=="judgment" and host.runtime.snapshot()==book_before,"direct chapter selection skips intermediate pages without authority changes")
	if not await click("pick_model_id_selvar_r18") or not await click("book_slot_next") or not await click("pick_appearance_id_visible_wear") or not await click("book_evidence") or not await click("link_appearance_id_"+evidence):
		return
	await capture("native-book-evidence")
	verify_book_bounds()
	if not await click("workspace_toggle"):
		return
	await create_timer(0.40).timeout
	var wear:String=""
	var model:String=""
	check(host.runtime.view().appraisal.deck.ready.is_empty() and host.runtime.view().appraisal.deck.direct_ready.size()==2,"native private cards projected directly")
	check(host._spatial.find_child("prepare_model_id",true,false)==null,"native book no extra prepare click")
	for card:Dictionary in host.runtime.view().appraisal.deck.direct_ready:
		if card.argument.slot_id=="appearance_id":
			wear=card.card_id
		else:
			model=card.card_id
	var private_before:Dictionary=host.runtime.snapshot()
	var public_sheet_node:=host._spatial.find_child("counter_public_sheet",true,false) as Control
	check(public_sheet_node!=null and public_sheet_node.get_meta("public_count")==0 and host._spatial.find_child("counter_customer_claim",true,false)==null,"no private judgment or fabricated customer card in public papers")
	var paper_pages:=host._spatial.find_child("counter_public_sheet_pages",true,false) as VBoxContainer
	var wear_card:=host._spatial.find_child("spatial_card_"+wear,true,false) as Control
	var wear_body:=wear_card.find_child("paper_body",true,false) as Label if wear_card!=null else null
	check(paper_pages!=null and host._spatial.find_child("counter_public_sheet_scroll",true,false)==null,"public sheet pages replace scroll")
	check(host._spatial.find_child("spatial_price_scroll",true,false)==null and not host._spatial.find_child("spatial_hand",true,false) is ScrollContainer,"native hand and price actions have no scroll container")
	check(wear_card!=null and wear_card.custom_minimum_size.x>=192 and wear_body!=null and wear_body.max_lines_visible==2,"wider hand paper supports two body lines")
	verify_counter_bounds()
	await capture("native-card-hand")
	await responsive_review("counter")
	if not await drag_public_card("spatial_card_"+wear,"spatial_customer_drop"):
		return
	var published:Dictionary=host.runtime.view().appraisal.deck.presented.back()
	var physical:=host._spatial.find_child("counter_placed_card",true,false) as Control
	var customer:=host._spatial.find_child("counter_customer_claim",true,false) as Control
	public_sheet_node=host._spatial.find_child("counter_public_sheet",true,false) as Control
	check(physical!=null and physical.get_meta("presentation_id")==published.presentation_id and customer!=null and customer.get_meta("claim_id")==published.customer_response.beat_id and public_sheet_node!=null and public_sheet_node.get_meta("public_count")==1,"actual placed paper, authored counterclaim, and single public sheet row")
	check(host.runtime.snapshot().wallets==private_before.wallets and host.runtime.snapshot().game_minutes==private_before.game_minutes,"card disclosure alone costs no cash or time")
	var reply:=host._spatial.find_child("spatial_speech_text",true,false) as Label
	check(reply!=null and reply.text==host._spatial._customer_id()+": "+host.tr_key(published.customer_response.label_key)+host.tr_key("ui.copy.customer_claim_20504483"),"native conversation focuses on actual customer reply; placed card retains player statement")
	await capture("native-card-counterclaim")
	if not await click("spatial_card_"+model) or not await click("spatial_customer_drop"):
		return
	check(host.runtime.view().appraisal.deck.presented.size()==2,"tap card and tabletop alternate")
	var paper_before:Dictionary=host.runtime.snapshot()
	var latest_claim:Dictionary=host.runtime.view().appraisal.deck.presented.back().customer_response
	var claim_navigation:=host._spatial.find_child("counter_claim_navigation",true,false) as Control
	check(claim_navigation!=null and root.get_visible_rect().encloses(claim_navigation.get_global_rect()),"multiple public customer cards have visible browse controls")
	# The second disclosure rebuilds the counter; never inspect the detached first card.
	customer=host._spatial.find_child("counter_customer_claim",true,false) as Control
	check(is_instance_valid(customer) and customer.is_inside_tree() and customer.get_meta("claim_id","")==latest_claim.beat_id,"current claim geometry is bound to the latest live customer card")
	# Require actual button and card geometry, then a real pointer transition.
	var claim_prev:=button("claim_previous")
	var claim_next:=button("claim_next")
	check(claim_prev!=null and is_instance_valid(customer) and customer.is_inside_tree() and not claim_prev.get_global_rect().intersects(customer.get_global_rect()),"claim previous button separated from drop target")
	check(claim_next!=null and is_instance_valid(customer) and customer.is_inside_tree() and not claim_next.get_global_rect().intersects(customer.get_global_rect()),"claim next button separated from drop target")
	if not await click("claim_previous"):
		return
	customer=host._spatial.find_child("counter_customer_claim",true,false) as Control
	check(host._spatial._claim_page==0,"previous claim pointer changes local page")
	check(customer!=null and customer.get_meta("claim_id","")==published.customer_response.beat_id and customer.get_meta("claim_page",-1)==0 and customer.get_meta("claim_count",0)==2 and host.runtime.snapshot()==paper_before,"earlier actual customer card accessible without new claim or price mutation")
	if not await click("claim_next"):
		return
	customer=host._spatial.find_child("counter_customer_claim",true,false) as Control
	check(customer!=null and customer.get_meta("claim_id","")==latest_claim.beat_id and host.runtime.snapshot()==paper_before,"latest customer card restored read-only")
	var current_offer:=button("spatial_offer")
	var blank_offer:=button("spatial_offer_blank")
	check(current_offer!=null and current_offer.get_meta("basis_ids",[])==host.runtime.view().appraisal.deck.public_basis_ids and current_offer.tooltip_text.contains(host.tr_key(published.argument.label_key)) and current_offer.tooltip_text.contains(host.tr_key(host.runtime.view().appraisal.deck.presented.back().argument.label_key)),"current offer exposes exact public basis, not private draft")
	check(blank_offer!=null and blank_offer.get_meta("basis_ids",null)==[] and blank_offer.tooltip_text==host.tr_key("counter.price.no_basis"),"price-only proposal explicitly has no basis")
	await capture("native-multiple-customer-claims")
	if _expected_pixels==Vector2i(1280,720) and not _wholesale:
		var saved_size:Vector2i=root.size
		var saved_scale:Vector2i=root.content_scale_size
		root.content_scale_size=Vector2i(960,720)
		root.size=Vector2i(960,720)
		await frames()
		var compact_prev:=button("claim_previous")
		var compact_card:=host._spatial.find_child("counter_customer_claim",true,false) as Control
		check(compact_prev!=null and compact_card!=null and root.get_visible_rect().encloses(compact_prev.get_global_rect()) and not compact_prev.get_global_rect().intersects(compact_card.get_global_rect()),"compact claim navigation independent of card")
		if not await click("claim_previous") or not await click("claim_next"):
			return
		check(host._spatial._claim_page==1 and host.runtime.snapshot()==paper_before,"compact claim navigation round trip read-only")
		root.content_scale_size=saved_scale
		root.size=saved_size
		await frames()
	if not await click("sheet_previous"):
		return
	check(host.runtime.snapshot()==paper_before,"paper paging changes no private or public game state")
	if not await click("sheet_next"):
		return
	verify_counter_bounds()
	await capture("native-card-public-sheet")
	# One focused 1080p path exercises actual observed-fact disclosure and
	# optional quality consent without modifying the 720p regression fixture.
	if _expected_pixels==Vector2i(1920,1080):
		if not await click("workspace_toggle"):
			return
		await create_timer(0.40).timeout
		if not await click("select_tool_function_detail") or not await click("region_function_detail"):
			return
		if not await click("workspace_toggle"):
			return
		await create_timer(0.40).timeout
		var condition: Dictionary=host.runtime.view().appraisal.price_offer.quality_option
		if not check(not condition.is_empty(),"actual function observation available for quality condition"):
			return
		var before_disclose: Dictionary=host.runtime.snapshot()
		var fact_card:String="spatial_card_fact_"+condition.evidence_id
		while button(fact_card)==null and button("hand_next")!=null:
			if not await click("hand_next"):
				return
		check(host.runtime.snapshot()==before_disclose,"hand paging changes no game state")
		if not await drag(fact_card,"spatial_customer_drop"):
			return
		var disclosed: Dictionary=host.runtime.view().appraisal.deck.presented.back()
		check(disclosed.argument.statement_kind=="observation" and disclosed.argument.observed_value==condition.observed_value and host.runtime.snapshot().wallets==before_disclose.wallets and host.runtime.snapshot().game_minutes==before_disclose.game_minutes,"direct observed fact without new cash or time")
		var speech:Label=host._spatial.find_child("spatial_speech_text",true,false) as Label
		check(speech!=null and not speech.text.contains("R001.function") and not speech.text.contains("serviceable"),"disclosed fact uses public translated label")
		if host._spatial._statements_open and not await click("close_overlay"):
			return
		check(button("spatial_offer_blank")!=null,"explicit price-only option separate from basis")
	var spin:=host._spatial.find_child("spatial_price_amount",true,false) as SpinBox
	if not check(spin!=null,"price field"):
		return
	spin.value=100
	var offer_button:String="spatial_offer_quality" if _expected_pixels==Vector2i(1920,1080) else "spatial_offer"
	for id:String in ["spatial_price_amount","spatial_offer","spatial_offer_blank","spatial_offer_quality","spatial_decline"]:
		var control:=host._spatial.find_child(id,true,false) as Control
		if control!=null:
			check(root.get_visible_rect().encloses(control.get_global_rect()),"fixed price control within viewport "+id)
	if not await click(offer_button):
		return
	var accepted:Dictionary=host.runtime.view().appraisal.price_offer.offers.back()
	var old_basis:=host._spatial.find_child("spatial_previous_basis",true,false) as Label
	check(old_basis!=null and old_basis.get_meta("basis_ids",[])==accepted.presented_ids and old_basis.tooltip_text.contains(host.tr_key("counter.price.previous_basis")),"prior offer shows exact historical basis")
	verify_counter_bounds()
	await capture("native-card-accepted-price")
	if not await click("spatial_checkout"):
		return
	check(host._spatial._notebook.vertical_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED,"native checkout uses a single grid page without scrolling")
	var confirm:=button("place_player_stock_0_0")
	check(confirm!=null and root.get_visible_rect().encloses(confirm.get_global_rect()),"checkout grid target fits viewport")
	await capture("native-card-checkout")
	if not await click("place_player_stock_0_0"):
		return
	var final_button:=button("confirm_checkout")
	check(final_button!=null and root.get_visible_rect().encloses(final_button.get_global_rect()),"checkout confirmation entirely visible")
	if not await click("confirm_checkout"):
		return
	if not check(host.runtime.view().wallet.VKC==80,"actual R001 purchase"):
		return
	var purchased:Dictionary=host.runtime.snapshot()
	if _expected_pixels==Vector2i(1920,1080):
		var sheet: Dictionary=host.runtime.item_history("R001").items[0].history.records[0].appraisal_sheet
		check(sheet.has("quality_condition") and sheet.quality_condition.observed_value=="serviceable" and sheet.statements.back().argument.statement_kind=="observation","actual pointer purchase retains conditions and factual disclosure")
	if not await click("office_toggle") or not await click("office_tab_ledger"):
		return
	check(host._office.find_child("history_item_R001",true,false)!=null and host.runtime.snapshot()==purchased,"ledger actual purchase and free query")
	verify_ledger_summary()
	await capture("native-v24-ledger")
	if not await click("history_item_R001"):
		return
	check(host._office._ledger_item=="R001" and host._office.find_child("office_ledger",true,false)!=null and host._office.find_children("history_trade_*_R001","Label",true,false).size()>0 and host.runtime.snapshot()==purchased,"selected purchase detail preserves recorded transaction and snapshot")
	var receipts:Array=host._office.find_children("history_receipt_*","PanelContainer",true,false)
	check(not receipts.is_empty(),"actual purchase uses grouped receipt")
	var disclosures:Array=host._office.find_children("history_receipt_toggle_*","Button",true,false)
	if not disclosures.is_empty():
		var disclosure:Button=disclosures[0]
		var disclosure_id:String=str(disclosure.name)
		var detail:=host._office.find_child(disclosure_id.replace("history_receipt_toggle_","history_receipt_detail_"),true,false) as Control
		check(detail!=null and not detail.is_visible_in_tree(),"public appraisal details initially collapsed")
		if not await click(disclosure_id):
			return
		check(detail!=null and detail.is_visible_in_tree() and host.runtime.snapshot()==purchased,"receipt disclosure opens without authority changes")
		if detail!=null:
			for offer_label:Node in detail.find_children("history_accepted_offer_*","Label",true,false):
				check(not str(offer_label.text).contains("demo_"),"native receipt hides internal offer ID")
		await capture("native-ledger-public-receipt")
		if not await click(disclosure_id):
			return
		check(detail!=null and not detail.is_visible_in_tree() and host.runtime.snapshot()==purchased,"receipt disclosure closes without authority changes")
	await capture("native-ledger-item-detail")
	if not await click("office_ledger_back"):
		return
	verify_ledger_summary()
	check(host.runtime.snapshot()==purchased,"ledger back is free")
	if not await click("office_toggle") or not await click("history_toggle"):
		return
	check(host._history.find_child("office_ledger_summary",true,false)!=null and host.runtime.snapshot()==purchased,"direct history uses same free item index")
	if not await click("history_item_R001"):
		return
	check(host._history.find_children("history_trade_*_R001","Label",true,false).size()>0 and host.runtime.snapshot()==purchased,"direct history shows same recorded purchase")
	if not await click("office_ledger_back") or not await click("history_toggle") or not await click("stock_toggle"):
		return
	var prior:Dictionary=host.runtime.snapshot()
	verify_inventory_grid_page()
	check_grid_icon("R001")
	if not await click("stock_cell_player_stock_0_0"):
		return
	check(host._management.find_child("native_selected_art",true,false)!=null and host.runtime.snapshot()==prior,"select shows same image for free")
	check(host._native_location.get_meta("mode")=="inventory","inventory navigation status")
	check(host._management.find_child("native_stock_summary",true,false)!=null and host._management.find_child("native_item_frame",true,false)!=null,"stock summary and selected illustration frame")
	var stock_art:=host._management.find_child("stock_room_layer",true,false) as TextureRect
	check(stock_art!=null and stock_art.texture.resource_path.ends_with("/rooms/stock_room.png") and stock_art.mouse_filter==Control.MOUSE_FILTER_IGNORE,"independent stock room art")
	await capture("native-v24-stock")
	await responsive_review("stock")
	if not await click("inventory_legend_toggle"):
		return
	var legend:=host._management.find_child("inventory_legend_player_stock",true,false) as Label
	check(legend!=null and legend.is_visible_in_tree() and legend.text.contains("R001") and host.runtime.snapshot()==prior,"explicit inventory list reads full item identity for free")
	check(not host._management.find_child("native_grid_player_stock",true,false).is_visible_in_tree(),"list page replaces grid instead of stacking")
	if not await click("inventory_legend_toggle"):
		return
	verify_inventory_grid_page()
	check(host.runtime.snapshot()==prior and host._management._selected=="R001","return to grid preserves selection and state")
	if not await drag("stock_cell_player_stock_1_0","stock_cell_player_stock_5_2"):
		return
	check(host.runtime.snapshot()==prior and host._management._destination==Vector2i(4,2),"art does not intercept drag")
	if not await click("stock_confirm"):
		return
	check_grid_icon("R001")
	if not await click("stock_cell_player_stock_4_2") or not await click("stock_rotate") or not await click("stock_cell_player_stock_4_2") or not await click("stock_confirm"):
		return
	check_grid_icon("R001")
	await capture("native-v24-stock-rotated")
	if not await click("stock_toggle"):
		return
	# Keep the established 720p hold/rotation path; the 1080p route now completes
	# the canonical first day and paid D2 handoff with actual pointer events.
	if _expected_pixels==Vector2i(1920,1080):
		await canonical_day_one()
		return
	# Both alternatives are actual user choices, not direct command setup.
	if not await click("next_customer"):
		return
	if not check(host.runtime.view().visits.active=="visit_g02_buy","retail buyer can be declined") or not await click("spatial_fixed_decline"):
		return
	if not await click("next_customer"):
		return
	var v:Dictionary=host.runtime.view()
	if not check(v.visits.active=="radio_wholesale" and v.trade.amount==135 and v.trade.buyer=="G03","finite wholesale offer 135"):
		return
	verify_native_speech()
	await capture("native-day1-wholesale-offer")
	if not await click("spatial_fixed_confirm" if _wholesale else "spatial_fixed_decline"):
		return
	var sale_cash:int=215 if _wholesale else 80
	if not check(host.runtime.view().wallet.VKC==sale_cash and host.runtime.snapshot().items.R001.owner_id==("G03" if _wholesale else "player"),"actual wholesale or hold choice"):
		return
	if not await click("next_customer"):
		return
	v=host.runtime.view()
	if not check(v.visits.active=="service1" and v.visits.terms.item_id=="W001","service still available on either alternative"):
		return
	verify_native_speech()
	if not await click("spatial_service_accept") or not await click("close_day"):
		return
	check(host._management.visible and host._management._native_time_index==5 and host.runtime.view().minute==600,"evening header reads actual close clock")
	if not _wholesale:
		check_grid_icon("R001")
	if not check(host.runtime.view().wallet.VKC==sale_cash-15,"actual operating cost 15 on alternative"):
		return
	if not await show_item_grid("W001"):
		return
	verify_inventory_grid_page()
	var source:String=inventory_cell("W001")
	if not check(not source.is_empty(),"service in custody") or not await drag(source,"inventory_detail_drop"):
		return
	var before:Dictionary=host.runtime.snapshot()
	verify_work_ticket()
	await responsive_review("workshop")
	if not await click("work_confirm"):
		return
	var closing_cash:int=190 if _wholesale else 55
	check(host.runtime.view().minute==600 and host.runtime.view().wallet.VKC==closing_cash and host.runtime.view().wallet.VKC==int(before.wallets.player.VKC)-10,"actual alternate closing cash")
	if not await click(inventory_cell("W001")):
		return
	check(host._management.find_child("native_service_complete",true,false)!=null,"completion visible in selected detail")
	check(host._native_location.get_meta("mode")=="workshop","evening navigation status")
	var stock_scene:=host._management.find_child("stock_art_scene",true,false) as Control
	check(stock_scene!=null and stock_scene.get_meta("time_index")==5,"dedicated stock scene uses actual evening clock")
	await capture("native-v24-evening")
	var closing:Dictionary=host.runtime.snapshot()
	if not await click("office_toggle") or not await click("office_tab_contracts"):
		return
	check(button("office_contract_pay_rad1_first")==null and host.runtime.snapshot()==closing,"evening contract actions unavailable, browsing free")
	var late_office:=host._office.find_child("office_art_scene",true,false) as Control
	check(late_office!=null and late_office.get_meta("time_index")==5,"office scene evening clock")
	await capture("native-v24-office-evening")
	if not await click("office_toggle") or not await click("work_next_day"):
		return
	if not check(host.runtime.view().minute==1440 and host.runtime.view().wallet.VKC==closing_cash,"next day authoritative clock and no auto payment"):
		return
	if not await click("next_customer"):
		return
	v=host.runtime.view()
	if not check(v.visits.active=="pickup1" and v.visits.terms.status=="complete","alternate D2 pickup"):
		return
	if not await click("spatial_service_deliver"):
		return
	if not check(host.runtime.view().wallet.VKC==closing_cash+30,"alternate actual fee 30"):
		return
	if not await click("next_customer"):
		return
	v=host.runtime.view()
	if _wholesale:
		check(v.visits.active=="watch_a" and host.runtime.view().wallet.VKC==220,"wholesale skips unavailable repeat sale")
	else:
		if not check(v.visits.active=="radio_recovery" and v.trade.amount==130 and v.trade.item_id=="R001","held stock D2 finite recovery 130"):
			return
		verify_native_speech()
		await capture("native-day2-recovery")
		if not await click("spatial_fixed_confirm"):
			return
		check(host.runtime.snapshot().items.R001.owner_id=="G03" and host.runtime.view().wallet.VKC==215,"actual held stock recovery and fee")
		await capture("native-day2-recovery-complete")

func verify_native_speech()->void:
	var speech:=host._spatial.find_child("spatial_speech_background",true,false) as Control
	check(speech!=null and not speech.get_global_rect().intersects(host._spatial._npc.get_global_rect()) and not speech.get_global_rect().intersects(host._spatial._item.get_global_rect()),"native fixed/service dialogue clear of portrait and item")

func verify_work_ticket()->void:
	var ticket:=host._management.find_child("native_service_work_ticket",true,false) as Control
	var image:=host._management.find_child("native_item_frame",true,false) as Control
	var commit:=button("work_confirm")
	check(ticket!=null and image!=null and ticket.get_index()<image.get_index(),"cost slip precedes item illustration")
	check(commit!=null and commit.text.contains("10 VKC"),"persistent work confirmation shows exact cost")

# No command shortcuts in this continuation. The original hold route is retained.
func canonical_day_one()->void:
	if not await click("next_customer"):
		return
	var v:Dictionary=host.runtime.view()
	if not check(v.visits.active=="visit_g02_buy" and v.trade.item_id=="R001" and v.trade.amount==170 and host._spatial.visible,"D1 actual retail buyer and finite 170 offer"):
		return
	check(host._spatial._native_window.visible and host._spatial._item.texture.resource_path.ends_with("native_v23/radio_counter.png"),"retail uses same native room and radio identity")
	verify_native_speech()
	await capture("native-day1-retail")
	if not await click("spatial_fixed_confirm"):
		return
	if not check(host.runtime.view().wallet.VKC==250 and host.runtime.snapshot().items.R001.owner_id=="G02","R001 actual retail 80 to 250"):
		return
	if not await click("next_customer"):
		return
	v=host.runtime.view()
	if not check(v.visits.active=="service1" and v.visits.terms.kind=="service_offer" and v.visits.terms.item_id=="W001","finite queue skips unavailable wholesale after retail"):
		return
	check(host._spatial.visible and host._spatial._native_window.visible,"service customer on shared native stage")
	var cost_label:=host._spatial.find_child("spatial_service_cost",true,false) as Label
	var fee_label:=host._spatial.find_child("spatial_service_fee",true,false) as Label
	check(v.get("service_cost_preview",{})=={"VKC":10,"USD":0} and cost_label!=null and cost_label.is_visible_in_tree() and cost_label.text.contains("10 VKC") and fee_label!=null and fee_label.is_visible_in_tree() and fee_label.text.contains("30 VKC"),"actual quoted service expense and conditional fee before accepting")
	verify_native_speech()
	await capture("native-day1-service")
	if not await click("spatial_service_accept"):
		return
	var item:Dictionary=host.runtime.snapshot().items.W001
	check(item.owner_id=="G02" and item.custodian_id=="player" and host.runtime.view().wallet.VKC==250,"service accepts custody, not revenue")
	if not await click("close_day"):
		return
	if not check(host.runtime.view().phase=="workshop" and host.runtime.view().wallet.VKC==235 and host.runtime.view().minute==600,"D1 close charges existing overhead 15"):
		return
	if not await show_item_grid("W001"):
		return
	verify_inventory_grid_page()
	var source:String=inventory_cell("W001")
	var before:Dictionary=host.runtime.snapshot()
	if not check(not source.is_empty(),"W001 in shared custody grid") or not await drag(source,"inventory_detail_drop"):
		return
	check(host.runtime.snapshot()==before and host._management.find_child("native_service_work_ticket",true,false)!=null,"free work slip review before commitment")
	verify_work_ticket()
	await capture("native-day1-work-slip")
	if not await click("work_confirm"):
		return
	if not check(host.runtime.view().wallet.VKC==225 and host.runtime.view().minute==600 and host.runtime.snapshot().items.W001.functional,"W001 restoration exact 10, frozen clock"):
		return
	if not await click(inventory_cell("W001")):
		return
	check(host._management.find_child("native_service_complete",true,false)!=null,"completed work status above illustration")
	await capture("native-day1-work-complete")
	if not await click("work_next_day"):
		return
	if not check(host.runtime.view().day==2 and host.runtime.view().minute==1440 and host.runtime.view().wallet.VKC==225,"D2 opens without automatic revenue"):
		return
	if not await click("next_customer"):
		return
	v=host.runtime.view()
	if not check(v.visits.active=="pickup1" and v.visits.terms.status=="complete" and v.visits.terms.fee.VKC==30,"D2 actual completed pickup offer"):
		return
	await capture("native-day2-pickup")
	if not await click("spatial_service_deliver"):
		return
	item=host.runtime.snapshot().items.W001
	check(item.owner_id=="G02" and item.custodian_id=="G02" and host.runtime.view().wallet.VKC==255,"D2 paid handoff returns custody and collects exact 30")
	if not await click("office_toggle"):
		return
	# The selected tab is intentionally disabled. Switch away and return to
	# verify a fresh ledger render via actual input rather than click it twice.
	if not check(host._office.visible,"office available after paid handoff"):
		return
	var settled:Dictionary=host.runtime.snapshot()
	if not await click("office_tab_news") or not await click("office_tab_ledger"):
		return
	check(host.runtime.snapshot()==settled,"post-delivery office navigation is read-only")
	check(host._office.find_child("history_item_R001",true,false)!=null and host._office.find_child("history_item_W001",true,false)!=null,"actual trade and work history after D2 delivery")
	verify_ledger_summary()
	await capture("native-day2-ledger")
	if not await click("history_item_W001"):
		return
	check(host._office._ledger_item=="W001" and host._office.find_children("history_work_*_W001","Label",true,false).size()>0 and host._office.find_child("history_item_R001",true,false)==null,"selected service history excludes unrelated radio entries")
	check(not host._office.find_children("history_work_receipt_*","PanelContainer",true,false).is_empty(),"service work displayed as separate receipt")
	check(host.runtime.snapshot()==settled,"service history query is read-only")
	await capture("native-day2-ledger-work-detail")
	if not await click("office_ledger_back"):
		return
	verify_ledger_summary()
	# One representative native civilian appraisal, after the canonical D1/D2 fixture.
	if not await click("office_toggle") or not await click("next_customer"):
		return
	if not check(host.runtime.view().visits.active=="watch_a","D2 watch precedes civilian purchase"):
		return
	# A new appraisal opens looking down at the item. Use the real gaze switch.
	if not await verify_live_specimen("WAT02","watch_wat02_native_pilot.svg","book_watch_wear_comparison"):
		return
	var before_gaze:Dictionary=host.runtime.snapshot()
	if not await click("workspace_toggle"):
		return
	await create_timer(0.40).timeout
	check(host.runtime.snapshot()==before_gaze,"watch gaze before decline is free")
	if not await click("spatial_decline") or not await click("next_customer"):
		return
	if not check(host.runtime.view().visits.active=="battery_buy","D2 battery after unavailable watch resale"):
		return
	var basic_before:Dictionary=host.runtime.snapshot()
	if not await click("spatial_basic_review"):
		return
	await create_timer(0.4).timeout
	check(host._spatial.visible and not host._app.visible and host.runtime.snapshot()==basic_before,"native opt-in shares physical appraisal without state change")
	check(host._spatial._item.texture.resource_path.ends_with("battery_counter_pilot.svg"),"battery uses own art not radio")
	var tool:=button("select_tool_basic_function_v1")
	check(tool!=null and tool.icon!=null,"functional tool has physical icon")
	await capture("native-basic-battery-tools")
	# Swap a shared civilian profile before a real drag, not just a geometry probe.
	var visual_art=preload("res://src/presentation/native_v23_art.gd")
	var original=visual_art.ITEMS.profiles["battery"]
	var substitute=original.duplicate(true)
	var image:=Image.create(160,120,false,Image.FORMAT_RGBA8)
	image.fill(Color("#737B65"))
	substitute.texture=ImageTexture.create_from_image(image)
	substitute.regions["basic_function_v1"]=Rect2(0.22,0.18,0.56,0.64)
	visual_art.ITEMS.profiles["battery"]=substitute
	host._spatial._build()
	await create_timer(0.12).timeout
	check(host._spatial._item.texture==substitute.texture and visual_art.stock_texture({"id":"BAT02"})==substitute.texture,"replacement shared immediately across inspection and inventory mapping")
	check(host.runtime.snapshot()==basic_before,"civilian art swap leaves state untouched")
	var applied:bool=await drag("select_tool_basic_function_v1","region_basic_function_v1")
	visual_art.ITEMS.profiles["battery"]=original
	host._spatial._build()
	await create_timer(0.12).timeout
	if not applied:
		return
	check(host._spatial._item.texture==original.texture,"original civilian placeholder restored")
	var basic:Dictionary=host.runtime.view().appraisal
	var readout:=host._spatial.find_child("inspection_acquired_visual",true,false) as Control
	check(readout!=null and readout.get_meta("evidence_id","")==basic.evidence[0].evidence_id and host._spatial.find_child("inspection_visible_crop",true,false)==null,"battery diagnostic displays acquired result, not fabricated image")
	await capture("native-basic-battery-readout")
	verify_review_bounds()
	check(basic.evidence.size()==1 and basic.evidence[0].observed_value=="serviceable" and host.runtime.snapshot().game_minutes==basic_before.game_minutes+5 and host.runtime.snapshot().wallets==basic_before.wallets,"same authoritative functional observation")
	var compared:Dictionary=host.runtime.snapshot()
	if not await click("open_book") or not await click("book_reference"):
		return
	verify_text_comparison("book_battery_function_comparison")
	await capture("native-basic-battery-reference")
	check(host.runtime.snapshot()==compared,"basic public reference adds no observation or judgment")
	if not await click("book_judgment") or not await click("pick_function_id_working") or not await click("workspace_toggle"):
		return
	await create_timer(0.4).timeout
	if not await drag("spatial_card_fact_"+str(basic.evidence[0].evidence_id),"spatial_customer_drop"):
		return
	await capture("native-basic-battery-counter")
	var amount:=host._spatial.find_child("spatial_price_amount",true,false) as SpinBox
	if not check(amount!=null and amount.value==40 and amount.value==host.runtime.view().appraisal.price_offer.asking,"plain-to-appraisal resets draft to the current seller asking price"):
		return
	if not await click("spatial_offer"):
		return
	if not check(host.runtime.view().appraisal.has("checkout"),"exact 40 offer accepted without repairing UI value in the test"):
		return
	if not await click("spatial_checkout"):
		return
	check(host.runtime.view().appraisal.checkout.amount==40 and host.runtime.view().appraisal.reference.estimate==null,"existing 40 price and unknown estimate")
	if not await click("place_player_stock_0_0") or not await click("confirm_checkout"):
		return
	check(host.runtime.snapshot().items.BAT02.owner_id=="player","actual shared battery purchase")
	# Continue only this existing 1080p route to the first D3 radio seller.
	# No fixture injection, new campaign loop, or artificial evidence.
	if not await click("close_day") or not await click("work_next_day") or not await click("next_customer"):
		return
	if not check(host.runtime.view().day==3 and host.runtime.view().visits.active=="gear_buy","D3 existing queue skips absent service pickup"):
		return
	if not await click("spatial_fixed_decline") or not await click("next_customer"):
		return
	if not check(host.runtime.view().visits.active=="radio3_buy","actual D3 R003 seller after optional gear declined"):
		return
	if not await verify_live_specimen("R003","radio_r003_native_pilot.svg","book_radio_wear_comparison"):
		return
	# One real R003 material inspection through the existing authority.
	var before_material:Dictionary=host.runtime.snapshot()
	if not await drag_native_tool("material_detail"):
		return
	var radio_app:Dictionary=host.runtime.view().appraisal
	var sample:=host._spatial.find_child("inspection_acquired_visual",true,false) as Control
	if not check(radio_app.evidence.size()==1,"R003 acquires exactly one observation"):
		return
	var fact:Dictionary=radio_app.evidence[0]
	check(fact.observation_key=="R001.material" and fact.observed_value=="cross" and fact.current and not fact.is_claim and sample!=null and sample.get_meta("evidence_id","")==fact.evidence_id,"R003 actual material observation uses its own authored reading")
	check(host.runtime.snapshot().game_minutes==before_material.game_minutes+5 and host.runtime.snapshot().wallets==before_material.wallets,"R003 existing five-minute cost, no money change")
	await capture("native-specimen-R003-acquired-material")
	var acquired:Dictionary=host.runtime.snapshot()
	if not await click("select_tool_material_detail"):
		return
	check(host.runtime.snapshot()==acquired,"R003 rereading cannot acquire or charge twice")

# Inspect the actual authored customer visit, without acquiring an observation.
# Read-only path is identical for the two existing public catalog families.
func verify_live_specimen(id:String,asset:String,comparison_id:String)->bool:
	var before:Dictionary=host.runtime.snapshot()
	var app:Dictionary=host.runtime.view().appraisal
	if not check(app.get("item_id","")==id and host._spatial.visible and host._spatial._inspect and host._spatial._item.texture.resource_path.ends_with(asset),"actual native specimen and public appraisal "+id):
		return false
	if not await click("select_tool_wear_detail") or not await click("open_book"):
		return false
	if not await click("book_slot_next") or not await click("book_reference"):
		return false
	var preview:=host._spatial.find_child("book_visible_preview",true,false) as TextureRect
	var examples:=host._spatial._notebook.find_child(comparison_id,true,false) as Control
	check(preview!=null and preview.texture is AtlasTexture and preview.texture.atlas==host._spatial._item.texture and not preview.has_meta("evidence_id"),"actual visible crop without acquired evidence "+id)
	check(examples!=null and examples.get_child_count()==3 and host._spatial._notebook.get_global_rect().encloses(examples.get_global_rect()),"public wear examples fit actual specimen book "+id)
	verify_book_bounds()
	await capture("native-specimen-"+id+"-comparison")
	if id=="WAT02":
		for comparison:String in ["book_watch_case_comparison","book_watch_function_comparison","book_watch_mark_comparison"]:
			if not await click("book_slot_next") or not await click("book_reference"):
				return false
			verify_text_comparison(comparison)
			await capture("native-"+comparison)
	if not await click("open_book"):
		return false
	return check(host.runtime.snapshot()==before,"specimen review changes no authority "+id)

func verify_text_comparison(id:String)->void:
	var row:=host._spatial._notebook.find_child(id,true,false) as Control
	if not check(row!=null and row.get_child_count()==2,"two alternatives on same public page "+id):
		return
	check(host._spatial._notebook.get_global_rect().encloses(row.get_global_rect()),"comparison row fits book "+id)
	var labels:Array[Node]=row.find_children("reference_comparative_text","Label",true,false)
	if not check(labels.size()==2,"two public text samples "+id):
		return
	for label:Label in labels:
		check(not label.text.begins_with("book.compare.") and label.get_visible_line_count()==label.get_line_count() and row.get_global_rect().encloses(label.get_global_rect()),"translated comparison readable "+id)
	verify_book_bounds()

# Geometry checks for labels and card feet, not only clickable centers.
func verify_counter_bounds()->void:
	var price:=host._spatial.find_child("price_paper",true,false) as Control
	for id:String in ["spatial_price_reference","spatial_price_estimate","spatial_previous_offer","spatial_previous_basis"]:
		var line:=host._spatial.find_child(id,true,false) as Label
		var required:bool=id in ["spatial_price_reference","spatial_price_estimate"] or not host.runtime.view().appraisal.price_offer.offers.is_empty()
		if required:
			check(price!=null and line!=null and not line.text.is_empty() and not line.text.contains("\n") and line.size.y>=26 and price.get_global_rect().encloses(line.get_global_rect()) and root.get_visible_rect().encloses(line.get_global_rect()),"independent visible price label "+id)
	for id:String in ["spatial_price_amount","spatial_offer","spatial_offer_blank","spatial_offer_quality","spatial_checkout","spatial_decline"]:
		var control:=host._spatial.find_child(id,true,false) as Control
		if control!=null:
			check(price.get_global_rect().encloses(control.get_global_rect()) and root.get_visible_rect().encloses(control.get_global_rect()),"complete fixed price control "+id)
	var hand:=host._spatial.find_child("spatial_hand",true,false) as Control
	for child:Node in hand.get_children():
		if child is Button:
			var foot:=child.find_child("paper_footer",true,false) as Label
			check(hand.get_global_rect().encloses(child.get_global_rect()) and root.get_visible_rect().encloses(child.get_global_rect()),"complete hand card "+str(child.name))
			check(foot!=null and child.get_global_rect().encloses(foot.get_global_rect()) and root.get_visible_rect().encloses(foot.get_global_rect()),"complete card footer "+str(child.name))

func drag_native_tool(id:String)->bool:
	var source:Button=button("select_tool_"+id)
	var target:Button=button("region_"+id)
	if not check(source!=null and target!=null,"physical tool and scoped target exist"):
		return false
	var before:Dictionary=host.runtime.snapshot()
	await reveal(source)
	var a:Vector2=source.get_global_rect().get_center()
	var b:Vector2=target.get_global_rect().get_center()
	pointer(a,true)
	motion(a+Vector2(25,-25),a)
	await frames()
	var active:bool=root.gui_is_dragging()
	var outline:=target.get_node_or_null("tool_drag_highlight") as Control
	check(active and outline!=null and outline.mouse_filter==Control.MOUSE_FILTER_IGNORE and host.runtime.snapshot()==before,"picked-up tool highlights eligible target without spending time")
	motion(b,a+Vector2(25,-25))
	await frames()
	pointer(b,false)
	await frames()
	check(host._spatial.find_children("tool_drag_highlight","Control",true,false).is_empty(),"drag highlight removed on completion")
	return check(active and not root.gui_is_dragging(),"actual tool pickup and drop")

func drag_public_card(source_id:String,target_id:String)->bool:
	var source:Button=button(source_id)
	var target:Button=button(target_id)
	if not check(source!=null and target!=null,"public card and legitimate target present"):
		return false
	var before:Dictionary=host.runtime.snapshot()
	await reveal(source)
	var a:Vector2=source.get_global_rect().get_center()
	var b:Vector2=target.get_global_rect().get_center()
	pointer(a,true)
	motion(a+Vector2(25,-25),a)
	await frames()
	var active:bool=root.gui_is_dragging()
	var outline:=target.get_node_or_null("card_drag_highlight") as Control
	check(active and outline!=null and outline.mouse_filter==Control.MOUSE_FILTER_IGNORE and host.runtime.snapshot()==before,"card pickup highlights public action without revealing or changing anything")
	motion(b,a+Vector2(25,-25))
	await frames()
	pointer(b,false)
	await frames()
	check(host._spatial.find_children("card_drag_highlight","Control",true,false).is_empty(),"card highlight removed on drop")
	return check(active and not root.gui_is_dragging(),"actual public card pickup and drop")

func verify_book_clue_bounds()->void:
	var clue:=host._spatial.find_child("book_observation_sample",true,false) as Control
	var caption:=host._spatial.find_child("book_observation_caption",true,false) as Label
	if not check(clue!=null and caption!=null,"book comparison sample and caption"):
		return
	check(root.get_visible_rect().encloses(clue.get_global_rect()) and root.get_visible_rect().encloses(caption.get_global_rect()),"comparison sample and caption in viewport")
	check(not clue.get_global_rect().intersects(host._spatial._item.get_global_rect()) and not clue.get_global_rect().intersects(host._spatial._notebook.get_global_rect()),"sample does not obscure item or book")
	check(caption.get_visible_line_count()==caption.get_line_count(),"acquired sample caption fully readable")

func verify_book_bounds()->void:
	var book:Control=host._spatial._notebook
	var item:Control=host._spatial._item
	var details:=host._spatial.find_child("single_view_detail_targets",true,false) as Control
	check(book.visible and root.get_visible_rect().encloses(book.get_global_rect()),"entire private book stays in viewport")
	check(not book.get_global_rect().intersects(item.get_global_rect()),"book does not cover physical item")
	if details!=null:
		check(not book.get_global_rect().intersects(details.get_global_rect()),"book leaves off-object detail targets accessible")

func verify_review_bounds()->void:
	var panel:=host._spatial.find_child("inspection_review",true,false) as Control
	var item:Control=host._spatial._item
	if not check(panel!=null and root.get_visible_rect().encloses(panel.get_global_rect()),"observation viewer stays in viewport"):
		return
	check(not panel.get_global_rect().intersects(item.get_global_rect()),"observation viewer leaves actual item visible")
	for id:String in ["inspection_review_title","inspection_visible_crop","inspection_acquired_visual","inspection_crop_caption","inspection_review_result"]:
		var child:=panel.find_child(id,true,false) as Control
		if child!=null:
			check(panel.get_global_rect().encloses(child.get_global_rect()),"review child fits fixed panel "+id)
			if child is Label:
				check(child.get_visible_line_count()==child.get_line_count(),"review text is fully visible "+id)

# Different aspect ratio and edited normalized region: no gameplay mutation.
# The authored fixture is restored before the actual timed pointer route.
func verify_art_swap()->void:
	var spatial=host._spatial
	var original=spatial.radio_visual_profile
	var state:Dictionary=host.runtime.snapshot()
	var substitute=original.duplicate(true)
	var image:=Image.create(160,80,false,Image.FORMAT_RGBA8)
	image.fill(Color("#646B68"))
	substitute.texture=ImageTexture.create_from_image(image)
	substitute.regions["wear_detail"]=Rect2(0.08,0.68,0.30,0.20)
	check(substitute.valid() and substitute.provisional,"replacement resource is valid provisional art")
	spatial.radio_visual_profile=substitute
	spatial._build()
	var art:TextureRect=spatial._item
	check(art.texture==substitute.texture and absf(art.size.x/art.size.y-2.0)<0.01,"different image aspect uses actual replacement size")
	var target:Control=spatial._regions["wear_detail"]
	var rect:Rect2=substitute.regions["wear_detail"]
	check(target.position.distance_to(art.position+rect.position*art.size)<2.0 and target.size.distance_to(rect.size*art.size)<2.0,"replacement geometry aligns with item target")
	check(host.runtime.snapshot()==state,"art replacement leaves authoritative snapshot unchanged")
	spatial.radio_visual_profile=original
	spatial._build()
	check(spatial._item.texture==original.texture and host.runtime.snapshot()==state,"restore authored placeholder without game mutation")

func verify_native_capability_routing()->void:
	var spatial=preload("res://src/presentation/spatial_radio_counter.gd")
	var before:Dictionary=host.runtime.snapshot()
	var appraisal:Dictionary=host.runtime.view().get("appraisal",{}).duplicate(true)
	check(spatial.supports_native_appraisal(appraisal),"actual public opening appraisal supported")
	var renamed:Dictionary=appraisal.duplicate(true)
	renamed.visit_id="presentation_only_other_visit"
	check(spatial.supports_native_appraisal(renamed),"public supported tools not bound to the demo visit ID")
	renamed.tools["unknown_presentation_tool"]={}
	check(not spatial.supports_native_appraisal(renamed),"unsupported tool falls back to generic renderer")
	renamed=appraisal.duplicate(true)
	renamed.catalog.def_id="unknown_presentation_catalog"
	check(not spatial.supports_native_appraisal(renamed),"unmapped public catalog does not claim native support")
	renamed=appraisal.duplicate(true)
	renamed.tools.clear()
	check(not spatial.supports_native_appraisal(renamed),"empty tool DTO cannot activate native appraisal")
	renamed=appraisal.duplicate(true)
	renamed.catalog.version=2
	check(not spatial.supports_native_appraisal(renamed),"incompatible catalog version falls back")
	renamed=appraisal.duplicate(true)
	renamed.tools["wear_detail"].evidence_id="unknown_reading"
	check(not spatial.supports_native_appraisal(renamed),"tool with mismatched public evidence falls back")
	renamed=appraisal.duplicate(true)
	renamed.tools.erase("wear_detail")
	check(not spatial.supports_native_appraisal(renamed),"incomplete public tool set falls back")
	var guide=preload("res://src/presentation/public_reference_guide.gd")
	var docs=preload("res://src/content/packaged_documents.gd")
	var watch_catalog:Dictionary=docs.read_object("res://data/campaign/gate2/watch_public_catalog.json")
	var watch_tools:Dictionary={}
	# Read only the public tool declarations, never specimens or readings.
	for tool:Dictionary in docs.read_object("res://data/campaign/gate2/watch_inspection_profile.json").profiles.fictional_watch_p2.tools:
		watch_tools[tool.id]={"evidence_id":tool.evidence_id}
	var watch_cap:Dictionary=guide.native_capability({"item_id":"presentation_watch","visit_id":"presentation_visit","catalog":watch_catalog,"tools":watch_tools})
	check(watch_cap.get("counter_role")=="counter" and watch_cap.get("tools",{}).get("batch_detail",{}).get("title")=="ui.copy.back_mark_reader_3f7e5eab","watch presentation descriptor selects public mark label")
	for def:String in ["battery","demo_tool","demo_electronics"]:
		var basic_catalog:Dictionary={"version":2,"def_id":def,"slots":[{"id":"function_id"}]}
		var basic_cap:Dictionary=guide.native_capability({"item_id":"presentation_item","visit_id":"presentation_visit","catalog":basic_catalog,"tools":{"basic_function_v1":{"evidence_id":"function_status"}}})
		check(basic_cap.get("counter_role")=="counter" and basic_cap.get("tools",{}).get("basic_function_v1",{}).get("title")=="review.basic.function","shared basic capability "+def)
	check(host.runtime.snapshot()==before,"renderer capability probe does not modify authority")

func verify_shared_item_profiles()->void:
	verify_native_capability_routing()
	var art=preload("res://src/presentation/native_v23_art.gd")
	var before:Dictionary=host.runtime.snapshot()
	for id:String in ["R003","WAT02","BAT02","TL04","EL06"]:
		var inspection=art.item_profile(id,"inspection")
		var counter=art.item_profile(id,"counter")
		check(inspection!=null and inspection.valid() and inspection.provisional,"shared provisional inspection profile "+id)
		check(inspection==counter and art.stock_texture({"id":id})==inspection.texture,"same resource in counter and stock "+id)
	for id:String in ["BAT02","TL04","EL06"]:
		check(art.item_profile(id,"inspection").regions.has("basic_function_v1"),"whole-item tool region "+id)
	var crop_profile=art.RADIO_PROFILE.duplicate(true)
	check(crop_profile.valid() and crop_profile.crop_regions.has("material_detail") and not crop_profile.regions.has("material_detail"),"separate validated opening casing crop")
	crop_profile.crop_regions["material_detail"]=Rect2(0.95,0.95,0.1,0.1)
	check(not crop_profile.valid(),"invalid crop geometry rejected")
	var radio=art.item_profile("R003","inspection")
	var watch=art.item_profile("WAT02","inspection")
	check(radio.texture.resource_path.ends_with("radio_r003_native_pilot.svg") and radio.texture!=art.RADIO_PROFILE.texture,"R003 distinct visible native specimen, not opening radio art")
	check(watch.texture.resource_path.ends_with("watch_wat02_native_pilot.svg"),"WAT02 distinct native dial illustration")
	check(not radio.regions.has("casing_detail") and not radio.regions.has("batch_detail") and not watch.regions.has("batch_detail"),"unseen identification marks remain explicit off-image tests")
	var shell:Rect2=radio.regions.material_detail
	var wear:Rect2=radio.regions.wear_detail
	var screen:Rect2=radio.regions.display_damage_detail
	check(shell.end.x<=0.26 and shell.position.y>=0.27 and not shell.intersects(wear) and not shell.intersects(screen),"R003 shell, visible wear and display geometry are separate")
	check(art.stock_texture({"id":"unknown_art_test"})==null,"unknown stock uses text fallback")
	check(host.runtime.snapshot()==before,"catalog projection cannot mutate game")


# Visual resource swap before the existing actual pointer route.
func verify_scene_art_swap()->void:
	var art=preload("res://src/presentation/native_v23_art.gd")
	var catalog=art.SCENES
	var snapshot:Dictionary=host.runtime.snapshot()
	var spatial=host._spatial
	var old_room:Texture2D=catalog.textures["counter.room"]
	var old_customer:Texture2D=catalog.textures["customer.opening"]
	var old_icon:Texture2D=catalog.tool_icons["wear_detail"]
	var image:=Image.create(32,24,false,Image.FORMAT_RGBA8)
	image.fill(Color("#596460"))
	var replacement:=ImageTexture.create_from_image(image)
	catalog.textures["counter.room"]=replacement
	catalog.textures["customer.opening"]=replacement
	catalog.tool_icons["wear_detail"]=replacement
	spatial._build()
	var tool:=spatial.find_child("select_tool_wear_detail",true,false) as Button
	check(catalog.provisional and spatial._bg.texture==replacement and spatial._npc.texture==replacement,"replaceable provisional room and customer")
	check(tool!=null and tool.icon==replacement,"tool override controls actual displayed icon")
	check(spatial._bg.mouse_filter==Control.MOUSE_FILTER_IGNORE and spatial._npc.mouse_filter==Control.MOUSE_FILTER_IGNORE,"replacement art remains passive")
	check(host.runtime.snapshot()==snapshot,"scene and tool art replacement does not mutate state")
	catalog.textures["counter.room"]=old_room
	catalog.textures["customer.opening"]=old_customer
	catalog.tool_icons["wear_detail"]=old_icon
	spatial._build()
	check(spatial._bg.texture==old_room and spatial._npc.texture==old_customer and spatial._tool_icon("wear_detail")!=replacement,"restore scene and fallback tool artwork")
	check(host.runtime.snapshot()==snapshot,"scene art restored without authority mutation")

# Both stock and customer custody use the same page-local real grid.
func show_item_grid(id:String)->bool:
	for row:Dictionary in host.runtime.view().stock:
		if row.id!=id:
			continue
		var grid_id:String=str(row.inventory)
		var before:Dictionary=host.runtime.snapshot()
		if host._management._grid_page_id!=grid_id:
			if not await click("inventory_grid_"+grid_id):
				return false
		check(host.runtime.snapshot()==before,"grid page switching is read-only")
		return true
	return false

func verify_inventory_grid_page()->void:
	var management=host._management
	var page:String=management._grid_page_id
	var pane:Control=management._stock_scroll
	var visible_grid:=management.find_child("spatial_grid_"+page,true,false) as Control
	check(visible_grid!=null and visible_grid.is_visible_in_tree() and pane.get_global_rect().encloses(visible_grid.get_global_rect()),"entire active stock grid visible without scroll")
	if visible_grid!=null:
		print("ZT_GRID_GEOMETRY pane=",pane.get_global_rect()," grid=",visible_grid.get_global_rect())
	for grid:Dictionary in host.runtime.view().stock_grids:
		if grid.id!=page:
			check(management.find_child("spatial_grid_"+str(grid.id),true,false)==null,"inactive grid not stacked below active grid")

func verify_ledger_summary()->void:
	var summary:=host._office.find_child("office_ledger_summary",true,false) as Control
	if not check(summary!=null and root.get_visible_rect().encloses(summary.get_global_rect()),"ledger summary bounded by viewport"):
		return
	check(host._office.find_child("office_ledger",true,false)==null and summary.find_children("*","ScrollContainer",true,false).is_empty(),"item index has no scrolling history list")
	var rows:Array=summary.find_children("history_item_*","Button",true,false)
	check(rows.size()<=3,"bounded item index page")
	for row:Button in rows:
		check(summary.get_global_rect().encloses(row.get_global_rect()) and row.size.y>=48,"ledger item immediately accessible "+str(row.name))


# Only the existing normal 720p route gains these bounded resize probes.
# No additional campaign, no authority commands and no automatic reveal/scroll.
func responsive_review(context:String)->void:
	if _expected_pixels!=Vector2i(1280,720) or _wholesale:
		return
	var before:Dictionary=host.runtime.snapshot()
	var previous_size:Vector2i=root.size
	var previous_scale:Vector2i=root.content_scale_size
	var selection:String=str(host._management._selected) if context in ["stock","workshop"] else ""
	for dimensions:Vector2i in [Vector2i(960,720),Vector2i(1152,720)]:
		root.content_scale_size=dimensions
		root.size=dimensions
		await frames()
		var tag:String=context+" "+str(dimensions.x)+"x"+str(dimensions.y)
		print("ZT_RESPONSIVE_REVIEW ",tag," viewport=",root.get_visible_rect()," pixels=",root.size)
		check(root.get_visible_rect().size==Vector2(dimensions),"explicit logical viewport "+tag)
		if context=="inspection":
			verify_review_bounds()
			for id:String in ["select_tool_wear_detail","region_wear_detail","open_book"]:
				responsive_target(host._spatial,id,tag)
		elif context=="counter":
			verify_counter_bounds()
			responsive_target(host._spatial,"spatial_customer_drop",tag)
		else:
			verify_inventory_grid_page()
			var management:Control=host._management
			var footer:=management.find_child("inventory_fixed_footer",true,false) as Control
			check(footer!=null and root.get_visible_rect().encloses(footer.get_global_rect()),"fixed footer fully visible "+tag)
			for id:String in (["stock_rotate","stock_confirm","inventory_detail_drop"] if context=="stock" else ["work_confirm","work_next_day","inventory_detail_drop"]):
				responsive_target(management,id,tag)
			check(host._management._selected==selection,"resize retains selected item "+tag)
		check(host.runtime.snapshot()==before,"responsive presentation only "+tag)
		await RenderingServer.frame_post_draw
		var img:Image=root.get_texture().get_image()
		check(img!=null and not img.is_empty() and img.get_size()==dimensions and img.save_png(out.path_join("responsive-"+context+"-"+str(dimensions.x)+"x"+str(dimensions.y)+".png"))==OK,"actual compact capture "+tag)
	root.content_scale_size=previous_scale
	root.size=previous_size
	await frames()
	check(host.runtime.snapshot()==before,"return to original size preserves authority "+context)

func responsive_target(panel:Control,id:String,tag:String)->void:
	var node:=panel.find_child(id,true,false) as Control
	check(node!=null and node.is_visible_in_tree() and panel.get_global_rect().encloses(node.get_global_rect()) and root.get_visible_rect().encloses(node.get_global_rect()),"unscrolled visible target "+id+" "+tag)
