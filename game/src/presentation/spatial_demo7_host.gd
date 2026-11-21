extends "res://src/presentation/demo7_host.gd"
## Independent candidate host: same runtime, save schema and commands.
## Unified inventory candidate, same authority and save; fallback scene retained.
const Spatial=preload("res://src/presentation/spatial_radio_counter.gd")
const ProvisionalArt=preload("res://src/presentation/native_v23_art.gd")
var _spatial:Control
const Management=preload("res://src/presentation/spatial_management.gd")
var _management:Control
const Office=preload("res://src/presentation/native_office.gd")
var _office:Control
var _office_button:Button
var _office_open:bool=false
var _office_slot:int=-1
var _native_location:Label
var _native_hud:HBoxContainer
var _native_status:Label
@export var preview_r001_pixel_art:bool=false
@export var preview_native_v23:bool=false

func _ready()->void:
	native_history_index=preview_native_v23
	compact_settings_overlay=preview_native_v23 and not separate_settings
	if preview_native_v23 and save_directory_override.is_empty():
		save_directory_override="user://zt_rebuild/demo7/alpha_playtest" if civilian_candidate and condition_pricing and condition_version==3 else ("user://zt_rebuild/demo7/integrated_b_eval" if civilian_candidate and condition_pricing and condition_version==2 else "user://zt_rebuild/demo7/native_v23_preview")
	if preview_r001_pixel_art and save_directory_override.is_empty():
		save_directory_override="user://zt_rebuild/demo7/r001_art_preview"
	super._ready()
	if not is_instance_valid(_app):
		return
	_spatial=Spatial.new()
	_spatial.preview_r001_pixel_art=preview_r001_pixel_art
	_spatial.preview_native_v23=preview_native_v23
	_spatial.name="spatial_counter"
	_spatial.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_app.get_parent().add_child(_spatial)
	_spatial.action_requested.connect(_act)
	_spatial.inspect_stock_requested.connect(_open_condition_stock)
	_spatial.basic_review_requested.connect(_open_basic_review)
	_spatial.hide()
	_management=Management.new()
	_management.preview_native_v23=preview_native_v23
	_management.name="spatial_management"
	_management.history_query=func(id:String)->Dictionary: return runtime.item_history(id)
	_management.composition_query=func(id:String)->Dictionary: return runtime.composition_options(id)
	_management.appraisal_query=func(id:String)->Dictionary: return runtime.inventory_appraisal(id)
	_management.discard_query=func(id:String)->Dictionary: return runtime.discard_preview(id)
	_management.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_app.get_parent().add_child(_management)
	_management.action_requested.connect(_act)
	_management.return_to_counter_requested.connect(_return_condition_counter)
	_management.hide()
	if preview_native_v23:
		ThemeSource.apply_native(theme)
		var backdrop:=get_node_or_null("demo_backdrop") as TextureRect
		if backdrop!=null:
			backdrop.texture=ProvisionalArt.scene_texture("counter.room")
			backdrop.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
			backdrop.modulate=Color(0.42,0.42,0.42,0.22)
		_native_location=Label.new()
		_native_location.name="native_location"
		_native_location.add_theme_color_override("font_color",Color("#C4B28B"))
		var header_parent:Control=_head.get_parent()
		var header:=HBoxContainer.new()
		header.name="native_hud"
		_native_hud=header
		header_parent.add_child(header)
		header_parent.move_child(header,_head.get_index())
		_head.reparent(header)
		_head.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_head.add_theme_font_size_override("font_size",18)
		_native_location.add_theme_font_size_override("font_size",14)
		_native_status=Label.new()
		_native_status.name="native_hud_status"
		_native_status.add_theme_color_override("font_color",Color("#A49F90"))
		_native_status.hide()
		header.add_child(_native_status)
		header.add_child(_native_location)
		header.resized.connect(_reflow_native_feedback)
		_office=Office.new()
		_office.name="native_office"
		_office.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_app.get_parent().add_child(_office)
		_office.action_requested.connect(_act)
		_office.hide()
		_office_button=Button.new()
		_office_button.name="office_toggle"
		_office_button.custom_minimum_size.y=48
		_workspace_button.get_parent().add_child(_office_button)
		_office_button.pressed.connect(_toggle_office)
	_configure_app()
	_refresh_visibility()
	print("ZT_SPATIAL_COUNTER_READY")

func _fixed_trade_active()->bool:
	return _view.get("appraisal",{}).is_empty() and not _view.get("trade",{}).is_empty() and _view.get("phase","")=="shop"

func _service_active()->bool:
	return _view.get("phase","")=="shop" and str(_view.get("visits",{}).get("terms",{}).get("kind","")).begins_with("service_")

func _spatial_active()->bool:
	var appraisal:Dictionary=_view.get("appraisal",{})
	var native_appraisal:bool=preview_native_v23 and Spatial.supports_native_appraisal(appraisal)
	var legacy_appraisal:bool=not preview_native_v23 and appraisal.get("visit_id","") in ["visit_g01","watch_a","radio3_buy","radio_return"]
	return is_instance_valid(_spatial) and (native_appraisal or legacy_appraisal or _fixed_trade_active() or _service_active()) and not _view.get("locked",true) and not _intro

