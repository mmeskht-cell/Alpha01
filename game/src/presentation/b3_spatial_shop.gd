extends "res://src/presentation/alpha_b1_host.gd"
## Inherit only the B3 session/save transport and contextual document actions.
const DeskProp = preload("res://src/presentation/b3_desk_prop.gd")
const COPY_PATH = "res://data/alpha_b3/w19_desk_ko.json"
var desk_copy: Dictionary
var phone_contact := ""
var phone_view: Control
var dock_slots: Array = []
var judgment_leaf := false
var book_choice := false
var index_group := -1
var index_page := 0
const Art = preload("res://src/presentation/native_v23_art.gd")
const R2Art = preload("res://src/presentation/b3_r2_preview_art.gd")
@export var r2_review_mode: bool = false
var r2_layers: Dictionary = {}
var r2_phone_art: Texture2D
var r2_room_active: bool = false
const R2Controls = preload("res://src/presentation/b3_r2_counter_controls.gd")
const R2Book = preload("res://src/presentation/b3_r2_reference_desk.gd")
const AttachmentPocket = preload("res://src/presentation/b3_attachment_pocket.gd")
var r2_controls := R2Controls.new()
var workspaces := R2Controls.new()
const ProductDocuments = preload("res://src/presentation/b3_product_documents.gd")
const PhoneDesk = preload("res://src/presentation/b3_phone_desk.gd")
var workspace_offsets: Dictionary = {}
var inventory_drop: Dictionary = {}
var inventory_drag_preview: Control
var hover_ticket := ""
const WorkTray = preload("res://src/presentation/b3_work_tray.gd")
const WeekPawn = preload("res://src/domain/alpha_b3_week_pawn.gd")
var r2_book: R2Book
var r2_book_content_key := ""
var r2_drag_source: Button
const KnownEstimate = preload("res://src/domain/known_estimate.gd")
const RatioQuote = preload("res://src/presentation/b3_ratio_offer.gd")
const RatioControl = preload("res://src/presentation/b3_ratio_offer_control.gd")
const CounterDialogue = preload("res://src/presentation/b3_counter_dialogue.gd")
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
const SpecimenSurface = preload("res://src/presentation/b3_specimen_surface.gd")
var counter_item: TextureRect
var standing_actor: TextureRect
var rail: Control
var rail_key := ""
var rail_used := false
var offer_editor: RatioControl
var editor_used := false
var offer_basis: Dictionary = {}
var offer_ratio: int = 1000
var provisional_amount: int = 1
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
var appraisal_context := ""
var lens_open := false
var surface_slot := ""
var reference_material := "metal"
var reference_variant := 0
var book_tab := 0
var previous_book_scroll := 0
var layout_after_drag := false
var pending_counter_drop: Dictionary = {}
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
	if r2_review_mode:
		r2_layers = R2Art.load_layers()
		var phone_path := "res://assets/art/shop_r2_candidate/phone.png"
		if not r2_layers.is_empty() and ResourceLoader.exists(phone_path,"Texture2D"):
			var prop := load(phone_path) as Texture2D
			if prop: r2_phone_art = prop
	desk_copy = JSON.parse_string(FileAccess.get_file_as_string(COPY_PATH))
	if save_directory_override.is_empty():
		save_directory_override = "user://zt_rebuild/r2_art_review" if r2_review_mode else "user://zt_rebuild/spatial_week"
	var continuing := FileAccess.file_exists(save_directory_override.path_join(_slot()+".a.json")) or FileAccess.file_exists(save_directory_override.path_join(_slot()+".b.json"))
	captions = JSON.parse_string(FileAccess.get_file_as_string(INTRO_FILE))
	resized.connect(_viewport_changed)
	super._ready()
	if theme!=null: theme.merge_with(preload("res://src/presentation/b3_shop_theme.tres"))
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
	if what==NOTIFICATION_DRAG_END and not inventory_drop.is_empty():
		_flush_inventory_drop.call_deferred()
	if what==NOTIFICATION_DRAG_END and r2_review_mode and is_instance_valid(drag_origin):
		inventory_drag_preview = null
		if not get_viewport().gui_is_drag_successful() and session!=null:
			var item: Dictionary = session.snapshot().items.get(selected,{})
			if not item.is_empty() and rotated!=bool(item.rotated):
				rotated = bool(item.rotated)
				refresh.call_deferred()
			_clear_hover()
	if what==NOTIFICATION_DRAG_END and is_instance_valid(r2_drag_source):
		r2_drag_source.self_modulate = Color.WHITE
		r2_drag_source = null
	if what==NOTIFICATION_DRAG_END and not pending_counter_drop.is_empty():
		_flush_counter_drop.call_deferred()
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
	if r2_review_mode and not _intro:
		return _workspace_action(kind,caption,Rect2(x,y,w,44),func()->void:_submit(kind,payload))
	return action(kind,caption,x,y,w,42,func()->void: _submit(kind,payload))

func open_drawer(which: String) -> void:
	if drawer=="stock": _clear_hover()
	if drawer=="notes": previous_book_scroll = drawer_scroll
	elif r2_review_mode: workspace_offsets[drawer] = drawer_scroll
	drawer_scroll = previous_book_scroll if which=="notes" else int(workspace_offsets.get(which,0))
	draft.clear()
	drawer = which
	if which=="notes" and not book_choice and lens_open and not surface_slot.is_empty(): book_tab = 1
	hint = ""
	refresh()
	if which=="notes" and not r2_room_active: _slide(motion_subjects.get("book"),Vector2(14,0),0.18)

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
	var actor: String = str(session.alpha_view().active.get("actor_id","")) if npc else ""
	var use_r2: bool = r2_review_mode and not r2_layers.is_empty() and not _intro and index in [1,5]
	var key := str([_intro,index,last_visit,npc,reduce_motion,use_r2])
	r2_room_active = use_r2
	if key == room_key:
		if is_instance_valid(standing_actor): motion_subjects["actor"] = standing_actor
		return
	room_key = key
	_clear_layer(scenery)
	standing_actor = null
	mounting = scenery
	if use_r2:
		var rear := pic(r2_layers.rear,0,0,1280,720,true)
		rear.name = "r2_rear"
		if index==5: rear.modulate = Color("#8e9ab3")
	else:
		pic(Art.WINDOWS[index],0,0,1280,720,true)
		pic(Art.ROOM,0,0,1280,720,true)
	if npc:
		var portrait: TextureRect
		if use_r2 and actor=="G01":
			portrait = pic(r2_layers.visitor,470,112,340,314,true)
			portrait.name = "r2_visitor"
		else:
			portrait = pic(Art.scene_texture("customer.opening" if actor=="G01" else "customer.watch" if actor=="G04" else "customer.neutral"),525,70,260,395)
		standing_actor = portrait
		motion_subjects["actor"] = portrait
		if not reduce_motion:
			portrait.pivot_offset = Vector2(portrait.size.x*0.5,portrait.size.y)
			var breath := portrait.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
			breath.tween_property(portrait,"scale:y",1.004,1.65)
			breath.tween_property(portrait,"scale:y",1.0,1.65)
	if use_r2:
		var counter := pic(r2_layers.counter,0,0,1280,720,true)
		counter.name = "r2_counter"
		if index==5: counter.modulate = Color("#d2bb9d")
	else:
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
	r2_controls.begin()
	workspaces.begin()
	_rebuild_stage()
	r2_controls.finish()
	workspaces.finish()
	if is_instance_valid(rail): rail.visible = rail_used
	if is_instance_valid(offer_editor): offer_editor.visible = editor_used
	if context!=appraisal_context or stock_id!=selected or field!="Amount": return
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
		if child != offer_editor and child != rail and child != counter_item and not child.has_meta("r2_desk_control"):
			interaction.remove_child(child)
			child.queue_free()
	if is_instance_valid(counter_item): counter_item.hide()
	mounting = interaction
	var same_shop := drawer in ["","notes","phone"] or (r2_review_mode and drawer in ["ledger","news","stock","item_history"])
	scenery.visible = not _blocked and session != null and ((_intro and _intro_page>=3) or (not _intro and same_shop))
	scenery.process_mode = Node.PROCESS_MODE_INHERIT if scenery.visible else Node.PROCESS_MODE_DISABLED
	if _blocked or reduce_motion or not drawer.is_empty(): _clear_layer(feedback)
	_scale_stage()
	if _blocked or session == null:
		var message := "현재 거래는 처리됐지만 저장에 실패했습니다. 아래에서 저장만 다시 시도할 수 있습니다." if r2_review_mode and pending_save else _message
		words(message,70,320,1120,90)
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
		r2_controls.scope(context)
		r2_book_content_key = ""
		judgment_leaf = false
		appraisal_context = context
		offer_basis.clear()
		offer_ratio = 1000
		provisional_amount = 1
		dock_slots.clear()
		book_choice = false
		index_group = -1
		index_page = 0
		lens_open = false
		surface_slot = ""
		previous_book_scroll = 0
		book_tab = 0
		reference_material = "metal"
		reference_variant = 0
		if drawer == "notes": drawer = ""
		if visit == last_visit:
			private_model = ""
			reference_model = ""
			chosen_tool = ""
			hand_page = 0
			reverse = false
			zoom = false
	if visit != last_visit:
		draft.clear()
		papers_open = false
		reference_model = ""
		private_model = ""
		tool_page = 0
		last_visit = visit
		zoom = false
		reverse = false
		chosen_tool = ""
		hand_page = 0
		hint = ""
	_room(5 if v.phase == "EVENING_WORK" else 1,not v.active.is_empty())
	if r2_review_mode and r2_layers.is_empty(): words("R2 검토 자산 누락 · 기존 화면",675,12,465,38,16)
	var cash: Dictionary = session.snapshot().wallets.player
	if r2_review_mode:
		_shift_heading(v,cash)
	else:
		words(_text("spatial.cash") % [v.day,cash.VKC,cash.USD],30,12,660,38)
	action("preferences","설정",1160,16,90,36,func()->void: open_drawer("settings"))
	if drawer.is_empty() and not zoom:
		var due: PackedStringArray = []
		for contract: Dictionary in v.contracts.values():
			if contract.get("status")=="accepted" and int(contract.due_day)<=int(v.day)+1: due.append("D"+str(contract.due_day))
		if v.phase=="OPEN_IDLE": words("남은 방문 "+str(v.remaining),720,12,205,38,17)
		if not due.is_empty(): words("계약 기한 "+", ".join(due),931,12,223,38,17)
	if drawer=="notes" and (v.appraisal.is_empty() or v.phase!="CUSTOMER_ACTIVE"): drawer = ""
	if drawer=="phone" and v.phase!="EVENING_WORK": drawer = ""
	if not drawer.is_empty():
		_drawer(v)
		return
	if not _message.is_empty() or not hint.is_empty():
		if r2_room_active and v.phase=="CUSTOMER_ACTIVE" and not v.appraisal.is_empty():
			words(_visible_notice(),32,687,736,32,16)
		else:
			words(_visible_notice(),28,660,940,48)
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
				if r2_room_active:
					var docket := paper(803,438,426,113,Color("#d6c9ac"))
					docket.mouse_filter = Control.MOUSE_FILTER_IGNORE
					var stamp := words("거래 영수증 · %d일차"%v.day,820,449,391,39,17)
					var amount := words("%d VKC  /  %d USD"%[receipt.amounts.VKC,receipt.amounts.USD],820,488,391,45,24)
					for field: Label in [stamp,amount]:
						field.remove_theme_constant_override("outline_size")
						field.add_theme_color_override("font_color",Color("#30271e"))
				else:
					words(_text("spatial.received")+" · %d VKC / %d USD"%[receipt.amounts.VKC,receipt.amounts.USD],405,466,546,46)
		"CUSTOMER_ACTIVE": _counter(v)
		"CLOSE_SETTLE": command_button("alpha_settle","장부 마감 · 저녁으로",496,400,290)
		"EVENING_WORK": command_button("alpha_next_day","하루 마치기",995,560,225)
		"NEXT_DAY": command_button("alpha_prepare_day","다음 날 아침",520,435,240)
		"COMPLETE": words("첫 주 영업 종료",480,380,420,80,36)
	if v.phase in ["CLOSE_SETTLE","EVENING_WORK"] and v.has("local_trade_flow"):
		if r2_review_mode:
			_day_statement(v)
		else:
			var flow: Dictionary = v.local_trade_flow
			words(desk_copy.close_flow%[flow.bought,flow.sold,flow.VKC,flow.USD],480,180,665,58,18)
	if v.phase == "CUSTOMER_ENTER":
		var greet := action("greet_visitor","",535,92,225,242,func()->void:_submit("alpha_ack_entry"))
		greet.flat = true
		greet.tooltip_text = _actor_label(v.active.actor_id)
		if visit=="visit_g01":
			var radio := Art.ITEMS.model_texture("portable_radio","inspection")
			if r2_room_active:
				if not is_instance_valid(counter_item):
					counter_item = SpecimenSurface.new()
					interaction.add_child(counter_item)
				counter_item.call("present",radio,Rect2(498,365,248,188))
				counter_item.mouse_filter = Control.MOUSE_FILTER_IGNORE
				motion_subjects["item"] = counter_item
				_counter_caption(_actor_label(v.active.actor_id),str(captions.g01))
			else:
				motion_subjects["item"] = pic(radio,382,418,355,132)
				words(captions.g01,774,244,420,64)
	if v.phase != "CUSTOMER_ACTIVE" or not zoom:
		action("stockroom","재고 서랍",32,75,154,44,func()->void: open_drawer("stock"))
		if r2_room_active and v.phase in ["DAY_PREP","OPEN_IDLE","EVENING_WORK","CLOSE_SETTLE"]:
			_desk_object("ledger","book","영업 장부",Rect2(36,405,154,106),func()->void:open_drawer("ledger"))
		else:
			action("ledger","장부 · 계약",32,126,164,44,func()->void: open_drawer("ledger"))
	if v.phase in ["DAY_PREP","OPEN_IDLE","EVENING_WORK"]:
		action("news",_text("spatial.news"),548,597,150,46,func()->void: open_drawer("news"))
	if v.phase == "EVENING_WORK":
		_desk_object("phone","phone","전화기",Rect2(942,403,178,149) if r2_room_active else Rect2(944,336,177,148),func()->void:open_drawer("phone"))
		_desk_object("address_book","book","연락처 수첩",Rect2(741,417,170,124) if r2_room_active else Rect2(721,350,178,132),func()->void:open_drawer("phone"))

