extends "res://src/presentation/alpha_b1_host.gd"
## Inherit only the B3 session/save transport and contextual document actions.
const DeskProp = preload("res://src/presentation/b3_desk_prop.gd")
const COPY_PATH = "res://data/alpha_b3/w19_desk_ko.json"
var desk_copy: Dictionary
var phone_contact := ""
var phone_terms := ""
var phone_revision := -1
var dock_slots: Array = []
var book_choice := false
var index_group := -1
var index_page := 0
const Art = preload("res://src/presentation/native_v23_art.gd")
const KnownEstimate = preload("res://src/domain/known_estimate.gd")
const SurfaceVisuals = preload("res://src/presentation/surface_visuals.gd")
const INTRO_FILE = "res://data/alpha_b3/spatial_intro_ko.json"
const BEATS = ["port","ledger","clinic","shutter","counter"]
var sound = preload("res://src/presentation/commit_feedback.gd").new()
var stage: Control
var scenery: Control
var interaction: Control
var feedback: Control
var mounting: Control
var room_key := ""
var drag_origin: Button
var standing_actor: TextureRect
var rail: Control
var rail_key := ""
var rail_used := false
var offer_editor: LineEdit
var editor_context := ""
var editor_used := false
var captions: Dictionary
var drawer := ""
var zoom := false
var reverse := false
var chosen_tool := ""
var selected := ""
var storage := "player_stock"
var rotated := false
var hand_page := 0
var tool_page := 0
var price_text := ""
var last_visit := ""
var reduce_motion := false
var motion_subjects: Dictionary = {}
var last_motion_event := ""
var pending_save := false
var _leaving_title := false
var hint := ""
var draft: Dictionary = {}
var papers_open := false
var receipt_id := ""
var compact_layout := false
var drawer_scroll := 0
var placement_hint: Label
var hover_ghost: ColorRect
var reading_scale := 100
var reference_model := ""
var private_model := ""
var estimate_text := ""
var appraisal_context := ""
var lens_open := false
var surface_slot := ""
var reference_material := "metal"
var reference_variant := 0
var book_tab := 0
var previous_book_scroll := 0
var layout_after_drag := false
var tag_draft: Dictionary = {}

func _actor_label(actor_id: String) -> String:
	if actor_id=="player": return _text("spatial.shop")
	var key := "alpha.named."+actor_id
	return _text(key) if _strings.has(key) else _text("spatial.visitor")

func _slot() -> String:
	return "spatial_week_v1"

func _week_source(seed_value: int) -> Dictionary:
	return preload("res://src/content/b3_spatial_week_seed.gd").content(seed_value)

func _ready() -> void:
	desk_copy = JSON.parse_string(FileAccess.get_file_as_string(COPY_PATH))
	if save_directory_override.is_empty():
		save_directory_override = "user://zt_rebuild/spatial_week"
	var continuing := FileAccess.file_exists(save_directory_override.path_join(_slot()+".a.json")) or FileAccess.file_exists(save_directory_override.path_join(_slot()+".b.json"))
	captions = JSON.parse_string(FileAccess.get_file_as_string(INTRO_FILE))
	resized.connect(_viewport_changed)
	super._ready()
	add_child(sound)
	if session != null: sound.prime(int(session.snapshot().revision))
	if continuing and not _blocked:
		_intro = false
		refresh()

func _viewport_changed() -> void:
	if not is_inside_tree(): return
	var compact := size.x < size.y * 1.5
	if get_viewport().gui_is_dragging():
		layout_after_drag = compact != compact_layout
		_scale_stage()
		return
	if compact != compact_layout and is_instance_valid(stage):
		compact_layout = compact
		refresh()
	else:
		compact_layout = compact
		_scale_stage()

func _notification(what: int) -> void:
	if what==NOTIFICATION_DRAG_END and is_instance_valid(drag_origin):
		drag_origin.self_modulate = Color.WHITE
		drag_origin = null
	if what==NOTIFICATION_DRAG_END and layout_after_drag:
		layout_after_drag = false
		_viewport_changed.call_deferred()

func _scale_stage() -> void:
	if is_instance_valid(stage):
		var factor := minf(size.x / 1280.0,size.y / 720.0)
		stage.scale = Vector2.ONE * factor
		stage.position = (size - Vector2(1280,720)*factor)*0.5

func place(node: Control, x: float,y: float,w: float,h: float) -> void:
	mounting.add_child(node)
	node.position = Vector2(x,y)
	node.size = Vector2(w,h)

func pic(tex: Texture2D,x: float,y: float,w: float,h: float,fill: bool=false) -> TextureRect:
	var node := TextureRect.new()
	node.texture = tex
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE if fill else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(node,x,y,w,h)
	return node

func paper(x: float,y: float,w: float,h: float,tint: Color=Color("#242322ed")) -> ColorRect:
	var node := ColorRect.new()
	node.color = tint
	place(node,x,y,w,h)
	return node

