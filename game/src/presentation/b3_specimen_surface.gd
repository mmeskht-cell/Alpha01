extends TextureRect
## Keep the active specimen on the desk when the register or reference leaf changes.
var source: Texture2D
var face: Texture2D

func present(model: Texture2D, desk: Rect2) -> void:
	if source!=model:
		source = model
		face = model
		if model!=null:
			var pixels := model.get_image()
			if pixels!=null and not pixels.is_empty():
				var bounds := pixels.get_used_rect()
				if bounds.has_area() and bounds.size!=pixels.get_size():
					var crop := AtlasTexture.new()
					crop.atlas = model
					crop.region = bounds
					face = crop
	texture = face
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = desk.size
	if face!=null:
		var natural := face.get_size()
		if natural.x>0 and natural.y>0:
			size = natural*minf(desk.size.x/natural.x,desk.size.y/natural.y)
	position = Vector2(desk.get_center().x-size.x*0.5,desk.end.y-size.y)
	show()
