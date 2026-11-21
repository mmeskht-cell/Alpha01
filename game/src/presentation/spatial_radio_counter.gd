extends Control
const PublicObservationText=preload("res://src/presentation/public_observation_text.gd")
const AppraisalVisuals=preload("res://src/presentation/public_appraisal_visuals.gd")
const ReferenceGuide=preload("res://src/presentation/public_reference_guide.gd")
const CivilianPrice=preload("res://src/domain/civilian_condition_price.gd")
## Public DTO only; same authority as the previously verified demo.
signal action_requested(kind:String,payload:Dictionary,revision:int)
signal inspect_stock_requested(item_id:String,revision:int)
signal basic_review_requested(visit_id:String,revision:int)
const DragSource=preload("res://src/presentation/generic_deck_drag.gd")
const DropTarget=preload("res://src/presentation/generic_deck_drop.gd")
const Notebook=preload("res://src/presentation/generic_appraisal_panel.gd")
const TOOL_NAMES:Dictionary={
	"wear_detail":["외관 확대경","Surface magnifier"],
	"casing_detail":["표식 관찰기","Mark reader"],
	"material_detail":["재질 관찰기","Material viewer"],
	"batch_detail":["생산 표식 관찰기","Batch reader"],
	"function_detail":["기능 시험기","Function tester"],
	"display_damage_detail":["표시창 확대경","Display magnifier"]
}
# Public geometric affordances, not specimen readings. The authority still
# checks the actual tool, target, active visit, time and identity.
const FRONT:Dictionary={
	"wear_detail":Rect2(0.06,0.74,0.46,0.23),
	"material_detail":Rect2(0.05,0.13,0.60,0.48),
	"display_damage_detail":Rect2(0.70,0.12,0.26,0.27),
	"function_detail":Rect2(0.70,0.50,0.26,0.44)
}
const BACK:Dictionary={
	"casing_detail":Rect2(0.04,0.10,0.25,0.73),
	"batch_detail":Rect2(0.32,0.29,0.48,0.33)
}
# Public geometric masks shared across specimen identities. Watch art is neutral.
const WATCH_FRONT:Dictionary={
	"wear_detail":Rect2(0.34,0.22,0.27,0.47),
	"material_detail":Rect2(0.23,0.22,0.10,0.47),
	"function_detail":Rect2(0.62,0.35,0.11,0.26)
}
const WATCH_BACK:Dictionary={
	"batch_detail":Rect2(0.38,0.27,0.22,0.41)
}
# Opt-in R001 art candidate; legacy scenes keep their existing textures and masks.
@export var preview_r001_pixel_art:bool=false
@export var preview_native_v23:bool=false
const NativeArt=preload("res://src/presentation/native_v23_art.gd")
const VisualProfile=preload("res://src/presentation/item_visual_profile.gd")
# Presentation resource can be replaced in Inspector or in the test scene.
@export var radio_visual_profile:VisualProfile=NativeArt.RADIO_PROFILE
const R001_PIXEL_FRONT=preload("res://assets/art/items/r001_pixel_front_candidate.png")
const R001_PIXEL_BACK=preload("res://assets/art/items/r001_pixel_back_candidate.png")
const R001_PIXEL_FRONT_REGIONS:Dictionary={
	"wear_detail":Rect2(0.07,0.79,0.44,0.16),
	"material_detail":Rect2(0.05,0.32,0.48,0.43),
	"display_damage_detail":Rect2(0.55,0.37,0.39,0.24),
	"function_detail":Rect2(0.57,0.65,0.37,0.25)
}
const R001_PIXEL_BACK_REGIONS:Dictionary={
	"casing_detail":Rect2(0.03,0.32,0.32,0.60),
	"batch_detail":Rect2(0.39,0.70,0.24,0.15)
}
var transitioning:bool=false
var _view:Dictionary={}
var _app:Dictionary={}
var _plain:bool=false
var _service:bool=false
var _tr:Callable
var _ko:bool=true
var _inspect:bool=false
var _visit:String=""
var _revision:int=-1
var _epoch:int=0
var _sent:bool=false
var _gaze:float=0.0
var _tween:Tween
var _back:bool=false
var _zoom:float=1.0
var _selected_tool:String=""
var _selected_card:String=""
var _hand_page:int=0
var _hand_slots:int=0
var _sheet_page:int=0
var _sheet_seen:int=-1
var _claim_page:int=0
var _claim_seen:int=-1
var _presentation_motion:bool=true
var _animate_presentation:bool=false
var _book_open:bool=false
var _book_clue:Control
var _checkout_open:bool=false
var _statements_open:bool=false
var _offer_draft:int=125
var _offer_count:int=-1
var _feedback:String=""
var _review_tool:String=""
var _native_window:TextureRect
var _native_cold:TextureRect
var _native_amber:TextureRect
var _native_lamp:TextureRect
var _native_index:int=-1
var _bg:TextureRect
var _npc:TextureRect
var _fg:TextureRect
var _mat:ColorRect
var _item:TextureRect
var _layer:Control
var _notebook:ScrollContainer
var _regions:Dictionary={}
var _tokens:Dictionary={}
var _layout:Dictionary={}

func _ready()->void:
	clip_contents=true
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	if preview_native_v23:
		_native_window=_texture(NativeArt.timed_texture("window",0),false)
		_native_window.hide()
	_bg=_texture(preload("res://assets/art/scenes/counter_pilot_bg.svg"),false)
	if preview_native_v23:
		_native_lamp=_texture(NativeArt.scene_texture("counter.lamp"),false)
		_native_lamp.hide()
	_npc=_texture(preload("res://assets/art/characters/g01_pilot.svg"),true)
	_fg=_texture(preload("res://assets/art/scenes/counter_pilot_fg.svg"),false)
	if preview_native_v23:
		_native_amber=_texture(NativeArt.scene_texture("counter.amber"),false)
		_native_cold=_texture(NativeArt.timed_texture("cold",0),false)
		_native_amber.hide()
		_native_cold.hide()
	_mat=ColorRect.new()
	_mat.color=Color("#33393B" if preview_native_v23 else "#303e35")
	_mat.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(_mat)
	_item=_texture(preload("res://assets/art/items/radio_face_probe_a.svg"),true)
	_layer=Control.new()
	_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_notebook=Notebook.new()
	_notebook.name="spatial_notebook"
	_notebook.z_index=4
	add_child(_notebook)
	_notebook.action_requested.connect(_book_action)
	_notebook.minimum_size_changed.connect(func()->void:
		if preview_native_v23 and _inspect and _book_open:
			_layout_scene.call_deferred())
	_notebook.hide()
	resized.connect(_layout_scene)
	resized.connect(_refresh_hand_capacity)
	_layout_scene()

func _texture(tex:Texture2D,aspect:bool)->TextureRect:
	var node:=TextureRect.new()
	node.texture=tex
	node.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED if aspect else TextureRect.STRETCH_SCALE
	node.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(node)
	return node

func word(ko:String,en:String)->String:
	return ko if _ko else en

func _label(key:String,arguments:Dictionary={})->String:
	if not _tr.is_valid():
		return key
	return str(_tr.call(key)) if arguments.is_empty() else str(_tr.call(key,arguments))

# The native renderer selects presentation capabilities from the public DTO.
# This never authorizes a visit, inspection, price, or card action.
static func supports_native_appraisal(app:Dictionary)->bool:
	return not ReferenceGuide.native_capability(app).is_empty()

func _is_watch()->bool:
	if preview_native_v23 and not _plain:
		return _app.get("catalog",{}).get("def_id","")=="fictional_watch_p2"
	return _app.get("visit_id","")=="watch_a"

func _uses_r001_pixel_art()->bool:
	return preview_r001_pixel_art and _app.get("visit_id","")=="visit_g01" and not _plain

func _uses_native_r001()->bool:
	return preview_native_v23 and _app.get("visit_id","")=="visit_g01" and not _plain

func _uses_native_room()->bool:
	return preview_native_v23 and not _visit.is_empty()

func _uses_native_counter_radio()->bool:
	return _uses_native_r001() or (preview_native_v23 and _plain and not _service and str(_view.get("trade",{}).get("item_id","")) in ["R001","R003"])

func _apply_native_room()->void:
	if not preview_native_v23:
		return
	var active:bool=_uses_native_room()
	for node:TextureRect in [_native_window,_native_lamp,_native_amber,_native_cold]:
		node.visible=active
	if active:
		_native_index=NativeArt.time_index(_view)
		_bg.texture=NativeArt.scene_texture("counter.room")
		_fg.texture=NativeArt.scene_texture("counter.foreground")
		_native_lamp.texture=NativeArt.scene_texture("counter.lamp")
		_native_amber.texture=NativeArt.scene_texture("counter.amber")
		_native_window.texture=NativeArt.timed_texture("window",_native_index)
		_native_cold.texture=NativeArt.timed_texture("cold",_native_index)
	else:
		_native_index=-1
		_bg.texture=preload("res://assets/art/scenes/counter_pilot_bg.svg")
		_fg.texture=preload("res://assets/art/scenes/counter_pilot_fg.svg")

func _single_view_items()->bool:
	return preview_native_v23 and not _plain

func _basic_tool_appraisal()->bool:
	return preview_native_v23 and _app.get("tools",{}).has("basic_function_v1")

func _radio_visual()->VisualProfile:
	if radio_visual_profile!=null and radio_visual_profile.valid():
		return radio_visual_profile
	return NativeArt.RADIO_PROFILE

func _face_regions()->Dictionary:
	if _uses_native_r001():
		return _radio_visual().regions
	if _single_view_items():
		var profile:VisualProfile=NativeArt.item_profile(str(_app.item_id),"inspection")
		# A missing display region remains an explicit off-image detail target,
		# not a fake hotspot or a missing authoritative tool.
		return profile.regions if profile!=null else {}
	if _uses_r001_pixel_art():
		return R001_PIXEL_BACK_REGIONS if _back else R001_PIXEL_FRONT_REGIONS
	if _is_watch():
		return WATCH_BACK if _back else WATCH_FRONT
	return BACK if _back else FRONT

# A small surface may have an honest visible crop while its actual tool
# action remains a separate accessible detail target.
func _visible_crop_regions()->Dictionary:
	var regions:Dictionary=_face_regions().duplicate()
	if not _single_view_items():
		return regions
	var profile:VisualProfile=_radio_visual() if _uses_native_r001() else NativeArt.item_profile(str(_app.get("item_id","")),"inspection")
	if profile!=null and profile.valid(false):
		regions.merge(profile.crop_regions,true)
	return regions

func _customer_id()->String:
	if preview_native_v23 and not _plain:
		var terms:Dictionary=_view.get("visits",{}).get("terms",{})
		var customer:String=str(terms.get("customer",""))
		if not customer.is_empty() and str(terms.get("item_id",""))==str(_app.get("item_id","")):
			return customer
	if _basic_tool_appraisal():
		return str(_view.get("visits",{}).get("terms",{}).get("customer",""))
	if _service:
		return str(_view.visits.terms.customer)
	if _app.get("visit_id","")=="radio_return":
		return "G02"
	if _app.get("visit_id","")=="radio3_buy":
		return "G10"
	if _plain:
		var trade:Dictionary=_view.get("trade",{})
		return str(trade.get("seller","")) if trade.get("buyer")=="player" else str(trade.get("buyer",""))
	return "G04" if _is_watch() else "G01"

