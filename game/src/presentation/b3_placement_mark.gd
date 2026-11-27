extends Control
## Pure screen-space mark for the authoritative grid footprint.
enum Kind { ORIGIN, DESTINATION, BLOCKED }
var kind: int = Kind.ORIGIN
var cell_size := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var edges := Rect2(Vector2(1,1),size-Vector2(2,2))
	if not edges.has_area(): return
	var border: Color = [Color("#e4c18d"),Color("#9be2ad"),Color("#f4a589")][kind]
	if kind==Kind.ORIGIN:
		for x in range(2,int(size.x)-2,12):
			var stop := minf(x+7,size.x-2)
			draw_line(Vector2(x,2),Vector2(stop,2),border,2)
			draw_line(Vector2(x,size.y-2),Vector2(stop,size.y-2),border,2)
		for y in range(2,int(size.y)-2,12):
			var stop := minf(y+7,size.y-2)
			draw_line(Vector2(2,y),Vector2(2,stop),border,2)
			draw_line(Vector2(size.x-2,y),Vector2(size.x-2,stop),border,2)
		return
	var tint := Color("#a15b494d") if kind==Kind.BLOCKED else Color("#66997852")
	draw_rect(edges,tint)
	if cell_size>0.0:
		var divider := Color(border,0.48)
		for x in range(1,floori(size.x/cell_size)):
			draw_line(Vector2(x*cell_size,1),Vector2(x*cell_size,size.y-1),divider)
		for y in range(1,floori(size.y/cell_size)):
			draw_line(Vector2(1,y*cell_size),Vector2(size.x-1,y*cell_size),divider)
	draw_rect(edges,border,false,2)
	if kind==Kind.BLOCKED:
		for x in range(2,int(size.x),16):
			var length := minf(13,minf(size.x-x-1,size.y-3))
			if length>0: draw_line(Vector2(x,2),Vector2(x+length,2+length),border)
