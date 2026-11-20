extends Control
## Public view only. Selection, rotation and previews are free UI actions.
## Existing move/restore_item commands remain the sole state authority.
signal action_requested(kind:String,payload:Dictionary,revision:int)
signal return_to_counter_requested(revision:int)
var _view:Dictionary={}
var _mode:String=""
var _stock_id:String="player_stock"
var _grid_page_id:String=""
var _legend_open:bool=false
var _detail_page:String="overview"
var _component_page:int=0
var _candidate_page:int=0
var _scroll_detail_page:String=""
var _detail_history_open:bool=false
var history_query:Callable
var composition_query:Callable
var appraisal_query:Callable
var discard_query:Callable
var _discard_draft:Dictionary={}
var _discard_open:bool=false
var _appraisal_target:String=""
var _keep_detail_pending:bool=false
var _prepared_composition:Dictionary={}
var _prepared_kind:String=""
var _components:Dictionary={}
var _component_cache_key:String=""
const History=preload("res://src/presentation/generic_trade_history.gd")
const NativeArt=preload("res://src/presentation/native_v23_art.gd")
const NativeGrid=preload("res://src/presentation/native_grid_art.gd")
var preview_native_v23:bool=false
var _native_time_index:int=-1
var _slot:int=-1
var _revision:int=-1
var _ko:bool=true
var _tr:Callable
var _selected:String=""
var _destination:Vector2i=Vector2i(-1,-1)
var _rotated:bool=false
var _body:VBoxContainer
var _stock_scroll:ScrollContainer
var _detail_scroll:ScrollContainer
var _scroll_selection:String=""
var _scroll_target:String=""
var _scroll_context:String=""
var _epoch:int=0
var _sent:bool=false
const DragCell=preload("res://src/presentation/management_drag_cell.gd")
var _tokens:Dictionary={}

func _drag_token(row:Dictionary,kind:String,offset:Vector2i=Vector2i.ZERO)->Dictionary:
	var token:Dictionary={"kind":kind,"id":row.id,"owner":get_instance_id(),"epoch":_epoch,"revision":_revision,"slot":_slot,"offset":offset}
	_tokens[str(row.id)+":"+str(offset)]=token.duplicate(true)
	return token

func _token_valid(data:Variant,kind:String)->bool:
	if not is_visible_in_tree() or _sent or _view.get("locked",true) or _view.get("complete",false) or not data is Dictionary or data.get("kind")!=kind:
		return false
	return _tokens.get(str(data.get("id",""))+":"+str(data.get("offset",Vector2i(-1,-1))),{})==data and data.get("owner")==get_instance_id() and data.get("revision")==_revision and data.get("slot")==_slot and data.get("epoch")==_epoch

func _detach_candidate(data:Variant,p:Vector2i)->Dictionary:
	if not _token_valid(data,"component") or _components.get("root_id","")!=_selected or not _components.get("enabled",false):
		return {}
	for slot:Dictionary in _components.slots:
		if slot.item_id!=data.id:
			continue
		for candidate:Dictionary in slot.get("detach_positions",[]):
			if int(candidate.x)==p.x and int(candidate.y)==p.y:
				return candidate
	return {}

func _stock_drop_allowed(data:Variant,p:Vector2i)->bool:
	if _mode=="inventory" and not _detach_candidate(data,p).is_empty():
		return true
	if _mode!="inventory" or not _token_valid(data,"stock"):
		return false
	var row:Dictionary=_item(str(data.id))
	if row.is_empty() or not row.owned or row.inventory!=_stock_id:
		return false
	# Drag anchor is the actual grabbed cell. Preserve orientation when moving.
	return _valid_placement(row,p-Vector2i(data.offset),bool(row.rotated))

func _stock_drop(data:Variant,p:Vector2i)->void:
	var candidate:Dictionary=_detach_candidate(data,p)
	if not candidate.is_empty():
		_stage_composition("detach",candidate)
		return
	if not _stock_drop_allowed(data,p):
		return
	var row:Dictionary=_item(str(data.id))
	_appraisal_target=""
	_detail_history_open=false
	_prepared_composition.clear()
	_prepared_kind=""
	_selected=row.id
	_component_page=0
	_candidate_page=0
	_detail_page="overview"
	_rotated=row.rotated
	_destination=p-Vector2i(data.offset)
	# Drop stages a free placement preview; a separate confirmation commits.
	_build()

func _detail_drop_allowed(data:Variant)->bool:
	return _mode=="inventory" and (_token_valid(data,"stock") or _token_valid(data,"detail")) and not _item(str(data.id)).is_empty()

func _detail_drop(data:Variant)->void:
	if _detail_drop_allowed(data):
		_select(str(data.id))


func word(ko:String,en:String)->String:
	return ko if _ko else en

func clear_selection()->void:
	_detail_page="overview"
	_component_page=0
	_candidate_page=0
	_discard_open=false
	_discard_draft.clear()
	_keep_detail_pending=false
	_tokens.clear()
	_detail_history_open=false
	_appraisal_target=""
	_prepared_composition.clear()
	_prepared_kind=""
	_components.clear()
	_component_cache_key=""
	_selected=""
	_destination=Vector2i(-1,-1)

func configure(view:Dictionary,mode:String,translator:Callable,locale:String,slot:int)->void:
	var stock_id:String=str(view.get("stock_inventory_id","player_stock"))
	var same_context:bool=slot==_slot and mode==_mode and str(view.phase)==str(_view.get("phase","")) and stock_id==_stock_id
	if not same_context:
		_grid_page_id=stock_id
		_legend_open=false
	var keep:bool=_keep_detail_pending and same_context and int(view.revision)==_revision+1 and not view.get("locked",true) and not view.get("complete",false)
	var keep_root:String=_selected if keep else ""
	var keep_target:String=_appraisal_target if keep else ""
	var keep_page:String=_detail_page if keep else "overview"
	var keep_component:int=_component_page if keep else 0
	var keep_candidate:int=_candidate_page if keep else 0
	if not same_context or int(view.revision)!=_revision:
		clear_selection()
	_keep_detail_pending=false
	_view=view.duplicate(true)
	_stock_id=stock_id
	_slot=slot
	_mode=mode
	_revision=int(view.revision)
	_tr=translator
	_ko=locale=="ko"
	if not keep_root.is_empty():
		var row:Dictionary=_item(keep_root)
		if not row.is_empty() and row.owned and row.inventory==_stock_id:
			_selected=keep_root
			_detail_page=keep_page
			_component_page=keep_component
			_candidate_page=keep_candidate
			_rotated=row.rotated
			if not keep_target.is_empty() and composition_query.is_valid() and appraisal_query.is_valid():
				var parts:Dictionary=composition_query.call(keep_root)
				for part:Dictionary in parts.get("slots",[]):
					if part.item_id==keep_target and not appraisal_query.call(keep_target).is_empty():
						_appraisal_target=keep_target
						break
	_build()

func _label(key:String,arguments:Dictionary={})->String:
	return str(_tr.call(key,arguments)) if _tr.is_valid() else key

