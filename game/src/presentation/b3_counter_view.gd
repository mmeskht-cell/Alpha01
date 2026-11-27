extends Control
## Shares the same counter between two view angles. All motion is in canvas space.
const FRONT_EDGE := 416.0
const OVERHEAD_EDGE := 68.0
const TURN_TIME := 0.26
const PAD := Rect2(287,161,516,433)
var front: Control
var wood: Texture2D
var overhead_wood: Texture2D
var overhead := false
var pitch := 0.0
var _turn: Tween
var _carry: Tween
var _carried: Dictionary = {}

func _ready() -> void:
	name = "counter_tabletop"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func aim(down: bool, instant: bool) -> void:
	var target := 1.0 if down else 0.0
	if instant:
		if _turn and _turn.is_valid(): _turn.kill()
		overhead = down
		_project(target)
	elif overhead!=down:
		overhead = down
		if _turn and _turn.is_valid(): _turn.kill()
		_turn = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_turn.tween_method(_project,pitch,target,TURN_TIME)

func _project(amount: float) -> void:
	pitch = amount
	front.scale = Vector2.ONE+Vector2(0.045,0.16)*amount
	var lip := lerpf(FRONT_EDGE,OVERHEAD_EDGE,amount)
	front.position = Vector2(-28.0*amount,lip-FRONT_EDGE*front.scale.y-64.0*amount*amount)
	front.visible = amount<1.0
	visible = amount>0.0
	self_modulate.a = minf(1.0,amount*5.0)
	queue_redraw()

func _draw() -> void:
	if pitch<=0.0: return
	var edge := lerpf(FRONT_EDGE,OVERHEAD_EDGE,pitch)
	var timber := PackedVector2Array([Vector2(-28,edge),Vector2(1308,edge),Vector2(1328,720),Vector2(-48,720)])
	draw_rect(Rect2(0,0,1280,edge),Color(0.10,0.085,0.071,pitch))
	draw_colored_polygon(timber,Color("#584534"))
	if overhead_wood:
		var top_uv := PackedVector2Array([Vector2.ZERO,Vector2(1,0),Vector2.ONE,Vector2(0,1)])
		draw_polygon(timber,PackedColorArray([Color.WHITE]),top_uv,overhead_wood)
	elif wood:
		# Reproject the opaque face of the approved R2 counter without its
		# transparent upper half or the illuminated front fascia.
		var uv := PackedVector2Array([Vector2(0.015,0.586),Vector2(0.985,0.586),Vector2(0.985,0.900),Vector2(0.015,0.900)])
		draw_polygon(timber,PackedColorArray([Color.WHITE]),uv,wood)
	else:
		for y in range(1,9):
			var seam := lerpf(edge,720.0,float(y)/9.0)
			draw_line(Vector2(0,seam),Vector2(1280,seam),Color("#342b23"),3)
			draw_line(Vector2(0,seam+3),Vector2(1280,seam+3),Color("#80644b"),1)
	draw_rect(Rect2(0,edge,1280,13),Color("#261c16"))
	draw_line(Vector2(0,edge+13),Vector2(1280,edge+13),Color("#aa8055"),2)
	draw_rect(Rect2(0,edge+15,1280,19),Color("#1d151075"))
	# Spill from the existing warm shop lamp on the upper-right side.
	draw_polygon(timber,PackedColorArray([Color("#29425018"),Color("#e7ad681f"),Color("#8f684710"),Color("#201a1851")]))
	_draw_pad()

func _draw_pad() -> void:
	# The mat eases into the new plane with the camera. Its contact shadow
	# stays below objects and never intercepts input.
	var p := PAD.position+Vector2(0,48)*(1.0-pitch)
	var end := p+PAD.size
	var shape := PackedVector2Array([p+Vector2(12,2),Vector2(end.x-7,p.y),end-Vector2(0,11),Vector2(end.x-17,end.y),p+Vector2(2,PAD.size.y-5)])
	var shadow := PackedVector2Array()
	for corner: Vector2 in shape: shadow.append(corner+Vector2(6,9))
	draw_colored_polygon(shadow,Color(0.09,0.06,0.04,0.64*pitch))
	draw_colored_polygon(shape,Color(0.19,0.19,0.15,pitch))
	shape.append(shape[0])
	draw_polyline(shape,Color(0.45,0.40,0.31,pitch),2.0)
	var seam := Rect2(p+Vector2(13,14),PAD.size-Vector2(27,29))
	for x in range(int(seam.position.x),int(seam.end.x),13):
		draw_line(Vector2(x,seam.position.y),Vector2(x+6,seam.position.y),Color(0.59,0.52,0.39,0.48*pitch))
		draw_line(Vector2(x,seam.end.y),Vector2(x+6,seam.end.y),Color(0.59,0.52,0.39,0.48*pitch))

func carry(previous: Rect2, display: Control, targets: Array[Control]) -> void:
	if previous.size.x<=0.0 or previous.size.y<=0.0 or not is_instance_valid(display): return
	var to := Rect2(display.position,display.size)
	if not to.has_area(): return
	clear_carry()
	_carry = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	for node: Control in targets:
		if not is_instance_valid(node) or not node.is_visible_in_tree(): continue
		var existing := node.get_meta("shop_slide") as Tween if node.has_meta("shop_slide") else null
		if existing and existing.is_valid(): existing.kill()
		var end := node.position
		_carried[node] = end
		node.position += previous.position-to.position
		node.scale = previous.size/to.size
		_carry.tween_property(node,"position",end,TURN_TIME)
		_carry.tween_property(node,"scale",Vector2.ONE,TURN_TIME)

func clear_carry() -> void:
	if _carry and _carry.is_valid(): _carry.kill()
	for node: Variant in _carried:
		if is_instance_valid(node):
			node.position = _carried[node]
			node.scale = Vector2.ONE
	_carried.clear()