func _visible_notice() -> String:
	if _message.is_empty(): return hint
	if not r2_review_mode or not _message.begins_with("입력 거절: "): return _message
	var reason := _message.trim_prefix("입력 거절: ")
	var key := "spatial.error."+reason
	if _strings.has(key): return _text(key)
	var guidance := {
		"alpha_offer_duplicate":"이미 같은 조건을 제안했습니다. 비율이나 제시할 근거를 바꾸세요.",
		"alpha_offer_shape_or_limit":"이 방문에서는 더 제안할 수 없습니다. 응대를 마치세요.",
		"week_pawn_funds":"담보 거래에 필요한 현금이 부족합니다.",
		"week_pawn_space":"담보를 보관할 자리가 부족합니다."}
	return str(guidance.get(reason,"지금 이 조건으로는 처리할 수 없습니다. 물품과 전표를 확인하세요."))

func _shift_heading(v: Dictionary,wallet: Dictionary) -> void:
	var phases := {"DAY_PREP":"개점 준비","OPEN_IDLE":"영업 중","CUSTOMER_ENTER":"손님 맞이","CUSTOMER_ACTIVE":"응대 중","CUSTOMER_EXIT":"배웅","CLOSE_SETTLE":"마감","EVENING_WORK":"저녁 작업","NEXT_DAY":"다음 날 준비","COMPLETE":"첫 주 마감"}
	var label := workspaces.mount(interaction,"r2_shift_heading",Rect2(30,9,675,45),func()->Control:
		var heading := Label.new()
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heading.add_theme_constant_override("outline_size",4)
		return heading) as Label
	label.text = "%d일차 · %s   |   %d VKC / %d USD"%[v.day,phases.get(v.phase,""),wallet.VKC,wallet.USD]
	label.add_theme_font_size_override("font_size",roundi(19*reading_scale/100.0))

func _day_statement(v: Dictionary) -> void:
	var state: Dictionary = session.snapshot()
	var inflow := {"VKC":0,"USD":0}
	var outflow := {"VKC":0,"USD":0}
	var counted: Dictionary = {}
	for entry: Dictionary in state.ledger:
		if int(entry.game_minutes/1440)+1!=int(v.day): continue
		if entry.to=="player" or entry.from=="player":
			var row := inflow if entry.to=="player" else outflow
			for currency: String in ["VKC","USD"]: row[currency] += int(entry.amounts[currency])
			counted[entry.event_id] = true
	for order: Dictionary in state.alpha_shop.get("outbound",{}).values():
		for payment: Dictionary in order.payments:
			if payment.day!=v.day or counted.has(payment.action_id): continue
			var row := outflow if payment.from=="player" else inflow
			row[payment.currency] += int(payment.amount)
	for transfer: Dictionary in state.alpha_shop.get("fx",{}).get("settlements",{}).values():
		if transfer.day!=v.day or counted.has(transfer.event_id): continue
		outflow[transfer.give_currency] += int(transfer.give_amount)
		inflow[transfer.receive_currency] += int(transfer.receive_amount)
	for event: Dictionary in state.alpha_shop.week_pawn.events:
		if event.day!=v.day or not event.has("amount") or counted.has(event.action): continue
		var row := outflow if event.payer=="player" else inflow
		for currency: String in ["VKC","USD"]: row[currency] += int(event.amount[currency])
	var due := PackedStringArray()
	for offer: Dictionary in v.contracts.values():
		if offer.status=="reserved": due.append("계약 %d일차"%offer.due_day)
	for job: Dictionary in v.services.entries:
		if job.status in ["accepted","custody","overdue_custody","repaired"]:
			due.append("수탁 %d일차"%job.due_day)
	var pawn: Dictionary = state.alpha_shop.week_pawn
	if pawn.status=="pledged": due.append("담보 %d일차"%pawn.due)
	var page := paper(420,145,445,213,Color("#45382ceb"))
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words("오늘의 장부",438,153,406,40,20)
	words("거래·이체 유입   %d VKC / %d USD\n거래·이체 유출   %d VKC / %d USD"%[inflow.VKC,inflow.USD,outflow.VKC,outflow.USD],438,202,405,81,17)
	words("미결 기한 · "+("없음" if due.is_empty() else ", ".join(due)),438,292,405,61,16)

func _counter(v: Dictionary) -> void:
	var a: Dictionary = v.appraisal
	var actor: String = _actor_label(str(v.active.actor_id))
	_counter_caption(actor,_counter_speech(v))
	if a.get("composite_access","")=="not_requested":
		action("f3_consent","내부 확인 요청",32,310,164,40,func()->void:_submit("alpha_composite_consent"))
	elif a.get("composite_access","") in ["granted","denied"]:
		words("내부 확인 허용" if a.composite_access=="granted" else "내부 확인 거부",32,310,170,40,16)
	if not r2_room_active and not a.is_empty() and not a.offers.is_empty():
		var latest: Dictionary = a.offers.back()
		words(_text("spatial.terms")%[latest.amount,latest.currency]+" · "+("수락" if latest.response=="accepted" else "거절"),799,142,410,40,17)
	if v.active.id == "alpha_marcus_intro":
		var sheet := _terms_sheet("계약 전표")
		_add_contract_actions(sheet,v)
		_finish_terms_sheet(sheet)
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

	if zoom and drawer.is_empty():
		_finish_counter(v)
	if not zoom:
		if v.can_exchange:
			var contact := command_button("alpha_exchange_contact","연락처 교환",42,235,175,{"actor_id":v.active.actor_id,"accepted":true})
			_paper_face(contact)
		elif v.contacts.any(func(record:Dictionary)->bool:return record.actor_id==v.active.actor_id):
			words(_actor_label(str(v.active.actor_id))+" · 연락처 수첩",40,233,240,48,16)
		if v.active.id=="watch_a":
			if r2_room_active:
				_pawn_ticket(session.snapshot())
			else:
				command_button("week_pledge","시계 전당 · 40 VKC",42,280,216)
		if v.active.id != "alpha_marcus_intro" or not v.contracts.get("rad1_first",{}).get("can_accept",false):
			_finish_counter(v)

func _pawn_ticket(state: Dictionary) -> void:
	var pawn: Dictionary = state.alpha_shop.week_pawn
	if pawn.status!="available": return
	var sheet := paper(34,274,330,126,Color("#4f4235ed"))
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words("담보 전표   /   %d VKC"%WeekPawn.PRINCIPAL.VKC,46,280,300,39,17)
	words("상환 %d VKC · 기한 %d일차"%[WeekPawn.REPAYMENT.VKC,pawn.due],46,316,302,34,16)
	var pledge := _workspace_action("week_pledge","시계 담보 접수",Rect2(46,350,302,44),func()->void:_submit("week_pledge"))
	_paper_face(pledge)

func _finish_counter(v: Dictionary) -> void:
	if r2_room_active and not v.appraisal.is_empty():
		var finish := _r2_action("alpha_finish_customer","응대 마치기",Rect2(1036,208,186,44),func()->void:
			_submit("alpha_finish_customer"))
		finish.flat = true
		return
	action("alpha_finish_customer","응대 마치기",1020,246,186,44,func()->void:_submit("alpha_finish_customer"))

func _counter_papers(v: Dictionary) -> void:
	var envelope := _workspace_action("visitor_papers","의뢰서 · 견적 보기",Rect2(42,182,235,45),func()->void:
		papers_open = not papers_open
		refresh())
	_paper_face(envelope,papers_open)
	if papers_open:
		var terms := _terms_sheet("접수 전표")
		_add_contract_actions(terms,v)
		_add_b2_commission_actions(terms,v)
		_add_b2_service_actions(terms,v)
		_add_b3_fx_actions(terms,v)
		_finish_terms_sheet(terms)

func _terms_sheet(title: String) -> VBoxContainer:
	if r2_room_active: return _counter_ticket(title)
	paper(790,294,446,218,Color("#534a3c"))
	paper(798,298,3,208,Color("#b49a71"))
	words(title,814,302,390,36,20)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	place(scroll,814,344,400,155)
	var terms := VBoxContainer.new()
	terms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(terms)
	return terms

func _counter_ticket(title: String) -> VBoxContainer:
	var cover := paper(790,268,448,232,Color("#504233"))
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words(title,806,274,412,38,19)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	place(scroll,804,316,419,176)
	var terms := VBoxContainer.new()
	terms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(terms)
	terms.set_meta("counter_ticket",true)
	return terms

func _finish_terms_sheet(terms: VBoxContainer) -> void:
	if terms.has_meta("counter_ticket"):
		var buttons := terms.find_children("*","Button",false,false)
		if buttons.size() in [1,2]:
			var footer := HBoxContainer.new()
			place(footer,804,445,419,47)
			var body := terms.get_parent() as ScrollContainer
			body.size.y = 123
			for button: Button in buttons:
				button.reparent(footer)
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				button.custom_minimum_size = Vector2(44,44)
				button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_paper_face(button)
			return
	var actions := HFlowContainer.new()
	terms.add_child(actions)
	for child in terms.get_children():
		if child is Button:
			child.custom_minimum_size = Vector2(132,44)
			child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			child.reparent(actions)
			_paper_face(child)

func _preview(kind: String,payload: Dictionary) -> void:
	var result: Dictionary = session.spatial_action_preview(kind,payload)
	draft = {"kind":kind,"payload":payload.duplicate(true),"result":result}
	refresh()