func _line(parent:Control,value:String)->Label:
	var label:=Label.new()
	label.text=value
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent:Control,id:String,value:String,callback:Callable,disabled:bool=false,drag_cell:bool=false)->Button:
	var b:Button=DragCell.new() if drag_cell else Button.new()
	b.name=id
	b.text=value
	b.custom_minimum_size=Vector2(48,48)
	b.disabled=disabled
	parent.add_child(b)
	if parent.name=="inventory_fixed_actions":
		b.tooltip_text=value
		# Size by the actual localized caption rather than count of glyphs.
		# Only this fixed toolbar gets bounded buttons; inventory grid and
		# component/inspection targets retain their existing size behavior.
		var preferred: float=b.get_combined_minimum_size().x
		b.clip_text=true
		b.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio=maxf(1.0,preferred/80.0)
	var epoch:int=_epoch
	b.pressed.connect(func()->void:
		if epoch==_epoch and not _sent and not b.disabled:
			callback.call())
	return b

func _emit(kind:String,payload:Dictionary)->void:
	if _sent or _view.get("locked",true) or _view.get("complete",false):
		return
	_sent=true
	# Inspection and cosmetic care preserve the selected root on a successful
	# single-revision refresh. All drag tokens and operation previews still reset.
	_keep_detail_pending=kind in ["observe","clean_exterior"]
	action_requested.emit(kind,payload,_revision)

func _item(id:String)->Dictionary:
	for row:Dictionary in _view.stock:
		if row.id==id:
			return row
	return {}

func _select(id:String,page:String="overview")->void:
	var row:Dictionary=_item(id)
	if row.is_empty():
		return
	_detail_history_open=false
	_discard_open=false
	_discard_draft.clear()
	_appraisal_target=""
	_prepared_composition.clear()
	_prepared_kind=""
	_selected=id
	_component_page=0
	_candidate_page=0
	_detail_page=page
	_rotated=row.rotated
	_destination=Vector2i(-1,-1)
	_build()

func _footprint(row:Dictionary)->Vector2i:
	var shape:=Vector2i(int(row.width),int(row.height))
	return shape if _rotated==row.rotated else Vector2i(shape.y,shape.x)

func _valid_destination(row:Dictionary,p:Vector2i)->bool:
	return _valid_placement(row,p,_rotated)

func _valid_placement(row:Dictionary,p:Vector2i,rotated:bool)->bool:
	if row.is_empty() or not row.owned or row.inventory!=_stock_id:
		return false
	var footprint:=Vector2i(int(row.width),int(row.height))
	if rotated!=row.rotated:
		footprint=Vector2i(footprint.y,footprint.x)
	var rect:=Rect2i(p,footprint)
	var bounds:=Rect2i(0,0,10,6)
	for grid:Dictionary in _view.stock_grids:
		if grid.id==_stock_id:
			bounds=Rect2i(0,0,int(grid.width),int(grid.height))
	if not bounds.encloses(rect):
		return false
	for other:Dictionary in _view.stock:
		if other.inventory==_stock_id and other.id!=row.id and rect.intersects(Rect2i(int(other.x),int(other.y),int(other.width),int(other.height))):
			return false
	return p!=Vector2i(int(row.x),int(row.y)) or rotated!=row.rotated

func _build()->void:
	var context:String=str(_slot)+":"+_mode+":"+str(_view.phase)+":"+_stock_id+":"+_grid_page_id+":"+str(_legend_open)
	var stock_offset:int=_stock_scroll.scroll_vertical if is_instance_valid(_stock_scroll) and _scroll_context==context else 0
	var detail_offset:int=_detail_scroll.scroll_vertical if is_instance_valid(_detail_scroll) and _scroll_context==context and _scroll_selection==_selected and _scroll_target==_appraisal_target and _scroll_detail_page==_detail_page else 0
	_scroll_context=context
	_scroll_selection=_selected
	_scroll_target=_appraisal_target
	_scroll_detail_page=_detail_page
	_epoch+=1
	_tokens.clear()
	_sent=false
	if is_instance_valid(_body):
		remove_child(_body)
		_body.queue_free()
	# The shell is not a ScrollContainer with disabled axes: that would
	# propagate its child's minimum extent to the host, and a tall detail
	# or wrapping toolbar can push the workspace outside the window.
	clip_contents=true
	_body=VBoxContainer.new()
	_body.name="inventory_bounded_body"
	add_child(_body)
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_inventory()
	_restore_scrolling.call_deferred(_epoch,stock_offset,detail_offset)

func _restore_scrolling(epoch:int,stock_offset:int,detail_offset:int)->void:
	if epoch!=_epoch or not is_instance_valid(_stock_scroll) or not is_instance_valid(_detail_scroll):
		return
	_stock_scroll.set_deferred("scroll_vertical",stock_offset)
	_detail_scroll.set_deferred("scroll_vertical",detail_offset)

func _pane(parent:Control,id:String)->ScrollContainer:
	var pane:=ScrollContainer.new()
	pane.name=id
	pane.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	pane.size_flags_vertical=Control.SIZE_EXPAND_FILL
	pane.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(pane)
	return pane

func _native_texture(texture:Texture2D)->TextureRect:
	var image:=TextureRect.new()
	image.texture=texture
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return image

func _build_native_header(evening:bool)->void:
	_native_time_index=NativeArt.time_index(_view)
	var band:=HBoxContainer.new()
	band.name="native_work_light"
	_body.add_child(band)
	# Keep the lighting preview present, but give the task panes priority
	# in the supported compact desktop landscape layout.
	var scene:=NativeArt.space_preview("stock",_view,Vector2(112,63))
	band.add_child(scene)
	var text:=VBoxContainer.new()
	text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	band.add_child(text)
	_line(text,_label("ui.copy.after_hours_workspace_6bed36b7") if evening else _label("ui.copy.business_stockroom_78d9de60"))
	_line(text,_label("ui.copy.18_00_clock_paused_work_lamp_2937810e") if evening else _label("ui.copy.lighting_follows_business_clock_6cfe15a9"))

