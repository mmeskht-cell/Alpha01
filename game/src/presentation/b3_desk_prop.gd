extends Control
## Desk objects share silhouette geometry for resting, held, and drag presentations.
var kind := ""
var sample: Texture2D
var lifted := false
var follow_target := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(follow_target)

func _process(_delta: float) -> void:
	var target := get_parent() as Control
	if target==null: return
	var cursor := target.get_local_mouse_position()
	visible = Rect2(Vector2.ZERO,target.size).has_point(cursor)
	position = cursor+Vector2(12,-size.y*0.6)

func _draw() -> void:
	var brass := Color("#af9874")
	var steel := Color("#a9b0a7")
	var dark := Color("#302f29")
	var center := size*0.5
	if kind=="sample":
		var radius := minf(size.x,size.y)*0.44
		draw_line(center+Vector2(-radius*1.35,radius*0.9),center,brass,2)
		draw_circle(center,radius+5,dark)
		draw_circle(center,radius+3,brass)
		var points := PackedVector2Array()
		var uv := PackedVector2Array()
		for index in range(64):
			var normal := Vector2.from_angle(TAU*index/64.0)
			points.append(center+normal*radius)
			uv.append(Vector2.ONE*0.5+normal*0.5)
		if sample: draw_polygon(points,PackedColorArray([Color.WHITE]),uv,sample)
		return
	draw_set_transform(Vector2(1,-4 if lifted else 0),0,Vector2(size.x/96.0,size.y/70.0))
	if kind=="book":
		draw_colored_polygon(PackedVector2Array([Vector2(5,13),Vector2(79,6),Vector2(92,52),Vector2(17,62)]),Color("#46382d"))
		draw_colored_polygon(PackedVector2Array([Vector2(16,55),Vector2(90,46),Vector2(89,51),Vector2(17,60)]),Color("#c3b394"))
		draw_colored_polygon(PackedVector2Array([Vector2(4,9),Vector2(78,2),Vector2(90,46),Vector2(16,56)]),Color("#536052"))
		draw_line(Vector2(13,9),Vector2(24,54),brass,2)
		draw_line(Vector2(31,20),Vector2(69,16),brass,1)
	elif kind=="phone":
		draw_colored_polygon(PackedVector2Array([Vector2(12,61),Vector2(22,30),Vector2(72,30),Vector2(85,61)]),dark)
		draw_circle(Vector2(49,46),12,brass)
		draw_circle(Vector2(49,46),6,dark)
		draw_polyline(PackedVector2Array([Vector2(12,31),Vector2(17,18),Vector2(73,18),Vector2(81,32)]),steel,10,true)
	elif kind in ["wear_detail","display_damage_detail","material_detail"]:
		draw_line(Vector2(46,33),Vector2(77,57),dark,12,true)
		draw_line(Vector2(47,32),Vector2(75,54),brass,7,true)
		draw_circle(Vector2(34,22),19,dark)
		draw_circle(Vector2(34,22),16,steel)
		draw_circle(Vector2(34,22),13,Color("#536565"))
		draw_arc(Vector2(34,22),10,3.3,4.9,12,Color("#dbdec9"),2,true)
	elif kind in ["function_detail","condition_detail"]:
		draw_rect(Rect2(16,7,43,44),dark)
		draw_rect(Rect2(20,12,35,17),steel)
		draw_line(Vector2(34,25),Vector2(43,15),dark,2)
		draw_circle(Vector2(38,39),6,brass)
		draw_polyline(PackedVector2Array([Vector2(53,47),Vector2(66,59),Vector2(76,48),Vector2(72,24)]),steel,3,true)
	else:
		draw_set_transform(Vector2(size.x*0.22,size.y*0.16),-0.12,Vector2(size.x/96.0,size.y/70.0))
		draw_rect(Rect2(3,4,48,39),dark)
		draw_rect(Rect2(0,0,48,39),Color("#c6b898"))
		for y in [10,18,26]: draw_line(Vector2(6,y),Vector2(35,y),brass,2)