func _draft_controls(x: float,y: float,id: String) -> void:
	if draft.is_empty(): return
	var result: Dictionary = draft.result
	if result.ok:
		words(_text("spatial.preview_cash")%[result.VKC,result.USD],x,y,404,36,17)
		var button := action(id,"영구 폐기 확정" if draft.kind=="spatial_discard" else _text("spatial.confirm"),x,y+39,168,42,func()->void:
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

func _r2_action(id: String, caption: String, rect: Rect2, callback: Callable) -> Button:
	var button := r2_controls.button(interaction,id,rect,caption,callback)
	button.add_theme_font_size_override("font_size",roundi(16.0*reading_scale/100.0))
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return button

func _desk_action(id: String, caption: String, rect: Rect2, callback: Callable) -> Button:
	if r2_room_active: return _r2_action(id,caption,rect,callback)
	return action(id,caption,rect.position.x,rect.position.y,rect.size.x,rect.size.y,callback)

func _r2_object_image(key: String) -> TextureRect:
	var image := TextureRect.new()
	image.name = "r2_"+key
	image.texture = r2_phone_art if key=="phone" else r2_layers[key]
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

func _r2_hand_visual(slot: String, extent: Vector2) -> Control:
	var held: Control
	if slot in SurfaceVisuals.SLOTS:
		held = _r2_object_image("lens")
	else:
		var prop := DeskProp.new()
		prop.kind = slot
		held = prop
	held.size = extent
	held.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return held

func _desk_object(id: String,kind: String,caption: String,rect: Rect2,callback: Callable) -> Button:
	var button := _desk_action(id,"",rect,callback) if (id=="notes" or id.begins_with("tool_")) else action(id,"",rect.position.x,rect.position.y,rect.size.x,rect.size.y,callback)
	button.flat = true
	button.tooltip_text = caption
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var art_key := ""
	if r2_room_active and id in ["notes","ledger","phone_ledger","address_book"]: art_key = "book_closed"
	elif r2_room_active and id=="phone" and r2_phone_art!=null: art_key = "phone"
	elif r2_room_active and id.begins_with("tool_") and kind in SurfaceVisuals.SLOTS: art_key = "lens"
	var existing := button.get_node_or_null("DeskVisual") as Control
	if existing:
		existing.position.y = -5 if kind==chosen_tool else 0
		return button
	var prop: Control
	if not art_key.is_empty():
		var image := _r2_object_image(art_key)
		if art_key=="lens" and kind!="wear_detail": image.name = "r2_lens_"+kind
		var holder := Control.new()
		holder.name = "DeskVisual"
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(holder)
		holder.add_child(image)
		image.size = Vector2(rect.size.x,rect.size.y-17)
		prop = holder
	else:
		prop = _prop(button,kind,Rect2(0,0,rect.size.x,rect.size.y-18))
		prop.name = "DeskVisual"
		prop.set("lifted",kind==chosen_tool)
	if r2_room_active and kind==chosen_tool: prop.position.y = -5
	var label := Label.new()
	label.text = caption
	if r2_room_active: label.add_theme_constant_override("outline_size",3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(0,rect.size.y-(17 if r2_room_active else 25))
	label.size = Vector2(rect.size.x,25)
	if r2_room_active:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	var texture: Texture2D = Art.ITEMS.model_texture(str(a.def_id),"inspection",id,reverse and zoom)
	if not r2_room_active: _tray(52,475,246,38)
	
	var surface_slots: Array = SurfaceVisuals.observation_slots(a.cards)
	if chosen_tool in surface_slots and surface_slot.is_empty(): surface_slot = chosen_tool
	# Preserve the selected, not-yet-observed slot until the inspect command commits.
	if surface_slot not in surface_slots and (surface_slot not in SurfaceVisuals.SLOTS or surface_slot!=chosen_tool):
		surface_slot = str(surface_slots[0]) if not surface_slots.is_empty() else ""
	var sample: Dictionary = SurfaceVisuals.observed(a.cards,surface_slot,int(a.surface_seed)) if lens_open and not reverse else {}
	var surface_texture: Texture2D = SurfaceVisuals.texture_for(sample)
	if not is_instance_valid(counter_item):
		counter_item = SpecimenSurface.new()
		interaction.add_child(counter_item)
	var item_area := Rect2(470,385,314,167) if r2_room_active else Rect2(324,390,460,166)
	if r2_room_active and str(a.item_id)=="R001": item_area = Rect2(498,365,248,188)
	counter_item.call("present",texture,item_area)
	interaction.move_child(counter_item,-1)
	var specimen := counter_item
	var shadow_rect := Rect2(specimen.position.x+8,specimen.position.y+specimen.size.y-4,maxf(1,specimen.size.x-16),9)
	if r2_room_active:
		r2_controls.mount(interaction,"r2_contact_shadow",shadow_rect,_make_r2_contact_shadow)
	else:
		paper(shadow_rect.position.x,shadow_rect.position.y,shadow_rect.size.x,7,Color("#28251fb8")).mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction.move_child(specimen,-1)
	if not zoom or (r2_room_active and chosen_tool.is_empty()):
		var focus_item := _desk_action("specimen","",Rect2(specimen.position,specimen.size),func()->void:
			zoom = true
			refresh())
		focus_item.set_drag_forwarding(Callable(),func(at:Vector2,data:Variant)->bool:
			return _tool_drop_allowed(at/focus_item.size,data,v,a),func(at:Vector2,data:Variant)->void:
			if _tool_drop_allowed(at/focus_item.size,data,v,a): _queue_counter_drop("inspect",str(data.tool),v,a))
		focus_item.flat = true
		focus_item.tooltip_text = "물품 살펴보기"
		focus_item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var lens_toggle := _desk_action("lens","표본 접기" if lens_open else "표본 보기",Rect2(36,352,146,44) if r2_room_active else Rect2(51,324,136,44),func()->void:
		lens_open = not lens_open
		refresh()
		_slide(motion_subjects.get("item"),Vector2(0,6),0.14))
	if r2_room_active: lens_toggle.visible = lens_open or not surface_slots.is_empty()
	motion_subjects["item"] = specimen
	if lens_open and not reverse:
		if surface_texture!=null:
			var loupe: Control
			if r2_room_active:
				loupe = r2_controls.mount(interaction,"r2_observed_sample",Rect2(298,300,152,152),func()->Control:
					var plate := DeskProp.new()
					plate.kind = "sample"
					plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
					return plate)
			else:
				loupe = _prop(interaction,"sample",Rect2(562,352,188,188))
			loupe.set("sample",surface_texture)
			loupe.queue_redraw()
			if r2_room_active:
				var observation := words(str(sample.caption),297,453,168,62,16)
				observation.add_theme_color_override("font_color",Color("#eee3d0"))
			else:
				words(str(desk_copy.subject)+" · "+str(sample.caption),366,548,396,32,15)
		elif sample.is_empty():
			if r2_room_active: words("렌즈를 물품에 대세요.",32,301,236,48,16)
			else: words("표면을 직접 조사하세요",322,262,355,44,15)
		else: words(str(sample.caption)+" · 이미지 미반입",285,425,480,35,14)
		if not surface_slots.is_empty() and not sample.is_empty():
			var index: int = surface_slots.find(surface_slot)
			var caption: String = SurfaceVisuals.SLOT_NAMES[SurfaceVisuals.SLOTS.find(surface_slot)]
			_desk_action("surface_next",caption+" · "+str(index+1)+"/"+str(surface_slots.size()),Rect2(284,246,192,44) if r2_room_active else Rect2(487,330,177,44),func()->void:
				surface_slot = str(surface_slots[(index+1)%surface_slots.size()])
				refresh())
	elif lens_open: words("뒷면 확대 표본 없음",322,262,355,44,15)
	specimen.mouse_filter = Control.MOUSE_FILTER_STOP
	specimen.set_drag_forwarding(Callable(),func(at:Vector2,data:Variant)->bool:
		return _tool_drop_allowed(at/specimen.size,data,v,a),func(at:Vector2,data:Variant)->void:
		if _tool_drop_allowed(at/specimen.size,data,v,a): _queue_counter_drop("inspect",str(data.tool),v,a))
	if zoom and (drawer!="notes" or r2_room_active):
		_desk_action("close_mat","도구 내려놓기",Rect2(36,246,176,44) if r2_room_active else Rect2(52,259,146,44),func()->void:
			chosen_tool = ""
			lens_open = false
			zoom = false
			refresh())
	if Art.ITEMS.model_art.get(str(a.def_id),{}).has("back"):
		_desk_action("turn_item","뒤집기",Rect2(338,522 if reading_scale>100 else 493,112,44) if r2_room_active else Rect2(304,331,106,44),func()->void:
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
		var tool_rect := Rect2(32+(index%3)*86,418,84,96) if r2_room_active else Rect2(44+(index%3)*86,391,88,104)
		var tool := _desk_object("tool_"+slot,slot,caption,tool_rect,func()->void:
			zoom = true
			chosen_tool = slot
			lens_open = slot in SurfaceVisuals.SLOTS
			surface_slot = slot if lens_open else ""
			refresh())
		tool.visible = floori(index/3.0)==tool_page
		tool.modulate = Color("#f4d5a7") if chosen_tool==slot else Color.WHITE
		tool.tooltip_text = caption+(" · "+str(desk_copy.held) if chosen_tool==slot else "")
		motion_subjects["tool_"+slot] = tool
		tool.set_drag_forwarding(func(_at:Vector2)->Variant:
			var held := _r2_hand_visual(slot,Vector2(88,76)*stage.scale) if r2_room_active else _prop_drag_preview(slot)
			held.position = -held.size*0.5
			if r2_room_active:
				r2_drag_source = tool
				tool.self_modulate = Color(1,1,1,0.4)
			tool.set_drag_preview(held)
			return {"tool":slot,"visit":v.active.id,"item":a.item_id},Callable(),Callable())

	if page_count>1:
		_desk_action("more_tools","도구함  %d/%d  ›"%[tool_page+1,page_count],Rect2(36,528,176,44) if r2_room_active else Rect2(49,518,165,43),func()->void:
			tool_page = (tool_page+1)%page_count
			refresh())
	if not chosen_tool.is_empty() and chosen_tool in dock_slots:
		var apply := _desk_action("apply_tool","",Rect2(specimen.position,specimen.size),func()->void:
			_inspect_drop(chosen_tool))
		var held := apply.get_node_or_null("HeldPreview") as Control
		if is_instance_valid(held) and str(held.get_meta("slot"))!=chosen_tool:
			apply.remove_child(held)
			held.queue_free()
			held = null
		if r2_room_active:
			if not is_instance_valid(held):
				held = _r2_hand_visual(chosen_tool,Vector2(78,56))
				held.name = "HeldPreview"
				held.set_meta("slot",chosen_tool)
				held.hide()
				apply.add_child(held)
			if not apply.has_meta("r2_follows_pointer"):
				apply.set_meta("r2_follows_pointer",true)
				apply.gui_input.connect(func(event:InputEvent)->void:
					var preview := apply.get_node_or_null("HeldPreview") as Control
					if preview and event is InputEventMouseMotion:
						preview.position = event.position+Vector2(8,-36)
						preview.visible = not get_viewport().gui_is_dragging())
				apply.mouse_exited.connect(func()->void:
					var preview := apply.get_node_or_null("HeldPreview") as Control
					if preview: preview.hide())
		else:
			var prop := DeskProp.new()
			prop.kind = chosen_tool
			prop.follow_target = true
			prop.size = Vector2(64,50)
			prop.hide()
			apply.add_child(prop)
		apply.flat = true
		apply.mouse_default_cursor_shape = Control.CURSOR_CROSS
		apply.tooltip_text = "선택한 도구로 살펴보기"
		apply.set_drag_forwarding(Callable(),func(at:Vector2,data:Variant)->bool:
			return _tool_drop_allowed(at/apply.size,data,v,a),func(at:Vector2,data:Variant)->void:
			if _tool_drop_allowed(at/apply.size,data,v,a): _queue_counter_drop("inspect",str(data.tool),v,a))

	_evidence_rail(v,a)
	_offer_docket(v,a,id)

func _make_r2_contact_shadow() -> Control:
	var shadow := TextureRect.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var fade := Gradient.new()
	fade.set_color(0,Color("#251d16aa"))
	fade.set_color(1,Color("#251d1600"))
	var image := GradientTexture2D.new()
	image.gradient = fade
	image.width = 64
	image.height = 16
	image.fill = GradientTexture2D.FILL_RADIAL
	image.fill_from = Vector2(0.5,0.5)
	image.fill_to = Vector2(1.0,0.5)
	shadow.texture = image
	return shadow

func _prop_drag_preview(slot: String) -> Control:
	var prop := DeskProp.new()
	prop.kind = slot
	prop.custom_minimum_size = Vector2(88,76)*stage.scale
	prop.size = prop.custom_minimum_size
	prop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return prop

func _evidence_rail(v: Dictionary,a: Dictionary) -> void:
	if a.cards.is_empty(): return
	if r2_room_active:
		_r2_evidence_hand(v,a)
		return
	var per_page := 2 if reading_scale>100 or compact_layout else 3
	var card_width := 684.0/per_page
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
		var note := action("fact_"+slot,(("공개 중 · 다시 제시" if card.selected else "공개 중") if card.public_active else ("제시 예정" if card.selected else "내 기록"))+"\n"+fact,32+(i-start)*card_width,580,card_width-8,103,func()->void: _submit("alpha_card_toggle",{"slot":slot,"selected":not card.selected}))
		note.tooltip_text = _text(card.text_key)+" · "+fact
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
			return {"slot":slot,"visit":v.active.id,"item":a.item_id},Callable(),Callable())
	if a.cards.size()>per_page:
		action("more_facts","›",718,600,54,48,func()->void:
			hand_page = (hand_page+1)%ceili(float(a.cards.size())/per_page)
			refresh())
	mounting = interaction

func _r2_evidence_hand(v: Dictionary,a: Dictionary) -> void:
	var count := 2 if reading_scale>100 or compact_layout else 3
	var last_page := ceili(float(a.cards.size())/count)-1
	hand_page = clampi(hand_page,0,last_page)
	var width := 681.0/count
	var first := hand_page*count
	for index in range(first,mini(first+count,a.cards.size())):
		var card: Dictionary = a.cards[index]
		var slot := str(card.slot)
		var fact := _fact_caption(slot,card.value)
		var marked := bool(card.selected)
		var stamp := "제시 예정" if marked else "내 기록"
		if card.public_active: stamp = "다시 제시" if marked else "공개 중"
		elif card.get("ever_disclosed",false): stamp = "철회 · 제시 예정" if marked else "철회됨"
		var caption := stamp+"\n"+fact
		var note := _r2_action("fact_"+slot,caption,Rect2(30+(index-first)*width,580,width-10,100),func()->void:
			_submit("alpha_card_toggle",{"slot":slot,"selected":not marked}))
		_paper_face(note,marked)
		note.alignment = HORIZONTAL_ALIGNMENT_LEFT
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		note.tooltip_text = _text(card.text_key)+" · "+fact
		motion_subjects["card_"+slot] = note
		note.set_drag_forwarding(func(_at:Vector2)->Variant:
			var preview := Button.new()
			preview.text = caption
			preview.alignment = HORIZONTAL_ALIGNMENT_LEFT
			preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			preview.add_theme_font_size_override("font_size",roundi(16.0*reading_scale/100.0))
			preview.custom_minimum_size = note.size*stage.scale
			preview.position = -preview.custom_minimum_size*0.5
			preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_paper_face(preview,true)
			note.set_drag_preview(preview)
			r2_drag_source = note
			note.self_modulate = Color(1,1,1,0.4)
			return {"slot":slot,"visit":v.active.id,"item":a.item_id},Callable(),Callable())
	if last_page>0:
		var more := _r2_action("more_facts","›",Rect2(718,598,54,48),func()->void:
			hand_page = (hand_page+1)%(last_page+1)
			refresh())
		more.tooltip_text = "감정 카드 %d/%d"%[hand_page+1,last_page+1]

func _basis_caption(base: Dictionary) -> String:
	if base.is_empty(): return "감정가 기준 선택"
	var caption: String = {"appraisal_range":"내 감정가","catalog_reference":"도감 참고가","posted_ask":"매대 표시가","personal_provisional":"내 임시 평가액","public_quote":"공개 요구가"}.get(str(base.source),"평가 기준")
	if base.get("reference_source")=="customer_at_counter": caption="손님 제시가"
	if base.source=="catalog_reference" and base.get("judgment","unknown")!="unknown": caption="도감 기반 내 감정가"
	return "%s · %d %s"%[caption,base.amount,base.currency]

func _known_offer_basis(v: Dictionary) -> Dictionary:
	var a: Dictionary = v.appraisal
	var history: Dictionary = session.alpha_item_history(str(a.item_id),last_visit)
	return RatioQuote.basis(KnownEstimate.evaluate(history,a,private_model,int(v.day)),str(a.offer_currency))

# Same catalogue source used by the explicit price-book selection.
func _public_offer_catalog(a: Dictionary) -> Dictionary:
	var path: String = {"portable_radio":"res://data/campaign/gate2/demo_radio_catalog.json","fictional_watch_p2":"res://data/campaign/gate2/watch_public_catalog.json"}.get(str(a.def_id),"")
	if path.is_empty(): return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary and data.get("currency")==a.offer_currency else {}

func _updated_offer_basis(v: Dictionary) -> Dictionary:
	if offer_basis.is_empty(): return {}
	var a: Dictionary = v.appraisal
	var fresh: Dictionary = _known_offer_basis(v)
	if fresh.is_empty() and offer_basis.get("source")=="catalog_reference":
		var catalog := _public_offer_catalog(a)
		for slot: Dictionary in catalog.get("slots",[]):
			if slot.get("effect")!="base": continue
			for candidate: Dictionary in slot.get("candidates",[]):
				if candidate.get("id")==offer_basis.get("model"):
					fresh = RatioQuote.catalog_basis(catalog,candidate,str(a.surface_judgments.get("exterior","unknown")),str(a.offer_currency))
	if fresh.is_empty() or fresh==offer_basis: return {}
	return fresh

func _apply_updated_basis(base: Dictionary) -> void:
	if base.is_empty() or RatioQuote.amount(base,offer_ratio)<=0: return
	# Keep the chosen percentage; actual prior submitted offers remain unchanged.
	offer_basis = base.duplicate(true)
	refresh()

func _choose_offer_basis(base: Dictionary) -> void:
	if base.is_empty(): return
	offer_basis = base.duplicate(true)
	offer_ratio = 1000
	refresh()

func _open_offer_basis() -> void:
	book_choice = true
	book_tab = 2
	previous_book_scroll = 0
	drawer_scroll = 0
	open_drawer("notes")

func _counter_speech(v: Dictionary) -> String:
	var a: Dictionary = v.appraisal
	if a.is_empty():
		var original := _b2_npc_line(v)
		return original if not original.is_empty() else _text(v.active.purpose_key)
	var public_context: Dictionary = v.get("npc_context",{})
	if v.has("customer_bid_vkc") and public_context.get("current_offer",{}).is_empty() and public_context.get("latest_spoken",{}).is_empty():
		if public_context.get("prior",{}).get("outcome","")=="departed":
			return "지난번엔 값이 안 맞았죠. 오늘은 %d VKC에 사겠습니다."%v.customer_bid_vkc
		return "이 물건을 사러 왔습니다. %d VKC면 어떻습니까?"%v.customer_bid_vkc
	if r2_room_active and v.active.id=="visit_g01":
		if public_context.get("current_offer",{}).is_empty() and public_context.get("latest_spoken",{}).is_empty() and public_context.get("prior",{}).is_empty():
			return str(captions.g01)
	return CounterDialogue.line(public_context,bool(a.we_buy),str(v.active.actor_id))

func _counter_caption(actor: String,speech: String) -> void:
	if r2_room_active:
		var speech_rect := Rect2(914,67,313,117) if reading_scale==100 else Rect2(810,64,417,131)
		var panel := r2_controls.mount(interaction,"r2_dialogue",speech_rect,_make_r2_dialogue) as PanelContainer
		var nameplate := panel.get_node("Lines/Actor") as Label
		var utterance := panel.get_node("Lines/Utterance") as Label
		nameplate.text = actor
		utterance.text = speech
		nameplate.add_theme_font_size_override("font_size",roundi(16.0*reading_scale/100.0))
		utterance.add_theme_font_size_override("font_size",roundi(19.0*reading_scale/100.0))
		panel.visible = not speech.is_empty()
		return
	var nameplate := words(actor,813,65,400,28,16)
	nameplate.add_theme_color_override("font_color",Color("#cbb99c"))
	words(speech,813,95,400,47,19)

func _make_r2_dialogue() -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#242727ed")
	style.border_color = Color("#917653")
	style.border_width_left = 2
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel",style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lines := VBoxContainer.new()
	lines.name = "Lines"
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(lines)
	for id: String in ["Actor","Utterance"]:
		var label := Label.new()
		label.name = id
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_color",Color("#cebfa5") if id=="Actor" else Color("#eee7d8"))
		lines.add_child(label)
	return panel

func _make_r2_price_slip() -> Control:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge := StyleBoxFlat.new()
	edge.bg_color = Color("#cfc0a4")
	edge.border_color = Color("#74634f")
	edge.border_width_bottom = 3
	edge.shadow_color = Color("#221a1599")
	edge.shadow_size = 4
	edge.shadow_offset = Vector2(2,3)
	panel.add_theme_stylebox_override("panel",edge)
	return panel

func _drop_card_at_counter(slot: String) -> void:
	if _blocked or _leaving_title or session==null: return
	var live: Dictionary = session.alpha_view()
	if live.phase!="CUSTOMER_ACTIVE" or live.appraisal.is_empty(): return
	_queue_counter_drop("attach",slot,live,live.appraisal)

func _offer_docket(v: Dictionary,a: Dictionary,id: String) -> void:
	# A separate evidence presentation strip, not part of the numeric controls.
	var pocket: AttachmentPocket
	if r2_room_active:
		pocket = r2_controls.mount(interaction,"attachment_pocket",Rect2(800,506,432,46),func()->Control:
			var target := AttachmentPocket.new()
			target.use_desk_finish = true
			target.attach.connect(_drop_card_at_counter)
			return target) as AttachmentPocket
	else:
		pocket = AttachmentPocket.new()
		place(pocket,800,510,432,44)
		pocket.attach.connect(func(slot:String)->void:_queue_counter_drop("attach",slot,v,a))
	var slips := {}
	for card: Dictionary in a.cards:
		slips[str(card.slot)] = {"caption":_fact_caption(str(card.slot),card.value),"selected":card.selected,"public":card.public_active}
	pocket.bind(str(v.active.id),slips,str(a.item_id))
	if not a.we_buy and drawer!="notes" and not (r2_room_active and papers_open):
		var tag: Dictionary = Alpha.displayed_ask(session.snapshot(),id)
		if not tag.is_empty():
			words("매대 표시가 · %d %s"%[tag.amount,tag.currency],805,402 if r2_room_active else 472,224 if r2_room_active else 403,65 if r2_room_active else 36,17)
	elif drawer!="notes" and not a.customer_claims.is_empty() and not (r2_room_active and papers_open):
		var claim := _text(a.customer_claims[0].text_key)
		if r2_room_active:
			var backing := paper(800,261,434,76,Color("#242727e8"))
			backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
			words("손님 주장 · "+claim,812,268,408,62,16)
		else:
			words("손님 주장 · "+claim,805,183,399,64,17)
	var denomination := str(a.offer_currency)
	if r2_room_active:
		r2_controls.mount(interaction,"r2_price_slip",Rect2(792,552,448,153),_make_r2_price_slip)
		if drawer!="notes" and not a.offers.is_empty() and a.accepted.is_empty():
			var last: Dictionary = a.offers.back()
			words("직전 제안   %d %s"%[last.amount,last.currency],805,345,411,42,17)
	else:
		paper(794,554,448,143,Color("#463f34")).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if a.accepted.is_empty():
		var updated := _updated_offer_basis(v)
		var title := _basis_caption(offer_basis)
		if not updated.is_empty(): title = "기준 %d · 새 평가 %d %s"%[offer_basis.amount,updated.amount,updated.currency]
		var basis_button := _desk_action("counter_offer",title,Rect2(800,555,432,44),_open_offer_basis)
		basis_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		basis_button.tooltip_text = _basis_caption(offer_basis) if updated.is_empty() else "현재 제안 기준 유지 · "+_basis_caption(updated)+" · 도감에서 적용"
		_paper_face(basis_button)
		if not is_instance_valid(offer_editor):
			offer_editor = RatioControl.new()
			place(offer_editor,800,600,432,48)
			offer_editor.ratio_changed.connect(func(value:int)->void: offer_ratio=value)
		if r2_room_active:
			offer_editor.position.y = 598
			offer_editor.size.y = 58
		elif r2_review_mode:
			offer_editor.position.y = 600
			offer_editor.size.y = 48
		if r2_review_mode: offer_editor.present_as_receipt(r2_room_active)
		offer_editor.bind(offer_basis,offer_ratio)
		editor_used = true
		offer_editor.visible = true
		interaction.move_child(offer_editor,-1)
		var send_offer := _desk_action("offer",("매입 제안" if a.we_buy else "판매 제안")+" · "+denomination,Rect2(800,657 if r2_room_active else 650,432,44),func()->void:
			var proposed: int = RatioQuote.amount(offer_basis,offer_ratio)
			if proposed>0 and offer_basis.get("currency")==denomination:
				_submit("alpha_price_offer",{"amount":proposed})
			else:
				hint = "먼저 감정가 기준을 선택하세요."
				refresh())
		send_offer.disabled = offer_basis.is_empty()
	else:
		var agreement := words("합의가 · %d %s"%[a.accepted.amount,a.accepted.currency],806,558,410,44,21)
		if r2_room_active:
			agreement.add_theme_color_override("font_color",Color("#302a22"))
			agreement.remove_theme_constant_override("outline_size")
	if not a.accepted.is_empty():
		_desk_action("settle_trade","거래 확정 · %d %s"%[a.accepted.amount,a.accepted.currency],Rect2(806,603,410,50),func()->void:
			var trade: Dictionary = session.snapshot().visits[v.active.id]
			var dest: String = "player_stock" if a.we_buy else str(trade.buyer)+"_grid"
			var fit: Dictionary = session.spatial_fit(id,dest)
			if fit.get("ok",false):
				_submit("alpha_trade",{"visit_id":v.active.id,"item_id":id,"seller":trade.seller,"buyer":trade.buyer,"currency":a.accepted.currency,"amount":a.accepted.amount,"inventory":dest,"x":fit.x,"y":fit.y,"rotated":fit.rotated})
			else:
				hint = "물건을 놓을 빈 공간이 없습니다."
				refresh())
	
	if drawer!="notes" and not (r2_room_active and papers_open):
		var book_rect := Rect2(1041,401,156,100) if r2_room_active else Rect2(899,307,215,157)
		_desk_object("notes","book",str(desk_copy.book),book_rect,func()->void: open_drawer("notes"))

# A native drop callback must not remove the source or target while Godot is
# still finishing the GUI drag. Defer the existing authority command, never
# fabricate a second inspection or attachment. Revalidate the live context.
func _queue_counter_drop(kind: String, slot: String, v: Dictionary, a: Dictionary) -> void:
	if _blocked or _leaving_title or session==null or not pending_counter_drop.is_empty(): return
	var live: Dictionary = session.alpha_view()
	if live.phase!="CUSTOMER_ACTIVE" or live.active.get("id","")!=v.active.id or live.appraisal.get("item_id","")!=a.item_id: return
	pending_counter_drop = {"kind":kind,"slot":slot,"visit":v.active.id,"item":a.item_id,"revision":int(session.snapshot().revision)}
	_flush_counter_drop.call_deferred()

func _flush_counter_drop() -> void:
	if pending_counter_drop.is_empty(): return
	if not is_inside_tree():
		pending_counter_drop.clear()
		return
	if get_viewport().gui_is_dragging(): return
	var drop: Dictionary = pending_counter_drop
	pending_counter_drop = {}
	if _blocked or _leaving_title or session==null: return
	if int(session.snapshot().revision)!=int(drop.revision): return
	var live: Dictionary = session.alpha_view()
	if live.phase!="CUSTOMER_ACTIVE" or live.active.get("id","")!=drop.visit or live.appraisal.get("item_id","")!=drop.item: return
	if drawer not in ["","notes"]: return
	var a: Dictionary = live.appraisal
	var slot: String = str(drop.slot)
	match str(drop.kind):
		"inspect":
			if a.tools.any(func(tool:Dictionary)->bool:return tool.id==slot) or a.cards.any(func(card:Dictionary)->bool:return card.slot==slot):
				_inspect_drop(slot)
		"attach":
			if a.cards.any(func(card:Dictionary)->bool:return card.slot==slot and not card.selected):
				_submit("alpha_card_toggle",{"slot":slot,"selected":true})

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
	if not data is Dictionary or data.get("visit")!=v.active.id or data.get("item")!=a.item_id or not data.has("tool"): return false
	if not a.tools.any(func(tool:Dictionary)->bool:return tool.id==data.tool) and not a.cards.any(func(card:Dictionary)->bool:return card.slot==data.tool): return false
	return Rect2(0,0,1,1).has_point(relative)

func _drawer(v: Dictionary) -> void:
	var current: Dictionary = session.snapshot()
	if drawer=="notes":
		_counter_caption(_actor_label(str(v.active.actor_id)),_counter_speech(v))
		_specimen(v,v.appraisal)
		if r2_room_active:
			_show_r2_book(v)
			return
		paper(777,184,456,321,Color("#574535"))
		paper(783,189,442,311,Color("#9c8c70"))
		paper(788,192,430,303,Color("#cabc9e"))
		paper(789,192,9,303,Color("#a28d6b"))
	elif drawer=="phone":
		if r2_room_active and r2_phone_art!=null:
			pic(r2_phone_art,498,405,254,166).name = "r2_phone_receiver"
		else:
			_prop(interaction,"phone",Rect2(520,350,225,185))
		_desk_object("phone_ledger","book","영업 장부",Rect2(382,571,134,103) if r2_room_active else Rect2(555,540,168,100),func()->void:open_drawer("ledger"))
	elif not r2_room_active or drawer=="settings":
		pic(Art.STOCK_ROOM if drawer=="stock" else Art.OFFICE_ROOM,0,0,1280,720,true)
	if drawer not in ["notes","phone"]:
		if r2_room_active and drawer!="settings":
			var scrim := paper(45,115 if drawer!="stock" else 63,1190,560 if drawer!="stock" else 623,Color("#241f1dde"))
			scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			paper(44,50,1192,625,Color("#241f1deb"))
	action("close_drawer","재고로" if drawer=="item_history" else "카운터로",1045,128 if drawer=="notes" else 64,165,44,func()->void: open_drawer("stock" if drawer=="item_history" else ""))
	if r2_review_mode and drawer in ["ledger","item_history","news"]:
		_product_document_workspace(v,current)
		return
	if drawer=="ledger":
		_ledger_workspace(v,current)
		return
	if drawer=="phone":
		_phone_workspace(v)
		return
	if drawer=="stock":
		_inventory(v,current)
		return
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if drawer=="notes": place(scroll,803,196,410,304)
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
func _record_alias(state: Dictionary, actor: String) -> String:
	var label := _actor_label(actor)
	if label!=_text("spatial.visitor"): return label
	var book: Dictionary = state.alpha_shop.get("contacts",{})
	var ids := book.keys()
	var index := ids.find(actor)
	return "수첩의 연락처 %02d"%(index+1) if index>=0 else label

func _product_document_workspace(v: Dictionary,state: Dictionary) -> void:
	var name_key := drawer
	var folio := workspaces.mount(interaction,"folio_"+name_key,Rect2(62,127,1156,540),func()->Control:
		return ProductDocuments.new()) as ProductDocuments
	var groups: Dictionary = {}
	var header := ""
	match drawer:
		"ledger":
			header = "장부   /   보유 현금 %d VKC · %d USD"%[state.wallets.player.VKC,state.wallets.player.USD]
			groups = _ledger_groups(v,state)
		"news":
			header = str(desk_copy.region)%v.day
			var notices: Array = []
			if v.has("market_bulletin"): notices.append({"key":"battery_notice","caption":"지역 시장 납품 공지","detail":v.market_bulletin})
			for notice: Dictionary in v.news:
				var stamp := "게시일 %d일차"%int(notice.day) if notice.has("day") else "게시일 기록 없음"
				var notice_text := _text("alpha.news."+str(notice.text_key))
				notices.append({"key":"bulletin_"+str(notice.id),"caption":stamp+" · 공개 공지","detail":stamp+" · 상점에 게시된 공개 공지\n"+notice_text})
			groups["news"] = {"caption":"게시된 소식","rows":notices,"empty":_text("spatial.quiet")}
		"item_history":
			var item: Dictionary = state.items.get(selected,{})
			header = "물품 이력   /   "+_text("b2.item."+str(item.get("def_id","")))
			var id := selected
			groups["item"] = {"caption":"같은 물품의 거래와 작업","rows":[{"key":"history_"+id,"caption":_text("b2.item."+str(item.get("def_id",""))),"detail":"공개된 거래 사실과 당시 판단 기록"}],"render":func(page:VBoxContainer)->void:_history_lines(page,id)}
	folio.open(header,groups,reading_scale,JSON.stringify([state.revision,reading_scale,selected if drawer=="item_history" else ""]))

func _ledger_groups(v: Dictionary,state: Dictionary) -> Dictionary:
	var trade_rows: Array = []
	var inbound: Array = []
	var outbound: Array = []
	var contracts: Array = []
	var incoming := {"VKC":0,"USD":0}
	var outgoing := {"VKC":0,"USD":0}
	for entry: Dictionary in state.ledger:
		var paid: bool = entry.from=="player"
		if not paid and entry.to!="player": continue
		var money: Dictionary = entry.amounts
		var flow := outgoing if paid else incoming
		for currency: String in ["VKC","USD"]: flow[currency] += int(money[currency])
		var party := _record_alias(state,str(entry.to if paid else entry.from))
		var names := _receipt_items(state,entry.root_ids)
		var stamp := "%d일차"%[int(entry.game_minutes/1440)+1]
		var amount := "%d VKC · %d USD"%[money.VKC,money.USD]
		var direction := "지출" if paid else "입금"
		var facts := PackedStringArray([stamp+" · "+party,direction+" "+amount,names if not names.is_empty() else "물품 이체 기록 없음"])
		if not paid and not entry.root_ids.is_empty():
			for currency: String in ["VKC","USD"]:
				var basis: Variant = entry.basis[currency]
				if basis!=null: facts.append("%s 원가 %d · 차액 %d"%[currency,int(basis),int(money[currency])-int(basis)])
				else: facts.append(currency+" 원가 자료 부족")
		trade_rows.push_front({"key":"r_"+str(entry.event_id),"caption":stamp+" · "+party+" · "+direction+" "+amount+"\n"+names,"detail":"\n".join(facts)})
	# Keep terminal-item records in the existing ledger after stock is gone.
	if state.alpha_shop.profile.has("f3_composite_trial"):
		for event:Dictionary in state.object_events:
			if event.type not in ["discard","restore_item"]: continue
			var item_id:String=str(event.item_ids[0])
			var specimen:Dictionary=state.items.get(item_id,state.tombstones.get(item_id,{}))
			if specimen.get("def_id") not in ["f3_receiver_v1","f3_module_a","f3_module_b"]: continue
			var title:String=("폐기 · " if event.type=="discard" else "정비 · ")+_receipt_items(state,event.item_ids)
			var cost:Dictionary=event.basis if event.type=="discard" else event.expenses
			var detail:String=title+"\n"+("원가 손실" if event.type=="discard" else "실제 정비 비용")+" · %s VKC / %s USD"%[str(cost.VKC),str(cost.USD)]
			var history:Dictionary=session.alpha_item_history(item_id)
			for offer:Dictionary in history.prior_offers:
				detail+="\n당시 제안 %d %s"%[offer.amount,offer.currency]
				for fact:Dictionary in offer.facts:
					detail+="\n"+_text("b2.inspect."+str(fact.slot))+" · "+_fact_caption(fact.slot,fact.value)
			trade_rows.push_front({"key":"work_"+str(event.event_id),"caption":title,"detail":detail})
	for transfer: Dictionary in state.alpha_shop.get("fx",{}).get("settlements",{}).values():
		var change := "%d %s 지급 · %d %s 수령"%[transfer.give_amount,transfer.give_currency,transfer.receive_amount,transfer.receive_currency]
		var stamp := "%d일차 · 환전"%transfer.day
		trade_rows.push_front({"key":"fx_"+str(transfer.event_id),"caption":stamp+" · "+change,"detail":stamp+"\n"+_record_alias(state,str(transfer.counterparty))+"\n"+change})
		outgoing[transfer.give_currency] += int(transfer.give_amount)
		incoming[transfer.receive_currency] += int(transfer.receive_amount)
	for job: Dictionary in v.services.entries:
		var title := _text("b2.item."+str(job.def_id))
		inbound.append({"key":"service_"+str(job.job_id),"caption":_record_alias(state,str(job.actor_id))+" · "+title,"detail":_text("b2.service.receipt")%[title,job.due_day,job.fee.VKC,_text("b2.service.status."+str(job.status))]})
	for request: Dictionary in v.commissions.entries:
		var caption := _text("b2.commission.status."+str(request.status))
		inbound.append({"key":"request_"+str(request.request_id),"caption":_record_alias(state,str(request.actor_id))+" · "+caption,"detail":_text(request.text_key)+"\n기한 %d일차 · %s"%[request.due_day,caption]})
	for id: String in state.alpha_shop.get("outbound",{}):
		var order: Dictionary = state.alpha_shop.outbound[id]
		var lines := _outbound_order_lines(order)
		outbound.append({"key":"order_"+id,"caption":_record_alias(state,str(order.actor_id))+" · "+str(lines[0]),"detail":"\n".join(lines)})
	for id: String in v.contracts:
		var offer: Dictionary = v.contracts[id]
		if v.phase=="CUSTOMER_ACTIVE" and v.active.actor_id!=offer.supplier: continue
		var status := _text("alpha.contract.status."+str(offer.status))
		contracts.append({"key":"contract_"+id,"caption":_record_alias(state,str(offer.supplier))+" · "+status,"detail":_text("alpha.contract.header")+"\n%s · %d VKC · 기한 %d일차"%[status,offer.price.VKC,offer.due_day]})
	return {
		"trades":{"caption":"거래","rows":trade_rows,"render":func(page:VBoxContainer)->void:
			_board_line(page,"cash_in","거래 유입 · %d VKC / %d USD"%[incoming.VKC,incoming.USD])
			_board_line(page,"cash_out","거래 유출 · %d VKC / %d USD"%[outgoing.VKC,outgoing.USD])},
		"inbound":{"caption":"받은 의뢰","rows":inbound,"render":func(page:VBoxContainer)->void:
			if v.phase in ["OPEN_IDLE","EVENING_WORK"]: _add_b2_commission_actions(page,v)},
		"outbound":{"caption":"맡긴 의뢰","rows":outbound},
		"contracts":{"caption":"계약·담보","rows":contracts,"render":func(page:VBoxContainer)->void:
			if v.phase!="CUSTOMER_ACTIVE": _add_contract_actions(page,v)
			_pawn_folio(page,v,state)},
	}

func _pawn_folio(page: VBoxContainer,v: Dictionary,state: Dictionary) -> void:
	var pawn: Dictionary = state.alpha_shop.week_pawn
	if pawn.status=="available": return
	var title := _receipt_items(state,["WAT02"])
	_board_line(page,"pledge",title+" · "+_text("week."+str(pawn.status))+" · 기한 %d일차"%pawn.due)
	if pawn.status=="pledged" and v.phase=="CLOSE_SETTLE" and v.day==pawn.due:
		_button(page,"week_redeem",_text("week.redeem"),func()->void:_submit("week_redeem"))
		if pawn.due==4: _button(page,"week_extend",_text("week.extend"),func()->void:_submit("week_extend"))

func _outbound_order_lines(order: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray([_text("week."+str(order.status))])
	for payment: Dictionary in order.payments:
		var verb := "선금 지급" if payment.from=="player" else "환급 수령"
		lines.append("%d일차 · %s · %d %s"%[payment.day,verb,payment.amount,payment.currency])
	return lines

func _ledger_workspace(v: Dictionary,current: Dictionary) -> void:
	var ledger := preload("res://src/presentation/b3_ledger_spread.gd").new()
	place(ledger,62,126,1154,520)
	var rows: Array = []
	for entry: Dictionary in current.ledger:
		var names := _receipt_items(current,entry.root_ids)
		var amount := "%d VKC  /  %d USD"%[entry.amounts.VKC,entry.amounts.USD]
		var day := "D"+str(entry.day) if entry.has("day") else "날짜 미기록"
		var facts := PackedStringArray([day,names, _actor_label(entry.from)+" → "+_actor_label(entry.to),amount])
		if entry.from!="player" and entry.to=="player":
			for currency: String in ["VKC","USD"]:
				var basis: Variant = entry.basis[currency]
				if basis!=null: facts.append("원가 %d · 실현손익 %d %s"%[int(basis),int(entry.amounts[currency])-int(basis),currency])
				else: facts.append(currency+" 원가 자료 부족")
		rows.append({"key":str(entry.event_id),"caption":day+"   "+names+"   "+amount,"facts":"\n".join(facts)})
	var pages := ledger.open(current.wallets.player,rows,receipt_id)
	ledger.receipt_selected.connect(func(key:String)->void:receipt_id=key)
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

func _show_r2_book(v: Dictionary) -> void:
	r2_book = r2_controls.mount(interaction,"r2_reference_desk",Rect2(797,204,441,298),func()->Control:
		var desk := R2Book.new()
		desk.closed.connect(func()->void:
			open_drawer("")
			var cover := interaction.get_node_or_null("notes") as Button
			if cover and cover.is_visible_in_tree(): cover.grab_focus())
		desk.page_requested.connect(func(index:int)->void:
			book_choice = true
			book_tab = index
			_refresh_book(desk.pages,true))
		desk.ready.connect(func()->void:
			desk.scroll.get_v_scroll_bar().value_changed.connect(func(value:float)->void:
				if desk.is_visible_in_tree() and drawer=="notes": drawer_scroll = roundi(value)))
		return desk) as R2Book
	if r2_book_content_key!=_r2_book_key(v):
		_refresh_r2_book_body(r2_book.pages,v,drawer_scroll)
	else:
		r2_book.scroll.set_deferred("scroll_vertical",drawer_scroll)
	motion_subjects["book"] = r2_book

func _r2_book_key(v: Dictionary) -> String:
	return JSON.stringify([reading_scale,book_tab,v.day,v.appraisal,offer_basis,offer_ratio])

func _refresh_r2_book_body(pages: VBoxContainer,v: Dictionary, offset: int) -> void:
	r2_book_content_key = _r2_book_key(v)
	_clear_layer(pages)
	r2_book.select_page(book_tab,reading_scale)
	_book_body(pages,v)
	for button: Button in pages.find_children("*","Button",true,false):
		button.add_theme_font_size_override("font_size",roundi(16.0*reading_scale/100.0))
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = maxf(44,button.custom_minimum_size.y)
	for label: Label in pages.find_children("*","Label",true,false):
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size",roundi(16.0*reading_scale/100.0))
	drawer_scroll = offset
	r2_book.scroll.set_deferred("scroll_vertical",offset)

func _refresh_book(pages: VBoxContainer,top: bool=false) -> void:
	if drawer!="notes" or not pages.is_inside_tree(): return
	var scroll := pages.get_parent() as ScrollContainer
	var offset := 0 if top else scroll.scroll_vertical
	if r2_room_active and is_instance_valid(r2_book) and pages==r2_book.pages:
		_refresh_r2_book_body(pages,session.alpha_view(),offset)
		return
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
	_book_body(pages,v)

func _book_body(pages: VBoxContainer,v: Dictionary) -> void:
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
		if not features.is_empty(): _board_line(pages,"reference_features","확인할 항목 · "+", ".join(features))
		if Art.ITEMS.model_art.has(reference_model):
			_button(pages,"record_model","이 모델로 추정",func()->void:
				private_model = reference_model
				_refresh_book(pages))
	if not private_model.is_empty():
		_button(pages,"clear_model","내 가설 · "+_text("b2.item."+private_model)+"  ×",func()->void:
			private_model = ""
			_refresh_book(pages))

func _surface_page(pages: VBoxContainer,v: Dictionary) -> void:
	var leaf := preload("res://src/presentation/b3_surface_leaf.gd").new()
	pages.add_child(leaf)
	leaf.bind(reference_material,reference_variant,judgment_leaf,reading_scale,84 if r2_room_active else 102)
	leaf.turn.connect(func(family:String,variant:int,judging:bool)->void:
		reference_material = family
		reference_variant = variant
		judgment_leaf = judging
		_refresh_book(pages,true))
	if not judgment_leaf: return
	var choices: Dictionary = preload("res://src/domain/alpha_card_trade.gd").SURFACE_CHOICES
	var groups := ["exterior","material"] if r2_room_active else ["material","exterior"]
	for group: String in groups:
		var values: Array = choices[group]
		var saved := str(v.appraisal.surface_judgments.get(group,"unknown"))
		var selected_index := maxi(0,values.find(saved))
		var labels := ["보류","금속","플라스틱","종이","직물","유리"] if group=="material" else ["보류","경미","보통","심함"]
		var row := HBoxContainer.new()
		pages.add_child(row)
		if group=="material":
			var caption := Label.new()
			caption.text = "내 재질 판단 · "+str(labels[selected_index])
			if r2_room_active:
				pages.add_child(caption)
				pages.move_child(caption,row.get_index())
				caption.custom_minimum_size.y = 25
			else:
				row.add_child(caption)
			var step := Button.new()
			step.text = "표본 재질로 기록"
			step.custom_minimum_size.y = 44
			if r2_room_active:
				step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				step.custom_minimum_size.x = 180
			row.add_child(step)
			step.pressed.connect(func()->void:
				_submit("alpha_hypothesis",{"slot":"material","judgment":reference_material}))
			var clear := Button.new()
			clear.text = "보류"
			clear.custom_minimum_size.y = 44
			if r2_room_active: clear.custom_minimum_size.x = 88
			row.add_child(clear)
			clear.pressed.connect(func()->void: _submit("alpha_hypothesis",{"slot":"material","judgment":"unknown"}))
		else:
			for index in range(values.size()):
				var grade := Button.new()
				grade.name = "exterior_"+str(values[index])
				grade.text = str(labels[index])
				grade.tooltip_text = "내 외관 판단"
				grade.custom_minimum_size.y = 44
				grade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(grade)
				_paper_face(grade,index==selected_index)
				var value := str(values[index])
				grade.pressed.connect(func()->void: _submit("alpha_hypothesis",{"slot":"exterior","judgment":value}))
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
	var a: Dictionary = v.appraisal
	var currency: String = str(a.offer_currency)
	if v.has("market_bulletin"): _board_line(pages,"market_notice",v.market_bulletin)
	if v.has("customer_bid_vkc"):
		var bid := RatioQuote.basis({},currency,{"kind":"public_quote","source":"customer_at_counter","amount":v.customer_bid_vkc,"currency":"VKC"})
		if not bid.is_empty():
			_button(pages,"customer_bid","손님 제시가 적용 · %d VKC"%v.customer_bid_vkc,func()->void: _choose_offer_basis(bid))
	_board_line(pages,"basis_status",_basis_caption(offer_basis),true)
	var updated := _updated_offer_basis(v)
	if not updated.is_empty():
		_board_line(pages,"basis_update_notice","새 평가 "+_basis_caption(updated)+" · 현재 제안 기준 유지 중")
		var apply_update := _button(pages,"basis_update","새 평가 적용 · 비율 유지",func()->void: _apply_updated_basis(updated))
		apply_update.disabled = RatioQuote.amount(updated,offer_ratio)<=0
	var known := _known_offer_basis(v)
	if not known.is_empty():
		_button(pages,"basis_known","내 감정가 적용 · %d %s"%[known.amount,currency],func()->void: _choose_offer_basis(known))
	# These are dated/provisional public catalogue candidates. Choosing one
	# does not identify the actual hidden model. No default is selected.
	var catalog := _public_offer_catalog(a)
	for slot: Dictionary in catalog.get("slots",[]):
		if slot.get("effect")!="base": continue
		for candidate: Dictionary in slot.get("candidates",[]):
			var base := RatioQuote.catalog_basis(catalog,candidate,str(a.surface_judgments.get("exterior","unknown")),currency)
			if base.is_empty(): continue
			_button(pages,"basis_catalog_"+str(candidate.id),("도감 평가 · " if base.get("judgment","unknown")!="unknown" else "도감 참고 · ")+str({"selvar_r18":"셀바르 R18","selvar_r18s":"셀바르 R18S","meridian_12":"메리디언 12","meridian_12a":"메리디언 12A"}.get(str(candidate.id),_text(str(candidate.label_key))))+" · %d %s"%[base.amount,currency],func()->void: _choose_offer_basis(base))
	if not a.we_buy:
		var posted: Dictionary = Alpha.displayed_ask(session.snapshot(),str(a.item_id))
		var base := RatioQuote.basis({},currency,{"kind":"posted_ask","source":"player_displayed_ask","amount":posted.get("amount",0),"currency":posted.get("currency","")})
		if not base.is_empty(): _button(pages,"basis_posted","내 매대 표시가 적용 · %d %s"%[base.amount,currency],func()->void: _choose_offer_basis(base))
	_board_line(pages,"provisional_caption","내 임시 평가액 · 자료 부족 시 직접 판단 (시세 아님)")
	var provisional := Label.new()
	provisional.name = "provisional_amount"
	provisional.text = "%d %s"%[provisional_amount,currency]
	pages.add_child(provisional)
	for magnitude: int in [1,10,100,1000]:
		var row := HBoxContainer.new()
		pages.add_child(row)
		for delta: int in [-magnitude,magnitude]:
			var adjust := Button.new()
			adjust.name = "provisional_"+("minus_" if delta<0 else "plus_")+str(absi(delta))
			adjust.text = "%+d"%delta
			adjust.custom_minimum_size.y = 44
			adjust.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(adjust)
			adjust.pressed.connect(func()->void:
				provisional_amount = clampi(provisional_amount+delta,1,RatioQuote.MAX_AMOUNT)
				provisional.text = "%d %s"%[provisional_amount,currency])
	_button(pages,"basis_provisional","내 임시 평가액 적용",func()->void:
		_choose_offer_basis(RatioQuote.basis({},currency,{"kind":"personal_provisional","source":"player","amount":provisional_amount,"currency":currency})))
	_known_price(pages,a,int(v.day))
	_history_lines(pages,str(a.item_id))

func _phone_workspace(v: Dictionary) -> void:
	if v.phase!="EVENING_WORK": return
	var state: Dictionary = session.snapshot()
	var contacts: Array = []
	for contact: Dictionary in v.contacts:
		var actor := str(contact.actor_id)
		var alias := _record_alias(state,actor)
		contacts.append({"actor":actor,"caption":alias+"\n%d일차에 교환"%int(contact.acquired_day)})
	var options: Array = []
	for option: Dictionary in v.get("outbound_options",[]):
		options.append({"id":str(option.id),"actor":str(option.actor),"command":str(option.command),"body":_text(option.label)})
	var receipts: Dictionary = {}
	for order: Dictionary in state.alpha_shop.get("outbound",{}).values():
		receipts[order.actor_id] = _outbound_order_lines(order)
	var phone: PhoneDesk
	if r2_review_mode:
		phone = workspaces.mount(interaction,"r2_phone_workspace",Rect2(0,0,1280,720),_make_phone_desk) as PhoneDesk
	else:
		phone = _make_phone_desk()
		place(phone,0,0,1280,720)
	phone_view = phone
	phone.populate(contacts,options,receipts,phone_contact,int(state.revision),reading_scale)
	if not hint.is_empty(): words(hint,783,585,442,74,16)

func _make_phone_desk() -> PhoneDesk:
	var phone := PhoneDesk.new()
	phone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phone.selected_contact.connect(func(actor:String)->void: phone_contact=actor)
	phone.confirm_order.connect(func(actor:String,id:String,command:String,revision:int)->void:
		var view: Dictionary = session.alpha_view()
		if view.phase!="EVENING_WORK" or revision!=int(session.snapshot().revision) or not view.get("outbound_options",[]).any(func(now:Dictionary)->bool:return now.id==id and now.actor==actor and now.command==command):
			hint="의뢰 조건이 바뀌었습니다. 전표를 다시 확인하세요."
			refresh()
			return
		hint=""
		_submit(command,{"request_id":id}))
	return phone

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
	if r2_review_mode:
		_board_line(pages,"past_appraisal_heading","당시의 제안과 내 판단",true)
		if past.is_empty(): _board_line(pages,"empty_appraisal","이전 제안 기록이 없습니다.")
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
			_board_line(pages,"past_fact",_text("b2.inspect."+str(fact.slot))+" · "+_fact_caption(fact.slot,fact.value)+(" · "+("현재 유효" if fact.current else "이전 관찰") if fact.has("current") else ""))
	for work: Dictionary in history.get("work_records",[]):
		var action_name := str(work.kind)
		var title: String = {"attach":"구성품 결합","detach":"구성품 분리","restore_item":"재생·정비 작업","discard":"폐기"}.get(action_name,"구성 또는 정비")
		var related := str(work.get("related_item_id",""))
		var names := _receipt_items(session.snapshot(),[related]) if not related.is_empty() else ""
		_board_line(pages,"work_"+str(work.event_id),"작업 기록 · "+title+(" · "+names if not names.is_empty() else ""))
		if work.has("expense"): _board_line(pages,"work_cost","정비 비용 · %s VKC / %s USD"%[work.expense.VKC,work.expense.USD])
		if work.has("group_size"): _board_line(pages,"work_loss","폐기 %d개 · "%work.group_size+("%s VKC 손실"%work.loss.VKC if work.loss is Dictionary else "묶음 원가 손실"))
	if r2_review_mode:
		_board_line(pages,"claim_boundary","미확인 주장",true)
		_board_line(pages,"claim_data","현재 물품 이력에는 확인되지 않은 주장 기록이 제공되지 않습니다.")
	if int(history.get("omitted",0))>0: _board_line(pages,"older","이전 거래는 전체 장부에서 확인")
	if int(history.get("work_omitted",0))>0: _board_line(pages,"older_work","이전 작업 기록 일부 생략")

func _receipt_items(state: Dictionary, roots: Array) -> String:
	var names := PackedStringArray()
	for id: String in roots:
		var item: Dictionary = state.items.get(id,state.get("tombstones",{}).get(id,{}))
		if item.has("def_id"): names.append(_text("b2.item."+str(item.def_id)))
	return ", ".join(names)

func _workspace_action(id: String,caption: String,rect: Rect2,callback: Callable) -> Button:
	if not r2_review_mode:
		return action(id,caption,rect.position.x,rect.position.y,rect.size.x,rect.size.y,callback)
	var button := workspaces.button(interaction,id,rect,caption,callback)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size",roundi(16.0*reading_scale/100.0))
	return button

func _queue_inventory_drop(kind: String,destination: Variant,data: Variant) -> void:
	if not data is Dictionary or data.get("item")!=selected or not inventory_drop.is_empty(): return
	var state: Dictionary = session.snapshot()
	var item: Dictionary = state.items.get(selected,{})
	if item.is_empty() or item.inventory!=data.get("origin"): return
	inventory_drop = {"kind":kind,"value":destination,"item":selected,"revision":state.revision,"storage":storage}
	_flush_inventory_drop.call_deferred()

func _flush_inventory_drop() -> void:
	if inventory_drop.is_empty() or get_viewport().gui_is_dragging(): return
	var drop := inventory_drop
	inventory_drop = {}
	if _blocked or _leaving_title or drawer!="stock" or selected!=drop.item or storage!=drop.storage: return
	if session.snapshot().revision!=drop.revision: return
	match str(drop.kind):
		"cell":
			_place_selection(drop.value)
		"tab":
			storage = str(drop.value)
			draft.clear()
			refresh()
		"attach":
			var payload: Dictionary = drop.value
			selected = str(payload.root_id)
			_preview("spatial_attach",payload)

func _inventory_cell_valid(data: Variant) -> bool:
	return data is Dictionary and data.get("item")==selected

func _inventory_grid_art(s: Dictionary) -> void:
	if not r2_review_mode: return
	var grid: Dictionary = s.inventories.get(storage,{})
	if grid.is_empty(): return
	var cell := minf(64,630.0/float(grid.width))
	var bed := paper(69,152,grid.width*cell+13,grid.height*cell+14,Color("#272720"))
	bed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var detail := paper(730,145,507,530,Color("#3c342be8"))
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _inventory_sprite(parent: Control,texture: Texture2D,bounds: Vector2,turned: bool) -> void:
	var sprite := parent.get_node_or_null("ItemArt") as Sprite2D
	if not sprite:
		sprite = Sprite2D.new()
		sprite.name = "ItemArt"
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		parent.add_child(sprite)
	sprite.texture = texture
	if not texture: return
	var art_size := texture.get_size()
	if turned: art_size = Vector2(art_size.y,art_size.x)
	var capacity := (bounds-Vector2(10,10)).max(Vector2.ONE)
	sprite.scale = Vector2.ONE*minf(capacity.x/art_size.x,capacity.y/art_size.y)
	sprite.position = bounds*0.5
	sprite.rotation = PI*0.5 if turned else 0.0

func _inventory(v: Dictionary,s: Dictionary) -> void:
	_inventory_grid_art(s)
	placement_hint = words("",76,122,640,36,16)
	var grids := ["player_stock","storefront_grid","service_grid","pawn_grid"]
	var titles := ["창고","외부 매대","수탁 보관","담보 보관"]
	for n: int in range(grids.size()):
		var destination: String = grids[n]
		if s.inventories.has(destination):
			var tab := _workspace_action("tab_"+destination,titles[n],Rect2(76+n*165,77,152,44),func()->void:
				draft.clear()
				storage = destination
				refresh())
			if r2_review_mode or destination==storage: _paper_face(tab,destination==storage)
			if destination==storage: tab.text = "▸ "+titles[n]
			tab.set_drag_forwarding(Callable(),func(_at:Vector2,data:Variant)->bool:
				return _inventory_cell_valid(data),func(_at:Vector2,data:Variant)->void:
				if r2_review_mode:
					_queue_inventory_drop("tab",destination,data)
				else:
					storage = destination
					draft.clear()
					refresh())
	var spec: Dictionary = s.inventories[storage]
	var cell := minf(64,630.0/float(spec.width))
	for y: int in range(int(spec.height)):
		for x: int in range(int(spec.width)):
			var target := Vector2i(x,y)
			var button := _workspace_action("cell_%d_%d"%[x,y],"",Rect2(76+x*cell,160+y*cell,cell-2,cell-2),func()->void: _place_selection(target))
			if not button.has_meta("inventory_hover"):
				button.set_meta("inventory_hover",true)
				button.mouse_entered.connect(func()->void: _hover_inventory_cell(target))
				button.mouse_exited.connect(_clear_hover)
			button.set_drag_forwarding(Callable(),func(_at:Vector2,data:Variant)->bool:
				if not _inventory_cell_valid(data): return false
				if r2_review_mode: _hover_inventory_cell(target)
				return true,func(_at:Vector2,data:Variant)->void:
					if r2_review_mode: _queue_inventory_drop("cell",target,data)
					else: _place_selection(target))
	for id: String in s.items:
		var item: Dictionary = s.items[id]
		if item.inventory != storage or not item.parent_id.is_empty(): continue
		var dims: Array = session.spatial_dimensions(id)
		var w := int(dims[1] if item.rotated else dims[0])
		var h := int(dims[0] if item.rotated else dims[1])
		var token := _workspace_action("stock_"+id,"",Rect2(76+item.x*cell,160+item.y*cell,cell*w-2,cell*h-2),func()->void:
			draft.clear()
			selected = id
			rotated = item.rotated
			refresh())
		if r2_review_mode or id==selected: _paper_face(token,id==selected)
		var texture: Texture2D = Art.ITEMS.model_texture(str(item.def_id),"stock",id)
		token.icon = null if r2_review_mode else texture
		if r2_review_mode: _inventory_sprite(token,texture,token.size,item.rotated)
		motion_subjects["stock_"+id] = token
		token.expand_icon = true
		token.tooltip_text = _text("b2.item."+str(item.def_id))
		if texture == null: token.text = token.tooltip_text
		token.set_drag_forwarding(func(_at:Vector2)->Variant:
			draft.clear()
			selected = id
			rotated = item.rotated
			drag_origin = token
			token.self_modulate = Color(1,1,1,0.42)
			var bounds := token.size*stage.scale
			if r2_review_mode:
				var preview := Control.new()
				preview.size = bounds
				preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_inventory_sprite(preview,texture,bounds,rotated)
				token.set_drag_preview(preview)
				inventory_drag_preview = preview
			else:
				var preview := TextureRect.new()
				preview.texture = texture
				preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				preview.custom_minimum_size = bounds
				preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
				token.set_drag_preview(preview)
			return {"item":id,"origin":item.inventory},func(at:Vector2,data:Variant)->bool:
				if not r2_review_mode or not _inventory_cell_valid(data): return false
				_hover_inventory_cell(Vector2i(item.x,item.y)+Vector2i((at/cell).floor()))
				return true,func(at:Vector2,data:Variant)->void:
					_queue_inventory_drop("cell",Vector2i(item.x,item.y)+Vector2i((at/cell).floor()),data))
	if r2_review_mode:
		words("%d×%d 보관 격자"%[spec.width,spec.height],76,557,642,34,16)
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
	if r2_review_mode:
		var occupied := 0
		for id: String in s.items:
			var row: Dictionary = s.items[id]
			if row.inventory!=storage or not str(row.parent_id).is_empty(): continue
			var footprint: Array = session.spatial_dimensions(id)
			if footprint.size()==2: occupied += int(footprint[0])*int(footprint[1])
		words("사용 %d / %d칸 · 거래 이력 %d건"%[occupied,int(spec.width)*int(spec.height),history.records.size()+int(history.omitted)],76,596,642,34,16)
		words(condition,76,634,642,35,16)
	else:
		words(condition+"   /   거래 이력 %d건"%(history.records.size()+int(history.omitted)),76,560,642,42,16)
	words(_text("b2.item."+str(item.def_id)),746,152,434,54)
	motion_subjects["work"] = pic(Art.ITEMS.model_texture(str(item.def_id),"stock",selected),760,210,378,99)
	if item.owner_id=="player":
		words(_text("spatial.basis") % [str(item.basis.VKC) if item.basis.VKC!=null else "?",str(item.basis.USD) if item.basis.USD!=null else "?"],746,309,420,38,17)
	var permission := _text("spatial.locked") if not str(item.reservation_id).is_empty() else ("보호품" if item.protected else "")
	words("소유 "+_actor_label(item.owner_id)+"  /  보관 "+_actor_label(item.custodian_id)+"  "+permission,747,350,435,47)
	_workspace_action("rotate","배치 방향 전환 · "+("90°" if rotated else "0°"),Rect2(746,406,400,44),func()->void:
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
		if draft.kind=="spatial_discard":
			var loss:Dictionary=session.discard_preview(selected)
			summary="영구 폐기 %d개 · 원가 %s VKC / %s USD 손실"%[pending.confirmed_ids.size(),str(loss.get("basis",{}).get("VKC","?")),str(loss.get("basis",{}).get("USD","?"))]
		var part_id := str(pending.get("child_id",""))
		if s.items.has(part_id): summary += " · "+_text("b2.item."+str(s.items[part_id].def_id))
		words(summary,746,455,445,38)
		if r2_review_mode:
			var difference := _inventory_difference(s,pending)
			if not difference.is_empty(): words(difference,746,497,475,65,16)
			_draft_controls(746,568,"confirm_work")
		else:
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
		var tray: WorkTray
		if r2_review_mode:
			tray = workspaces.mount(interaction,"r2_work_tray",Rect2(746,459,457,158),func()->Control:return WorkTray.new()) as WorkTray
		else:
			tray = WorkTray.new()
			place(tray,746,459,420,150)
		var composition: Dictionary = session.composition_options(root_id,"player_stock")
		var restore: Dictionary = composition.get("restore_cost",{}) if r2_review_mode else {}
		tray.populate(root_id,composition,s.items,Art.ITEMS,desk_copy,_text,func(kind:String,payload:Dictionary)->void:
			selected = root_id
			_preview(kind,payload),restore,func(payload:Dictionary,data:Variant)->void:
				if r2_review_mode: _queue_inventory_drop("attach",payload,data)
				else:
					selected = root_id
					_preview("spatial_attach",payload))
	if draft.is_empty() and v.phase=="EVENING_WORK" and item.status=="custody_service":
		for job: Dictionary in v.services.entries:
			if job.get("item_id")==selected and job.can_repair:
				action("b2_service_repair",_text("b2.service.repair"),746,459,420,52,func()->void:
					_preview("alpha_service_repair",{"job_id":job.job_id,"item_id":selected}))
	_workspace_action("item_history","물품 이력",Rect2(746,630 if r2_review_mode else 611,212,44),func()->void:open_drawer("item_history")).visible = not r2_review_mode or draft.is_empty()
	if draft.is_empty() and v.phase=="EVENING_WORK" and item.inventory=="player_stock" and s.alpha_shop.profile.has("f3_composite_trial"):
		var disposal:Dictionary=session.alpha_discard_preview(selected)
		if not disposal.is_empty():
			_workspace_action("f3_discard","물품 폐기",Rect2(966,630 if r2_review_mode else 611,212,44),func()->void:_preview("spatial_discard",disposal.payload))
	if not _message.is_empty(): words(_visible_notice(),74,645 if r2_review_mode else 608,650,55,16)

func _inventory_difference(state: Dictionary,pending: Dictionary) -> String:
	var item: Dictionary = state.items.get(selected,{})
	if item.is_empty(): return ""
	if draft.kind in ["alpha_display","alpha_withdraw_display","spatial_move"]:
		var shelves := {"player_stock":"창고","storefront_grid":"외부 매대","service_grid":"수탁 보관","pawn_grid":"담보 보관"}
		var names := "%s → %s"%[shelves.get(item.inventory,"현재 보관함"),shelves.get(storage,"대상 보관함")]
		return names+" · %d행 %d열"%[int(pending.y)+1,int(pending.x)+1]+(" · 90°" if bool(pending.rotated) else " · 0°")
	var part_id := str(pending.get("child_id",""))
	if not part_id.is_empty():
		var title := _receipt_items(state,[part_id])
		if draft.kind=="spatial_attach": return title+"   /   별도 보관 → 본체에 결합"
		if draft.kind=="spatial_detach": return title+"   /   본체 → 창고 %d행 %d열"%[int(pending.y)+1,int(pending.x)+1]
	if draft.kind=="alpha_service_repair":
		return "정비 전 → 정비 완료\n소유권과 수탁 보관은 그대로입니다."
	return "작업 후 상태는 확정하면 기록됩니다."

func _hover_inventory_cell(target: Vector2i) -> void:
	if drawer!="stock": return
	var spec: Dictionary = session.snapshot().inventories.get(storage,{})
	if spec.is_empty(): return
	_hover_cell(target,spec,minf(64,630.0/float(spec.width)))

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
	hover_ticket = ""
	if is_instance_valid(placement_hint): placement_hint.text = ""
	if is_instance_valid(hover_ghost):
		hover_ghost.hide()
		hover_ghost.queue_free()
	hover_ghost = null

func _hover_cell(target: Vector2i,spec: Dictionary,cell: float) -> void:
	var key := "%s/%s/%s/%s"%[storage,selected,target,rotated]
	if r2_review_mode and key==hover_ticket and is_instance_valid(hover_ghost): return
	_clear_hover()
	if selected.is_empty() or not draft.is_empty(): return
	var plan := _placement(target)
	if plan.is_empty(): return
	hover_ticket = key
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
		"spatial_discard": return "영구 폐기"
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
	elif drawer=="phone" and is_instance_valid(phone_view) and phone_view.is_inside_tree() and not str(phone_view.get("preview")).is_empty():
		phone_view.set("preview","")
		phone_view.call("show_sheet")
		return true
	elif (drawer.is_empty() or (r2_room_active and drawer=="notes")) and zoom and not chosen_tool.is_empty():
		chosen_tool = ""
		if r2_room_active: lens_open = false
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
	if get_viewport().gui_get_focus_owner() is LineEdit and event.keycode!=KEY_ESCAPE: return
	if event.keycode == KEY_ESCAPE:
		if not _cancel_local(): return
	elif event.keycode == KEY_R and drawer=="stock" and not selected.is_empty():
		rotated = not rotated
		draft.clear()
		if r2_review_mode and get_viewport().gui_is_dragging() and is_instance_valid(inventory_drag_preview):
			var previous := inventory_drag_preview.size
			inventory_drag_preview.size = Vector2(previous.y,previous.x)
			var image := inventory_drag_preview.get_node("ItemArt") as Sprite2D
			_inventory_sprite(inventory_drag_preview,image.texture,inventory_drag_preview.size,rotated)
			_clear_hover()
			get_viewport().set_input_as_handled()
			return
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
				var original_pose: bool = r2_room_active and previous_actor==r2_layers.get("visitor")
				var departing := pic(previous_actor,470 if original_pose else 525,112 if original_pose else 70,340 if original_pose else 260,314 if original_pose else 395,original_pose)
				departing.reparent(scenery,false)
				var foreground := scenery.get_node_or_null("r2_counter")
				scenery.move_child(departing,foreground.get_index() if foreground else mini(2,scenery.get_child_count()-1))
				var leave := departing.create_tween().set_parallel(true)
				leave.tween_property(departing,"position:x",departing.position.x-53,0.38)
				leave.tween_property(departing,"modulate:a",0.0,0.38)
				leave.chain().tween_callback(departing.queue_free)
		"alpha_trade":
			if previous_item:
				var handed := pic(previous_item,492,350,290,124)
				var transfer := handed.create_tween().set_parallel(true)
				transfer.tween_property(handed,"position:y",396,0.28)
				transfer.tween_property(handed,"modulate:a",0.0,0.28)
				transfer.chain().tween_callback(handed.queue_free)
			if not r2_review_mode:
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