func _build_inventory()->void:
	var evening:bool=_view.phase=="workshop"
	if preview_native_v23:
		_build_native_header(evening)
	if not preview_native_v23:
		_line(_body,_label("ui.copy.inventory_evening_work_enabled_c70bc29e") if evening else _label("ui.copy.inventory_stock_management_b833915b"))
	var split:=HBoxContainer.new()
	split.size_flags_vertical=Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation",12)
	_body.add_child(split)
	var left:=VBoxContainer.new()
	left.name="inventory_grid_column"
	left.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio=1.0
	split.add_child(left)
	var right:=VBoxContainer.new()
	right.name="inventory_detail_column"
	right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio=0.85 if preview_native_v23 else 1.15
	split.add_child(right)
	if not preview_native_v23:
		_line(left,_label("ui.copy.stock_select_drag_cb25bbc5"))
	if preview_native_v23:
		var owned:int=0
		var custody:int=0
		for row:Dictionary in _view.stock:
			if row.owned:
				owned+=1
			else:
				custody+=1
		var summary:=_line(left,_label("inventory.format.stock_counts",{"owned":str(owned),"custody":str(custody)}))
		summary.name="native_stock_summary"
		summary.add_theme_color_override("font_color",Color("#A49F90"))
		_build_grid_tabs(left)
	_stock_scroll=_pane(left,"inventory_stock_scroll")
	var storage:=VBoxContainer.new()
	storage.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_stock_scroll.add_child(storage)
	var selected:Dictionary=_item(_selected)
	var heading_parent:Control=right
	if preview_native_v23:
		var heading_row:=HBoxContainer.new()
		heading_row.name="inventory_heading_row"
		right.add_child(heading_row)
		heading_parent=heading_row
	var heading:Label=_line(heading_parent,_label("ui.copy.item_details_714a9da7") if selected.is_empty() else _label("inventory.format.item_heading",{"item":str(selected.id),"name":_label(selected.label)}))
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	heading.name="inventory_selection_header"
	heading.tooltip_text=heading.text
	var drop:Button=_button(right,"inventory_detail_drop",_label("ui.copy.select_drop_item_here_574430c9"),func()->void: pass,false,true)
	drop.clip_text=true
	drop.accepts=_detail_drop_allowed
	drop.commit=_detail_drop
	var grid_back:Button=null
	if preview_native_v23:
		grid_back=_button(heading_parent,"inventory_detail_grid",_label("inventory.legend.grid"),func()->void:
			_detail_page="overview"
			_legend_open=false
			_build())
		grid_back.custom_minimum_size.x=96
		grid_back.hide()
	if preview_native_v23 and not selected.is_empty():
		_build_detail_tabs(right,selected)
	_detail_scroll=_pane(right,"inventory_detail_scroll")
	var detail:=VBoxContainer.new()
	detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_detail_scroll.add_child(detail)
	if preview_native_v23 and _detail_page=="history":
		# The history renderer owns its scroll surface; do not nest two active
		# vertical scrolling regions for the same record.
		_detail_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		_detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		detail.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var key:String=str(_revision)+":"+str(_slot)+":"+str(_view.phase)+":"+_stock_id+":"+_selected
	if key!=_component_cache_key:
		_components=composition_query.call(_selected) if not selected.is_empty() and selected.owned and composition_query.is_valid() else {}
		_component_cache_key=key
	var mutable:bool=not selected.is_empty() and selected.owned and selected.inventory==_stock_id and not _view.locked and not _view.complete
	# Compact unique display codes, never used as an authority identifier.
	# Full identity is available in the legend, tooltip and fixed selection header.
	var display_ids:Array=[]
	for row:Dictionary in _view.stock:
		display_ids.append(str(row.id))
	display_ids.sort()
	var codes:Dictionary={}
	for i:int in range(display_ids.size()):
		codes[display_ids[i]]="%02d" % (i+1)
	for grid:Dictionary in _view.stock_grids:
		if preview_native_v23 and grid.id!=_grid_page_id:
			continue
		if not preview_native_v23:
			_line(storage,_label("ui.copy.owned_stock_ce8e11c5") if grid.id==_stock_id else _label("ui.copy.customer_custody_not_movable_5b46d3f"))
		var cells:=GridContainer.new()
		cells.name="spatial_grid_"+grid.id
		cells.columns=int(grid.width)
		var art_grid:Control=null
		if preview_native_v23:
			art_grid=NativeGrid.new()
			art_grid.name="native_grid_"+str(grid.id)
			storage.add_child(art_grid)
			art_grid.add_child(cells)
		else:
			storage.add_child(cells)
		for y:int in range(int(grid.height)):
			for x:int in range(int(grid.width)):
				var occupied:Dictionary={}
				for row:Dictionary in _view.stock:
					if row.inventory==grid.id and Rect2i(int(row.x),int(row.y),int(row.width),int(row.height)).has_point(Vector2i(x,y)):
						occupied=row
						break
				var p:=Vector2i(x,y)
				var anchor:bool=not occupied.is_empty() and x==int(occupied.x) and y==int(occupied.y)
				var value:String="·" if occupied.is_empty() else (str(codes[occupied.id]) if anchor else "■")
				var preview:bool=mutable and grid.id==_stock_id and _destination.x>=0 and Rect2i(_destination,_footprint(selected)).has_point(p)
				if _prepared_kind in ["detach","replace_component"] and grid.id==_stock_id and p==Vector2i(int(_prepared_composition.x),int(_prepared_composition.y)):
					preview=true
				if preview:
					value="▧"
				var cell:Button=_button(cells,"stock_cell_"+grid.id+"_"+str(x)+"_"+str(y),value,func()->void:
					if grid.id==_stock_id and mutable and (occupied.is_empty() or occupied.id==_selected):
						_prepared_composition.clear()
						_prepared_kind=""
						_destination=p
						_build()
					elif not occupied.is_empty():
						_select(occupied.id),false,true)
				cell.clip_text=true
				# Codes must fit the 48-unit grid even at large UI font settings.
				# Full names in the legend use the normal accessible UI font.
				cell.add_theme_font_size_override("font_size",16)
				cell.set_meta("item_id",str(occupied.id) if not occupied.is_empty() else "")
				cell.set_meta("display_code",str(codes[occupied.id]) if anchor else "")
				if grid.id==_stock_id:
					cell.accepts=func(data:Variant)->bool: return _stock_drop_allowed(data,p)
					cell.commit=func(data:Variant)->void: _stock_drop(data,p)
				if not occupied.is_empty() and not _view.locked and not _view.complete:
					var kind:String="stock" if grid.id==_stock_id and occupied.owned else "detail"
					cell.token=_drag_token(occupied,kind,p-Vector2i(int(occupied.x),int(occupied.y)))
				if preview:
					cell.modulate=Color("#9BB2A5" if preview_native_v23 else "#a8d6ac") if _prepared_kind in ["detach","replace_component"] or _valid_destination(selected,_destination) else Color("#BF8E83" if preview_native_v23 else "#df9e91")
				elif not occupied.is_empty() and occupied.id==_selected:
					cell.modulate=Color("#C4B28B" if preview_native_v23 else "#e9d0a2")
				cell.tooltip_text=_label("ui.copy.empty_cell_48b5c4e3") if occupied.is_empty() else str(codes[occupied.id])+" · "+str(occupied.id)+" · "+_label(occupied.label)
		if is_instance_valid(art_grid):
			art_grid.setup(cells,grid,_view.stock,_selected,_destination)
			# Keep the complete grid at its real cell minimum, plus scrollbar reserve.
			# This minimum is based on the active public grid, never on window guesses.
			left.custom_minimum_size.x=maxf(left.custom_minimum_size.x,cells.get_combined_minimum_size().x+16.0)
			art_grid.visible=not _legend_open
		var legend_text:Array[String]=[]
		for id:String in display_ids:
			var row:Dictionary=_item(id)
			if row.inventory==grid.id:
				legend_text.append(str(codes[id])+" · "+id+" · "+_label(row.label))
		if not legend_text.is_empty() or preview_native_v23:
			var legend:Label=_line(storage,"\n".join(legend_text) if not legend_text.is_empty() else _label("inventory.legend.empty"))
			legend.name="inventory_legend_"+str(grid.id)
			if preview_native_v23:
				# Optional full list has its own explicit view, not a clipped line
				# under the grid. Tooltips still identify every occupied cell.
				legend.visible=_legend_open
	var footer:=VBoxContainer.new()
	footer.name="inventory_fixed_footer"
	_body.add_child(footer)
	# Use a single bounded row of fixed actions, not a wrapping flow whose
	# deferred minimum height can grow after the content panes are laid out.
	# Short captions and full tooltips retain meaning, while clip_text
	# permits shrinking horizontally without reducing the 48px target.
	var controls:=HBoxContainer.new()
	controls.name="inventory_fixed_actions"
	controls.add_theme_constant_override("separation",6)
	footer.add_child(controls)
	if not evening and (not _view.get("condition_quote",{}).is_empty() or not str(_view.get("basic_sale_review_id","")).is_empty()):
		_button(controls,"inventory_return_counter",_label("ui.copy.return_to_counter_cebd9414"),func()->void:
			return_to_counter_requested.emit(_revision))
	_button(controls,"stock_rotate",_label("ui.copy.rotate_f4b9db24"),func()->void:
		_prepared_composition.clear()
		_prepared_kind=""
		_rotated=not _rotated
		_build(),not mutable)
	_button(controls,"stock_confirm",_label("ui.copy.place_7dd2830a"),func()->void:
		_emit("move",{"actor":"player","item_id":_selected,"inventory":_stock_id,"x":_destination.x,"y":_destination.y,"rotated":_rotated}),not mutable or not _valid_destination(selected,_destination))
	_button(controls,"stock_cancel",_label("ui.copy.cancel_d94f1bb5"),func()->void:
		clear_selection()
		_build(),_selected.is_empty())
	if mutable and _destination.x>=0:
		_line(footer,_label("ui.copy.placement_available_2b4c9c70") if _valid_destination(selected,_destination) else _label("ui.copy.unavailable_collision_bounds_or_same_placem_cb2ee070"))
	_build_detail(detail,controls,footer,selected,evening)
	if preview_native_v23:
		_filter_native_actions(controls,mutable,selected.is_empty(),evening)
		# Reading-oriented detail tabs get a full-width focus view when
		# the actual grid and accessible text cannot coexist. Composition
		# stays split for real drag targets. Reflow is UI-only, without rebuilds
		# or a change to selection, evidence, revision or drag authority.
		var layout_epoch:int=_epoch
		var native_header:=_body.find_child("native_work_light",false,false) as Control
		# Preserve the filtered action visibility when responsive focus ends.
		# Placement controls are meaningless without a visible grid.
		var placement_actions:Dictionary={}
		for node:Node in controls.get_children():
			if node is Button and str(node.name) in ["stock_rotate","stock_confirm","stock_cancel"]:
				placement_actions[node]=node.visible
		var reflow:Callable=func()->void:
			if layout_epoch!=_epoch or not is_instance_valid(left) or not is_instance_valid(grid_back):
				return
			var detail_width:float=maxf(420.0,float(get_theme_default_font_size())*21.0)
			var focused:bool=_detail_page in ["appraisal","plan","history"] and not _selected.is_empty() and not _discard_open and _prepared_composition.is_empty() and _destination.x<0 and split.size.x<left.custom_minimum_size.x+detail_width+12.0
			var entering_focus:bool=focused and left.visible
			left.visible=not focused
			drop.visible=not focused
			grid_back.visible=focused
			# The decorative lighting vignette is not a decision input. The
			# contextual clock remains in the HUD; reclaim reading height.
			if is_instance_valid(native_header):
				native_header.visible=not (focused and _detail_page in ["plan","history"])
			for action:Button in placement_actions:
				if is_instance_valid(action):
					action.visible=bool(placement_actions[action]) and not focused
			if entering_focus:
				_detail_scroll.set_deferred("scroll_vertical",0)
				_detail_scroll.set_deferred("scroll_horizontal",0)
		split.resized.connect(reflow)
		reflow.call_deferred()