# Proven prior player transactions only. This is not a trust or identity score.
func _previous_trade_copy()->String:
	var memory:Dictionary=_view.get("customer_memory",{})
	if memory.is_empty():
		return ""
	return _label("history.customer.previous_trade",{"count":str(memory.trades),"day":str(memory.last_day)})

func _tool_title(id:String)->String:
	if preview_native_v23:
		var capability:Dictionary=ReferenceGuide.native_capability(_app)
		var title:String=str(capability.get("tools",{}).get(id,{}).get("title",""))
		if not title.is_empty():
			return _label(title)
	if id=="basic_function_v1":
		return _label(str(_app.tools[id].text_key))
	if _is_watch() and id=="batch_detail":
		return _label("ui.copy.back_mark_reader_3f7e5eab")
	return _label("ui.tool."+id) if TOOL_NAMES.has(id) else _label("ui.tool.unknown")

func _rect(node:Control,r:Rect2)->void:
	node.position=r.position
	node.size=r.size

func _relative(r:Rect2)->Rect2:
	return Rect2(r.position*size,r.size*size)

func _fit(r:Rect2,ratio:float)->Rect2:
	var width:float=minf(r.size.x,r.size.y*ratio)
	var height:float=width/ratio
	return Rect2(r.get_center()-Vector2(width,height)*0.5,Vector2(width,height))

func _layout_scene()->void:
	if not is_instance_valid(_bg):
		return
	_rect(_bg,_relative(Rect2(0.0,-0.66*_gaze,1.0,1.0+0.7*_gaze)))
	_rect(_npc,_relative(Rect2(0.34,0.04-0.78*_gaze,0.32,0.60)))
	if _uses_native_r001():
		_rect(_npc,_relative(Rect2(264.0/640.0,46.0/360.0-0.78*_gaze,144.0/640.0,192.0/360.0)))
	if _uses_native_room():
		_rect(_native_window,Rect2(_bg.position,_bg.size))
		_rect(_native_lamp,Rect2(_bg.position,_bg.size))
		_native_amber.modulate.a=1.0-_gaze
		_native_cold.modulate.a=1.0-_gaze
	_npc.modulate.a=1.0-_gaze
	_rect(_fg,_relative(Rect2(0.0,-0.80*_gaze,1.0,1.0+0.8*_gaze)))
	if _uses_native_room():
		_rect(_native_amber,Rect2(_fg.position,_fg.size))
		_rect(_native_cold,Rect2(_fg.position,_fg.size))
	var mat:Rect2=_relative(Rect2(0.24,0.12,0.72,0.69))
	_rect(_mat,mat)
	_mat.modulate.a=_gaze
	var aspect:float=4.0/3.0 if (_uses_native_counter_radio() or _uses_r001_pixel_art()) else 1.92
	if preview_native_v23 and _item.texture!=null and _item.texture.get_height()>0:
		aspect=float(_item.texture.get_width())/float(_item.texture.get_height())
	var up:Rect2=_fit(_relative(Rect2(0.34,0.56,0.32,0.23)),aspect)
	if _uses_native_counter_radio():
		# Above the hand: 214+72 < 360*0.80. Keep the full physical sprite visible.
		up=_fit(_relative(Rect2(281.0/640.0,214.0/360.0,96.0/640.0,72.0/360.0)),aspect)
	var down:Rect2=_fit(_relative(Rect2(0.27,0.16,0.67,0.54)),aspect)
	if preview_native_v23 and _inspect and not _book_open and not _current_review_tool().is_empty():
		down=_fit(_relative(Rect2(0.25,0.17,0.36,0.54)),aspect)
	if _book_open and _inspect:
		var book_item:=Rect2(0.24,0.19,0.21,0.40) if preview_native_v23 else Rect2(0.25,0.21,0.35,0.40)
		if preview_native_v23 and is_instance_valid(_book_clue):
			# Reserve an independent comparison specimen area. At maximum zoom
			# the item still stays outside the notebook and clue.
			book_item=Rect2(0.265,0.17,0.19,0.32)
		down=_fit(_relative(book_item),aspect)
	down=Rect2(down.get_center()-down.size*_zoom*0.5,down.size*_zoom)
	_rect(_item,Rect2(up.position.lerp(down.position,_gaze),up.size.lerp(down.size,_gaze)))
	for node:Control in _layout:
		if is_instance_valid(node):
			_rect(node,_relative(_layout[node]))
	for id:String in _regions:
		var target:Control=_regions[id]
		if is_instance_valid(target):
			var raw:Rect2=_face_regions()[id]
			_rect(target,Rect2(_item.position+raw.position*_item.size,raw.size*_item.size))
	_rect(_notebook,_relative((Rect2(0.49,0.15,0.50,0.82) if preview_native_v23 else Rect2(0.60,0.04,0.39,0.70)) if _inspect else (Rect2(0.06,0.04,0.83,0.91) if preview_native_v23 else Rect2(0.11,0.06,0.78,0.72))))

func _set_gaze(value:float)->void:
	_gaze=value
	_layout_scene()

func clear_visit()->void:
	_visit=""
	_plain=false
	_service=false
	_app.clear()
	_view.clear()
	_apply_native_room()
	if _tween!=null and _tween.is_valid():
		_tween.kill()
	transitioning=false
	if is_instance_valid(_notebook):
		_notebook.hide()

func configure(view:Dictionary,inspect:bool,translator:Callable,locale:String,motion:bool)->void:
	if not is_instance_valid(_layer):
		return
	var app:Dictionary=view.get("appraisal",{})
	if app.is_empty():
		clear_visit()
		return
	# Entering a scoped appraisal from a plain offer is also a new session,
	# even when the visit ID already matches. Never carry another seller’s draft.
	var changed:bool=_plain or _app.is_empty() or _visit!=app.visit_id or _app.get("item_id","")!=app.item_id
	_plain=false
	_service=false
	var switch:bool=not changed and _inspect!=inspect
	_presentation_motion=motion
	_animate_presentation=not changed and not inspect and not _app.is_empty() and app.deck.presented.size()>_app.deck.presented.size()
	if changed:
		_visit=app.visit_id
		_back=false
		_zoom=1.0
		_selected_tool=""
		_selected_card=""
		_hand_page=0
		_sheet_page=0
		_sheet_seen=-1
		_claim_page=0
		_claim_seen=-1
		_book_open=false
		_checkout_open=false
		_statements_open=false
		_offer_count=-1
		_feedback=""
		_review_tool=""
	if changed or _offer_count!=app.price_offer.offers.size():
		_offer_count=app.price_offer.offers.size()
		_offer_draft=int(app.price_offer.asking) if _offer_count==0 else int(app.price_offer.offers.back().amount)
	_view=view.duplicate(true)
	_app=app.duplicate(true)
	_revision=int(view.revision)
	_tr=translator
	_ko=locale=="ko"
	_inspect=inspect
	if _tween!=null and _tween.is_valid():
		_tween.kill()
	transitioning=false
	if switch and motion:
		transitioning=true
		_layer.hide()
		_notebook.hide()
		_tween=create_tween()
		_tween.tween_method(_set_gaze,_gaze,1.0 if inspect else 0.0,0.34).set_trans(Tween.TRANS_SINE)
		_tween.tween_callback(func()->void:
			transitioning=false
			_build())
	else:
		_gaze=1.0 if _inspect else 0.0
		_build()

# Ordinary fixed-price trade has no appraisal profile. Do not synthesize
# evidence, negotiation or a new authority command for these commodities.
func configure_plain(view:Dictionary,translator:Callable,locale:String)->void:
	var trade:Dictionary=view.get("trade",{})
	if trade.is_empty() or not is_instance_valid(_layer):
		clear_visit()
		return
	_configure_non_appraisal(view,str(trade.visit_id),translator,locale,false)

func configure_service(view:Dictionary,translator:Callable,locale:String)->void:
	if not is_instance_valid(_layer) or not str(view.get("visits",{}).get("terms",{}).get("kind","")).begins_with("service_"):
		clear_visit()
		return
	_configure_non_appraisal(view,str(view.visits.active),translator,locale,true)

func _configure_non_appraisal(view:Dictionary,visit_id:String,translator:Callable,locale:String,service:bool)->void:
	if _tween!=null and _tween.is_valid():
		_tween.kill()
	transitioning=false
	_plain=true
	_service=service
	_visit=visit_id
	_view=view.duplicate(true)
	_app.clear()
	_offer_count=-1
	_offer_draft=int(view.get("trade",{}).get("amount",0))
	_hand_page=0
	_sheet_page=0
	_sheet_seen=-1
	_feedback=""
	_review_tool=""
	_revision=int(view.revision)
	_tr=translator
	_ko=locale=="ko"
	_inspect=false
	_gaze=0.0
	_back=false
	_zoom=1.0
	_book_open=false
	_checkout_open=false
	_statements_open=false
	_selected_tool=""
	_selected_card=""
	_build()

func _region_node(node:Control,r:Rect2)->void:
	_layer.add_child(node)
	_layout[node]=r

