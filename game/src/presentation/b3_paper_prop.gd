extends Control
## Irregular paper silhouettes drawn under real labels and hit targets.
const INK := Color("#392d22")
var form := "card"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_on(self,size,form)

static func draw_on(canvas: CanvasItem, extent: Vector2, crease: String) -> void:
	if extent.x<24.0 or extent.y<24.0: return
	var w := extent.x
	var h := extent.y
	var fold := minf(24.0,h*0.20)
	var shape := PackedVector2Array([Vector2(4,6),Vector2(w-fold,2),Vector2(w-3,fold),Vector2(w-7,h-8),Vector2(w*0.68,h-5),Vector2(12,h-3),Vector2(3,h*0.50)])
	var shadow := PackedVector2Array()
	for point: Vector2 in shape: shadow.append(point+Vector2(4,6))
	canvas.draw_colored_polygon(shadow,Color("#19120fb5"))
	var stock := Color("#d3c3a3")
	match crease:
		"receipt": stock = Color("#e2d3ae")
		"notes": stock = Color("#d0bc94")
		"file": stock = Color("#c6b18c")
		"news": stock = Color("#b2a58a")
		"marked": stock = Color("#dfc497")
		"book":
			_book(canvas,w,h)
			return
	if crease in ["file","news"]:
		var leaf := PackedVector2Array([Vector2(11,0),Vector2(w-14,1),Vector2(w-1,h-17),Vector2(w-19,h-2),Vector2(1,h-10)])
		canvas.draw_colored_polygon(leaf,Color("#a28c6e"))
	canvas.draw_colored_polygon(shape,stock)
	var edge := shape.duplicate()
	edge.append(shape[0])
	canvas.draw_polyline(edge,Color("#98805e"),1)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(w-fold,2),Vector2(w-fold+1,fold+4),Vector2(w-3,fold)]),stock.darkened(0.22))
	if crease in ["price","receipt","file","notes"]:
		var y := roundf(h*0.31)
		canvas.draw_line(Vector2(17,y),Vector2(w-18,y-2),Color("#8a6c4c59"))
	if crease=="marked":
		canvas.draw_line(Vector2(14,20),Vector2(14,h-17),Color("#8d592c"),2)
	elif crease=="news":
		canvas.draw_line(Vector2(w*0.49,8),Vector2(w*0.51,h-10),Color("#78694f89"))
		for y in range(23,int(h)-8,8):
			canvas.draw_line(Vector2(15,y),Vector2(w*0.43,y),Color("#7c6a506a"))
			canvas.draw_line(Vector2(w*0.57,y+2),Vector2(w-18,y+2),Color("#7c6a506a"))
	# Sparse, deterministic fibers keep the print clean at 100% and 150%.
	for n in range(12):
		var x := 17+fposmod(float(n*71),maxf(1,w-36))
		var y := 11+fposmod(float(n*23),maxf(1,h-22))
		canvas.draw_rect(Rect2(x,y,2+(n%3),1),Color("#795e3e20"))

static func _book(canvas: CanvasItem, w: float,h: float) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(4,12),Vector2(w-3,8),Vector2(w-1,h-6),Vector2(7,h-1)]),Color("#433b30"))
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(9,14),Vector2(w-9,12),Vector2(w-6,h-10),Vector2(11,h-7)]),Color("#a99471"))
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(15,12),Vector2(36,6),Vector2(45,15),Vector2(w-25,4),Vector2(w-13,15),Vector2(w-12,h-16),Vector2(46,h-12),Vector2(25,h-17),Vector2(12,h-11)]),Color("#d9c9a7"))
	canvas.draw_line(Vector2(34,7),Vector2(38,h-16),Color("#a58d66"),4)
	canvas.draw_line(Vector2(41,15),Vector2(44,h-13),Color("#f0dfbb"),2)
	canvas.draw_line(Vector2(50,65),Vector2(w-23,65),Color("#9e8561"),1)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(w-56,2),Vector2(w-40,2),Vector2(w-39,29),Vector2(w-48,24),Vector2(w-55,29)]),Color("#85644c"))

static func ink_action(button: Button, marked: bool = false) -> void:
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color.TRANSPARENT if state in ["normal","disabled","focus"] else Color("#94693d2d")
		style.border_color = Color("#785537") if marked or state!="normal" else Color("#9a7e576c")
		style.border_width_bottom = 2 if state!="disabled" else 0
		style.content_margin_left = 8
		style.content_margin_right = 8
		button.add_theme_stylebox_override(state,style)
	for key: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]:
		button.add_theme_color_override(key,INK)
	button.add_theme_color_override("font_disabled_color",Color("#65584a"))