# Keep confirmation modes focused. This never creates a command or changes its payload.
func _filter_native_actions(controls:Control,mutable:bool,empty:bool,evening:bool)->void:
	var pending:Array[String]=[]
	if not _prepared_composition.is_empty():
		pending=["component_confirm","component_cancel"]
	elif _discard_open:
		pending=["discard_confirm","discard_cancel"]
	for node:Node in controls.get_children():
		if not node is Button:
			continue
		var id:String=str(node.name)
		if not pending.is_empty():
			node.visible=id in pending
		elif id in ["component_confirm","component_cancel"]:
			node.hide()
		elif id in ["stock_rotate","stock_confirm"] and not mutable:
			node.hide()
		elif id=="stock_cancel" and empty:
			node.hide()
		elif id=="work_confirm" and not evening:
			node.hide()
		elif id=="work_confirm" and not _view.work.any(func(row:Dictionary)->bool: return row.id==_selected):
			node.hide()

# Page switching changes no game state, selection or destination.
# Keep the chosen grid across revision refreshes within the same context.
func _build_grid_tabs(parent:Control)->void:
	var available:Array[String]=[]
	for grid:Dictionary in _view.stock_grids:
		available.append(str(grid.id))
	if available.is_empty():
		_grid_page_id=""
		return
	if _grid_page_id not in available:
		_grid_page_id=_stock_id if _stock_id in available else available[0]
	var tabs:=HBoxContainer.new()
	tabs.name="inventory_grid_tabs"
	parent.add_child(tabs)
	for id:String in available:
		var caption:String=_label("ui.copy.owned_stock_ce8e11c5") if id==_stock_id else _label("ui.copy.custody_8dedb8de").strip_edges()
		var tab:=_button(tabs,"inventory_grid_"+id,caption,func()->void:
			_grid_page_id=id
			_legend_open=false
			_build(),id==_grid_page_id and not _legend_open)
		tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tab.clip_text=true
		tab.tooltip_text=_label("ui.copy.stock_select_drag_cb25bbc5") if id==_stock_id else _label("ui.copy.customer_custody_not_movable_5b46d3f")
	var list_button:=_button(tabs,"inventory_legend_toggle",_label("inventory.legend.grid" if _legend_open else "inventory.legend.list"),func()->void:
		_legend_open=not _legend_open
		_build())
	list_button.clip_text=true
	list_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL

# The detail pages share the same selection, revision and authority.
# Only page-local content participates in layout; footer actions stay fixed.
func _build_detail_tabs(parent:Control,selected:Dictionary)->void:
	var pages:Array[String]=["overview"]
	if selected.owned:
		pages.append_array(["appraisal","components","plan"])
	pages.append("history")
	if _detail_page not in pages:
		_detail_page="overview"
	var tabs:=HBoxContainer.new()
	tabs.name="inventory_detail_tabs"
	tabs.add_theme_constant_override("separation",3)
	parent.add_child(tabs)
	for id:String in pages:
		var caption:String=_label("inventory.page."+id)
		var tab:=_button(tabs,"inventory_detail_"+id,caption,func()->void:
			_detail_page=id
			_build(),id==_detail_page or not _prepared_composition.is_empty())
		tab.custom_minimum_size.x=48
		tab.clip_text=true
		tab.tooltip_text=caption
		tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL

func _detail_section(parent:VBoxContainer,page:String)->VBoxContainer:
	if not preview_native_v23:
		return parent
	var content:=VBoxContainer.new()
	content.name="inventory_section_"+page
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(content)
	content.visible=_detail_page==page
	return content