func words(value: String,x: float,y: float,w: float,h: float,points: int=20) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",roundi(float(points)*reading_scale/100.0))
	label.add_theme_constant_override("outline_size",4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(label,x,y,w,h)
	return label

func action(id: String,caption: String,x: float,y: float,w: float,h: float,callback: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = caption
	button.add_theme_font_size_override("font_size",roundi(16.0*reading_scale/100.0))
	button.gui_input.connect(func(event:InputEvent)->void:
		if event is InputEventKey and event.keycode in [KEY_ENTER,KEY_KP_ENTER]: button.accept_event())
	button.pressed.connect(func()->void:
		if button.is_inside_tree() and not _leaving_title: callback.call())
	place(button,x,y,w,h)
	return button

func command_button(kind: String,caption: String,x: float,y: float,w: float,payload: Dictionary={}) -> Button:
	return action(kind,caption,x,y,w,42,func()->void: _submit(kind,payload))

func open_drawer(which: String) -> void:
	if drawer=="notes": previous_book_scroll = drawer_scroll
	drawer_scroll = previous_book_scroll if which=="notes" else 0
	draft.clear()
	drawer = which
	phone_terms = ""
	phone_revision = -1
	if which=="notes" and not book_choice and lens_open and not surface_slot.is_empty(): book_tab = 1
	hint = ""
	refresh()
	if which=="notes": _slide(motion_subjects.get("book"),Vector2(14,0),0.18)

func _layer() -> Control:
	var layer := Control.new()
	layer.size = Vector2(1280,720)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(layer)
	return layer

func _clear_layer(layer: Control) -> void:
	for node in layer.get_children():
		layer.remove_child(node)
		node.queue_free()

func _room(index: int,npc: bool) -> void:
	var key := str([_intro,index,last_visit,npc,reduce_motion])
	if key == room_key:
		if is_instance_valid(standing_actor): motion_subjects["actor"] = standing_actor
		return
	room_key = key
	_clear_layer(scenery)
	standing_actor = null
	mounting = scenery
	pic(Art.WINDOWS[index],0,0,1280,720,true)
	pic(Art.ROOM,0,0,1280,720,true)
	if npc:
		var actor: String = str(session.alpha_view().active.get("actor_id",""))
		var portrait := pic(Art.scene_texture("customer.opening" if actor=="G01" else "customer.watch" if actor=="G04" else "customer.neutral"),525,70,260,395)
		standing_actor = portrait
		motion_subjects["actor"] = portrait
		if not reduce_motion:
			portrait.pivot_offset = Vector2(130,395)
			var breath := portrait.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
			breath.tween_property(portrait,"scale:y",1.004,1.65)
			breath.tween_property(portrait,"scale:y",1.0,1.65)
	pic(Art.COUNTER,0,0,1280,720,true)
	pic(Art.AMBER,0,0,1280,720,true)
	pic(Art.LAMP,0,0,1280,720,true)
	mounting = interaction

func intro_next() -> void:
	if _intro_page == BEATS.size()-1:
		intro_skip()
	else:
		_intro_page += 1
		refresh()

func _intro_scene() -> void:
	match _intro_page:
		0:
			var street := preload("res://src/presentation/menu_street.gd").new()
			street.animated = not reduce_motion
			place(street,0,0,1280,720)
		1: pic(Art.OFFICE_ROOM,0,0,1280,720,true)
		2:
			pic(Art.OFFICE_ROOM,0,0,1280,720,true)
			pic(Art.OFFICE_FOREGROUND,0,0,1280,720,true)
			pic(Art.OFFICE_LAMP,0,0,1280,720,true)
		_: _room(0,false)
	if _intro_page == 3 and not reduce_motion:
		var shutter := paper(0,0,1280,410,Color("#24292c"))
		shutter.create_tween().tween_property(shutter,"position:y",-420,0.65)
	if _intro_page in [1,2]:
		paper(135,82,530,218,Color("#b4a688"))
		paper(146,93,5,185,Color("#89745a"))
		var ink := words("크라벤스크   /   " + ("중고상점 영업부" if _intro_page==1 else "진료 기록"),169,106,473,48,23)
		ink.add_theme_color_override("font_color",Color("#332e27"))
		ink.add_theme_constant_override("outline_size",0)
		var entry := words("7.26   재고 0   /   미결 정리\n7.28   이송 승인 취소" if _intro_page==1 else "10.31   알렉세이 바린 · 38세\nRAD-1   1회분",169,163,455,92)
		entry.add_theme_color_override("font_color",Color("#43392e"))
		entry.add_theme_constant_override("outline_size",0)
	var beat: Array = captions[BEATS[_intro_page]]
	paper(56,360,1168,318)
	words(beat[0],92,380,1040,46,32)
	words(beat[1],92,442,1080,168)
	action("intro_motion","동작 줄이기" if not reduce_motion else "동작 줄임",90,610,160,45,func()->void:
		reduce_motion = not reduce_motion
		sound.set_motion(not reduce_motion)
		refresh())
	action("intro_mute","음소거",264,610,120,45,func()->void:AudioServer.set_bus_mute(0,not AudioServer.is_bus_mute(0)))
	action("intro_next","개점 준비" if _intro_page == 4 else "다음",998,610,168,48,intro_next)
	action("intro_skip","건너뛰기",810,610,168,48,intro_skip)

func refresh() -> void:
	var focused := get_viewport().gui_get_focus_owner() as LineEdit
	var field := str(focused.name) if focused else ""
	var caret := focused.caret_column if focused else 0
	var context := appraisal_context
	var stock_id := selected
	editor_used = false
	rail_used = false
	_rebuild_stage()
	if is_instance_valid(rail): rail.visible = rail_used
	if is_instance_valid(offer_editor): offer_editor.visible = editor_used
	if context!=appraisal_context or stock_id!=selected or field not in ["price","private_estimate","Amount"]: return
	var replacement := stage.find_child(field,true,false) as LineEdit
	if replacement and replacement.is_visible_in_tree() and not replacement.has_focus():
		replacement.grab_focus()
		replacement.caret_column = mini(caret,replacement.text.length())

func _rebuild_stage() -> void:
	motion_subjects.clear()
	if not is_instance_valid(stage):
		stage = Control.new()
		stage.size = Vector2(1280,720)
		add_child(stage)
		scenery = _layer()
		interaction = _layer()
		feedback = _layer()
	for child in interaction.get_children():
		if child != offer_editor and child != rail:
			interaction.remove_child(child)
			child.queue_free()
	mounting = interaction
	scenery.visible = not _blocked and session != null and ((_intro and _intro_page>=3) or (not _intro and drawer in ["","notes","phone"]))
	scenery.process_mode = Node.PROCESS_MODE_INHERIT if scenery.visible else Node.PROCESS_MODE_DISABLED
	if _blocked or reduce_motion or not drawer.is_empty(): _clear_layer(feedback)
	_scale_stage()
	if _blocked or session == null:
		words(_message,70,320,1120,90)
		if pending_save: action("retry_save","현재 거래 저장 다시 시도",70,438,380,48,_retry_save)
		action("leave_blocked","제목으로",480,438,170,48,_return_to_title)
		return
	if _intro:
		_intro_scene()
		return
	var v: Dictionary = session.alpha_view()
	var visit: String = str(v.active.get("id",""))
	var context := visit + "/" + str(v.appraisal.get("item_id",""))
	if context != appraisal_context:
		appraisal_context = context
		dock_slots.clear()
		book_choice = false
		index_group = -1
		index_page = 0
		lens_open = false
		surface_slot = ""
		previous_book_scroll = 0
		book_tab = 0
		if drawer == "notes": drawer = ""
		if visit == last_visit:
			private_model = ""
			reference_model = ""
			estimate_text = ""
			chosen_tool = ""
			price_text = ""
			hand_page = 0
			reverse = false
			zoom = false
	if visit != last_visit:
		draft.clear()
		papers_open = false
		reference_model = ""
		private_model = ""
		estimate_text = ""
		tool_page = 0
		last_visit = visit
		zoom = false
		reverse = false
		chosen_tool = ""
		hand_page = 0
		price_text = ""
		hint = ""
	_room(5 if v.phase == "EVENING_WORK" else 1,not v.active.is_empty())
	var cash: Dictionary = session.snapshot().wallets.player
	words(_text("spatial.cash") % [v.day,cash.VKC,cash.USD],30,12,660,38)
	action("preferences","설정",1160,16,90,36,func()->void: open_drawer("settings"))
	if drawer.is_empty() and not zoom:
		var due: PackedStringArray = []
		for contract: Dictionary in v.contracts.values():
			if contract.get("status")=="accepted" and int(contract.due_day)<=int(v.day)+1: due.append("D"+str(contract.due_day))
		if v.phase=="OPEN_IDLE": words("남은 방문 "+str(v.remaining),720,12,205,38,17)
		if not due.is_empty(): words("계약 기한 "+", ".join(due),931,12,223,38,17)
	if drawer=="notes" and (v.appraisal.is_empty() or v.phase!="CUSTOMER_ACTIVE"): drawer = ""
	if not drawer.is_empty():
		_drawer(v)
		return
	if not _message.is_empty() or not hint.is_empty():
		words(_message if not _message.is_empty() else hint,28,660,940,48)
	match v.phase:
		"DAY_PREP": command_button("alpha_open","셔터 올리기",520,514,240)
		"OPEN_IDLE":
			if v.remaining > 0: command_button("alpha_next_customer","문 열어 손님 맞기",485,400,310)
			command_button("alpha_close","영업 마감",1010,580,205)
		"CUSTOMER_ENTER": command_button("alpha_ack_entry",str(captions.reply) if visit=="visit_g01" else "어서 오세요",548,355,185)
		"CUSTOMER_EXIT":
			command_button("alpha_ack_exit","손님 배웅",548,355,185)
			var records: Array = session.snapshot().ledger
			if not records.is_empty() and records.back().visit_id==visit:
				var receipt: Dictionary = records.back()
				words(_text("spatial.received")+" · %d VKC / %d USD"%[receipt.amounts.VKC,receipt.amounts.USD],405,466,546,46)
		"CUSTOMER_ACTIVE": _counter(v)
		"CLOSE_SETTLE": command_button("alpha_settle","장부 마감 · 저녁으로",496,400,290)
		"EVENING_WORK": command_button("alpha_next_day","하루 마치기",995,560,225)
		"NEXT_DAY": command_button("alpha_prepare_day","다음 날 아침",520,435,240)
		"COMPLETE": words("첫 주 영업 종료",480,380,420,80,36)
	if v.phase in ["CLOSE_SETTLE","EVENING_WORK"] and v.has("local_trade_flow"):
		var flow: Dictionary = v.local_trade_flow
		words(desk_copy.close_flow%[flow.bought,flow.sold,flow.VKC,flow.USD],480,180,665,58,18)
	if v.phase == "CUSTOMER_ENTER":
		var greet := action("greet_visitor","",535,92,225,242,func()->void:_submit("alpha_ack_entry"))
		greet.flat = true
		greet.tooltip_text = _actor_label(v.active.actor_id)
		if visit=="visit_g01":
			motion_subjects["item"] = pic(Art.RADIO_COUNTER,500,415,245,100)
			words(captions.g01,774,244,420,64)
	if v.phase != "CUSTOMER_ACTIVE" or not zoom:
		action("stockroom","재고 서랍",32,75,154,44,func()->void: open_drawer("stock"))
		action("ledger","장부 · 계약",32,126,164,44,func()->void: open_drawer("ledger"))
	if v.phase in ["DAY_PREP","OPEN_IDLE","EVENING_WORK"]:
		action("news",_text("spatial.news"),548,597,150,46,func()->void: open_drawer("news"))
	if v.phase == "EVENING_WORK":
		_desk_object("phone","phone","전화기",Rect2(944,336,177,148),func()->void:open_drawer("phone"))
		_desk_object("address_book","book","연락처 수첩",Rect2(721,350,178,132),func()->void:open_drawer("phone"))

func _counter(v: Dictionary) -> void:
	var a: Dictionary = v.appraisal
	var actor: String = _actor_label(str(v.active.actor_id))
	var speech: String = _b2_npc_line(v)
	if speech.is_empty(): speech = _text(v.active.purpose_key)
	words(actor+"   "+speech,799,65,413,79)
	if not a.is_empty() and not a.offers.is_empty():
		var latest: Dictionary = a.offers.back()
		words(_text("spatial.terms")%[latest.amount,latest.currency]+" · "+("수락" if latest.response=="accepted" else "거절"),799,142,410,40,17)
	if v.active.id == "alpha_marcus_intro":
		var terms := VBoxContainer.new()
		place(terms,420,365,440,180)
		_add_contract_actions(terms,v)
	elif not a.is_empty():
		_specimen(v,a)
	else:
		var visit: Dictionary = session.snapshot().visits.get(str(v.active.id),{})
		if not visit.is_empty() and not visit.prices.is_empty() and not bool(visit.scope.get("completed",false)):
			words(_text("spatial.no_terms"),466,352,400,90)
		else:
			for job: Dictionary in v.services.entries:
				if job.actor_id==v.active.actor_id and job.has("item_id"):
					var sample: Texture2D = Art.ITEMS.model_texture(str(job.def_id),"counter",str(job.item_id))
					if sample != null: pic(sample,476,336,300,95)
					break


	if (not zoom or a.is_empty()) and v.active.id!="alpha_marcus_intro":
		var actor_id: String = v.active.actor_id
		var has_terms: bool = v.get("fx",{}).get("at_counter",false)
		for group: Array in [v.services.entries,v.commissions.entries]:
			for entry: Dictionary in group:
				if entry.actor_id==actor_id: has_terms = true
		for contract: Dictionary in v.contracts.values():
			if contract.supplier==actor_id: has_terms = true
		if has_terms: _counter_papers(v)

	if not zoom:
		if v.can_exchange:
			var contact := command_button("alpha_exchange_contact","연락처 교환",42,235,175,{"actor_id":v.active.actor_id,"accepted":true})
			_paper_face(contact)
		elif v.contacts.any(func(record:Dictionary)->bool:return record.actor_id==v.active.actor_id):
			words(_actor_label(str(v.active.actor_id))+" · 연락처 수첩",40,233,240,48,16)
		if v.active.id == "watch_a": command_button("week_pledge","시계 전당 · 40 VKC",42,280,216)
		if v.active.id != "alpha_marcus_intro" or not v.contracts.get("rad1_first",{}).get("can_accept",false):
			command_button("alpha_finish_customer","응대 마치기",1020,246,186)

func _counter_papers(v: Dictionary) -> void:
	var envelope := action("visitor_papers","의뢰서 · 견적 보기",42,182,235,45,func()->void:
		papers_open = not papers_open
		refresh())
	_paper_face(envelope,papers_open)
	if papers_open:
		paper(796,135,446,297)
		var scroll := ScrollContainer.new()
		place(scroll,808,146,422,272)
		var terms := VBoxContainer.new()
		terms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(terms)
		_add_contract_actions(terms,v)
		_add_b2_commission_actions(terms,v)
		_add_b2_service_actions(terms,v)
		_add_b3_fx_actions(terms,v)

func _preview(kind: String,payload: Dictionary) -> void:
	var result: Dictionary = session.spatial_action_preview(kind,payload)
	draft = {"kind":kind,"payload":payload.duplicate(true),"result":result}
	refresh()

func _draft_controls(x: float,y: float,id: String) -> void:
	if draft.is_empty(): return
	var result: Dictionary = draft.result
	if result.ok:
		words(_text("spatial.preview_cash")%[result.VKC,result.USD],x,y,404,36,17)
		var button := action(id,_text("spatial.confirm"),x,y+39,168,42,func()->void:
			if draft.is_empty() or not draft.result.ok: return
			if session.snapshot().revision != draft.result.revision:
				_preview(draft.kind,draft.payload)
				return
			_submit(draft.kind,draft.payload))
		button.focus_mode = Control.FOCUS_ALL
	else:
		var key := "spatial.error."+str(result.error)
		words(_text(key if _strings.has(key) else "spatial.error.permission"),x,y,410,48,17)
	action("discard_draft",_text("spatial.cancel"),x+180,y+39,138,42,func()->void:
		_discard_preview()
		refresh())

func _paper_face(button: Button,marked: bool=false) -> void:
	for state: String in ["normal","hover","pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#dfceb0") if state=="hover" else (Color("#d4bb8d") if marked else Color("#c7b89a"))
		style.border_color = Color("#806644") if marked else Color("#91836c")
		style.border_width_left = 5 if marked else 1
		style.border_width_bottom = 2
		style.content_margin_left = 7
		style.content_margin_right = 7
		button.add_theme_stylebox_override(state,style)
	for key: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		button.add_theme_color_override(key,Color("#302c25"))

func _prop(parent: Control,kind: String,rect: Rect2) -> Control:
	var prop := DeskProp.new()
	prop.kind = kind
	prop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(prop)
	prop.position = rect.position
	prop.size = rect.size
	return prop

func _desk_object(id: String,kind: String,caption: String,rect: Rect2,callback: Callable) -> Button:
	var button := action(id,"",rect.position.x,rect.position.y,rect.size.x,rect.size.y,callback)
	button.flat = true
	button.tooltip_text = caption
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var prop := _prop(button,kind,Rect2(0,0,rect.size.x,rect.size.y-18))
	prop.set("lifted",kind==chosen_tool)
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(0,rect.size.y-25)
	label.size = Vector2(rect.size.x,25)
	label.add_theme_font_size_override("font_size",16)
	button.add_child(label)
	button.mouse_entered.connect(func()->void: prop.modulate=Color("#ffdfab"))
	button.mouse_exited.connect(func()->void: prop.modulate=Color.WHITE)
	return button

func _tray(x: float,y: float,w: float,h: float) -> void:
	paper(x+4,y+5,w,h,Color("#211c19")).mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper(x,y,w,h,Color("#6a5744")).mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper(x+5,y+4,w-10,h-9,Color("#45473a")).mouse_filter = Control.MOUSE_FILTER_IGNORE

func _specimen(v: Dictionary,a: Dictionary) -> void:
	var id: String = a.item_id
	var texture: Texture2D = Art.ITEMS.model_texture(str(a.def_id),"inspection" if zoom else "counter",id,reverse and zoom)
	_tray(52,475,246,38)
	paper(393,502,305,9,Color("#262722")).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var surface_slots: Array = SurfaceVisuals.observation_slots(a.cards)
	if chosen_tool in surface_slots and surface_slot.is_empty(): surface_slot = chosen_tool
	# Preserve the selected, not-yet-observed slot until the inspect command commits.
	if surface_slot not in surface_slots and (surface_slot not in SurfaceVisuals.SLOTS or surface_slot!=chosen_tool):
		surface_slot = str(surface_slots[0]) if not surface_slots.is_empty() else ""
	var sample: Dictionary = SurfaceVisuals.observed(a.cards,surface_slot,int(a.surface_seed)) if lens_open and not reverse else {}
	var surface_texture: Texture2D = SurfaceVisuals.texture_for(sample)
	var specimen := pic(texture,315,294,334 if surface_texture!=null else 460,218)
	if not zoom:
		var focus_item := action("specimen","",315,294,specimen.size.x,218,func()->void:
			zoom = true
			refresh())
		focus_item.set_drag_forwarding(Callable(),func(at:Vector2,data:Variant)->bool:
			return _tool_drop_allowed(at/focus_item.size,data,v,a),func(at:Vector2,data:Variant)->void:
			if _tool_drop_allowed(at/focus_item.size,data,v,a): _inspect_drop(str(data.tool)))
		focus_item.flat = true
		focus_item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	action("lens","확대경 접기" if lens_open else "확대경",51,324,136,44,func()->void:
		lens_open = not lens_open
		refresh()
		_slide(motion_subjects.get("item"),Vector2(0,6),0.14))
	motion_subjects["item"] = specimen
	if lens_open and not reverse:
		if surface_texture!=null:
			var loupe := _prop(interaction,"sample",Rect2(568,311,194,194))
			loupe.set("sample",surface_texture)
			words(str(desk_copy.subject)+" · "+str(sample.caption),426,512,345,42,15)
		elif sample.is_empty(): words("표면을 직접 조사하세요",322,262,355,44,15)
		else: words(str(sample.caption)+" · 이미지 미반입",285,425,480,35,14)
		if not surface_slots.is_empty() and not sample.is_empty():
			var index: int = surface_slots.find(surface_slot)
			var caption: String = SurfaceVisuals.SLOT_NAMES[SurfaceVisuals.SLOTS.find(surface_slot)]
			action("surface_next",caption+" · "+str(index+1)+"/"+str(surface_slots.size()),322,262,355,44,func()->void:
				surface_slot = str(surface_slots[(index+1)%surface_slots.size()])
				refresh())
	elif lens_open: words("뒷면 확대 표본 없음",322,262,355,44,15)
	specimen.mouse_filter = Control.MOUSE_FILTER_STOP
	specimen.set_drag_forwarding(Callable(),func(at:Vector2,data:Variant)->bool:
		return _tool_drop_allowed(at/specimen.size,data,v,a),func(at:Vector2,data:Variant)->void:
		if _tool_drop_allowed(at/specimen.size,data,v,a): _inspect_drop(str(data.tool)))
	if drawer!="notes" and zoom:
		action("close_mat","카운터",52,259,146,44,func()->void:
			chosen_tool = ""
			lens_open = false
			zoom = false
			refresh())
	if Art.ITEMS.model_art.get(str(a.def_id),{}).has("back"):
		action("turn_item","뒤집기",310,510,106,42,func()->void:
			reverse = not reverse
			refresh())
	for row: Dictionary in a.tools:
		if not dock_slots.has(row.id): dock_slots.append(row.id)
	for card: Dictionary in a.cards:
		if not dock_slots.has(card.slot): dock_slots.append(card.slot)
	var page_count := maxi(1,ceili(dock_slots.size()/3.0))
	tool_page = mini(tool_page,page_count-1)
	for index in range(dock_slots.size()):
		var slot: String = dock_slots[index]
		var caption := str(desk_copy.tool_names.get(slot,_text("b2.inspect."+slot)))
		var tool := _desk_object("tool_"+slot,slot,caption,Rect2(44+(index%3)*86,391,88,104),func()->void:
			zoom = true
			chosen_tool = slot
			lens_open = slot in SurfaceVisuals.SLOTS
			surface_slot = slot if lens_open else ""
			refresh())
		tool.visible = floori(index/3.0)==tool_page
		if chosen_tool==slot: tool.modulate = Color("#f4d5a7")
		tool.tooltip_text = caption+(" · "+str(desk_copy.held) if chosen_tool==slot else "")
		motion_subjects["tool_"+slot] = tool
		tool.set_drag_forwarding(func(_at:Vector2)->Variant:
			var held := DeskProp.new()
			held.kind = slot
			held.custom_minimum_size = Vector2(88,76)*stage.scale
			tool.set_drag_preview(held)
			return {"tool":slot,"visit":v.active.id},Callable(),Callable())

	if page_count>1:
		action("more_tools","도구함  %d/%d  ›"%[tool_page+1,page_count],49,518,165,43,func()->void:
			tool_page = (tool_page+1)%page_count
			refresh())
	if not chosen_tool.is_empty() and chosen_tool in dock_slots:
		var apply := action("apply_tool","",specimen.position.x,specimen.position.y,specimen.size.x,specimen.size.y,func()->void:
			_inspect_drop(chosen_tool))
		var held := DeskProp.new()
		held.kind = chosen_tool
		held.follow_target = true
		held.size = Vector2(64,50)
		held.hide()
		apply.add_child(held)
		apply.flat = true
		apply.mouse_default_cursor_shape = Control.CURSOR_CROSS
		apply.tooltip_text = "선택한 도구로 살펴보기"
		apply.set_drag_forwarding(Callable(),func(at:Vector2,data:Variant)->bool:
			return _tool_drop_allowed(at/apply.size,data,v,a),func(at:Vector2,data:Variant)->void:
			if _tool_drop_allowed(at/apply.size,data,v,a): _inspect_drop(str(data.tool)))

	_evidence_rail(v,a)
	_offer_docket(v,a,id)

func _evidence_rail(v: Dictionary,a: Dictionary) -> void:
	if a.cards.is_empty(): return
	var per_page := 2 if reading_scale>100 or compact_layout else 3
	var card_width := 584.0/per_page
	hand_page = clampi(hand_page,0,maxi(0,ceili(float(a.cards.size())/per_page)-1))
	var signature := JSON.stringify([appraisal_context,a.cards,hand_page,per_page,reading_scale])
	rail_used = true
	if not is_instance_valid(rail):
		rail = Control.new()
		rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		interaction.add_child(rail)
	if signature==rail_key:
		for card: Dictionary in a.cards:
			var slip := rail.get_node_or_null("fact_"+str(card.slot)) as Button
			if slip: motion_subjects["card_"+str(card.slot)] = slip
		return
	rail_key = signature
	_clear_layer(rail)
	mounting = rail
	var start := hand_page*per_page
	for i: int in range(start,mini(start+per_page,a.cards.size())):
		var card: Dictionary = a.cards[i]
		var slot: String = card.slot
		var fact := _fact_caption(slot,card.value)
		var note := action("fact_"+slot,(("공개 중 · 재첨부" if card.selected else "공개 중") if card.public_active else ("첨부 예정" if card.selected else "내 기록"))+"\n"+_text(card.text_key)+" · "+fact,60+(i-start)*card_width,566,card_width-9,80,func()->void: _submit("alpha_card_toggle",{"slot":slot,"selected":not card.selected}))
		_paper_face(note,card.selected)
		motion_subjects["card_"+slot] = note
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.set_drag_forwarding(func(_at: Vector2)->Variant:
			var slip := Button.new()
			slip.text = note.text
			slip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			slip.custom_minimum_size = note.size*stage.scale
			slip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_paper_face(slip,card.selected)
			note.set_drag_preview(slip)
			return {"slot":slot,"visit":v.active.id},Callable(),Callable())
	if a.cards.size()>per_page:
		action("more_facts","카드 넘기기",642,582,115,42,func()->void:
			hand_page = (hand_page+1)%ceili(float(a.cards.size())/per_page)
			refresh())
	mounting = interaction

func _offer_docket(v: Dictionary,a: Dictionary,id: String) -> void:
	paper(782,516,449,165,Color("#463f34"))
	paper(787,520,3,154,Color("#b6a282"))
	var public_cards := PackedStringArray()
	for card: Dictionary in a.cards:
		if card.selected: public_cards.append(_text(card.text_key))
	var target := words("다음 제안에 첨부 · "+("없음" if public_cards.is_empty() else ", ".join(public_cards)),800,550,417,44,16)
	target.mouse_filter = Control.MOUSE_FILTER_STOP
	target.set_drag_forwarding(Callable(),func(_at:Vector2,data:Variant)->bool: return data is Dictionary and data.get("visit")==v.active.id and a.cards.any(func(c:Dictionary)->bool:return c.slot==data.get("slot")),func(_at:Vector2,data:Variant)->void: _submit("alpha_card_toggle",{"slot":data.slot,"selected":true}))
	if not a.we_buy and drawer!="notes":
		var tag: Dictionary = Alpha.displayed_ask(session.snapshot(),id)
		if not tag.is_empty(): words("매대 표시가 · %d %s"%[tag.amount,tag.currency],805,472,403,40,17)
	elif drawer!="notes" and not a.customer_claims.is_empty(): words("손님 주장 · "+_text(a.customer_claims[0].text_key),805,183,399,70,17)
	var denomination := str(a.offer_currency)
	var quote_label := "가격 제안 · "+denomination
	if not a.accepted.is_empty(): quote_label = "합의가 · %d %s"%[a.accepted.amount,a.accepted.currency]
	elif not a.offers.is_empty():
		var latest: Dictionary = a.offers.back()
		quote_label = "직전 제안 · %d %s"%[latest.amount,latest.currency]
	var amount_link := action("counter_offer",quote_label,800,518,393,34,func()->void:
		if is_instance_valid(offer_editor): offer_editor.grab_focus())
	amount_link.flat = true
	amount_link.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if a.accepted.is_empty(): words(("내 매입 목표가" if a.we_buy else "내 판매 계획가")+(" · "+estimate_text+" "+denomination if not estimate_text.is_empty() else " · 미설정"),800,640,405,36,15)
	if not is_instance_valid(offer_editor):
		offer_editor = LineEdit.new()
		offer_editor.name = "price"
		offer_editor.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		offer_editor.max_length = 9
		offer_editor.placeholder_text = "제안할 금액"
		offer_editor.text_changed.connect(func(value:String)->void: price_text=value)
		place(offer_editor,800,595,200,44)
	var money := offer_editor
	if editor_context != appraisal_context:
		editor_context = appraisal_context
		money.text = price_text
		if price_text.is_empty() and not a.we_buy:
			var posted: Dictionary = Alpha.displayed_ask(session.snapshot(),id)
			if posted.get("currency")==denomination: money.text = str(posted.amount)
	editor_used = true
	money.show()
	interaction.move_child(money,-1)
	var currency: String = denomination
	action("offer","제안 · "+currency,1010,595,200,44,func()->void:
		# Read the actual edited control. Programmatic caret insertion and IME
		# composition need not emit text_changed before the button is pressed.
		var proposed: String = money.text.strip_edges()
		if proposed.is_valid_int() and int(proposed)>0:
			price_text = proposed
			_submit("alpha_price_offer",{"amount":int(proposed)})
		else:
			hint = "제안할 금액을 양의 정수로 입력해 주세요."
			refresh())
	if not a.accepted.is_empty():
		action("settle_trade","거래 확정 · %d %s"%[a.accepted.amount,a.accepted.currency],803,643,410,42,func()->void:
			var trade: Dictionary = session.snapshot().visits[v.active.id]
			var dest: String = "player_stock" if a.we_buy else str(trade.buyer)+"_grid"
			var fit: Dictionary = session.spatial_fit(id,dest)
			if fit.get("ok",false):
				_submit("alpha_trade",{"visit_id":v.active.id,"item_id":id,"seller":trade.seller,"buyer":trade.buyer,"currency":a.accepted.currency,"amount":a.accepted.amount,"inventory":dest,"x":fit.x,"y":fit.y,"rotated":fit.rotated})
			else:
				hint = "물건을 놓을 빈 공간이 없습니다."
				refresh())
	
	if drawer!="notes": _desk_object("notes","book",str(desk_copy.book),Rect2(899,307,215,157),func()->void: open_drawer("notes"))

func _inspect_drop(slot: String) -> void:
	zoom = true
	chosen_tool = slot
	if slot in SurfaceVisuals.SLOTS:
		lens_open = true
		surface_slot = slot
	if session.alpha_view().appraisal.cards.any(func(card:Dictionary)->bool:return card.slot==slot):
		refresh()
		return
	_submit("alpha_inspect",{"slot":slot})

func _tool_drop_allowed(relative:Vector2,data:Variant,v:Dictionary,a:Dictionary) -> bool:
	if not data is Dictionary or data.get("visit")!=v.active.id or not data.has("tool"): return false
	if not a.tools.any(func(tool:Dictionary)->bool:return tool.id==data.tool) and not a.cards.any(func(card:Dictionary)->bool:return card.slot==data.tool): return false
	return Rect2(0,0,1,1).has_point(relative)

func _drawer(v: Dictionary) -> void:
	var current: Dictionary = session.snapshot()
	if drawer=="notes":
		var line: String = _b2_npc_line(v)
		if line.is_empty(): line = _text(v.active.purpose_key)
		words(_actor_label(str(v.active.actor_id))+"   "+line,799,65,413,79)
		_specimen(v,v.appraisal)
		paper(777,184,456,321,Color("#574535"))
		paper(783,189,442,311,Color("#9c8c70"))
		paper(788,192,430,303,Color("#cabc9e"))
		paper(789,192,9,303,Color("#a28d6b"))
	elif drawer=="phone":
		_desk_object("phone_ledger","book",_text("spatial.shop")+" · 장부",Rect2(954,480,175,120),func()->void:open_drawer("ledger"))
	else:
		pic(Art.STOCK_ROOM if drawer=="stock" else Art.OFFICE_ROOM,0,0,1280,720,true)
	if drawer not in ["notes","phone"]: paper(44,50,1192,625,Color("#241f1deb"))
	action("close_drawer","재고로" if drawer=="item_history" else "카운터로",1045,128 if drawer=="notes" else 64,165,44,func()->void: open_drawer("stock" if drawer=="item_history" else ""))
	if drawer=="stock":
		_inventory(v,current)
		return
	var scroll := ScrollContainer.new()
	if drawer=="notes": place(scroll,803,196,407,292)
	elif drawer=="phone": place(scroll,55,205,896,369)
	else: place(scroll,84,126,1100,510)
	motion_subjects["book"] = scroll
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	pages.add_theme_font_size_override("font_size",roundi(16.0*reading_scale/100.0))
	scroll.set_deferred("scroll_vertical",drawer_scroll)
	scroll.get_v_scroll_bar().value_changed.connect(func(value:float)->void:
		if is_instance_valid(scroll) and scroll.is_inside_tree(): drawer_scroll=roundi(value))
	match drawer:
		"item_history":
			_history_lines(pages,selected)
		"news":
			_board_line(pages,"news_day",desk_copy.region%v.day,true)
			for notice: Dictionary in v.news:
				_board_line(pages,str(notice.id),_text("alpha.news."+str(notice.text_key)))
			if v.news.is_empty(): _board_line(pages,"empty",_text("spatial.quiet"))
		"settings":
			for percent: int in [100,125,150]:
				_button(pages,"font_"+str(percent),"글자 크기 · %d%%"%percent,func()->void:
					reading_scale = percent
					refresh())
			_button(pages,"motion","동작 줄이기 · "+("켜짐" if reduce_motion else "꺼짐"),func()->void:
				reduce_motion = not reduce_motion
				sound.set_motion(not reduce_motion)
				refresh())
			_button(pages,"mute","음소거 전환",func()->void: AudioServer.set_bus_mute(0,not AudioServer.is_bus_mute(0)))
			_button(pages,"return_title","제목 화면",_return_to_title)
		"notes": _book_contents(pages,v)
		"phone": _phone_pages(pages,v)
		"ledger":
			_board_line(pages,"cash","보유 현금   %d VKC   /   %d USD"%[current.wallets.player.VKC,current.wallets.player.USD])
			if v.phase!="CUSTOMER_ACTIVE": _add_contract_actions(pages,v)
			for contract: Dictionary in v.contracts.values():
				if v.phase!="CUSTOMER_ACTIVE": break
				_board_line(pages,"contract_record",_text("alpha.contract.header")+" · "+_text("alpha.contract.status."+str(contract.status))+" · D"+str(contract.due_day))
			for job: Dictionary in v.services.entries:
				_board_line(pages,"service_record",_text("b2.service.receipt")%[_text("b2.item."+str(job.def_id)),job.due_day,job.fee.VKC,_text("b2.service.status."+str(job.status))])
			if v.phase in ["OPEN_IDLE","EVENING_WORK"]:
				_add_b2_commission_actions(pages,v)
			else:
				for request: Dictionary in v.commissions.entries:
					_board_line(pages,"commission_record",_text(request.text_key)+" · D"+str(request.due_day)+" · "+_text("b2.commission.status."+str(request.status)))
			var pawn: Dictionary = current.alpha_shop.week_pawn
			if pawn.status != "available":
				_board_line(pages,"pledge",_text("b2.item."+str(current.items.get("WAT02",current.get("tombstones",{}).get("WAT02",{})).get("def_id","watch")))+" · "+_text("week."+str(pawn.status))+" · D"+str(pawn.due))
				if pawn.status=="pledged" and v.phase=="CLOSE_SETTLE" and v.day==pawn.due:
					_button(pages,"week_redeem",_text("week.redeem"),func()->void:_submit("week_redeem"))
					if pawn.due==4: _button(pages,"week_extend",_text("week.extend"),func()->void:_submit("week_extend"))
			for order: Dictionary in current.alpha_shop.get("outbound",{}).values():
				_board_line(pages,"order",_text("week.order")%_text("week."+str(order.status)))
				for payment: Dictionary in order.payments:
					_board_line(pages,"p_"+str(payment.action_id),"D%d · %s → %s · %d %s"%[payment.day,_actor_label(payment.from),_actor_label(payment.to),payment.amount,payment.currency])
			for entry: Dictionary in current.ledger:
				var receipt_key: String = entry.event_id
				_button(pages,"r_"+receipt_key,"%s → %s   %d VKC / %d USD   ·   %s"%[_actor_label(entry.from),_actor_label(entry.to),entry.amounts.VKC,entry.amounts.USD,_receipt_items(current,entry.root_ids)],func()->void:
					receipt_id = "" if receipt_id==receipt_key else receipt_key
					refresh())
				if receipt_id==receipt_key and entry.from!="player" and entry.to=="player":
					for currency: String in ["VKC","USD"]:
						var basis: Variant = entry.basis[currency]
						var profit: String = str(int(entry.amounts[currency])-int(basis)) if basis!=null else "?"
						_board_line(pages,"detail_"+currency,"원가 %s · 실현손익 %s %s"%[str(basis) if basis!=null else "?",profit,currency])

func _refresh_book(pages: VBoxContainer,top: bool=false) -> void:
	if drawer!="notes" or not pages.is_inside_tree(): return
	var scroll := pages.get_parent() as ScrollContainer
	var offset := 0 if top else scroll.scroll_vertical
	for child in pages.get_children():
		pages.remove_child(child)
		child.queue_free()
	_book_contents(pages,session.alpha_view())
	scroll.set_deferred("scroll_vertical",offset)

func _book_contents(pages: VBoxContainer,v: Dictionary) -> void:
	var tabs := HBoxContainer.new()
	pages.add_child(tabs)
	var titles := ["모델 대조","표면 감정","가격·기록"]
	for i in range(titles.size()):
		var tab := Button.new()
		tab.text = titles[i]
		tab.name = ["book_models","book_surface","book_prices"][i]
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = true
		tab.button_pressed = i==book_tab
		tabs.add_child(tab)
		tab.pressed.connect(func()->void:
			book_choice = true
			book_tab = i
			_refresh_book(pages,true))
	match book_tab:
		0: _model_page(pages)
		1: _surface_page(pages,v)
		2: _price_page(pages,v)
	for label in pages.find_children("*","Label",true,false):
		label.add_theme_color_override("font_color",Color("#322e28"))

func _model_page(pages: VBoxContainer) -> void:
	var entries: Dictionary = Art.ITEMS.reference_entries()
	for model: String in Art.ITEMS.model_art: entries[model] = _text("b2.item."+model)
	var keys := PackedStringArray()
	if index_group<0:
		for card: Dictionary in session.alpha_view().appraisal.cards:
			if card.slot=="identity" and entries.has(str(card.value)): keys.append(str(card.value))
		if not keys.is_empty(): _board_line(pages,"known_index",desk_copy.known)
	else:
		for model: String in entries:
			var group := 1 if model.begins_with("food_") else (2 if model.begins_with("medical_") else (3 if model.begins_with("utility_") else 0))
			if group==index_group: keys.append(model)
	var groups := GridContainer.new()
	groups.columns = 2
	pages.add_child(groups)
	for group in range(4):
		var link := Button.new()
		link.text = desk_copy.groups[group]
		groups.add_child(link)
		link.pressed.connect(func()->void:
			index_group=group
			index_page=0
			reference_model=""
			_refresh_book(pages,true))
	var strips := HBoxContainer.new()
	pages.add_child(strips)
	for k in range(index_page*3,mini(index_page*3+3,keys.size())):
		var model := keys[k]
		var tile := Button.new()
		tile.custom_minimum_size = Vector2(0,78)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.icon = Art.ITEMS.model_texture(model,"inspection")
		tile.expand_icon = true
		tile.tooltip_text = str(entries[model])
		_paper_face(tile,model==reference_model)
		var leaf := VBoxContainer.new()
		leaf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strips.add_child(leaf)
		leaf.add_child(tile)
		var nameplate := Label.new()
		nameplate.text = str(entries[model])
		nameplate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		leaf.add_child(nameplate)
		tile.pressed.connect(func()->void:
			reference_model=model
			_refresh_book(pages))
	if keys.size()>3:
		_button(pages,"next_models","›  %d / %d"%[index_page+1,ceili(keys.size()/3.0)],func()->void:
			index_page=(index_page+1)%ceili(keys.size()/3.0)
			_refresh_book(pages))
	if not reference_model.is_empty():
		var plate := TextureRect.new()
		plate.texture = Art.ITEMS.model_texture(reference_model,"inspection")
		plate.custom_minimum_size = Vector2(0,112)
		plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pages.add_child(plate)
		var features := PackedStringArray()
		for source: Dictionary in preload("res://src/domain/alpha_card_trade.gd").config().specimen_sources:
			if source.def_id != reference_model: continue
			var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(source.path))
			if not doc is Dictionary: continue
			for tool: Dictionary in doc.get("profiles",{}).get(reference_model,{}).get("tools",[]):
				var feature := _text("b2.inspect."+str(tool.id))
				if feature not in features: features.append(feature)
		if not features.is_empty(): _board_line(pages,"reference_features","대조할 특징 · "+", ".join(features))
		if Art.ITEMS.model_art.has(reference_model):
			_button(pages,"record_model","이 모델로 추정",func()->void:
				private_model = reference_model
				_refresh_book(pages))
	if not private_model.is_empty():
		_button(pages,"clear_model","내 가설 · "+_text("b2.item."+private_model)+"  ×",func()->void:
			private_model = ""
			_refresh_book(pages))

func _surface_page(pages: VBoxContainer,v: Dictionary) -> void:
	_board_line(pages,"reference_material","재질 대조 · 금속의 가공결, 플라스틱의 성형선, 종이의 절단면, 직물의 짜임, 유리의 반사면")
	_board_line(pages,"reference_exterior","외관 대조 · 경미한 국소 흔적 / 여러 부위의 마모 / 넓은 파손이나 변형")
	_surface_reference(pages)
	for group: String in ["material","exterior"]:
		var choice := OptionButton.new()
		var labels := ["재질 추정 · 보류","금속","플라스틱","종이","직물","유리"] if group=="material" else ["외관 추정 · 보류","훼손 경미","훼손 보통","훼손 심함"]
		for caption: String in labels: choice.add_item(caption)
		var values: Array = preload("res://src/domain/alpha_card_trade.gd").SURFACE_CHOICES[group]
		choice.select(maxi(0,values.find(v.appraisal.surface_judgments.get(group,"unknown"))))
		choice.item_selected.connect(func(index:int)->void:
			_submit("alpha_hypothesis",{"slot":group,"judgment":values[index]}))
		pages.add_child(choice)
	for claim: Dictionary in v.appraisal.get("customer_claims",[]):
		_board_line(pages,"claim_"+str(claim.claim_key),"손님 주장 · "+_text(claim.text_key))
		if claim.can_challenge:
			_button(pages,"query_"+str(claim.claim_key),"확인한 단서로 되묻기",func()->void:_submit("alpha_claim_challenge",{"claim_key":claim.claim_key}))
	for guess: Dictionary in v.appraisal.get("hypotheses",[]):
		_board_line(pages,"guess_status_"+str(guess.slot),_text("b2.inspect."+str(guess.slot))+" · "+_text("b2.hypothesis."+str(guess.judgment)))
		var slot: String = guess.slot
		for value: String in ["serviceable","inoperable","unknown"]:
			_button(pages,"guess_"+slot+"_"+value,"내 추정 · "+_text("b2.inspect."+slot)+" · "+_text("b2.value."+value),func()->void: _submit("alpha_hypothesis",{"slot":slot,"judgment":value}))
	for fact: Dictionary in v.appraisal.get("cards",[]):
		if fact.ever_disclosed:
			var slot: String = fact.slot
			var kind := "alpha_statement_retract" if fact.public_active else "alpha_statement_reaffirm"
			_button(pages,"spoken_"+slot,("공개 진술 철회 · " if fact.public_active else "진술 재확인 · ")+_text(fact.text_key),func()->void: _submit(kind,{"slot":slot}))

func _price_page(pages: VBoxContainer,v: Dictionary) -> void:
	_known_price(pages,v.appraisal,int(v.day))
	var estimate := LineEdit.new()
	estimate.name = "private_estimate"
	estimate.placeholder_text = ("내 매입 목표가" if v.appraisal.we_buy else "내 판매 계획가")+" · 개인 메모"
	estimate.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	estimate.max_length = 9
	estimate.text = estimate_text
	estimate.text_changed.connect(func(value:String)->void: estimate_text=value)
	pages.add_child(estimate)
	_history_lines(pages,str(v.appraisal.item_id))

func _phone_pages(pages: VBoxContainer,v: Dictionary) -> void:
	if v.phase!="EVENING_WORK": return
	if v.contacts.is_empty():
		_board_line(pages,"empty","교환한 연락처가 없습니다.")
		return
	var spread := HBoxContainer.new()
	pages.add_child(spread)
	var address_book := VBoxContainer.new()
	spread.add_child(address_book)
	var call_sheet := VBoxContainer.new()
	call_sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spread.add_child(call_sheet)
	for contact: Dictionary in v.contacts:
		var actor := str(contact.actor_id)
		var tab := _button(address_book,"contact_"+actor,_actor_label(actor),func()->void:
			phone_contact = actor
			phone_terms = ""
			refresh())
		_paper_face(tab,phone_contact==actor)
	if phone_contact.is_empty(): return
	_board_line(call_sheet,"recipient",_actor_label(phone_contact),true)
	for option: Dictionary in v.get("outbound_options",[]):
		if option.actor!=phone_contact: continue
		var id := str(option.id)
		var command := str(option.command)
		_button(call_sheet,"terms_"+id,_text(option.label),func()->void:
			phone_terms = id
			phone_revision = int(session.snapshot().revision)
			refresh())
		if phone_terms!=id: continue
		_button(call_sheet,"phone_"+id,desk_copy.confirm if command=="alpha_salvage_dispatch" else _text(option.label),func()->void:
			var options: Array = session.alpha_view().get("outbound_options",[])
			if phone_revision!=int(session.snapshot().revision) or not options.any(func(now:Dictionary)->bool:return now.id==id and now.actor==phone_contact and now.command==command):
				phone_terms=""
				refresh()
				return
			phone_terms=""
			_submit(command,{"request_id":id}))
		_button(call_sheet,"cancel_call",desk_copy.cancel,func()->void:
			phone_terms=""
			refresh())
	for order: Dictionary in session.snapshot().alpha_shop.get("outbound",{}).values():
		if order.get("actor_id","")!=phone_contact: continue
		_board_line(call_sheet,"order_state",_text("week."+str(order.status)))
		for payment: Dictionary in order.payments:
			_board_line(call_sheet,"payment","D%d · %s → %s · %d %s"%[payment.day,_actor_label(payment.from),_actor_label(payment.to),payment.amount,payment.currency])

func _surface_reference(pages: VBoxContainer) -> void:
	var families := HFlowContainer.new()
	pages.add_child(families)
	for index in range(SurfaceVisuals.MATERIALS.size()):
		var family := str(SurfaceVisuals.MATERIALS[index])
		var tab := Button.new()
		tab.text = SurfaceVisuals.MATERIAL_NAMES[index]
		tab.custom_minimum_size = Vector2(56,44)
		_paper_face(tab,reference_material==family)
		families.add_child(tab)
		tab.pressed.connect(func()->void:
			reference_material = family
			_refresh_book(pages))
	var controls := HBoxContainer.new()
	pages.add_child(controls)
	var variant_button := Button.new()
	variant_button.text = "다른 표본 · %d/4"%(reference_variant+1)
	controls.add_child(variant_button)
	variant_button.pressed.connect(func()->void:
		reference_variant = (reference_variant+1)%4
		_refresh_book(pages))
	var row := HBoxContainer.new()
	pages.add_child(row)
	for grade: int in range(3):
		var sample: Dictionary = SurfaceVisuals.reference_sample(reference_material,grade,reference_variant)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		var texture: Texture2D = SurfaceVisuals.texture_for(sample)
		if texture!=null:
			var swatch := TextureRect.new()
			swatch.texture = texture
			swatch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			swatch.custom_minimum_size = Vector2(0,96)
			swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			column.add_child(swatch)
		var label := Label.new()
		label.text = str(sample.caption) if texture!=null else str(sample.caption)+" · 미반입"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(label)
	_board_line(pages,"reference_limit","비교 예시이며 현재 물품의 재질이나 상태를 확정하지 않습니다.")

func _fact_caption(slot: String,value: Variant) -> String:
	var fact := str(value)
	if slot in SurfaceVisuals.SLOTS:
		var sample: Dictionary = SurfaceVisuals.observed([{"slot":slot,"value":value}],slot,0)
		if not sample.is_empty(): return str(sample.caption)
		if slot!="material_detail": return "확대 관찰 기록"
	for prefix: String in ["b2.value.","b2.item."]:
		if _strings.has(prefix+fact): return _text(prefix+fact)
	return fact

func _price_band_text(band: Dictionary,currency: String) -> String:
	var bounds: String = str(band.low) if band.low==band.high else "%d–%d"%[band.low,band.high]
	return "%s %s · D%d–D%d · %d건"%[bounds,currency,band.first_day,band.last_day,band.count]

func _known_price(pages: VBoxContainer,appraisal: Dictionary,day: int) -> void:
	var history: Dictionary = session.alpha_item_history(str(appraisal.item_id),last_visit)
	var known: Dictionary = KnownEstimate.evaluate(history,appraisal,private_model,day)
	if known.estimate.is_empty():
		_board_line(pages,"personal_estimate","내 감정 추정가 · 자료 부족")
	else:
		for currency: String in ["VKC","USD"]:
			if known.estimate.has(currency):
				_board_line(pages,"estimate_"+currency,"내 감정 추정가 · "+_price_band_text(known.estimate[currency],currency))
		_board_line(pages,"estimate_basis","내 상점 장부 · 모델·판단·공개 단서가 일치한 과거 개별 매각 표본. 미확인 상태·현재 수요는 미반영.")
	for currency: String in ["VKC","USD"]:
		if known.reference.has(currency):
			_board_line(pages,"known_"+currency,"과거 동일 물품 매각 · "+_price_band_text(known.reference[currency],currency))
	if known.reference.is_empty():
		_board_line(pages,"known_empty","과거 동일 물품 개별 매각 기록 없음")
	elif known.omitted>0:
		_board_line(pages,"known_omitted","최근 표시된 기록 기준 · 이전 기록 제외")
	_board_line(pages,"market_source","크라벤스크 D%d · 지역 예상 매각 범위 · 시장 자료 부족"%day)

func _history_lines(pages: VBoxContainer,id: String) -> void:
	var history: Dictionary = session.alpha_item_history(id,last_visit)
	_board_line(pages,"history_heading","공개 거래 이력 · 최근 거래부터",true)
	if history.records.is_empty(): _board_line(pages,"empty_history","기록된 거래가 없습니다.")
	for row: Dictionary in history.records:
		var label := "매입" if row.direction=="purchase" else "판매"
		var amounts: Variant = row.get("amounts")
		var price := "%d VKC / %d USD"%[amounts.VKC,amounts.USD] if amounts is Dictionary else "개별 체결가 미기록"
		_board_line(pages,"record_"+str(row.event_id),"D%d · %s · %s"%[int(row.minute/1440)+1,label,price])
		var sheet: Dictionary = row.get("offer_reference",{})
		if not sheet.is_empty():
			_board_line(pages,"sheet_"+str(row.event_id),"실제 체결에 연결된 제안 · 공개 단서 %d건"%sheet.get("facts",[]).size())
			for fact: Dictionary in sheet.get("facts",[]):
				var key := "b2.inspect."+str(fact.get("slot",""))
				if _strings.has(key): _board_line(pages,"historical_fact",_text(key)+" · "+_fact_caption(str(fact.slot),fact.get("value","")))
	var past: Array = history.prior_offers
	for offer: Dictionary in past:
		var response := "수락" if offer.response=="accepted" else "거절"
		_board_line(pages,"past_offer","당시 가격 제안 · %d %s · %s"%[offer.amount,offer.currency,response])
		var terms := {"metal":"금속","plastic":"플라스틱","paper":"종이","fabric":"직물","glass":"유리","minimal":"경미","moderate":"보통","severe":"심함"}
		for group: String in offer.assessment:
			_board_line(pages,"past_guess","당시 내 "+("재질" if group=="material" else "외관")+" 추정 · "+str(terms.get(offer.assessment[group],"보류")))
		if not offer.assessment.is_empty():
			var known := PackedStringArray()
			for slot: String in offer.observed_slots: known.append(_text("b2.inspect."+slot))
			_board_line(pages,"past_basis","당시 확인한 단서 · "+("없음" if known.is_empty() else ", ".join(known)))
		for fact: Dictionary in offer.facts:
			_board_line(pages,"past_fact",_text("b2.inspect."+str(fact.slot))+" · "+_fact_caption(fact.slot,fact.value))
	for work: Dictionary in history.get("work_records",[]):
		_board_line(pages,"work_"+str(work.event_id),"작업 기록 · "+str(work.kind)+" "+str(work.get("related_item_id","")))
	if int(history.get("omitted",0))>0: _board_line(pages,"older","이전 거래는 전체 장부에서 확인")
	if int(history.get("work_omitted",0))>0: _board_line(pages,"older_work","이전 작업 기록 일부 생략")

func _receipt_items(state: Dictionary, roots: Array) -> String:
	var names := PackedStringArray()
	for id: String in roots:
		var item: Dictionary = state.items.get(id,state.get("tombstones",{}).get(id,{}))
		if item.has("def_id"): names.append(_text("b2.item."+str(item.def_id)))
	return ", ".join(names)

func _inventory(v: Dictionary,s: Dictionary) -> void:
	placement_hint = words("",76,119,640,38,16)
	var grids := ["player_stock","storefront_grid","service_grid","pawn_grid"]
	var titles := ["창고","외부 매대","수탁 보관","담보 보관"]
	for n: int in range(grids.size()):
		var destination: String = grids[n]
		if s.inventories.has(destination):
			var tab := action("tab_"+destination,titles[n],76+n*165,77,152,42,func()->void:
				draft.clear()
				storage = destination
				refresh())
			if destination==storage:
				_paper_face(tab,true)
				tab.text = "▸ "+titles[n]
			tab.set_drag_forwarding(Callable(),func(_at:Vector2,data:Variant)->bool:
				return data is Dictionary and data.get("item")==selected,func(_at:Vector2,_data:Variant)->void:
				storage = destination
				draft.clear()
				refresh())
	var spec: Dictionary = s.inventories[storage]
	var cell := minf(68,630.0/float(spec.width))
	for y: int in range(int(spec.height)):
		for x: int in range(int(spec.width)):
			var target := Vector2i(x,y)
			var button := action("cell_%d_%d"%[x,y],"",76+x*cell,160+y*cell,cell-2,cell-2,func()->void: _place_selection(target))
			button.mouse_entered.connect(func()->void: _hover_cell(target,spec,cell))
			button.mouse_exited.connect(_clear_hover)
			button.set_drag_forwarding(Callable(),func(_at:Vector2,data:Variant)->bool:return data is Dictionary and data.get("item")==selected,func(_at:Vector2,_data:Variant)->void:_place_selection(target))
	for id: String in s.items:
		var item: Dictionary = s.items[id]
		if item.inventory != storage or not item.parent_id.is_empty(): continue
		var dims: Array = session.spatial_dimensions(id)
		var w := int(dims[1] if item.rotated else dims[0])
		var h := int(dims[0] if item.rotated else dims[1])
		var token := action("stock_"+id,"",76+item.x*cell,160+item.y*cell,cell*w-2,cell*h-2,func()->void:
			draft.clear()
			selected = id
			rotated = item.rotated
			refresh())
		if id==selected: _paper_face(token,true)
		token.icon = Art.ITEMS.model_texture(str(item.def_id),"stock",id)
		motion_subjects["stock_"+id] = token
		token.expand_icon = true
		token.tooltip_text = _text("b2.item."+str(item.def_id))
		if token.icon == null: token.text = token.tooltip_text
		token.set_drag_forwarding(func(_at:Vector2)->Variant:
			draft.clear()
			selected = id
			rotated = item.rotated
			drag_origin = token
			token.self_modulate = Color(1,1,1,0.42)
			var preview := TextureRect.new()
			preview.texture = token.icon
			preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			preview.custom_minimum_size = token.size * stage.scale
			preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
			token.set_drag_preview(preview)
			return {"item":id},Callable(),Callable())
	if not s.items.has(selected) or s.items[selected].inventory not in grids or not str(s.items[selected].parent_id).is_empty():
		selected = ""
		draft.clear()
		words("물건을 골라 살펴보세요.",760,211,400,84)
		return
	var item: Dictionary = s.items[selected]
	var history: Dictionary = session.alpha_item_history(selected,last_visit)
	var condition := "기능 관찰 기록 없음"
	for row: Dictionary in history.records:
		var known := false
		for fact: Dictionary in row.get("offer_reference",{}).get("facts",[]):
			if fact.slot in ["condition_detail","function_detail"]:
				condition = "거래 당시 기능 · "+_fact_caption(str(fact.slot),fact.value)
				known = true
				break
		if known: break
	words(condition+"   /   거래 이력 %d건"%(history.records.size()+int(history.omitted)),76,560,642,42,16)
	words(_text("b2.item."+str(item.def_id)),746,152,434,54)
	motion_subjects["work"] = pic(Art.ITEMS.model_texture(str(item.def_id),"stock",selected),760,210,378,99)
	if item.owner_id=="player":
		words(_text("spatial.basis") % [str(item.basis.VKC) if item.basis.VKC!=null else "?",str(item.basis.USD) if item.basis.USD!=null else "?"],746,309,420,38,17)
	var permission := _text("spatial.locked") if not str(item.reservation_id).is_empty() else ("보호품" if item.protected else "")
	words("소유 "+_actor_label(item.owner_id)+"  /  보관 "+_actor_label(item.custodian_id)+"  "+permission,747,350,435,47)
	action("rotate","배치 방향 전환 · "+("90°" if rotated else "0°"),746,406,400,40,func()->void:
		draft.clear()
		rotated = not rotated
		refresh())
	if not draft.is_empty():
		var pending: Dictionary = draft.payload
		if pending.has("x") and pending.has("y") and draft.kind in ["alpha_display","alpha_withdraw_display","spatial_move"]:
			var dims: Array = session.spatial_dimensions(selected)
			var footprint := Vector2i(int(dims[1] if rotated else dims[0]),int(dims[0] if rotated else dims[1]))
			var visible := Rect2i(int(pending.x),int(pending.y),footprint.x,footprint.y).intersection(Rect2i(0,0,int(spec.width),int(spec.height)))
			var ghost := paper(76+visible.position.x*cell,160+visible.position.y*cell,visible.size.x*cell,visible.size.y*cell,Color("#77bc8c88") if draft.result.ok else Color("#d4665488"))
			ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var summary := _work_label(draft.kind)
		var part_id := str(pending.get("child_id",""))
		if s.items.has(part_id): summary += " · "+_text("b2.item."+str(s.items[part_id].def_id))
		words(summary,746,455,405,42)
		_draft_controls(746,506,"confirm_work")
	elif selected in v.displayed_items and storage=="storefront_grid":
		var tag: Dictionary = Alpha.displayed_ask(s,selected)
		words("매대 표시가 · "+("%d %s"%[tag.amount,tag.currency] if not tag.is_empty() else "미설정"),746,461,435,40)
		if v.phase in ["OPEN_IDLE","EVENING_WORK"]:
			var slip := preload("res://scenes/app/spatial_price_slip.tscn").instantiate() as HBoxContainer
			place(slip,746,515,420,48)
			var amount := slip.get_node("Amount") as LineEdit
			var currency := slip.get_node("Currency") as OptionButton
			var apply_button := slip.get_node("Apply") as Button
			amount.placeholder_text = "표시가"
			if tag_draft.get("item") != selected or tag_draft.get("source") != tag:
				tag_draft = {"item":selected,"source":tag.duplicate(),"amount":str(tag.get("amount","")),"currency":str(tag.get("currency","VKC"))}
			amount.text = tag_draft.amount
			amount.text_changed.connect(func(value:String)->void: tag_draft.amount=value)
			currency.add_item("VKC")
			currency.add_item("USD")
			currency.select(1 if tag_draft.currency=="USD" else 0)
			currency.item_selected.connect(func(index:int)->void: tag_draft.currency=currency.get_item_text(index))
			apply_button.text = "가격표 갱신"
			apply_button.pressed.connect(func()->void:
				if amount.text.is_valid_int() and int(amount.text)>0:
					_submit("alpha_reprice_display",{"item_id":selected,"amount":int(amount.text),"currency":currency.get_item_text(currency.selected)}))
	elif v.phase=="EVENING_WORK" and item.inventory=="player_stock":
		var root_id := selected
		var tray := preload("res://src/presentation/b3_work_tray.gd").new()
		place(tray,746,459,420,150)
		tray.populate(root_id,session.composition_options(root_id,"player_stock"),s.items,Art.ITEMS,desk_copy,_text,func(kind:String,payload:Dictionary)->void:
			selected = root_id
			_preview(kind,payload))
	if draft.is_empty() and v.phase=="EVENING_WORK" and item.status=="custody_service":
		for job: Dictionary in v.services.entries:
			if job.get("item_id")==selected and job.can_repair:
				action("b2_service_repair",_text("b2.service.repair"),746,459,420,52,func()->void:
					_preview("alpha_service_repair",{"job_id":job.job_id,"item_id":selected}))
	action("item_history","물품 이력",746,611,212,40,func()->void:open_drawer("item_history"))
	if not _message.is_empty(): words(_message,74,608,650,46)

func _placement(target: Vector2i) -> Dictionary:
	var items: Dictionary = session.snapshot().items
	if not items.has(selected): return {}
	var origin: String = items[selected].inventory
	var payload := {"item_id":selected,"x":target.x,"y":target.y,"rotated":rotated}
	var kind := "spatial_move"
	if origin=="player_stock" and storage=="storefront_grid":
		kind = "alpha_display"
	elif origin=="storefront_grid" and storage=="player_stock":
		kind = "alpha_withdraw_display"
	else:
		payload.actor = "player"
		payload.inventory = storage
	return {"kind":kind,"payload":payload,"result":session.spatial_action_preview(kind,payload)}

func _clear_hover() -> void:
	if is_instance_valid(placement_hint): placement_hint.text = ""
	if is_instance_valid(hover_ghost):
		hover_ghost.hide()
		hover_ghost.queue_free()
	hover_ghost = null

func _hover_cell(target: Vector2i,spec: Dictionary,cell: float) -> void:
	_clear_hover()
	if selected.is_empty() or not draft.is_empty(): return
	var plan := _placement(target)
	if plan.is_empty(): return
	var dims: Array = session.spatial_dimensions(selected)
	var footprint := Vector2i(int(dims[1] if rotated else dims[0]),int(dims[0] if rotated else dims[1]))
	if is_instance_valid(placement_hint):
		var reason := "spatial.error."+str(plan.result.get("error",""))
		placement_hint.text = ("배치 가능" if plan.result.ok else _text(reason if _strings.has(reason) else "spatial.error.permission"))+" · %d×%d"%[footprint.x,footprint.y]
	var bounds := Rect2i(target,footprint).intersection(Rect2i(0,0,int(spec.width),int(spec.height)))
	hover_ghost = paper(76+target.x*cell,160+target.y*cell,bounds.size.x*cell,bounds.size.y*cell,Color("#77bc8c66") if plan.result.ok else Color("#d4665466"))
	hover_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _place_selection(target: Vector2i) -> void:
	var plan := _placement(target)
	if plan.is_empty(): return
	draft = plan
	refresh()

func _work_label(kind: String) -> String:
	match kind:
		"spatial_restore_item","alpha_service_repair": return _text("spatial.work_restore")
		"spatial_attach": return _text("spatial.work_attach")
		"spatial_detach": return _text("spatial.work_detach")
		_: return _text("spatial.place")

func _discard_preview() -> void:
	if draft.get("kind","") in ["spatial_move","alpha_display","alpha_withdraw_display"]:
		var item: Dictionary = session.snapshot().items.get(selected,{})
		if not item.is_empty():
			storage = str(item.inventory)
			rotated = bool(item.rotated)
	draft.clear()

func _cancel_local() -> bool:
	if not draft.is_empty(): _discard_preview()
	elif drawer=="phone" and not phone_terms.is_empty(): phone_terms = ""
	elif drawer.is_empty() and zoom and not chosen_tool.is_empty(): chosen_tool = ""
	elif drawer=="item_history": drawer = "stock"
	elif not drawer.is_empty():
		if drawer=="notes": previous_book_scroll = drawer_scroll
		drawer = ""
	elif papers_open: papers_open = false
	elif zoom: zoom = false
	else: return false
	return true

func _unhandled_input(event: InputEvent) -> void:
	if _intro or _blocked or _leaving_title: return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
		if _cancel_local():
			get_viewport().set_input_as_handled()
			refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if _leaving_title or _intro or _blocked or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		if not _cancel_local(): return
	elif event.keycode == KEY_R and drawer=="stock" and not selected.is_empty():
		rotated = not rotated
		draft.clear()
	else: return
	get_viewport().set_input_as_handled()
	refresh()

func _return_to_title() -> void:
	if _leaving_title:
		return
	_leaving_title = true
	sound.remember_score_position()
	# Ogg stream playback is retired by the audio mixer asynchronously.
	# Stop while the scene is alive, then allow one bounded drain interval
	# before changing scenes (Godot audio teardown / CI leak regression).
	sound.shutdown_audio()
	await get_tree().create_timer(0.25).timeout
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/app/main_menu.tscn")

func _slide(node: Control, offset: Vector2, duration: float) -> void:
	if reduce_motion or not is_instance_valid(node): return
	var previous: Tween
	if node.has_meta("shop_slide"): previous = node.get_meta("shop_slide") as Tween
	var end: Vector2 = node.position
	if previous and previous.is_valid():
		end = node.get_meta("shop_slide_end")
		previous.kill()
	node.position = end + offset
	var slide := node.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	node.set_meta("shop_slide",slide)
	node.set_meta("shop_slide_end",end)
	slide.tween_property(node,"position",end,duration)

func _committed_motion(kind: String,payload: Dictionary,previous_actor: Texture2D,previous_item: Texture2D) -> void:
	if reduce_motion: return
	match kind:
		"alpha_next_customer": _slide(motion_subjects.get("actor"),Vector2(-42,0),0.42)
		"alpha_ack_entry","alpha_inspect": _slide(motion_subjects.get("item"),Vector2(0,-9),0.18)
		"alpha_card_toggle": _slide(motion_subjects.get("card_"+str(payload.get("slot",""))),Vector2(0,8),0.16)
		"alpha_price_offer","alpha_claim_challenge": _slide(motion_subjects.get("actor"),Vector2(4,0),0.18)
		"alpha_ack_exit":
			if previous_actor:
				var departing := pic(previous_actor,525,70,260,395)
				# Keep the departing portrait behind the counter.
				departing.reparent(scenery,false)
				scenery.move_child(departing,mini(2,scenery.get_child_count()-1))
				var leave := departing.create_tween().set_parallel(true)
				leave.tween_property(departing,"position:x",472,0.38)
				leave.tween_property(departing,"modulate:a",0.0,0.38)
				leave.chain().tween_callback(departing.queue_free)
		"alpha_trade":
			if previous_item:
				var handed := pic(previous_item,492,350,290,124)
				var transfer := handed.create_tween().set_parallel(true)
				transfer.tween_property(handed,"position:y",396,0.28)
				transfer.tween_property(handed,"modulate:a",0.0,0.28)
				transfer.chain().tween_callback(handed.queue_free)
			var receipt := words("거래 체결 · %s %s"%[payload.get("amount",""),payload.get("currency","")],806,492,320,42)
			_slide(receipt,Vector2(0,-12),0.28)
			var fade := receipt.create_tween()
			fade.tween_property(receipt,"modulate:a",0.0,0.22).set_delay(0.8)
			fade.tween_callback(receipt.queue_free)
		"spatial_attach","spatial_detach","alpha_service_repair","spatial_restore_item": _slide(motion_subjects.get("work"),Vector2(12,0),0.35)
		"spatial_move","alpha_display","alpha_withdraw_display": _slide(motion_subjects.get("stock_"+selected),Vector2(0,-6),0.14)
		"alpha_open","alpha_settle","alpha_next_day","alpha_prepare_day":
			var shade := paper(0,0,1280,720,Color("#26211e65"))
			shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var light := shade.create_tween()
			light.tween_property(shade,"modulate:a",0.0,0.64)
			light.tween_callback(shade.queue_free)

func _submit(kind: String,payload: Dictionary={}) -> void:
	if _blocked or _leaving_title or session == null: return
	var portrait := motion_subjects.get("actor") as TextureRect
	var item := motion_subjects.get("item") as TextureRect
	var previous_actor := portrait.texture if portrait else null
	var previous_item := item.texture if item else null
	var before: int = session.snapshot().revision
	super._submit(kind,payload)
	var after: int = session.snapshot().revision
	if after != before+1: return
	if not draft.is_empty():
		draft.clear()
		refresh()
	if _blocked:
		pending_save = true
		refresh()
		return
	var event: Dictionary = session.alpha_presentation_event(after,kind,payload)
	if event.is_empty() or str(event.event_id)==last_motion_event: return
	last_motion_event = str(event.event_id)
	mounting = feedback
	_committed_motion(kind,payload,previous_actor,previous_item)
	mounting = interaction
	var cues := {"alpha_open":"next_visit","alpha_next_customer":"next_visit","alpha_finish_customer":"decline_visit","alpha_inspect":"observe","alpha_price_offer":"subject_price_offer","alpha_trade":"trade","alpha_settle":"day_one_close","alpha_display":"move","week_pledge":"accept_rad1_contract","alpha_salvage_dispatch":"accept_rad1_contract"}
	sound.committed(str(cues.get(kind,kind.trim_prefix("spatial_"))),before,after,not _blocked)
	sound.set_phase("workshop" if session.alpha_view().phase=="EVENING_WORK" else "shop")

func _retry_save() -> void:
	if not pending_save or session==null: return
	var saved: Dictionary = _repo.save_session(session,_slot())
	if saved.get("ok",false):
		pending_save = false
		_blocked = false
		_message = ""
		sound.prime(int(session.snapshot().revision))
	refresh()
