extends Control
## A presentation-only overlay over real inventory cells. No input or authority.
const Art=preload("res://src/presentation/native_v23_art.gd")
var _grid:GridContainer
var _spec:Dictionary
var _rows:Array=[]
var _images:Dictionary={}
var _selected:String=""
var _destination:Vector2i
var _layer:Control

func setup(grid:GridContainer,spec:Dictionary,rows:Array,selected:String,destination:Vector2i)->void:
	_grid=grid
	_spec=spec.duplicate(true)
	_rows=rows.duplicate(true)
	_selected=selected
	_destination=destination
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size=_grid.get_combined_minimum_size()
	_layer=Control.new()
	_layer.name="native_art_layer"
	_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for row:Dictionary in _rows:
		if row.inventory!=_spec.id:
			continue
		var texture:Texture2D=Art.stock_texture(row)
		if texture==null:
			continue
		if row.rotated:
			var pixels:Image=texture.get_image()
			if pixels!=null and not pixels.is_empty():
				pixels.rotate_90(CLOCKWISE)
				texture=ImageTexture.create_from_image(pixels)
		var icon:=TextureRect.new()
		icon.name="native_item_"+str(row.id)
		icon.texture=texture
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		icon.set_meta("item_id",row.id)
		icon.set_meta("owned",row.owned)
		icon.set_meta("rotated",row.rotated)
		# Placement preview belongs to the real cells; fade committed art only.
		if row.id==_selected and _destination.x>=0:
			icon.modulate.a=0.45
		_layer.add_child(icon)
		_images[row.id]=icon
	_grid.sort_children.connect(_sync.call_deferred)
	resized.connect(_sync.call_deferred)
	_sync.call_deferred()

func _sync()->void:
	if not is_instance_valid(_grid) or not is_instance_valid(_layer):
		return
	var columns:int=int(_spec.width)
	for row:Dictionary in _rows:
		if not _images.has(row.id):
			continue
		var first:int=int(row.y)*columns+int(row.x)
		var last:int=(int(row.y)+int(row.height)-1)*columns+int(row.x)+int(row.width)-1
		if first<0 or last>=_grid.get_child_count():
			continue
		var a:Control=_grid.get_child(first)
		var b:Control=_grid.get_child(last)
		var bounds:Rect2=a.get_rect().merge(b.get_rect())
		var icon:TextureRect=_images[row.id]
		icon.position=bounds.position+Vector2(3,3)
		icon.size=(bounds.size-Vector2(6,6)).max(Vector2.ONE)