func _money_basis(value:Dictionary)->String:
	return _label("inventory.format.money_pair",{"vkc":str(value.get("VKC") if value.get("VKC")!=null else "—"),"usd":str(value.get("USD") if value.get("USD")!=null else "—")})

func _build_detail(area:VBoxContainer,actions:Control,footer:VBoxContainer,selected:Dictionary,evening:bool)->void:
	var job:Dictionary={}
	for row:Dictionary in _view.work:
		if row.id==_selected:
			job=row
	if selected.is_empty():
		_line(area,_label("ui.copy.select_an_item_review_is_free_4169758e"))
	else:
		var overview:VBoxContainer=_detail_section(area,"overview")
		# Ownership, footprint and recorded basis are decision inputs, not decoration.
		_line(overview,_label("ui.copy.player_owned_stock_632e1d7a") if selected.owned else _label("ui.copy.customer_owned_authorized_service_only_77420968")).name="inventory_overview_ownership"
		_line(overview,_label("inventory.format.footprint",{"width":str(selected.width),"height":str(selected.height)})).name="inventory_overview_footprint"
		if selected.owned:
			_line(overview,_label("inventory.format.root_basis" if not _components.is_empty() else "inventory.format.individual_basis",{"basis":_money_basis(selected.basis)})).name="inventory_overview_basis"
		var availability:String=""
		if not evening:
			availability=_label("ui.copy.restoration_and_composition_changes_availab_24359ec5")
		elif job.is_empty():
			var status:String=str(selected.get("restoration",{}).get("status",""))
			var reason:String="review.work."+status if status in ["review_required","incomplete","known_bad_component","serviceable"] else "ui.copy.no_available_restoration_77a6ed7c"
			availability=_label(reason)
		if preview_native_v23:
			# Cost and completion status precede the illustration, so even a short
			# detail pane presents the transaction consequence before work.
			if evening and not job.is_empty():
				var ticket:=PanelContainer.new()
				ticket.name="native_service_work_ticket"
				overview.add_child(ticket)
				var details:=VBoxContainer.new()
				ticket.add_child(details)
				_line(details,_label("ui.copy.work_slip_e2c533c4")).add_theme_color_override("font_color",Color("#C4B28B"))
				_line(details,_label("inventory.format.restoration_cost",{"cost":_money_basis(job.cost)}))
			for id:String in _view.get("services",{}):
				var service:Dictionary=_view.services[id]
				if service.item_id==selected.id and service.status=="complete":
					var done:=_line(overview,_label("ui.copy.service_complete_awaiting_customer_pickup_89f3cde7"))
					done.name="native_service_complete"
					done.add_theme_color_override("font_color",Color("#9BB2A5"))
			# Keep the work eligibility explanation above the optional image as well.
			if not availability.is_empty():
				_line(overview,availability).name="inventory_overview_availability"
			var texture:Texture2D=NativeArt.stock_texture(selected)
			if texture!=null:
				var portrait:=_native_texture(texture)
				portrait.name="native_selected_art"
				# A cosmetic dust tint disappears after recorded exterior care.
				# This is presentation only, never functional condition or value.
				var recorded: Dictionary = selected.get("exterior_care",{})
				if not recorded.is_empty():
					portrait.modulate=Color.WHITE if recorded.cleaned else Color("#C9C3B6")
					portrait.set_meta("exterior_cleaned",recorded.cleaned)
				portrait.custom_minimum_size.y=112
				portrait.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				var illustration_frame:=PanelContainer.new()
				illustration_frame.name="native_item_frame"
				overview.add_child(illustration_frame)
				illustration_frame.add_child(portrait)
		if evening and selected.owned and discard_query.is_valid():
			var preview:Dictionary=discard_query.call(str(selected.id))
			if preview.get("ok",false) and preview.revision==_revision:
				if not _discard_open:
					_button(actions,"discard_preview",_label("ui.copy.review_discard_3c8f4db7"),func()->void:
						_discard_draft=preview.duplicate(true)
						_discard_open=true
						_detail_page="overview"
						_prepared_composition.clear()
						_prepared_kind=""
						_destination=Vector2i(-1,-1)
						_build())
				elif _discard_draft==preview:
					_line(footer,_label("inventory.format.discard_summary",{"count":str(preview.item_ids.size()),"basis":_money_basis(preview.basis)}))
					_line(overview,_label("inventory.format.discard_ids",{"ids":", ".join(preview.item_ids)}))
					_button(actions,"discard_confirm",_label("ui.copy.discard_4f578617"),func()->void:
						_emit("discard",{"actor":"player","item_id":selected.id,"confirmed_ids":preview.item_ids.duplicate()}),_view.locked or _view.complete)
					_button(actions,"discard_cancel",_label("ui.copy.keep_item_181a689b"),func()->void:
						_discard_open=false
						_discard_draft.clear()
						_build())
		if selected.owned:
			_build_disposition(_detail_section(area,"plan"),selected,job,evening)
		var care: Dictionary = selected.get("exterior_care",{})
		if not care.is_empty():
			_line(overview,_label("ui.copy.exterior_care_recorded_no_price_function_ch_d0113030") if care.cleaned else _label("ui.copy.no_exterior_care_recorded_94fe8880"))
			if evening and not care.cleaned:
				# Keep the selected item's action available regardless of which
				# portion of its independently scrolling detail is displayed.
				_button(actions,"care_exterior",_label("ui.copy.wipe_exterior_86cb1372"),func()->void:
					_emit("clean_exterior",{"actor":"player","item_id":_selected}),not care.allowed or _view.locked or _view.complete)
		if not preview_native_v23:
			if not availability.is_empty():
				_line(overview,availability).name="inventory_overview_availability"
			elif not job.is_empty():
				_line(overview,_label("inventory.format.restoration_cost",{"cost":_money_basis(job.cost)}))
		if not preview_native_v23:
			for id:String in _view.get("services",{}):
				var service:Dictionary=_view.services[id]
				if service.item_id==selected.id and service.status=="complete":
					_line(overview,_label("ui.copy.service_complete_awaiting_customer_pickup_89f3cde7"))
		if not preview_native_v23:
			_button(area,"detail_history_toggle",_label("ui.copy.close_history_d14c1606") if _detail_history_open else _label("ui.copy.transaction_and_work_history_a0515557"),func()->void:
				_detail_history_open=not _detail_history_open
				_build())
		if (_detail_page=="history" if preview_native_v23 else _detail_history_open):
			var history_area:VBoxContainer=_detail_section(area,"history")
			var history:=History.new()
			history.custom_minimum_size.y=160
			if preview_native_v23:
				history.name="inventory_history_records"
				history.native_receipts=true
				history_area.size_flags_vertical=Control.SIZE_EXPAND_FILL
				history.size_flags_vertical=Control.SIZE_EXPAND_FILL
			var index:Dictionary=history_query.call(str(selected.id)) if history_query.is_valid() else {"items":[],"omitted":0}
			history_area.add_child(history)
			history.configure(index,_tr,"ko" if _ko else "en")
		if evening and selected.owned and composition_query.is_valid():
			_build_components(_detail_section(area,"components"),actions,footer,_components)
		if selected.owned and appraisal_query.is_valid():
			_build_appraisal(_detail_section(area,"appraisal"),appraisal_query.call(_appraisal_target if not _appraisal_target.is_empty() else str(selected.id)))
		if not evening and selected.owned and composition_query.is_valid():
			_build_components(_detail_section(area,"components"),actions,footer,_components)
	var affordable:bool=not job.is_empty() and int(_view.wallet.VKC)>=int(job.cost.VKC) and int(_view.wallet.USD)>=int(job.cost.USD)
	var work_caption:String=_label("ui.copy.restore_f7ee4ed5")
	if preview_native_v23 and not job.is_empty():
		# The work slip retains both currency amounts, including zero.
		# The persistent confirm button shows every nonzero direct charge.
		work_caption=_label("inventory.format.restore_both",{"vkc":str(job.cost.VKC),"usd":str(job.cost.USD)}) if int(job.cost.USD)>0 else _label("inventory.format.restore_vkc",{"vkc":str(job.cost.VKC)})
	_button(actions,"work_confirm",work_caption,func()->void:
		_emit("restore_item",{"actor":"player","item_id":_selected}),not evening or not affordable or _view.locked or _view.complete or (preview_native_v23 and not _prepared_composition.is_empty()))
	if evening:
		_button(actions,"work_next_day",_label("ui.copy.next_morning_296e989c"),func()->void:
			_emit("calendar_morning",{}),_view.locked or _view.complete)

