extends Button
## UI-only prepared-card identity; never embeds a value or private truth.
var token: Dictionary = {}

func _get_drag_data(_position: Vector2) -> Variant:
	if disabled or token.is_empty():
		return null
	if has_meta("native_tool_drag") and icon!=null and token.get("kind")=="tool":
		var preview:=Control.new()
		var picture:=TextureRect.new()
		picture.texture=icon
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
		picture.position=Vector2(-28,-28)
		picture.size=Vector2(56,56)
		preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
		preview.add_child(picture)
		set_drag_preview(preview)
	elif has_meta("paper_drag_text"):
		var preview:=PanelContainer.new()
		preview.custom_minimum_size=Vector2(192,86)
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("#B8C5B8" if get_meta("paper_drag_kind")=="fact" else "#BDAD8E")
		style.border_color=Color("#74644C")
		style.set_border_width_all(2)
		style.content_margin_left=8
		style.content_margin_right=8
		style.content_margin_top=6
		style.content_margin_bottom=6
		preview.add_theme_stylebox_override("panel",style)
		var caption:=Label.new()
		caption.text=str(get_meta("paper_drag_text"))
		caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		caption.add_theme_color_override("font_color",Color("#242B2C"))
		caption.add_theme_font_size_override("font_size",15)
		preview.add_child(caption)
		set_drag_preview(preview)
	elif icon!=null:
		var tray:=HBoxContainer.new()
		var picture:=TextureRect.new()
		picture.texture=icon
		picture.custom_minimum_size=Vector2(36,36)
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		tray.add_child(picture)
		var caption:=Label.new()
		caption.text=text
		tray.add_child(caption)
		set_drag_preview(tray)
	else:
		var preview := Label.new()
		preview.text = text
		set_drag_preview(preview)
	return token.duplicate(true)
