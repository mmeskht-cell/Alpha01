extends RefCounted
## Imported, licensed font is resolved when the scene starts, not while the editor imports assets.
const PATH: String = "res://assets/fonts/NotoSansCJKkr-Regular.otf"

static func apply_to(root: Control) -> bool:
	if not ResourceLoader.exists(PATH, "FontFile"):
		push_error("ZT_FONT_NOT_PREPARED: run tools/prepare_runtime_assets.py and import")
		return false
	var font := ResourceLoader.load(PATH, "FontFile") as Font
	if font == null or not font.has_char(0xD55C) or not font.has_char(0xAE00):
		push_error("ZT_FONT_INVALID")
		return false
	var ui := Theme.new()
	ui.default_font = font
	ui.default_font_size = 16
	ui.set_color("font_color", "Label", Color("#e8e1cd"))
	ui.set_color("font_color", "Button", Color("#e8e1cd"))
	ui.set_color("font_hover_color", "Button", Color("#f8efd9"))
	ui.set_color("font_pressed_color", "Button", Color("#f8efd9"))
	ui.set_color("font_disabled_color", "Button", Color("#92958a"))
	ui.set_stylebox("normal", "Button", _surface("#3d483e", "#7f8b74"))
	ui.set_stylebox("hover", "Button", _surface("#505d4d", "#c2af79"))
	ui.set_stylebox("pressed", "Button", _surface("#2b3830", "#c2af79"))
	ui.set_stylebox("disabled", "Button", _surface("#323831", "#545b50"))
	ui.set_stylebox("focus", "Button", _focus())
	ui.set_stylebox("panel", "PanelContainer", _surface("#252e29", "#8e8468", 12))
	root.theme = ui
	return true

static func _surface(fill: String, edge: String, inset: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(edge)
	style.set_border_width_all(1)
	style.content_margin_left = inset
	style.content_margin_right = inset
	style.content_margin_top = inset
	style.content_margin_bottom = inset
	return style

static func _focus() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = Color("#e6c974")
	style.set_border_width_all(2)
	return style

## Native candidate only; keep old baseline theme unchanged.
static func apply_native(ui:Theme)->void:
	for kind:String in ["Label","Button","OptionButton","CheckButton","LineEdit","RichTextLabel"]:
		ui.set_color("font_color",kind,Color("#D5D0C3"))
		ui.set_color("font_hover_color",kind,Color("#D5D0C3"))
		ui.set_color("font_pressed_color",kind,Color("#D5D0C3"))
		ui.set_color("font_focus_color",kind,Color("#D5D0C3"))
		ui.set_color("font_disabled_color",kind,Color("#A49F90"))
	for kind:String in ["Button","OptionButton"]:
		ui.set_stylebox("normal",kind,_surface("#2A3032","#536168"))
		ui.set_stylebox("hover",kind,_surface("#394247","#C4B28B"))
		ui.set_stylebox("pressed",kind,_surface("#202628","#D18A4F"))
		ui.set_stylebox("disabled",kind,_surface("#202628","#33393B"))
		var focus:=_focus()
		focus.border_color=Color("#C4B28B")
		ui.set_stylebox("focus",kind,focus)
	ui.set_stylebox("panel","PanelContainer",_surface("#2A3032","#536168",12))
	ui.set_stylebox("panel","ScrollContainer",_surface("#202628","#33393B",4))
	ui.set_stylebox("normal","LineEdit",_surface("#15191B","#738087"))
	ui.set_stylebox("read_only","LineEdit",_surface("#202628","#536168"))
	ui.set_stylebox("panel","PopupMenu",_surface("#252A2D","#738087"))
	ui.set_color("font_color","PopupMenu",Color("#D5D0C3"))
	ui.set_color("font_hover_color","PopupMenu",Color("#D5D0C3"))
	ui.set_stylebox("hover","PopupMenu",_surface("#394247","#C4B28B"))