# Read-only comparison from the same revision; never predicts future proceeds.
func _build_disposition(area:VBoxContainer,selected:Dictionary,job:Dictionary,evening:bool)->void:
	var has_parts:bool=not _components.is_empty() and int(_components.get("revision",-1))==_revision and _components.has("material_basis")
	var family_basis:String=_money_basis(selected.get("family_basis",_components.get("family_basis",selected.basis)))
	var trade:Dictionary=_view.get("trade",{})
	var quote:Dictionary=_view.get("condition_quote",{})
	var active_buyer:bool=not evening and not _view.locked and not _view.complete and trade.get("item_id")==selected.id and trade.get("seller")=="player" and not trade.get("placement",{}).is_empty() and quote.get("can_sell",true) and quote.get("buyer_can_pay",_view.get("trade_can_pay",false))
	var offer_text:String=_label("inventory.format.offer_amount",{"amount":str(trade.amount),"currency":str(trade.currency)}) if active_buyer else _label("review.plan.no_offer")
	var opportunity:String=offer_text if active_buyer else _label("review.value.unknown")
	var recovered:Array[String]=[]
	for slot:Dictionary in (_components.slots if has_parts else []):
		if not _components.enabled or slot.get("detach",{}).is_empty():
			continue
		var id:String=slot.item_id
		var basis:Dictionary=_components.material_basis.get(id,{})
		recovered.append(_label("inventory.format.recovered_basis",{"item":id,"basis":_money_basis(basis)}))
	var restore_text:String=_label("review.plan.no_restore")
	var affordable:bool=false
	if not job.is_empty():
		restore_text=_money_basis(job.cost)
		affordable=evening and not _view.locked and not _view.complete and int(_view.wallet.VKC)>=int(job.cost.VKC) and int(_view.wallet.USD)>=int(job.cost.USD)
	_line(area,_label("review.plan.title")).name="disposition_title"
	_line(area,_label("inventory.format.plan_basis",{"basis":family_basis})).name="disposition_basis"
	if preview_native_v23:
		_build_disposition_cards(area,active_buyer,offer_text,opportunity,recovered,restore_text,not job.is_empty(),affordable)
		return
	# Historical presentation retains all of its prior information and order.
	_line(area,_label("inventory.format.plan_sale",{"offer":offer_text})).name="disposition_sale"
	if active_buyer:
		_line(area,_label("review.plan.quote_only"))
	_line(area,_label("review.plan.hold")).name="disposition_hold"
	_line(area,_label("review.plan.recover")).name="disposition_recover"
	for row:String in recovered:
		_line(area,row)
	if recovered.is_empty():
		_line(area,_label("review.plan.recover_empty"))
	if not job.is_empty():
		restore_text=_label("inventory.format.plan_cost_status",{"cost":restore_text,"status":_label("review.plan.restore_available" if affordable else "review.plan.restore_unavailable")})
	_line(area,_label("inventory.format.plan_restore",{"cost":restore_text})).name="disposition_restore"
	_line(area,_label("inventory.format.plan_opportunity",{"offer":opportunity})).name="disposition_opportunity"
	_line(area,_label("review.plan.unknown_demand"))
	_line(area,_label("review.plan.not_revenue"))

# Four alternative choices, not four additive cash flows. Every displayed
# amount comes from the same existing public revision; no projected profit.
func _plan_card(parent:GridContainer,id:String)->VBoxContainer:
	var panel:=PanelContainer.new()
	panel.name="disposition_card_"+id
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	# Preserve the theme and normal font size while removing excess vertical
	# padding from dense, read-only comparison cards.
	var compact_style:=panel.get_theme_stylebox("panel").duplicate() as StyleBox
	compact_style.set_content_margin(SIDE_TOP,4.0)
	compact_style.set_content_margin(SIDE_BOTTOM,4.0)
	panel.add_theme_stylebox_override("panel",compact_style)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",2)
	panel.add_child(column)
	return column

func _build_disposition_cards(area:VBoxContainer,active_buyer:bool,offer_text:String,opportunity:String,recovered:Array[String],restore_text:String,has_job:bool,affordable:bool)->void:
	var grid:=GridContainer.new()
	grid.name="disposition_comparison"
	grid.columns=2
	grid.add_theme_constant_override("h_separation",6)
	grid.add_theme_constant_override("v_separation",6)
	area.add_child(grid)
	var sale:=_plan_card(grid,"sale")
	_line(sale,_label("inventory.format.plan_sale",{"offer":offer_text})).name="disposition_sale"
	if active_buyer:
		_line(sale,_label("review.plan.offer_pending"))
	var hold:=_plan_card(grid,"hold")
	_line(hold,_label("review.plan.hold")).name="disposition_hold"
	_line(hold,_label("inventory.format.plan_opportunity",{"offer":opportunity})).name="disposition_opportunity"
	var recover:=_plan_card(grid,"recover")
	_line(recover,_label("review.plan.recover_short")).name="disposition_recover"
	_line(recover,_label("review.plan.recover_empty") if recovered.is_empty() else _label("inventory.format.plan_count",{"count":str(recovered.size())})).name="disposition_recover_count"
	var restore:=_plan_card(grid,"restore")
	_line(restore,_label("inventory.format.plan_restore_short",{"cost":restore_text})).name="disposition_restore"
	if has_job:
		_line(restore,_label("review.plan.restore_ready" if affordable else "review.plan.restore_blocked"))
	_line(area,_label("review.plan.unknown_demand")).name="disposition_demand"
	_line(area,_label("review.plan.not_revenue")).name="disposition_basis_notice"
	var more:=_button(area,"disposition_details_toggle",_label("review.plan.more"),func()->void: pass)
	var details:=VBoxContainer.new()
	details.name="disposition_details"
	area.add_child(details)
	details.hide()
	# Long per-material basis entries and full qualifications are optional
	# reading, never preselected actions or additional financial estimates.
	if active_buyer:
		_line(details,_label("review.plan.quote_only"))
	_line(details,_label("review.plan.recover"))
	for row:String in recovered:
		_line(details,row).name="disposition_recovered_"+str(details.get_child_count())
	if recovered.is_empty():
		_line(details,_label("review.plan.recover_empty"))
	if has_job:
		_line(details,_label("review.plan.restore_available" if affordable else "review.plan.restore_unavailable"))
	more.pressed.connect(func()->void:
		if not is_instance_valid(details):
			return
		details.visible=not details.visible
		more.text=_label("review.plan.less" if details.visible else "review.plan.more"))
	var reflow:Callable=func()->void:
		if is_instance_valid(grid) and is_instance_valid(area):
			grid.columns=2 if area.size.x>=maxf(420.0,float(get_theme_default_font_size())*21.0) else 1
	area.resized.connect(reflow)
	reflow.call_deferred()