func _configure_app()->void:
	super._configure_app()
	if _spatial_active():
		if _fixed_trade_active():
			_spatial.configure_plain(_view,tr_key,_language)
		elif _service_active():
			_spatial.configure_service(_view,tr_key,_language)
		else:
			_spatial.configure(_view,_compact_appraisal,tr_key,_language,_prefs.get("motion",true))
	elif is_instance_valid(_spatial):
		_spatial.clear_visit()

func _refresh_visibility()->void:
	super._refresh_visibility()
	if not is_instance_valid(_spatial):
		return
	if is_instance_valid(_office):
		var allowed:bool=_office_available()
		if not allowed or _stock_open or _history_open or _office_slot!=_slot_index:
			_office_open=false
		_office_button.disabled=not allowed
		_office_button.text=tr_key("ui.copy.close_office_1f6d1b1f") if _office_open else tr_key("ui.copy.office_b376d3f2")
		_office.visible=_office_open
		if _office_open:
			_update_native_location("office")
			_office.configure(_view,tr_key,_language,_slot_index)
			for panel:Control in [_counter,_app,_history,_stock,_spatial,_management]:
				panel.hide()
			_workspace_button.hide()
			return
	var active:bool=_spatial_active() and not _history_open and not _stock_open
	_spatial.visible=active
	if is_instance_valid(_management):
		var manage:bool=not _intro and not _history_open and not _view.get("locked",true) and (_stock_open or _view.get("phase","")=="workshop")
		_management.visible=manage
		if manage:
			_update_native_location("workshop" if _view.get("phase","")=="workshop" else "inventory")
			_management.configure(_view,"inventory",tr_key,_language,_slot_index)
			_stock.hide()
			_counter.hide()
			_app.hide()
			_spatial.hide()
			_workspace_button.hide()
			return
		else:
			_management.clear_selection()
	_update_native_location("history" if _history_open else ("inspection" if active and _compact_appraisal else "counter"))
	if active:
		_counter.hide()
		_app.hide()
		_workspace_button.visible=not _fixed_trade_active() and not _service_active()

func _update_native_location(mode:String)->void:
	if not is_instance_valid(_native_location):
		return
	_native_location.visible=not _intro and not _view.get("locked",true) and not _view.get("complete",false)
	_native_location.set_meta("mode",mode)
	_native_location.text=tr_key("ui.location."+mode)
	if not _view.is_empty():
		_head.text=tr_key("ui.format.native_hud",{"day":str(8 if _view.complete else _view.day),"time":Clock.clock_text(int(_view.minute)),"vkc":str(_view.wallet.VKC),"usd":str(_view.wallet.USD)})

	_reflow_native_feedback()

# Only a generic successful action may share the one-line HUD. Errors,
# recovery messages, and long localized feedback retain the full-width row.
# The source Label and its translated text remain intact for every view.
func _refresh_feedback()->void:
	super._refresh_feedback()
	_reflow_native_feedback()

func _reflow_native_feedback()->void:
	if not is_instance_valid(_native_hud) or not is_instance_valid(_native_status) or not is_instance_valid(_feedback):
		return
	_native_status.text=_feedback.text
	var generic_success:bool=_feedback_key=="ui.copy.completed_12ead41e" and _feedback_suffix.is_empty() and not _view.is_empty() and not _intro and not _view.get("locked",true) and not _view.get("complete",false)
	var required:float=_head.get_combined_minimum_size().x+_native_location.get_combined_minimum_size().x+_native_status.get_combined_minimum_size().x+24.0
	var compact:bool=generic_success and _native_hud.size.x>=required
	_native_status.visible=compact
	_feedback.visible=not compact and not _feedback.text.is_empty()

func _office_available()->bool:
	if _intro or _view.get("locked",true) or _view.get("complete",false):
		return false
	var active:String=str(_view.get("visits",{}).get("active",""))
	if active.is_empty():
		return true
	for id:String in _view.get("merchant_contracts",{}).get("pawns",{}):
		var p:Dictionary=_view.merchant_contracts.pawns[id]
		if p.status=="offered" and p.visit_id==active:
			return true
	return false

func _toggle_office()->void:
	if not _office_available() or get_viewport().gui_is_dragging():
		return
	_office_open=not _office_open
	_office_slot=_slot_index
	_stock_open=false
	_history_open=false
	_refresh_visibility()

func _toggle_workspace()->void:
	if _spatial_active() and _spatial.transitioning:
		return
	super._toggle_workspace()

# A view switch only: both directions are revision-bound, do not create a
# journal command and never authorize an observation automatically.
func _open_condition_stock(id:String,revision:int)->void:
	if revision!=_view.revision or not _spatial.visible or _view.get("locked",true) or (_view.get("condition_quote",{}).get("item_id")!=id and _view.get("basic_sale_review_id","")!=id) or runtime.inventory_appraisal(id).is_empty() or get_viewport().gui_is_dragging():
		return
	_stock_open=true
	_history_open=false
	refresh()
	if _management.visible:
		_management._select(id,"appraisal")

func _return_condition_counter(revision:int)->void:
	if revision!=_view.revision or not _management.visible or not _stock_open or _view.get("locked",true) or (_view.get("condition_quote",{}).is_empty() and str(_view.get("basic_sale_review_id","")).is_empty()) or get_viewport().gui_is_dragging():
		return
	_stock_open=false
	refresh()