func _paper(button:Button)->void:
	for mode:String in ["normal","hover","pressed"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("#C4C0B2" if preview_native_v23 else "#d8cdb1") if mode=="normal" else Color("#D5D0C3" if preview_native_v23 else "#f0e2bf")
		style.border_color=Color("#857354")
		style.set_border_width_all(2)
		button.add_theme_stylebox_override(mode,style)
	for key:String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		button.add_theme_color_override(key,Color("#252A2D" if preview_native_v23 else "#292d25"))

func _text(value:String,align:HorizontalAlignment=HORIZONTAL_ALIGNMENT_LEFT)->Label:
	var node:=Label.new()
	node.text=value
	node.horizontal_alignment=align
	node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return node

func _button(parent:Control,id:String,label:String,callback:Callable,disabled:bool=false)->Button:
	var b:=Button.new()
	b.name=id
	b.text=label
	b.custom_minimum_size.y=48
	b.disabled=disabled
	parent.add_child(b)
	var epoch:int=_epoch
	b.pressed.connect(func()->void:
		if epoch==_epoch and not transitioning and not _sent and not b.disabled:
			callback.call())
	return b

func _payload(fields:Dictionary)->Dictionary:
	var p:Dictionary={"visit_id":_app.visit_id,"item_id":_app.item_id}
	p.merge(fields)
	return p

func _emit(kind:String,payload:Dictionary)->void:
	if _sent or transitioning or _view.get("locked",true) or (_app.is_empty() and not _plain):
		return
	_sent=true
	action_requested.emit(kind,payload,_revision)

func _book_action(kind:String,payload:Dictionary,revision:int)->void:
	if revision==_revision:
		_emit(kind,payload)

func _known(id:String)->bool:
	if not _app.tools.has(id):
		return false
	for fact:Dictionary in _app.evidence:
		if fact.current and not fact.is_claim and fact.observation_key==_app.tools[id].evidence_id:
			return true
	return false

func _apply_tool(id:String,region:String)->void:
	if id.is_empty() or id!=region or not _app.tools.has(id) or _known(id):
		_feedback=_label("ui.copy.choose_the_appropriate_region_for_the_selec_b6c2d1e5")
		_build()
		return
	_feedback=""
	_selected_tool=""
	_review_tool=id
	_emit("inspect_subject",_payload({"tool_id":id,"target":_app.tools[id].target}))

func _token_valid(data:Variant,id:String,kind:String)->bool:
	return data is Dictionary and not transitioning and not _sent and data.get("kind")==kind and data.get("id")==id and _tokens.get(kind+":"+id,{})==data

func _build()->void:
	if _app.is_empty() and not _plain:
		return
	_epoch+=1
	_sent=false
	_tokens.clear()
	_regions.clear()
	_layout.clear()
	_book_clue=null
	for child:Node in _layer.get_children():
		_layer.remove_child(child)
		child.queue_free()
	_layer.show()
	_apply_native_room()
	if _plain:
		if _service:
			_build_service()
		else:
			_build_plain()
		_layout_scene()
		return
	if preview_native_v23:
		var id:String=str(_app.item_id)
		var role:String="inspection" if _inspect else "counter"
		var profile:VisualProfile=NativeArt.item_profile(id,role)
		if _uses_native_r001() and _inspect:
			profile=_radio_visual()
		# Public presentation descriptor selects the role, not the item type.
		# Preserve the opening radio dedicated counter sprite exception.
		var capability:Dictionary=ReferenceGuide.native_capability(_app)
		if not _uses_native_r001() and not _inspect and capability.get("counter_role")=="inspection":
			profile=NativeArt.item_profile(id,"inspection")
		_item.texture=profile.texture if profile!=null else null
		var customer_id:String=_customer_id()
		_npc.texture=NativeArt.scene_texture("customer.opening" if customer_id=="G01" else ("customer.watch" if customer_id=="G04" else "customer.neutral"))
	elif _is_watch():
		_item.texture=preload("res://assets/art/items/watch_spatial_back_pilot.svg") if _inspect and _back and not _single_view_items() else preload("res://assets/art/items/watch_spatial_face_pilot.svg")
		_npc.texture=preload("res://assets/art/characters/g04_pilot.svg")
	else:
		if _uses_r001_pixel_art():
			_item.texture=R001_PIXEL_BACK if _inspect and _back else R001_PIXEL_FRONT
		else:
			_item.texture=preload("res://assets/art/items/radio_spatial_back_pilot.svg") if _inspect and _back and not _single_view_items() else preload("res://assets/art/items/radio_face_probe_a.svg")
		_npc.texture=preload("res://assets/art/characters/visitor_neutral_pilot.svg") if _app.visit_id in ["radio_return","radio3_buy"] else preload("res://assets/art/characters/g01_pilot.svg")
	_notebook.hide()
	if _inspect:
		_build_inspection()
	else:
		_build_customer()
	_layout_scene()

func _ordinary_item_art(id:String)->Texture2D:
	if preview_native_v23:
		var profile:VisualProfile=NativeArt.item_profile(id,"counter")
		return profile.texture if profile!=null else null
	match id:
		"R001","R003":
			return preload("res://assets/art/items/radio_face_probe_a.svg")
		"WAT02":
			return preload("res://assets/art/items/watch_spatial_face_pilot.svg")
		"GE03":
			return preload("res://assets/art/items/fictional_gear_pilot.svg")
		"BAT02":
			return preload("res://assets/art/items/battery_counter_pilot.svg")
		"TL04":
			return preload("res://assets/art/items/tool_counter_pilot.svg")
		"HY05":
			return preload("res://assets/art/items/hygiene_counter_pilot.svg")
		_:
			return preload("res://assets/art/items/electronics_counter_pilot.svg")
	return null

func _build_plain()->void:
	var trade:Dictionary=_view.trade
	var id:String=trade.item_id
	var buying:bool=trade.buyer=="player"
	var quote:Dictionary=_view.get("condition_quote",{})
	_npc.texture=NativeArt.scene_texture("customer.neutral") if preview_native_v23 else preload("res://assets/art/characters/visitor_neutral_pilot.svg")
	_item.texture=_ordinary_item_art(id)
	_notebook.hide()
	var speech:=ColorRect.new()
	speech.name="spatial_speech_background"
	speech.color=Color("#2A3032" if preview_native_v23 else "#28312b")
	speech.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_region_node(speech,Rect2(0.68,0.10,0.31,0.23) if preview_native_v23 else Rect2(0.20,0.32,0.60,0.13))
	var caption:=_text(_customer_id()+": "+(_label("ui.copy.will_you_buy_this_item_dedc031b") if buying else _label("ui.copy.i_d_like_to_buy_this_item_91619a57")),HORIZONTAL_ALIGNMENT_CENTER)
	if not quote.is_empty():
		caption.text=_customer_id()+": "+_label("ui.condition."+str(quote.tier))
	# Authored public demand signals: no future firm bid or private state.
	if _view.get("alpha_playtest",false) and id=="TL06A" and buying:
		caption.text=_customer_id()+": "+word("현장 공구입니다. 수리반에서 찾는다는 얘긴 있지만 값은 미정입니다.","Field tool. Repair crews are asking, but no firm price.")
	elif _view.get("alpha_playtest",false) and id=="CR06" and buying:
		caption.text=_customer_id()+": "+word("고장 난 수신기입니다. 부품 상태는 직접 확인해 보세요.","A faulty receiver. Check its parts yourself.")
	var remembered:String=_previous_trade_copy()
	if not remembered.is_empty():
		caption.text+="
"+remembered
	caption.name="spatial_speech_text"
	caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART if preview_native_v23 else TextServer.AUTOWRAP_OFF
	caption.clip_text=true
	caption.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_region_node(caption,Rect2(0.69,0.11,0.29,0.21) if preview_native_v23 else Rect2(0.21,0.32,0.58,0.13))
	var label:=_text(_label(trade.label)+" · "+id,HORIZONTAL_ALIGNMENT_CENTER)
	label.name="spatial_trade_item"
	label.autowrap_mode=TextServer.AUTOWRAP_OFF
	label.clip_text=true
	_region_node(label,Rect2(0.20,0.80,0.44,0.10))
	var panel:=PanelContainer.new()
	panel.name="spatial_fixed_price_paper"
	_region_node(panel,Rect2(0.66,0.60,0.33,0.39))
	var controls:=VBoxContainer.new()
	panel.add_child(controls)
	var price_text:String=_label("inventory.format.offer_amount",{"amount":str(trade.amount),"currency":str(trade.currency)}) if quote.get("can_sell",true) else _label("ui.copy.no_confirmed_offer_8858b07c")
	var slip:Label=_text((_label("ui.copy.purchase_slip_3a9c7ac5") if buying else _label("ui.copy.sale_slip_eca790c8"))+" · "+price_text)
	slip.name="spatial_fixed_price_label"
	controls.add_child(slip)
	var affordable:bool=(not buying or int(_view.wallet.get(trade.currency,0))>=int(trade.amount)) and quote.get("buyer_can_pay",_view.get("trade_can_pay",true))
	if trade.placement.is_empty():
		controls.add_child(_text(_label("ui.copy.no_available_placement_e13e4384")))
	elif not affordable and quote.get("can_sell",true):
		controls.add_child(_text(_label("ui.copy.insufficient_cash_e996d3a2") if buying else _label("ui.copy.customer_cannot_pay_this_offer_917ad803")))
	if _view.get("basic_review_available",false):
		_button(controls,"spatial_basic_review",_label("review.basic.open"),func()->void:
			basic_review_requested.emit(_visit,_revision))
	if (not quote.is_empty() and quote.tier!="unavailable") or _view.get("basic_sale_review_id","")==id:
		_button(controls,"spatial_condition_inspect",_label("ui.copy.inspect_owned_item_1ce27160"),func()->void:
			inspect_stock_requested.emit(id,_revision))
	_button(controls,"spatial_fixed_confirm",_label("ui.copy.confirm_purchase_4f429f57") if buying else _label("ui.copy.confirm_sale_4f728d10"),func()->void:
		var payload:Dictionary=trade.duplicate(true)
		payload.erase("label")
		payload.erase("placement")
		payload.merge(trade.placement)
		_emit("trade",payload),trade.placement.is_empty() or not affordable or not quote.get("can_sell",true))
	var quality:Dictionary=_view.get("basic_sale_quality",{})
	if not buying and not quality.is_empty():
		var label_key:String="review.sale.working" if quality.observed_value=="serviceable" else "review.sale.inoperable"
		_button(controls,"spatial_sale_quality_confirm",_label(label_key),func()->void:
			var payload:Dictionary=trade.duplicate(true)
			payload.erase("label")
			payload.erase("placement")
			payload.merge(trade.placement)
			payload["sale_quality_evidence_id"]=quality.evidence_id
			_emit("trade",payload),trade.placement.is_empty() or not affordable or not quote.get("can_sell",true))
	_button(controls,"spatial_fixed_decline",_label("ui.copy.decline_19995241"),func()->void:
		_emit("calendar_decline_visit",{"visit_id":_visit}))

# The service contract is distinct from owned stock. Its status and fee
# come solely from the public service terms, and authority controls payment.
func _build_service()->void:
	var terms:Dictionary=_view.visits.terms
	var accepting:bool=terms.kind=="service_offer"
	var complete:bool=terms.status=="complete"
	_npc.texture=NativeArt.scene_texture("customer.neutral") if preview_native_v23 else preload("res://assets/art/characters/visitor_neutral_pilot.svg")
	_item.texture=_ordinary_item_art(str(terms.item_id)) if preview_native_v23 else preload("res://assets/art/items/fictional_gear_pilot.svg")
	_notebook.hide()
	var speech:=ColorRect.new()
	speech.name="spatial_speech_background"
	speech.color=Color("#2A3032" if preview_native_v23 else "#28312b")
	speech.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_region_node(speech,Rect2(0.68,0.10,0.31,0.23) if preview_native_v23 else Rect2(0.20,0.32,0.60,0.13))
	var caption:=_text(_customer_id()+": "+(_label("ui.copy.i_d_like_this_serviced_7edcb5a2") if accepting else _label("ui.copy.i_m_here_to_collect_my_item_582aa83c")),HORIZONTAL_ALIGNMENT_CENTER)
	caption.name="spatial_speech_text"
	caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART if preview_native_v23 else TextServer.AUTOWRAP_OFF
	caption.clip_text=true
	caption.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_region_node(caption,Rect2(0.69,0.11,0.29,0.21) if preview_native_v23 else Rect2(0.21,0.32,0.58,0.13))
	var label:=_text(str(terms.item_id)+" · "+_label("ui.copy.customer_owned_service_item_f25dc339"),HORIZONTAL_ALIGNMENT_CENTER)
	label.name="spatial_service_custody"
	label.autowrap_mode=TextServer.AUTOWRAP_OFF
	label.clip_text=true
	_region_node(label,Rect2(0.15,0.80,0.50,0.10))
	var panel:=PanelContainer.new()
	panel.name="spatial_service_paper"
	_region_node(panel,Rect2(0.66,0.56,0.33,0.43))
	var controls:=VBoxContainer.new()
	panel.add_child(controls)
	var fee_text:=_text(_label("ui.format.service_fee",{"cost":_label("inventory.format.money_pair",{"vkc":str(terms.fee.VKC),"usd":str(terms.fee.USD)}) if int(terms.fee.USD)>0 else _label("inventory.format.offer_amount",{"amount":str(terms.fee.VKC),"currency":str("VKC")})}))
	fee_text.name="spatial_service_fee"
	controls.add_child(fee_text)
	if accepting:
		var cost:Dictionary=_view.get("service_cost_preview",{})
		var cost_text:=_text(_label("ui.service.unknown_cost") if cost.is_empty() else _label("ui.format.service_cost",{"cost":_label("inventory.format.money_pair",{"vkc":str(cost.VKC),"usd":str(cost.USD)}) if int(cost.USD)>0 else _label("inventory.format.offer_amount",{"amount":str(cost.VKC),"currency":str("VKC")})}))
		cost_text.name="spatial_service_cost"
		controls.add_child(cost_text)
	controls.add_child(_text(_label("ui.copy.new_request_b95fd718") if accepting else (_label("ui.copy.completed_return_after_check_fbd996e0") if complete else _label("ui.copy.work_incomplete_125702a0"))))
	var payload:Dictionary={"visit_id":_visit,"job_id":terms.job_id}
	if accepting:
		_button(controls,"spatial_service_accept",_label("ui.copy.accept_service_ad106ab3"),func()->void:
			_emit("calendar_accept_service",payload))
	else:
		_button(controls,"spatial_service_deliver",_label("ui.copy.return_and_collect_fee_68cab1a0"),func()->void:
			_emit("calendar_deliver_service",payload),not complete)
		_button(controls,"spatial_service_unpaid",_label("ui.copy.return_unpaid_460b2b55"),func()->void:
			_emit("calendar_return_unpaid",payload))
	_button(controls,"spatial_service_decline",_label("ui.copy.decline_visit_1b22e3e3"),func()->void:
		_emit("calendar_decline_visit",{"visit_id":_visit}))

func _detail_target(id:String)->Button:
	var target:=DropTarget.new()
	target.name="region_"+id
	target.text=_tool_title(id)+(" · "+_label("ui.copy.known_e7b32f47") if _known(id) else "")
	target.tooltip_text=(_tool_title(id)+" · "+_label("ui.copy.select_the_detail_target_above_the_item_4719621e")) if _visible_crop_regions().has(id) else _label("ui.copy.inspect_a_detail_not_shown_in_the_represent_cf021d06")
	target.custom_minimum_size.y=40
	target.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	target.disabled=_known(id)
	target.accepts=func(data:Variant)->bool:
		return _token_valid(data,id,"tool")
	target.commit=func(data:Variant)->void:
		_apply_tool(str(data.id),id)
	target.pressed.connect(func()->void:
		_apply_tool(_selected_tool,id))
	return target

# Visible masks retain their exact normalized geometry. Style never changes
# which observations are allowed or the underlying item condition.
func _native_target_style(target:Button,id:String)->void:
	var selected:bool=_selected_tool==id
	var known:bool=_known(id)
	var edge:Color=Color("#9BB2A5") if known else (Color("#D18A4F") if selected else Color("#C4B28B"))
	for mode:String in ["normal","hover","pressed","disabled"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color(0.08,0.10,0.11,0.70 if selected or mode=="hover" else 0.30)
		style.border_color=edge
		style.set_border_width_all(2 if selected or known else 1)
		target.add_theme_stylebox_override(mode,style)
	for key:String in ["font_color","font_hover_color","font_pressed_color","font_disabled_color","font_focus_color"]:
		target.add_theme_color_override(key,edge)
	target.add_theme_font_size_override("font_size",16)
	target.modulate.a=1.0

# Small original tool icons are presentation only, not a source of evidence.
var _tool_icons:Dictionary={}
func _tool_icon(id:String)->Texture2D:
	# Resource replacement takes priority over generated provisional icons.
	var replacement:Texture2D=NativeArt.tool_texture(id)
	if replacement!=null:
		return replacement
	if _tool_icons.has(id):
		return _tool_icons[id]
	var image:=Image.create(24,24,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var metal:=Color("#9CADA5")
	var dark:=Color("#4F605E")
	var amber:=Color("#C4B28B")
	if id in ["wear_detail","display_damage_detail","material_detail"]:
		for y:int in range(2,16):
			for x:int in range(2,16):
				var radius:float=Vector2(x-8,y-8).length()
				if radius>=4.5 and radius<=7:
					image.set_pixel(x,y,metal)
		for i:int in range(8):
			image.fill_rect(Rect2i(13+i,13+i,3,3),dark)
	else:
		image.fill_rect(Rect2i(4,3,16,18),dark)
		image.fill_rect(Rect2i(5,4,14,7),metal)
		image.fill_rect(Rect2i(7,6,10,3),Color("#283A38"))
		image.fill_rect(Rect2i(7,14,4,4),amber)
		image.fill_rect(Rect2i(13,14,4,4),metal)
	var texture:=ImageTexture.create_from_image(image)
	_tool_icons[id]=texture
	return texture

# Valid drag tokens identify a visual target only. Do not dispatch on pickup.
func _notification(what:int)->void:
	if not preview_native_v23 or not is_instance_valid(_layer) or not is_inside_tree():
		return
	if what==NOTIFICATION_DRAG_END:
		_clear_tool_drag_focus()
		_clear_card_drag_focus()
	elif what==NOTIFICATION_DRAG_BEGIN and not _plain:
		var data:Variant=get_viewport().gui_get_drag_data()
		if data is Dictionary:
			var id:String=str(data.get("id",""))
			if _inspect and data.get("kind")=="tool" and _token_valid(data,id,"tool"):
				_show_tool_drag_focus(id)
			elif not _inspect and data.get("kind")=="claim" and _token_valid(data,id,"claim"):
				_show_card_drag_focus(id)

# Only actionable public drop targets are lit. An offered claim need not
# be correct; the existing public rebuttal options govern the second target.
func _clear_card_drag_focus()->void:
	for target_name:String in ["spatial_customer_drop","counter_customer_claim"]:
		var target:=_layer.find_child(target_name,true,false) as Button
		if target==null:
			continue
		var outline:=target.get_node_or_null("card_drag_highlight")
		if outline!=null:
			target.remove_child(outline)
			outline.queue_free()

func _show_card_drag_focus(id:String)->void:
	_clear_card_drag_focus()
	if _app.deck.remaining_events<=0 or _app.deck.remaining_presentations<=0:
		return
	for target_name:String in ["spatial_customer_drop","counter_customer_claim"]:
		var target:=_layer.find_child(target_name,true,false) as Button
		if target==null or target.disabled:
			continue
		if target_name=="counter_customer_claim" and _rebuttal_card(id,str(target.get_meta("claim_id",""))).is_empty():
			continue
		var outline:=Panel.new()
		outline.name="card_drag_highlight"
		outline.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var style:=StyleBoxFlat.new()
		style.bg_color=Color(0,0,0,0)
		style.border_color=Color("#E4AC64")
		style.set_border_width_all(3)
		outline.add_theme_stylebox_override("panel",style)
		target.add_child(outline)
		outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _clear_tool_drag_focus()->void:
	for node:Node in _layer.find_children("region_*","Button",true,false):
		var target:=node as Button
		if target.has_meta("tool_drag_alpha"):
			target.modulate.a=float(target.get_meta("tool_drag_alpha"))
			target.remove_meta("tool_drag_alpha")
		var outline:=target.get_node_or_null("tool_drag_highlight")
		if outline!=null:
			target.remove_child(outline)
			outline.queue_free()

func _show_tool_drag_focus(id:String)->void:
	_clear_tool_drag_focus()
	for node:Node in _layer.find_children("region_*","Button",true,false):
		var target:=node as Button
		if target.disabled:
			continue
		target.set_meta("tool_drag_alpha",target.modulate.a)
		if str(target.name)!="region_"+id:
			target.modulate.a*=0.55
			continue
		target.modulate.a=1.0
		var outline:=Panel.new()
		outline.name="tool_drag_highlight"
		outline.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var style:=StyleBoxFlat.new()
		style.bg_color=Color(0,0,0,0)
		style.border_color=Color("#E4AC64")
		style.set_border_width_all(3)
		outline.add_theme_stylebox_override("panel",style)
		target.add_child(outline)
		outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

# Provisional recessed holder, independent of all actual tool rules.
func _native_tool_holder(button:Button,active:bool,acquired:bool)->void:
	for mode:String in ["normal","hover","pressed"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("#303934") if mode=="normal" else Color("#454C40")
		style.border_color=Color("#BBA77D") if active or mode=="hover" else Color("#58665D")
		style.set_border_width_all(1)
		style.border_width_bottom=3
		style.content_margin_left=6
		style.content_margin_right=6
		style.content_margin_top=2
		style.content_margin_bottom=2
		button.add_theme_stylebox_override(mode,style)
	button.add_theme_color_override("font_color",Color("#B9C4B7") if acquired else Color("#D5D0C3"))

func _build_inspection()->void:
	var tools:=VBoxContainer.new()
	tools.name="tool_tray"
	_region_node(tools,Rect2(0.01,0.08,0.22,0.76))
	tools.add_child(_text(_label("ui.copy.inspection_tools_546ff394")))
	if _app.visit_id=="radio_return":
		tools.add_child(_text(str(_app.item_id)+" · "+_label("ui.copy.returning_item_747d92af")))
	for id:String in _app.tools:
		var spec:Dictionary=_app.tools[id]
		var button:=DragSource.new()
		button.name="select_tool_"+id
		var acquired:bool=_known(id)
		var minutes:int=0 if acquired and preview_native_v23 else int(spec.minutes)
		button.text=("✓ " if acquired else ("▶ " if _selected_tool==id else ""))+_tool_title(id)+"\n"+str(minutes)+_label("ui.copy.min_a419b7d")
		button.custom_minimum_size.y=48
		if preview_native_v23:
			button.icon=_tool_icon(id)
			button.add_theme_constant_override("icon_max_width",36)
			button.expand_icon=false
			button.set_meta("native_tool_drag",true)
			_native_tool_holder(button,_selected_tool==id,acquired)
		button.disabled=acquired and not preview_native_v23
		if not acquired:
			button.token={"kind":"tool","id":id,"epoch":_epoch,"revision":_revision,"visit":_visit}
			_tokens["tool:"+id]=button.token.duplicate()
		elif preview_native_v23:
			button.tooltip_text=_label("inspection.review_record")
		tools.add_child(button)
		var epoch:int=_epoch
		button.pressed.connect(func()->void:
			if epoch==_epoch and not button.disabled:
				_review_tool=id
				if _known(id):
					# Reviewing evidence is a local action; it cannot acquire or charge again.
					_selected_tool=""
					_feedback=""
					# Keep the current reference page open when selecting a known
					# observation in the native workspace.
					if not preview_native_v23:
						_book_open=false
				else:
					_selected_tool=id
					_feedback=_label("ui.copy.select_the_region_on_the_item_688ed27a") if not _single_view_items() or _face_regions().has(id) else _label("ui.copy.select_the_detail_target_above_the_item_4719621e")
				_build())
	var regions:Dictionary=_face_regions()
	for id:String in regions:
		if not _app.tools.has(id):
			continue
		var target:=DropTarget.new()
		target.name="region_"+id
		target.text=("✓" if _known(id) else "+") if _single_view_items() else (_label("ui.copy.known_e7b32f47") if _known(id) else ("+" if _selected_tool!=id else _label("ui.copy.inspect_1b481735")))
		target.tooltip_text=_tool_title(id)
		target.modulate.a=(1.0 if _selected_tool==id else 0.75) if preview_native_v23 else (0.82 if _selected_tool==id else 0.46)
		target.disabled=_known(id)
		if _uses_native_r001():
			_native_target_style(target,id)
		target.accepts=func(data:Variant)->bool:
			return _token_valid(data,id,"tool")
		target.commit=func(data:Variant)->void:
			_apply_tool(str(data.id),id)
		target.pressed.connect(func()->void:
			_apply_tool(_selected_tool,id))
		_layer.add_child(target)
		_regions[id]=target
	if _single_view_items():
		# Non-visible observations remain explicit targets, never fabricated visible hotspots.
		var details:=HBoxContainer.new()
		details.name="single_view_detail_targets"
		for id:String in _app.tools:
			if not regions.has(id):
				details.add_child(_detail_target(id))
		if details.get_child_count()>0:
			_region_node(details,Rect2(0.26,0.015,0.72,0.115))
		else:
			details.free()
	var strip:=HBoxContainer.new()
	_region_node(strip,Rect2(0.24,0.72,0.24,0.10) if preview_native_v23 and _book_open else Rect2(0.26,0.76,0.72,0.10))
	if not _single_view_items():
		_button(strip,"flip_item",_label("ui.copy.front_18a87342") if _back else _label("ui.copy.back_479b23d1"),func()->void:
			_back=not _back
			_build())
	_button(strip,"zoom_in","+",func()->void:
		_zoom=minf(1.22,_zoom+0.11)
		_layout_scene())
	_button(strip,"zoom_out","−",func()->void:
		_zoom=maxf(0.78,_zoom-0.11)
		_layout_scene())
	_button(strip,"open_book",_label("ui.copy.book_assessment_4558d616"),func()->void:
		_book_open=not _book_open
		_build())
	var note:=_text(_feedback if not _feedback.is_empty() else _label("ui.copy.drag_a_tool_onto_the_item_b8fb2c5b"))
	_region_node(note,Rect2(0.24,0.84,0.24,0.14) if preview_native_v23 and _book_open else Rect2(0.26,0.88,0.72,0.10))
	if not _app.evidence.is_empty() and _feedback.is_empty():
		var fact:Dictionary=_app.evidence.back()
		var result:String=PublicObservationText.fact(str(fact.observation_key),fact.observed_value,_tr)
		note.text=_label("ui.format.last_observation",{"reading":result})
	if preview_native_v23 and not _book_open:
		_build_observation_review()
	elif preview_native_v23 and _book_open:
		_build_book_clue(note)
	if _book_open:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("#D5CCB6" if preview_native_v23 else "#28312b")
		style.border_color=Color("#8C795A" if preview_native_v23 else "#a59776")
		style.set_border_width_all(2)
		if preview_native_v23:
			style.border_width_left=7
			style.content_margin_left=9
			style.content_margin_right=6
			style.content_margin_top=5
			style.content_margin_bottom=5
		_notebook.add_theme_stylebox_override("panel",style)
		var tool:String=_current_review_tool()
		_notebook.comparison_observation_key=str(_app.get("tools",{}).get(tool,{}).get("evidence_id",""))
		_notebook.configure(_app,_revision,_tr,"ko" if _ko else "en",false,"production_book_paged" if preview_native_v23 else "production_book")
		_notebook.show()

# Display a current acquired observation beside the physical object and book.
# No specimen tables, inference, price calculation or new inspection action.
func _build_book_clue(note:Label)->void:
	var id:String=_current_review_tool()
	var fact:Dictionary=_review_fact(id)
	var sample:Control=AppraisalVisuals.acquired_display(fact,_tr)
	# The visible artwork can be compared for free even before inspection.
	# Do not attach an evidence ID or reveal the inspection reading until acquired.
	var crop_regions:Dictionary=_visible_crop_regions()
	if sample==null and id in ["wear_detail","material_detail","display_damage_detail"] and crop_regions.has(id) and _item.texture!=null:
		var raw:Rect2=crop_regions[id]
		var pixels:Vector2=_item.texture.get_size()
		var atlas:=AtlasTexture.new()
		atlas.atlas=_item.texture
		atlas.region=Rect2(raw.position*pixels,raw.size*pixels)
		sample=AppraisalVisuals.texture_control(atlas)
		sample.set_meta("caption_key","inspection.visible_crop")
	if sample==null:
		# No visible image does not imply failure, or a previous tool result.
		# Keep the selected topic explicit even if no graphic is available.
		if not id.is_empty():
			note.name="book_observation_caption"
			var reading:String=_label("inspection.not_observed") if fact.is_empty() else PublicObservationText.reading(str(fact.observation_key),fact.observed_value,_tr)
			note.text=_label("inspection.compare.topic_reading",{"topic":_tool_title(id),"reading":reading})
			note.tooltip_text=note.text
		return
	_book_clue=sample
	sample.name="book_visible_preview" if fact.is_empty() else "book_observation_sample"
	if not fact.is_empty():
		sample.set_meta("evidence_id",fact.evidence_id)
	sample.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_region_node(sample,Rect2(0.24,0.53,0.24,0.18))
	var source_key:String=str(sample.get_meta("caption_key"))
	var compact_key:String={
		"inspection.visible_crop":"inspection.compare.crop",
		"book.texture.observation":"inspection.compare.texture",
		"inspection.mark_transcription":"inspection.compare.mark",
		"inspection.readout_caption":"inspection.compare.readout"
	}.get(source_key,source_key)
	note.name="book_observation_caption"
	if fact.is_empty():
		note.text=_label("inspection.not_observed")+"\n"+_label(compact_key)
		note.tooltip_text=_feedback+" · "+_label(source_key)
	else:
		note.text=PublicObservationText.reading(str(fact.observation_key),fact.observed_value,_tr)+"\n"+_label(compact_key)
		note.tooltip_text=PublicObservationText.fact(str(fact.observation_key),fact.observed_value,_tr)+" · "+_label(source_key)

# A read-only local viewer. It never queries specimen truth or creates evidence.
func _current_review_tool()->String:
	if _app.get("tools",{}).has(_selected_tool):
		return _selected_tool
	if _app.get("tools",{}).has(_review_tool):
		return _review_tool
	for index:int in range(_app.get("evidence",[]).size()-1,-1,-1):
		var fact:Dictionary=_app.evidence[index]
		if fact.current and not fact.is_claim:
			var id:String=_tool_from_evidence(str(fact.observation_key))
			if not id.is_empty():
				return id
	return ""

func _review_fact(id:String)->Dictionary:
	if not _app.get("tools",{}).has(id):
		return {}
	for fact:Dictionary in _app.evidence:
		if fact.current and not fact.is_claim and fact.observation_key==_app.tools[id].evidence_id:
			return fact
	return {}

# A Panel rather than a Container: intrinsic child sizes cannot enlarge the
# review area. Responsive anchors reserve separate space for all reading text.
func _review_region(parent:Control,child:Control,region:Rect2)->void:
	parent.add_child(child)
	child.set_anchor(SIDE_LEFT,region.position.x)
	child.set_anchor(SIDE_TOP,region.position.y)
	child.set_anchor(SIDE_RIGHT,region.end.x)
	child.set_anchor(SIDE_BOTTOM,region.end.y)
	child.offset_left=0
	child.offset_top=0
	child.offset_right=0
	child.offset_bottom=0

func _review_label(value:String,id:String)->Label:
	var line:=_text(value)
	line.name=id
	line.clip_text=true
	line.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	return line

func _build_observation_review()->void:
	var id:String=_current_review_tool()
	if id.is_empty():
		return
	var panel:=Panel.new()
	panel.name="inspection_review"
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.clip_contents=true
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("#252B2D")
	style.border_color=Color("#A89B80")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel",style)
	_region_node(panel,Rect2(0.66,0.15,0.32,0.58))
	var title:=_review_label(_tool_title(id),"inspection_review_title")
	title.add_theme_color_override("font_color",Color("#C4B28B"))
	_review_region(panel,title,Rect2(0.04,0.015,0.92,0.17))
	var regions:Dictionary=_visible_crop_regions()
	var fact:Dictionary=_review_fact(id)
	var acquired:Control=AppraisalVisuals.acquired_display(fact,_tr)
	var crop_available:bool=acquired==null and id in ["wear_detail","material_detail","display_damage_detail"] and regions.has(id) and _item.texture!=null
	var visual_available:bool=acquired!=null or crop_available
	# Crop only the already visible artwork. No hidden readings or fake photographs.
	if crop_available:
		var raw:Rect2=regions[id]
		var pixels:Vector2=_item.texture.get_size()
		var atlas:=AtlasTexture.new()
		atlas.atlas=_item.texture
		atlas.region=Rect2(raw.position*pixels,raw.size*pixels)
		var sample:=TextureRect.new()
		sample.name="inspection_visible_crop"
		sample.texture=atlas
		sample.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		sample.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sample.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		sample.mouse_filter=Control.MOUSE_FILTER_IGNORE
		_review_region(panel,sample,Rect2(0.04,0.20,0.92,0.35))
		var note:=_review_label(_label("inspection.visible_crop"),"inspection_crop_caption")
		note.add_theme_color_override("font_color",Color("#B4BAB3"))
		_review_region(panel,note,Rect2(0.04,0.56,0.92,0.19))
	if acquired!=null:
		_review_region(panel,acquired,Rect2(0.04,0.20,0.92,0.35))
		var caption:=_review_label(_label(str(acquired.get_meta("caption_key"))),"inspection_crop_caption")
		caption.add_theme_color_override("font_color",Color("#B4BAB3"))
		_review_region(panel,caption,Rect2(0.04,0.56,0.92,0.19))
	var result:=_review_label(_label("inspection.not_observed"),"inspection_review_result")
	if not fact.is_empty():
		result.text=PublicObservationText.fact(str(fact.observation_key),fact.observed_value,_tr)
		result.set_meta("evidence_id",fact.evidence_id)
	_review_region(panel,result,Rect2(0.04,0.76,0.92,0.22) if visual_available else Rect2(0.04,0.20,0.92,0.76))

func _tool_from_evidence(key:String)->String:
	for id:String in _app.tools:
		if _app.tools[id].evidence_id==key:
			return id
	return ""

func _present(id:String)->void:
	for card:Dictionary in _app.deck.direct_ready:
		if card.card_id==id and card.current:
			_selected_card=""
			_emit("subject_deck_action",_payload({"op":"present_direct","slot_id":card.argument.slot_id,"ref_id":card.argument.source_action}))
			return
	if preview_native_v23:
		for observed:Dictionary in _app.deck.get("observation_ready",[]):
			if id=="fact_"+str(observed.source_action):
				_selected_card=""
				_emit("subject_deck_action",_payload({"op":"present_observation","slot_id":observed.slot_id,"ref_id":observed.source_action}))
				return

# Physical paper furniture is a projection of the current public deck only.
# It never evaluates a hypothesis, changes a receipt, or makes a price offer.
func _argument_copy(arg:Dictionary)->String:
	if arg.get("statement_kind")=="observation":
		return PublicObservationText.fact(str(arg.label_key),arg.observed_value,_tr)
	return _label(str(arg.label_key))

func _argument_title(arg:Dictionary)->String:
	return _label("counter.card.fact" if arg.get("statement_kind")=="observation" else "counter.card.judgment")

func _card_style(fill:Color,edge:Color)->StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=fill
	style.border_color=edge
	style.set_border_width_all(1)
	style.border_width_top=4
	style.shadow_color=Color(0.08,0.07,0.06,0.52)
	style.shadow_size=3
	style.shadow_offset=Vector2(2,3)
	style.content_margin_left=6
	style.content_margin_right=6
	style.content_margin_top=4
	style.content_margin_bottom=4
	return style

func _paper_face(parent:Control,heading:String,body:String,foot:String,kind:String,selected:bool=false)->PanelContainer:
	var panel:=PanelContainer.new()
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.clip_contents=true
	var fill:Color=Color("#BDAD8E")
	var edge:Color=Color("#74644C")
	if kind=="fact":
		fill=Color("#B8C5B8")
		edge=Color("#617D70")
	elif kind=="customer":
		fill=Color("#AAB6BE")
		edge=Color("#597584")
	if selected:
		edge=Color("#D18A4F")
	var paper_style:=_card_style(fill,edge)
	if selected:
		paper_style.set_border_width_all(3)
		paper_style.border_width_top=5
	panel.add_theme_stylebox_override("panel",paper_style)
	parent.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content:=VBoxContainer.new()
	content.mouse_filter=Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation",1)
	panel.add_child(content)
	var tag:=_text(heading)
	tag.add_theme_font_size_override("font_size",13)
	tag.add_theme_color_override("font_color",Color("#403D34"))
	tag.autowrap_mode=TextServer.AUTOWRAP_OFF
	tag.clip_text=true
	content.add_child(tag)
	var value:=_text(body)
	value.name="paper_body"
	value.add_theme_font_size_override("font_size",15)
	value.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	value.max_lines_visible=2
	value.add_theme_color_override("font_color",Color("#242B2C"))
	value.size_flags_vertical=Control.SIZE_EXPAND_FILL
	value.clip_text=true
	value.text_overrun_behavior=TextServer.OVERRUN_NO_TRIMMING
	content.add_child(value)
	if not foot.is_empty():
		var caption:=_text(foot)
		caption.name="paper_footer"
		caption.add_theme_font_size_override("font_size",12)
		caption.add_theme_color_override("font_color",Color("#49493F"))
		caption.autowrap_mode=TextServer.AUTOWRAP_OFF
		caption.clip_text=true
		content.add_child(caption)
	return panel

func _hand_card(cards:Control,id:String,arg:Dictionary,enabled:bool,correction:bool=false)->void:
	var b:=DragSource.new()
	b.name="spatial_card_"+id
	var fact:bool=arg.get("statement_kind")=="observation"
	var heading:String=_argument_title(arg)
	if correction:
		heading=_label("counter.card.correction")
	var body:String=_argument_copy(arg)
	var footer:String=_label("ui.format.source_count",{"count":str(arg.get("evidence_ids",[]).size())})
	b.text=""
	b.tooltip_text=heading+"\n"+body+"\n"+footer
	b.custom_minimum_size=Vector2(192,86)
	b.disabled=not enabled
	b.token={"kind":"claim","id":id,"epoch":_epoch,"revision":_revision,"visit":_visit}
	# Drag preview carries public face only; token remains scoped and opaque.
	b.set_meta("paper_drag_text",heading+"\n"+body+"\n"+footer)
	b.set_meta("paper_drag_kind","fact" if fact else "judgment")
	for mode:String in ["normal","hover","pressed","disabled","focus"]:
		b.add_theme_stylebox_override(mode,StyleBoxEmpty.new())
	cards.add_child(b)
	var face:=_paper_face(b,heading,body,footer,"fact" if fact else "judgment",id==_selected_card)
	face.modulate.a=1.0 if enabled else 0.55
	# A distinct focus indicator is visible even without a pointer.
	b.focus_entered.connect(func()->void: face.self_modulate=Color(1.10,1.06,0.96))
	b.focus_exited.connect(func()->void: face.self_modulate=Color.WHITE)
	if enabled:
		_tokens["claim:"+id]=b.token.duplicate()
	var epoch:int=_epoch
	b.pressed.connect(func()->void:
		if epoch==_epoch and not b.disabled:
			_selected_card=id
			_build())

func _rebuttal_card(id:String,claim_id:String)->Dictionary:
	for card:Dictionary in _app.deck.direct_ready:
		if card.card_id==id and card.current:
			for option:Dictionary in card.get("rebuttal_options",[]):
				if option.claim_id==claim_id:
					return card
	return {}

func _present_rebuttal(id:String,claim_id:String)->void:
	var card:Dictionary=_rebuttal_card(id,claim_id)
	if card.is_empty():
		return
	_selected_card=""
	_emit("subject_deck_action",_payload({"op":"present_direct","slot_id":card.argument.slot_id,"ref_id":card.argument.source_action,"claim_id":claim_id}))

func _hand_capacity()->int:
	return maxi(1,int(floor((size.x*0.63-108.0)/200.0)))

func _refresh_hand_capacity()->void:
	if preview_native_v23 and not _inspect and not _plain and not _app.is_empty() and _hand_slots!=_hand_capacity() and not transitioning:
		_build.call_deferred()

func _page_button(parent:Control,id:String,label:String,callback:Callable,disabled:bool)->Button:
	var b:=_button(parent,id,label,callback,disabled)
	b.custom_minimum_size=Vector2(48,48)
	return b

# Independent single-line labels prevent multi-line clipping in the paper.
func _fixed_price_label(parent:Control,id:String,copy:String)->Label:
	var line:=_text(copy)
	line.name=id
	line.autowrap_mode=TextServer.AUTOWRAP_OFF
	line.add_theme_font_size_override("font_size",13)
	line.add_theme_color_override("font_color",Color("#303530"))
	line.custom_minimum_size.y=26
	line.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	line.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	line.clip_text=true
	line.tooltip_text=copy
	parent.add_child(line)
	return line

func _compact_button(b:Button)->void:
	b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	b.clip_text=true
	b.tooltip_text=b.text
	b.add_theme_font_size_override("font_size",14)

func _build_public_papers()->void:
	# Browse the actual public claims, including older rebuttal targets.
	# A new response opens its own card; paging is presentation-only.
	var claims:Array[Dictionary]=[]
	for speech:Dictionary in _app.deck.presented:
		if not speech.get("customer_response",{}).is_empty():
			claims.append(speech.customer_response)
	if _claim_seen!=claims.size():
		_claim_page=maxi(0,claims.size()-1)
		_claim_seen=claims.size()
	if not claims.is_empty():
		_claim_page=clampi(_claim_page,0,claims.size()-1)
		var response:Dictionary=claims[_claim_page]
		var claim_area:=VBoxContainer.new()
		claim_area.name="counter_claim_area"
		claim_area.add_theme_constant_override("separation",4)
		_region_node(claim_area,Rect2(0.025,0.08,0.29,0.35) if claims.size()>1 else Rect2(0.025,0.15,0.29,0.24))
		if claims.size()>1:
			var nav:=HBoxContainer.new()
			nav.name="counter_claim_navigation"
			nav.add_theme_constant_override("separation",2)
			claim_area.add_child(nav)
			var previous:=_page_button(nav,"claim_previous","‹",func()->void:
				_claim_page=maxi(0,_claim_page-1)
				_build.call_deferred(),_claim_page==0)
			previous.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
			var number:=_text(_label("counter.claim.page",{"page":str(_claim_page+1),"total":str(claims.size())}),HORIZONTAL_ALIGNMENT_CENTER)
			number.name="counter_claim_page"
			number.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			number.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
			nav.add_child(number)
			var next:=_page_button(nav,"claim_next","›",func()->void:
				_claim_page=mini(claims.size()-1,_claim_page+1)
				_build.call_deferred(),_claim_page>=claims.size()-1)
			next.size_flags_horizontal=Control.SIZE_SHRINK_END
		var customer:=DropTarget.new()
		customer.name="counter_customer_claim"
		customer.text=""
		var claim_id:String=response.beat_id
		customer.set_meta("claim_id",claim_id)
		customer.set_meta("claim_page",_claim_page)
		customer.set_meta("claim_count",claims.size())
		customer.tooltip_text=_label("counter.card.customer")+" · "+_label(response.label_key)
		var rebutted:bool=false
		for statement:Dictionary in _app.deck.presented:
			if statement.get("rebuttal",{}).get("claim_id","")==claim_id:
				rebutted=true
		customer.set_meta("rebutted",rebutted)
		if rebutted:
			customer.tooltip_text+="\n"+_label("counter.claim.rebuttal_recorded")
		for mode:String in ["normal","hover","pressed","disabled","focus"]:
			customer.add_theme_stylebox_override(mode,StyleBoxEmpty.new())
		customer.accepts=func(data:Variant)->bool:
			return data is Dictionary and _token_valid(data,str(data.get("id","")),"claim") and not _rebuttal_card(str(data.id),claim_id).is_empty()
		customer.commit=func(data:Variant)->void: _present_rebuttal(str(data.id),claim_id)
		customer.pressed.connect(func()->void:
			if not _selected_card.is_empty():
				_present_rebuttal(_selected_card,claim_id))
		customer.size_flags_vertical=Control.SIZE_EXPAND_FILL
		claim_area.add_child(customer)
		var relation:String=_label("counter.card.agrees" if response.get("relation")=="agrees" else "counter.card.disagrees")
		_paper_face(customer,_label("counter.card.customer"),_label(response.label_key),_label("counter.claim.rebuttal_recorded") if rebutted else relation+" · "+_label("counter.card.unverified"),"customer")
	# Paper sheet: actual public statements, including corrections/withdrawals,
	# only. Read from the same immutable record used by the receipt history.
	var sheet:=PanelContainer.new()
	sheet.name="counter_public_sheet"
	sheet.add_theme_stylebox_override("panel",_card_style(Color("#C4BA9F"),Color("#82765D")))
	_region_node(sheet,Rect2(0.68,0.34,0.31,0.22))
	var rows:=VBoxContainer.new()
	rows.name="counter_public_sheet_pages"
	rows.add_theme_constant_override("separation",2)
	sheet.add_child(rows)
	sheet.set_meta("public_count",_app.deck.presented.size())
	# Each page is one public entry, one disclosed source, or one customer reply.
	# No new facts or saved fields; older pages remain accessible.
	var pages:Array[Dictionary]=[]
	var latest:int=0
	for speech:Dictionary in _app.deck.presented:
		var arg:Dictionary=speech.argument
		var prefix:String=_argument_title(arg)
		if speech.has("withdraws_presentation_id"):
			prefix=_label("counter.card.withdrawn")
		elif speech.has("rebuttal"):
			prefix=_label("counter.claim.rebuttal_hypothesis")
		elif speech.has("corrects_presentation_id"):
			prefix=_label("counter.card.correction")
		latest=pages.size()
		pages.append({"id":str(speech.presentation_id),"copy":prefix+" · "+_argument_copy(arg)+"\n"+_label("ui.format.source_count",{"count":str(arg.get("evidence_ids",[]).size())})})
		if speech.has("rebuttal"):
			pages.append({"id":str(speech.presentation_id)+"_rebuttal","copy":_label("counter.claim.rebuttal_target",{"claim":_label(speech.rebuttal.claim_label_key),"count":str(speech.rebuttal.new_evidence_ids.size())})})
		for source_id:String in arg.get("evidence_ids",[]):
			var source_copy:String=source_id
			for observation:Dictionary in _app.evidence:
				if observation.evidence_id==source_id:
					source_copy=PublicObservationText.fact(str(observation.observation_key),observation.observed_value,_tr)
					break
			pages.append({"id":source_id,"copy":_label("counter.card.sources")+" · "+source_copy})
		if not speech.get("customer_response",{}).is_empty():
			pages.append({"id":str(speech.customer_response.beat_id),"copy":_label("counter.card.customer")+" · "+_label(speech.customer_response.label_key)+" · "+_label("counter.card.unverified")})
	if pages.is_empty():
		pages.append({"id":"empty","copy":_label("counter.sheet.empty")})
	if _sheet_seen!=_app.deck.presented.size():
		_sheet_page=latest
		_sheet_seen=_app.deck.presented.size()
	_sheet_page=clampi(_sheet_page,0,pages.size()-1)
	sheet.set_meta("page_count",pages.size())
	sheet.set_meta("page_index",_sheet_page)
	var navigation:=HBoxContainer.new()
	rows.add_child(navigation)
	_page_button(navigation,"sheet_previous","‹",func()->void:
		_sheet_page-=1
		_build(),_sheet_page==0)
	var title:=_text(_label("ui.format.statement_page",{"page":str(_sheet_page+1),"total":str(pages.size())}),HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_font_size_override("font_size",13)
	title.add_theme_color_override("font_color",Color("#383B34"))
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	navigation.add_child(title)
	_page_button(navigation,"sheet_next","›",func()->void:
		_sheet_page+=1
		_build(),_sheet_page>=pages.size()-1)
	var line:=_text(str(pages[_sheet_page].copy))
	line.name="counter_sheet_"+str(pages[_sheet_page].id)
	line.add_theme_font_size_override("font_size",14)
	line.add_theme_color_override("font_color",Color("#303530"))
	line.clip_text=true
	line.size_flags_vertical=Control.SIZE_EXPAND_FILL
	line.tooltip_text=line.text
	rows.add_child(line)


func _build_native_hand()->void:
	var hand:=HBoxContainer.new()
	hand.name="spatial_hand"
	hand.add_theme_constant_override("separation",8)
	_region_node(hand,Rect2(0.015,0.80,0.63,0.19))
	var entries:Array[Dictionary]=[]
	var enabled:bool=_app.deck.remaining_presentations>0 and _app.deck.remaining_events>0
	for card:Dictionary in _app.deck.direct_ready:
		entries.append({"id":card.card_id,"arg":card.argument,"enabled":enabled and card.current,"correction":card.get("correction",false)})
	for fact:Dictionary in _app.deck.get("observation_ready",[]):
		entries.append({"id":"fact_"+str(fact.source_action),"arg":fact,"enabled":enabled,"correction":false})
	_hand_slots=_hand_capacity()
	var count:int=maxi(1,ceili(float(entries.size())/float(_hand_slots)))
	_hand_page=clampi(_hand_page,0,count-1)
	hand.set_meta("page_count",count)
	hand.set_meta("page_index",_hand_page)
	if entries.is_empty():
		var empty:=_text(_label("ui.copy.no_assessment_cards_inspect_and_choose_a_ju_54b904ca"))
		empty.name="spatial_empty_hand"
		empty.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		hand.add_child(empty)
		return
	if count>1:
		var nav:=VBoxContainer.new()
		nav.add_theme_constant_override("separation",0)
		hand.add_child(nav)
		var page:String=str(_hand_page+1)+"/"+str(count)
		var previous:=_page_button(nav,"hand_previous","‹ "+page,func()->void:
			_hand_page-=1
			_selected_card=""
			_build(),_hand_page==0)
		var next_page:=_page_button(nav,"hand_next","› "+page,func()->void:
			_hand_page+=1
			_selected_card=""
			_build(),_hand_page>=count-1)
		for arrow:Button in [previous,next_page]:
			arrow.custom_minimum_size=Vector2(64,48)
			arrow.add_theme_font_size_override("font_size",12)
	for i:int in range(_hand_page*_hand_slots,mini(entries.size(),(_hand_page+1)*_hand_slots)):
		var entry:Dictionary=entries[i]
		_hand_card(hand,entry.id,entry.arg,entry.enabled,entry.correction)

# Resolve the exact public statement IDs attached to an offer. Do not use
# the private assessment or reinterpret the earlier offer with today's basis.
func _offer_basis_detail(ids:Array)->String:
	if ids.is_empty():
		return _label("counter.price.no_basis")
	var lines:PackedStringArray=[]
	for speech:Dictionary in _app.deck.presented:
		if speech.presentation_id in ids:
			lines.append(_argument_title(speech.argument)+" · "+_argument_copy(speech.argument))
	return "\n".join(lines) if not lines.is_empty() else _label("counter.price.no_basis")

func _build_customer()->void:
	# Statement/checkout overlays are not the private paper handbook.
	if preview_native_v23:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("#2A3032")
		style.border_color=Color("#C4B28B")
		style.set_border_width_all(2)
		_notebook.add_theme_stylebox_override("panel",style)
	var dialogue:=_customer_id()+": "+(_label("ui.copy.do_you_buy_watches_d713ae5") if _is_watch() else _label("ui.copy.do_you_buy_things_here_badbda7b"))
	if _app.visit_id=="radio_return":
		dialogue=_customer_id()+": "+_label("ui.copy.i_bought_this_radio_here_before_it_is_not_i_f90fb14b")
	if not _app.deck.presented.is_empty():
		var latest:Dictionary=_app.deck.presented.back()
		if latest.has("withdraws_presentation_id"):
			dialogue=_label("ui.format.withdraw_dialogue",{"judgment":_label(latest.argument.label_key)})
		elif latest.argument.get("statement_kind")=="observation":
			dialogue=_label("ui.format.observation_dialogue",{"reading":PublicObservationText.fact(str(latest.argument.label_key),latest.argument.observed_value,_tr)})
		else:
			dialogue=_label("ui.copy.alexei_a19a8468")+(_label("ui.copy.correction_290b194e") if latest.has("corrects_presentation_id") else "")+_label(latest.argument.label_key)+_label("ui.copy.hypothesis_a46bd249")
		var response:Dictionary=latest.get("customer_response",{})
		if not response.is_empty():
			var reply:String=_customer_id()+": "+_label(response.label_key)+_label("ui.copy.customer_claim_20504483")
			# The native tabletop already carries the public player card.
			# Let the speech area focus on the actual customer response.
			dialogue=reply if preview_native_v23 else dialogue+"\n"+reply
	# A prior paid transaction is a fact; never imply recognition of the
	# current object's identity or reveal an unobserved customer memory.
	var remembered:String=_previous_trade_copy()
	if _app.deck.presented.is_empty() and not remembered.is_empty():
		dialogue+="
"+remembered
	# Bound the speech independently of wrapping/container minimum sizes.
	# Keep the customer, counter and physical item visible below the dialogue.
	var speech:=ColorRect.new()
	speech.name="spatial_speech_background"
	speech.color=Color("#2A3032" if preview_native_v23 else "#28312b")
	speech.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_region_node(speech,Rect2(0.66,0.10,0.32,0.23) if preview_native_v23 else Rect2(0.20,0.32,0.60,0.13))
	var caption:=_text(dialogue,HORIZONTAL_ALIGNMENT_CENTER)
	caption.name="spatial_speech_text"
	caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART if preview_native_v23 else TextServer.AUTOWRAP_OFF
	caption.clip_text=true
	caption.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_region_node(caption,Rect2(0.67,0.11,0.30,0.21) if preview_native_v23 else Rect2(0.21,0.32,0.58,0.13))
	var drop:=DropTarget.new()
	drop.name="spatial_customer_drop"
	drop.text=_label("ui.copy.present_a_card_to_customer_ce34e8f")
	drop.custom_minimum_size.y=48
	var has_cards:bool=not _app.deck.direct_ready.is_empty() or (preview_native_v23 and not _app.deck.get("observation_ready",[]).is_empty())
	drop.disabled=not has_cards or _app.deck.remaining_events<=0 or _app.deck.remaining_presentations<=0
	drop.accepts=func(data:Variant)->bool:
		return data is Dictionary and _token_valid(data,str(data.get("id","")),"claim")
	drop.commit=func(data:Variant)->void:
		_present(str(data.id))
	drop.pressed.connect(func()->void:
		if not _selected_card.is_empty():
			_present(_selected_card))
	_region_node(drop,Rect2(0.025,0.46,0.31,0.18) if preview_native_v23 else Rect2(0.31,0.46,0.38,0.09))
	if preview_native_v23:
		drop.text=""
		drop.tooltip_text=_label("counter.table.hint")
		drop.set_meta("physical_table",true)
		for mode:String in ["normal","hover","pressed","disabled","focus"]:
			var edge:=Color(0.55,0.46,0.33,0.70) if mode in ["hover","focus","pressed"] else Color(0.48,0.42,0.34,0.38)
			drop.add_theme_stylebox_override(mode,_card_style(Color(0.13,0.12,0.10,0.24),edge))
		if _app.deck.presented.is_empty():
			var first_hint:String="counter.table.start_hint" if not has_cards else "counter.table.first_hint"
			var hint:=_text(_label(first_hint),HORIZONTAL_ALIGNMENT_CENTER)
			hint.name="counter_first_visit_hint"
			hint.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
			drop.add_child(hint)
			hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		else:
			var last:Dictionary=_app.deck.presented.back()
			var arg:Dictionary=last.argument
			var headline:String=_label("counter.card.public") if not last.has("withdraws_presentation_id") else _label("counter.card.withdrawn")
			if last.has("rebuttal"):
				headline=_label("counter.claim.rebuttal_hypothesis")
			elif last.has("corrects_presentation_id"):
				headline=_label("counter.card.correction")
			var face:=_paper_face(drop,headline,_argument_copy(arg),_argument_title(arg),"fact" if arg.get("statement_kind")=="observation" else "judgment")
			face.name="counter_placed_card"
			face.set_meta("presentation_id",last.presentation_id)
			if _animate_presentation and _presentation_motion:
				face.modulate.a=0.25
				face.offset_top=12
				var settle:=face.create_tween().set_parallel(true)
				settle.tween_property(face,"modulate:a",1.0,0.20)
				settle.tween_property(face,"offset_top",0.0,0.20)
		_animate_presentation=false
		_build_public_papers()
	if preview_native_v23:
		_build_native_hand()
	else:
		var hand:=ScrollContainer.new()
		hand.name="spatial_hand"
		hand.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		_region_node(hand,Rect2(0.015,0.80,0.63,0.19))
		var cards:=HBoxContainer.new()
		hand.add_child(cards)
		if not has_cards:
			var empty:=_text(_label("ui.copy.no_assessment_cards_inspect_and_choose_a_ju_54b904ca"))
			empty.name="spatial_empty_hand"
			empty.autowrap_mode=TextServer.AUTOWRAP_OFF
			empty.custom_minimum_size=Vector2(300,48)
			empty.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
			if _uses_native_r001():
				empty.add_theme_color_override("font_color",Color("#A49F90"))
			cards.add_child(empty)
		for card:Dictionary in _app.deck.direct_ready:
			var id:String=card.card_id
			var b:=DragSource.new()
			b.name="spatial_card_"+id
			b.text=("▶ " if id==_selected_card else "")+(_label("ui.copy.correction_fe5aa275") if card.get("correction",false) else "")+_label(card.argument.label_key)+"\n"+_label("ui.copy.hypothesis_links_2ea00e9e")+str(card.argument.evidence_ids.size())
			b.custom_minimum_size=Vector2(142,92)
			b.disabled=not card.current or _app.deck.remaining_presentations<=0 or _app.deck.remaining_events<=0
			b.token={"kind":"claim","id":id,"epoch":_epoch,"revision":_revision,"visit":_visit}
			_paper(b)
			if not b.disabled:
				_tokens["claim:"+id]=b.token.duplicate()
			cards.add_child(b)
			var epoch:int=_epoch
			b.pressed.connect(func()->void:
				if epoch==_epoch and not b.disabled:
					_selected_card=id
					_build())
	# The amount is a local draft. No settlement occurs until authority confirms.
	var paper:=PanelContainer.new()
	paper.name="price_paper"
	if preview_native_v23:
		paper.add_theme_stylebox_override("panel",_card_style(Color("#BDB299"),Color("#82765D")))
	_region_node(paper,Rect2(0.68,0.57,0.31,0.42) if preview_native_v23 else Rect2(0.66,0.60,0.33,0.39))
	var price:=VBoxContainer.new()
	price.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if preview_native_v23:
		price.name="spatial_price_fixed"
		price.add_theme_constant_override("separation",3)
		paper.add_child(price)
	else:
		var price_scroll:=ScrollContainer.new()
		price_scroll.name="spatial_price_scroll"
		price_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		price_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
		paper.add_child(price_scroll)
		price_scroll.add_child(price)
	var summary_parent:Control=price
	var primary:Control=price
	var optional:Control=price
	if preview_native_v23:
		var summary:=HBoxContainer.new()
		summary.name="spatial_price_summary_row"
		summary.custom_minimum_size.y=58
		var first:=HBoxContainer.new()
		var second:=HBoxContainer.new()
		price.add_child(summary)
		price.add_child(first)
		price.add_child(second)
		summary_parent=summary
		primary=first
		optional=second
	var offer:Dictionary=_app.price_offer
	var estimate: Variant = _app.reference.get("estimate")
	var asking:String=_label("ui.format.asking",{"price":_label("inventory.format.offer_amount",{"amount":str(offer.asking),"currency":str(offer.currency)})})
	var estimate_copy:String=_label("ui.format.estimate",{"price":"—" if estimate==null else _label("inventory.format.offer_amount",{"amount":str(estimate),"currency":str(_app.catalog.currency)})})
	if preview_native_v23:
		var quote_column:=VBoxContainer.new()
		quote_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		quote_column.add_theme_constant_override("separation",0)
		summary_parent.add_child(quote_column)
		_fixed_price_label(quote_column,"spatial_price_reference",asking)
		_fixed_price_label(quote_column,"spatial_price_estimate",estimate_copy)
		if not offer.offers.is_empty():
			var last:Dictionary=offer.offers.back()
			var previous_column:=VBoxContainer.new()
			previous_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			previous_column.add_theme_constant_override("separation",0)
			summary_parent.add_child(previous_column)
			var result:=_fixed_price_label(previous_column,"spatial_previous_offer",_label("ui.format.offer_status",{"price":_label("inventory.format.offer_amount",{"amount":str(last.amount),"currency":str(last.currency)}),"status":_label("review.price.accepted" if last.accepted else "review.price.rejected")}))
			result.tooltip_text=_label("review.price.previous")+" · "+result.text
			var basis_label:=_fixed_price_label(previous_column,"spatial_previous_basis",_label("ui.format.offer_basis",{"count":str(last.presented_ids.size())}))
			basis_label.tooltip_text=_label("counter.price.previous_basis")+"\n"+_offer_basis_detail(last.presented_ids)
			basis_label.set_meta("basis_ids",last.presented_ids.duplicate())
			basis_label.mouse_filter=Control.MOUSE_FILTER_STOP
	else:
		var price_summary:Label=_text(asking+"\n"+estimate_copy)
		price_summary.name="spatial_price_reference"
		price.add_child(price_summary)
		if not offer.offers.is_empty():
			var last:Dictionary=offer.offers.back()
			var prior_offer:Label=_text(_label("review.price.previous")+" · "+_label("ui.format.offer_status",{"price":_label("inventory.format.offer_amount",{"amount":str(last.amount),"currency":str(last.currency)}),"status":_label("review.price.accepted" if last.accepted else "review.price.rejected")})+"\n"+_label("ui.format.offer_basis",{"count":str(last.presented_ids.size())}))
			prior_offer.name="spatial_previous_offer"
			price.add_child(prior_offer)
	var amount:=SpinBox.new()
	amount.name="spatial_price_amount"
	amount.min_value=1
	amount.max_value=1000000000
	amount.step=1
	amount.value=_offer_draft
	amount.editable=offer.can_offer
	if preview_native_v23:
		amount.custom_minimum_size=Vector2(104,48)
		amount.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		amount.tooltip_text=_label("counter.price.proposal")
	primary.add_child(amount)
	var epoch:int=_epoch
	amount.value_changed.connect(func(value:float)->void:
		if epoch==_epoch:
			_offer_draft=int(value))
	var refs:Array=_app.deck.public_basis_ids.duplicate()
	var main_offer:=_button(primary,"spatial_offer",_label("ui.copy.offer_with_basis_28e673c") if not refs.is_empty() else _label("ui.copy.make_offer_debd0b52"),func()->void:
		_emit("subject_price_offer",_payload({"currency":offer.currency,"amount":_offer_draft,"presented_ids":refs,"basis_version":"current_public_v1"})),not offer.can_offer)
	if preview_native_v23:
		_compact_button(main_offer)
		main_offer.tooltip_text=_label("counter.price.current_basis")+"\n"+_offer_basis_detail(refs)
		main_offer.set_meta("basis_ids",refs.duplicate())
	if not refs.is_empty():
		var blank:=_button(optional,"spatial_offer_blank",_label("ui.copy.price_only_4dd8fd0f"),func()->void:
			_emit("subject_price_offer",_payload({"currency":offer.currency,"amount":_offer_draft,"presented_ids":[],"basis_version":"current_public_v1"})),not offer.can_offer)
		if preview_native_v23:
			_compact_button(blank)
			blank.tooltip_text=_label("counter.price.no_basis")
			blank.set_meta("basis_ids",[])
	if not offer.get("quality_option",{}).is_empty():
		var condition: Dictionary = offer.quality_option
		var quality:=_button(optional,"spatial_offer_quality",_label("ui.format.counter_condition",{"condition":(_label("ui.copy.working_8ec30d03") if condition.observed_value=="serviceable" else _label("ui.copy.inoperable_2e345410"))}),func()->void:
			_emit("subject_price_offer",_payload({"currency":offer.currency,"amount":_offer_draft,"presented_ids":refs,"basis_version":"current_public_v1","quality_evidence_id":condition.evidence_id})),not offer.can_offer)
		if preview_native_v23:
			_compact_button(quality)
			quality.tooltip_text=_label("counter.price.current_basis")+"\n"+_offer_basis_detail(refs)+"\n"+quality.text
			quality.set_meta("basis_ids",refs.duplicate())
	if preview_native_v23 and optional.get_child_count()==0:
		optional.hide()
	if _app.has("checkout"):
		_button(price,"spatial_checkout",_label("ui.copy.placement_confirm_288df946"),func()->void:
			_checkout_open=not _checkout_open
			_statements_open=false
			_build())
	else:
		_button(price,"spatial_decline",_label("ui.copy.decline_19995241"),func()->void:
			_emit("calendar_decline_visit",{"visit_id":_visit}))
	var controls:=HBoxContainer.new()
	_region_node(controls,Rect2(0.015,0.66,0.30,0.10))
	if not _app.deck.presented.is_empty() or not _app.deck.get("observation_ready",[]).is_empty():
		_button(controls,"spatial_history",_label("ui.copy.sheet_facts_522abb77"),func()->void:
			_checkout_open=false
			_statements_open=not _statements_open
			_build())
	if not _selected_card.is_empty():
		for card:Dictionary in _app.deck.direct_ready:
			if card.card_id!=_selected_card:
				continue
			for option:Dictionary in card.get("rebuttal_options",[]):
				_button(controls,"spatial_rebut_"+option.claim_id,_label("ui.copy.rebut_1ebcc6f6"),func()->void:
					_selected_card=""
					_emit("subject_deck_action",_payload({"op":"present_direct","slot_id":card.argument.slot_id,"ref_id":card.argument.source_action,"claim_id":option.claim_id})))
	if _checkout_open and _app.has("checkout"):
		_notebook.configure(_app,_revision,_tr,"ko" if _ko else "en",false,"production_checkout_paged" if preview_native_v23 else "production_checkout")
		_notebook.show()
	elif _statements_open:
		_notebook.configure(_app,_revision,_tr,"ko" if _ko else "en",false,"production_statements_paged" if preview_native_v23 else "production_statements")
		_notebook.show()
	if _notebook.visible:
		var close_box:=HBoxContainer.new()
		_region_node(close_box,Rect2(0.90,0.02,0.09,0.10))
		_button(close_box,"close_overlay",_label("ui.copy.close_9033cd56"),func()->void:
			_checkout_open=false
			_statements_open=false
			_build())