# Abstract component slots. Stage only an authority-derived candidate; confirm separately.
func _stage_composition(kind:String,p:Dictionary)->void:
	_discard_open=false
	_discard_draft.clear()
	_prepared_kind=kind
	_prepared_composition=p.duplicate(true)
	if preview_native_v23:
		_detail_page="components"
	_destination=Vector2i(-1,-1)
	_build()

# Slot and candidate navigation are read-only. Never refresh authority here.
func _build_component_navigation(area:VBoxContainer,slots:Array,pending:bool)->void:
	if pending:
		_line(area,_label("inventory.component.preview")).add_theme_color_override("font_color",Color("#C4B28B"))
		return
	if slots.is_empty():
		_line(area,_label("inventory.page.no_components"))
		return
	_component_page=clampi(_component_page,0,slots.size()-1)
	var nav:=HBoxContainer.new()
	nav.name="component_slot_navigation"
	area.add_child(nav)
	_button(nav,"component_slot_previous","‹",func()->void:
		_component_page-=1
		_candidate_page=0
		_build(),_component_page==0)
	var title:=_line(nav,_label("inventory.format.slot_page",{"page":str(_component_page+1),"total":str(slots.size())}))
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_button(nav,"component_slot_next","›",func()->void:
		_component_page+=1
		_candidate_page=0
		_build(),_component_page+1>=slots.size())

func _component_candidates(area:VBoxContainer,values:Array)->Array:
	if not preview_native_v23 or values.size()<=1:
		return values
	_candidate_page=clampi(_candidate_page,0,values.size()-1)
	var nav:=HBoxContainer.new()
	nav.name="component_candidate_navigation"
	area.add_child(nav)
	_button(nav,"component_candidate_previous","‹",func()->void:
		_candidate_page-=1
		_build(),_candidate_page==0)
	var title:=_line(nav,_label("inventory.format.candidate_page",{"page":str(_candidate_page+1),"total":str(values.size())}))
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_button(nav,"component_candidate_next","›",func()->void:
		_candidate_page+=1
		_build(),_candidate_page+1>=values.size())
	return [values[_candidate_page]]

func _build_components(area:VBoxContainer,actions:Control,footer:VBoxContainer,data:Dictionary)->void:
	if data.is_empty() or int(data.get("revision",-1))!=_revision:
		if preview_native_v23:
			_line(area,_label("inventory.page.no_components"))
		return
	var pending:bool=not _prepared_composition.is_empty()
	if preview_native_v23:
		_build_component_navigation(area,data.slots,pending)
	else:
		_line(area,_label("ui.copy.abstract_component_slots_cc4c2618"))
	if data.has("material_basis"):
		if not preview_native_v23 or not pending:
			_line(area,_label("inventory.format.family_basis",{"basis":_money_basis(data.family_basis)}))
		if not preview_native_v23:
			_line(area,_label("inventory.format.additional_expense",{"basis":_money_basis(data.restore_cost)}))
			_line(area,_label("ui.copy.owned_materials_are_not_free_revenue_is_unk_1f4312df"))
		if not _prepared_composition.is_empty():
			var chosen: Dictionary = data.material_basis.get(_prepared_composition.child_id,{})
			var incoming: Dictionary = {} if _prepared_kind=="detach" else chosen
			var outgoing: Dictionary = chosen if _prepared_kind=="detach" else data.material_basis.get(_prepared_composition.get("old_child_id",""),{})
			if not incoming.is_empty():
				_line(area,_label("inventory.format.incoming_basis",{"basis":_money_basis(incoming)}))
			if not outgoing.is_empty():
				_line(area,_label("inventory.format.outgoing_basis",{"basis":_money_basis(outgoing)}))
			var allocated: Dictionary = {}
			for currency: String in ["VKC","USD"]:
				var base: Variant = data.family_basis.get(currency)
				var add: Variant = 0 if incoming.is_empty() else incoming.get(currency)
				var subtract: Variant = 0 if outgoing.is_empty() else outgoing.get(currency)
				allocated[currency] = null if base==null or add==null or subtract==null else int(base)+int(add)-int(subtract)
			_line(area,_label("inventory.format.projected_basis",{"basis":_money_basis(allocated)})).name="component_projected_basis"
			_line(area,_label("ui.copy.composition_itself_costs_no_cash_restoratio_c195f4d7")).name="component_cash_notice"
		if preview_native_v23:
			_line(area,_label("inventory.format.additional_expense",{"basis":_money_basis(data.restore_cost)})).name="component_restore_cost"
	var valid:bool=false
	var slot_number:int=0
	for slot:Dictionary in data.slots:
		slot_number+=1
		# Validate pending candidates across every authoritative slot, even when not rendered.
		if preview_native_v23:
			if _prepared_kind=="detach" and _prepared_composition in slot.get("detach_positions",[]):
				valid=true
			if _prepared_kind=="replace_component" and _prepared_composition in slot.get("replace",[]):
				valid=true
			if _prepared_kind=="attach" and _prepared_composition in slot.get("attach",[]):
				valid=true
			if pending or slot_number-1!=_component_page:
				continue
		var occupied:bool=not str(slot.item_id).is_empty()
		var card:=PanelContainer.new()
		card.name="component_slot_card"
		area.add_child(card)
		var content:=VBoxContainer.new()
		card.add_child(content)
		var title:String=_label("inventory.format.slot_number",{"number":str(slot_number)})
		if not str(slot.get("label_key","")).is_empty():
			title=_label("inventory.format.slot_named",{"number":str(slot_number),"name":_label(slot.label_key)})
		_line(content,_label("inventory.format.slot_contents",{"slot":title,"item":str(slot.item_id) if occupied else _label("ui.copy.empty_e5d310ea")}))
		var buttons:=HFlowContainer.new()
		content.add_child(buttons)
		if occupied:
			if appraisal_query.is_valid() and not appraisal_query.call(str(slot.item_id)).is_empty():
				_button(buttons,"component_appraisal_"+str(slot.item_id),_label("ui.copy.assess_ae77322c"),func()->void:
					_appraisal_target=str(slot.item_id)
					_detail_page="appraisal"
					_build())
			var candidate:Dictionary=slot.detach
			if _prepared_kind=="detach" and _prepared_composition in slot.get("detach_positions",[]):
				valid=true
			var source:Button=_button(buttons,"component_detach_"+str(slot.tag),_label("ui.copy.remove_995fb47b"),func()->void:
				_stage_composition("detach",candidate),candidate.is_empty() or not data.enabled,true)
			if not source.disabled:
				source.token=_drag_token({"id":slot.item_id},"component")
			for exchange:Dictionary in _component_candidates(content,slot.get("replace",[])):
				if _prepared_kind=="replace_component" and exchange==_prepared_composition:
					valid=true
				var replace_target:Button=_button(buttons,"component_replace_"+str(exchange.child_id),_label("inventory.format.exchange_item",{"item":str(exchange.child_id)}),func()->void:
					_stage_composition("replace_component",exchange),not data.enabled,true)
				replace_target.accepts=func(token:Variant)->bool:
					return data.enabled and _token_valid(token,"stock") and str(token.id)==str(exchange.child_id)
				replace_target.commit=func(_token:Variant)->void:
					_stage_composition("replace_component",exchange)
		else:
			for candidate:Dictionary in _component_candidates(content,slot.attach):
				if _prepared_kind=="attach" and candidate==_prepared_composition:
					valid=true
				var target:Button=_button(buttons,"component_attach_"+str(candidate.child_id),_label("inventory.format.attach_item",{"item":str(candidate.child_id)}),func()->void:
					_stage_composition("attach",candidate),not data.enabled,true)
				target.accepts=func(token:Variant)->bool:
					return data.enabled and _token_valid(token,"stock") and str(token.id)==str(candidate.child_id)
				target.commit=func(_token:Variant)->void:
					_stage_composition("attach",candidate)
	if not _prepared_composition.is_empty():
		var kind_text:String=_label("ui.copy.remove_995fb47b") if _prepared_kind=="detach" else (_label("ui.copy.attach_e13a33af") if _prepared_kind=="attach" else _label("ui.copy.exchange_66cb631a"))
		var summary:String=_label("inventory.format.pending_attach",{"kind":kind_text,"item":str(_prepared_composition.child_id)})
		if _prepared_kind=="replace_component":
			summary=_label("inventory.format.pending_replace",{"kind":kind_text,"item":str(_prepared_composition.child_id),"outgoing":str(_prepared_composition.old_child_id),"x":str(_prepared_composition.x+1),"y":str(_prepared_composition.y+1)})
		elif _prepared_kind=="detach":
			summary=_label("inventory.format.pending_detach",{"kind":kind_text,"item":str(_prepared_composition.child_id),"x":str(_prepared_composition.x+1),"y":str(_prepared_composition.y+1)})
		var preview_label:Label=_line(footer,summary)
		preview_label.name="inventory_preview_summary"
	_button(actions,"component_confirm",_label("ui.copy.apply_parts_69f89d86"),func()->void:
		_emit(_prepared_kind,_prepared_composition.duplicate(true)),not valid or not data.enabled)
	_button(actions,"component_cancel",_label("ui.copy.cancel_parts_ab9e9c5a"),func()->void:
		_prepared_composition.clear()
		_prepared_kind=""
		_build(),_prepared_composition.is_empty())

