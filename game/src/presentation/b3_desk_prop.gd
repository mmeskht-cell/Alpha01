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
	if kind=="surface_plate":
		var frame := Rect2(Vector2.ZERO,size)
		draw_rect(frame.grow(3.0),Color("#17140d9e"))
		draw_rect(frame,Color("#201f1b"))
		draw_rect(frame.grow(-3.0),Color("#8c795a"),false,2.0)
		if sample: draw_texture_rect(sample,frame.grow(-8.0),false)
		return
	if kind=="reference_plate":
		var side := minf(size.x,size.y)-6.0
		var mount := Rect2(center-Vector2.ONE*side/2.0,Vector2.ONE*side)
		draw_rect(mount.grow(2.0),Color("#8c7352"))
		draw_rect(mount,Color("#54493b"))
		if sample: draw_texture_rect(sample,mount.grow(-2.0),false)
		return
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
	if kind=="drawer":
		draw_colored_polygon(PackedVector2Array([Vector2(9,32),Vector2(86,29),Vector2(93,56),Vector2(8,60)]),Color("#211a15"))
		draw_colored_polygon(PackedVector2Array([Vector2(7,25),Vector2(84,23),Vector2(91,47),Vector2(7,50)]),Color("#624932"))
		draw_line(Vector2(10,46),Vector2(88,43),Color("#aa8055"),2)
		draw_rect(Rect2(12,51,72,10),Color("#362920"))
		draw_line(Vector2(37,53),Vector2(57,52),brass,3)
	elif kind=="book":
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
	elif kind=="material_detail":
		draw_rect(Rect2(18,14,49,42),dark)
		draw_rect(Rect2(20,14,43,36),Color("#7d7561"))
		draw_circle(Vector2(41,31),12,Color("#b7a585"))
		draw_circle(Vector2(41,31),8,Color("#47535a"))
		draw_line(Vector2(65,35),Vector2(83,33),brass,5)
	elif kind=="display_damage_detail":
		draw_colored_polygon(PackedVector2Array([Vector2(18,13),Vector2(69,13),Vector2(76,43),Vector2(26,49)]),dark)
		draw_colored_polygon(PackedVector2Array([Vector2(20,13),Vector2(66,13),Vector2(72,39),Vector2(28,44)]),steel)
		draw_rect(Rect2(30,19,29,15),Color("#526471"))
		draw_line(Vector2(49,42),Vector2(64,63),brass,5)
	elif kind=="wear_detail":
		draw_line(Vector2(46,33),Vector2(77,57),dark,12,true)
		draw_line(Vector2(47,32),Vector2(75,54),brass,7,true)
		draw_circle(Vector2(34,22),19,dark)
		draw_circle(Vector2(34,22),16,steel)
		draw_circle(Vector2(34,22),13,Color("#536565"))
		draw_arc(Vector2(34,22),10,3.3,4.9,12,Color("#dbdec9"),2,true)
	elif kind=="identity":
		draw_colored_polygon(PackedVector2Array([Vector2(12,10),Vector2(67,4),Vector2(84,47),Vector2(25,59)]),Color("#212721"))
		draw_colored_polygon(PackedVector2Array([Vector2(13,8),Vector2(65,3),Vector2(77,42),Vector2(24,52)]),Color("#4c5749"))
		draw_line(Vector2(25,48),Vector2(76,39),Color("#b2a283"),2)
		draw_rect(Rect2(32,16,22,10),Color("#bcaa85"))
	elif kind=="batch_detail":
		draw_rect(Rect2(17,28,54,27),dark)
		draw_rect(Rect2(14,23,53,25),Color("#9a835f"))
		draw_rect(Rect2(20,18,53,25),Color("#cbb997"))
		for column in range(6):
			draw_line(Vector2(26+column*6,26),Vector2(26+column*6,37),dark,1)
	elif kind=="casing_detail":
		draw_colored_polygon(PackedVector2Array([Vector2(9,47),Vector2(69,9),Vector2(85,25),Vector2(24,65)]),dark)
		draw_colored_polygon(PackedVector2Array([Vector2(8,44),Vector2(68,6),Vector2(81,21),Vector2(23,60)]),brass)
		for step in range(6):
			var tick := Vector2(16,43)+Vector2(9,-6)*step
			draw_line(tick,tick+Vector2(4,4 if step%2==0 else 2),dark,1.5)
	elif kind in ["function_detail","condition_detail","basic_function_v1"]:
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