# Actual observation buttons use existing authority, never a display-side truth.
func _build_appraisal(area:VBoxContainer,data:Dictionary)->void:
	if data.is_empty() or data.get("revision",-1)!=_revision:
		if preview_native_v23:
			_line(area,_label("inventory.page.no_assessment"))
		return
	# The selected root is already in the persistent detail heading. A child
	# still needs an explicit identity so its evidence cannot be misattributed.
	if not preview_native_v23 or not _appraisal_target.is_empty():
		_line(area,_label("inventory.format.assessed_item",{"item":str(data.item_id)}))
	var basis:Dictionary=data.get("basis",{})
	var basis_label:Label=_line(area,_label("inventory.format.assessment_family_basis" if _appraisal_target.is_empty() and not _components.is_empty() else "inventory.format.assessment_item_basis",{"basis":_money_basis(basis)}))
	basis_label.name="appraisal_basis_"+str(data.item_id)
	var quality:String=str(data.get("quality","unknown"))
	var quality_text:String=_label("ui.copy.unknown_a150fe4")
	match quality:
		"inoperable": quality_text=_label("ui.copy.inoperable_2e345410")
		"refurbished": quality_text=_label("ui.copy.refurbished_9d11a831")
		"serviceable": quality_text=_label("ui.copy.serviceable_f3da9c82")
	var quality_label:Label=_line(area,_label("inventory.format.assessment_quality",{"quality":quality_text}))
	quality_label.name="appraisal_quality_"+str(data.item_id)
	if not _appraisal_target.is_empty():
		_button(area,"appraisal_root",_label("ui.copy.return_to_root_assessment_5e3e949"),func()->void:
			_appraisal_target=""
			_build())
	for test:Dictionary in data.tests:
		var key:String=test.key
		var label:String=_label("ui.copy.function_db9959e9") if key=="functional" else (_label("ui.copy.completeness_62959d0b") if key=="complete" else _label("ui.copy.restoration_status_3bcca6d2"))
		var fact:Dictionary=test.fact
		var description:String=_label("ui.copy.unknown_a150fe4")
		if not fact.is_empty():
			description=_label("inventory.format.fact_current" if fact.current else "inventory.format.fact_historical",{"value":_label("ui.copy.yes_c5a2dae0") if fact.observed_value else _label("ui.copy.no_3885b742")})
		# HFlow apportions minimum widths; an autowrapped label can collapse
		# to a narrow column. A bounded expanding label and short action
		# inside HBox keep text readable and never stretch the button vertically.
		var fact_row:=HBoxContainer.new()
		fact_row.name="appraisal_row_"+str(data.item_id)+"_"+key
		fact_row.add_theme_constant_override("separation",8)
		area.add_child(fact_row)
		var fact_label:Label=_line(fact_row,_label("inventory.format.fact_row",{"name":label,"description":description}))
		fact_label.name="appraisal_fact_"+str(data.item_id)+"_"+key
		fact_label.custom_minimum_size.x=120
		fact_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		fact_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		# Explain what this public fact can establish without predicting a repair,
		# price or hidden condition. Keep the existing compact rows unchanged.
		var limit_key:String={"functional":"inventory.assessment.limit_function","complete":"inventory.assessment.limit_completeness","restored":"inventory.assessment.limit_restoration"}.get(key,"")
		if not limit_key.is_empty():
			fact_label.mouse_filter=Control.MOUSE_FILTER_STOP
			fact_label.tooltip_text=_label(limit_key)
		var inspect:Button=_button(fact_row,"inventory_observe_"+str(data.item_id)+"_"+key,(_label("ui.copy.free_review_f3820f59") if test.minutes==0 else _label("inventory.format.inspect_minutes",{"minutes":str(test.minutes)})),func()->void:
			var payload:Dictionary={"actor":"player","item_id":data.item_id,"key":key}
			if test.get("owned_review",false):
				payload["owned_review"]=true
			_emit("observe",payload),not test.allowed or _view.locked or _view.complete)
		inspect.custom_minimum_size.x=96
		inspect.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		inspect.tooltip_text=_label("inventory.format.inspect_tooltip",{"name":label,"minutes":str(test.minutes)})
		if not limit_key.is_empty():
			inspect.tooltip_text+="\n"+_label(limit_key)
