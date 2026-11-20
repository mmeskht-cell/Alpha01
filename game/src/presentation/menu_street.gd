extends Control
## Original authored native 640x360 pixel stage. No baked text or UI;
## separate time-driven mist, warm window reflection and windblown paper.
const W:int=640
const H:int=360
var _img:Image
var _texture:ImageTexture
var _time:float=0.0
var _accum:float=0.0
var animated:bool=true

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_img=Image.create(W,H,false,Image.FORMAT_RGBA8)
	_paint()
	_texture=ImageTexture.create_from_image(_img)
	queue_redraw()

func _rect(x:int,y:int,w:int,h:int,c:String)->void:
	var r:Rect2i=Rect2i(x,y,w,h).intersection(Rect2i(0,0,W,H))
	if r.has_area():
		_img.fill_rect(r,Color(c))

func _pixel(x:int,y:int,c:Color)->void:
	if x>=0 and x<W and y>=0 and y<H:
		_img.set_pixel(x,y,c)

func _line(x0:int,y0:int,x1:int,y1:int,c:String)->void:
	var dx:int=absi(x1-x0)
	var dy:int=-absi(y1-y0)
	var sx:int=1 if x0<x1 else -1
	var sy:int=1 if y0<y1 else -1
	var error:int=dx+dy
	var shade:=Color(c)
	while true:
		_pixel(x0,y0,shade)
		if x0==x1 and y0==y1:
			break
		var e:int=2*error
		if e>=dy:
			error+=dy
			x0+=sx
		if e<=dx:
			error+=dx
			y0+=sy

func _poly(points:Array,c:String)->void:
	var least:int=H-1
	var most:int=0
	for point:Vector2i in points:
		least=mini(least,point.y)
		most=maxi(most,point.y)
	for y:int in range(maxi(0,least),mini(H,most+1)):
		var intersections:Array[float]=[]
		for i:int in range(points.size()):
			var a:Vector2i=points[i]
			var b:Vector2i=points[(i+1)%points.size()]
			if (a.y<=y and b.y>y) or (b.y<=y and a.y>y):
				intersections.append(float(a.x)+float(y-a.y)*float(b.x-a.x)/float(b.y-a.y))
		intersections.sort()
		for i:int in range(0,intersections.size()-1,2):
			var x:int=ceili(intersections[i])
			_rect(x,y,maxi(0,floori(intersections[i+1])-x+1),1,c)

func _building(x:int,y:int,w:int,floors:int,shade:String,window:String)->void:
	_rect(x,y,w,257-y,shade)
	_rect(x+3,y-4,w-8,5,shade)
	for floor_index:int in range(floors):
		var yy:int=y+10+floor_index*22
		if yy>239:
			break
		for xx:int in range(x+5,x+w-6,13):
			_rect(xx,yy,6,12,window)
			_rect(xx,yy+10,6,2,shade)

func _paint()->void:
	_img.fill(Color("#272F35"))
	# Broad, stepped atmospheric colour planes; no pixel noise.
	for y:int in range(0,250,5):
		var sky:Color=Color("#252F37").lerp(Color("#59636A"),float(y)/250.0)
		_img.fill_rect(Rect2i(0,y,W,5),sky)
	_poly([Vector2i(0,67),Vector2i(92,52),Vector2i(162,61),Vector2i(229,51),Vector2i(306,74),Vector2i(0,89)],"#344047")
	_poly([Vector2i(0,105),Vector2i(57,99),Vector2i(137,111),Vector2i(223,95),Vector2i(312,111),Vector2i(0,124)],"#404B50")
	_building(4,135,49,6,"#39444A","#303B41")
	_building(54,156,33,4,"#49545A","#39444A")
	_building(100,116,39,6,"#414D53","#303B41")
	_building(145,145,58,5,"#414B50","#323D43")
	_building(213,93,43,8,"#3B464B","#2A3439")
	_building(266,153,78,4,"#414B4E","#343D40")
	# Broken top floors and irregular, empty silhouettes.
	_rect(218,93,9,18,"#2D363B")
	_rect(239,93,8,12,"#2D363B")
	_rect(105,116,11,10,"#455157")
	_poly([Vector2i(0,221),Vector2i(45,214),Vector2i(70,224),Vector2i(125,211),Vector2i(174,226),Vector2i(226,214),Vector2i(323,228),Vector2i(337,266),Vector2i(0,267)],"#292F32")
	_rect(0,256,W,104,"#272A2B")
	_poly([Vector2i(298,239),Vector2i(640,245),Vector2i(640,317),Vector2i(235,288),Vector2i(118,274)],"#45443E")
	_poly([Vector2i(298,263),Vector2i(640,278),Vector2i(640,292),Vector2i(266,275),Vector2i(128,274)],"#59564A")
	_line(128,275,639,292,"#1B2022")
	_line(249,280,639,300,"#323634")
	for x:int in range(150,640,29):
		_line(x,276,x-9,284,"#30332F")
		_line(x,284,x-10,287,"#282B29")
	# Storefront side wall and broad plaster planes.
	_poly([Vector2i(329,20),Vector2i(640,0),Vector2i(640,274),Vector2i(319,253)],"#4D4940")
	_poly([Vector2i(327,20),Vector2i(354,35),Vector2i(354,254),Vector2i(319,253)],"#323533")
	_rect(358,0,282,87,"#484A44")
	_rect(360,5,7,254,"#353834")
	_rect(368,2,7,257,"#55544A")
	_rect(630,0,10,275,"#2C3030")
	for x:int in [390,467,544]:
		_rect(x,10,55,58,"#303535")
		_rect(x+5,14,44,47,"#20282D")
		_rect(x+26,14,3,47,"#444744")
		_rect(x+5,36,44,3,"#3A403E")
		_rect(x-3,65,61,4,"#5E5B4D")
		_rect(x-3,69,61,2,"#30332F")
	# Plaster loss in clustered brick courses, not a uniform texture.
	for row:int in range(4):
		for col:int in range(5-row):
			var bx:int=578+col*11+(row%2)*4
			var by:int=5+row*6
			_rect(bx,by,10,5,"#5D483C" if (row+col)%2==0 else "#655344")
	_line(375,20,382,39,"#262C2D")
	_line(382,39,377,55,"#262C2D")
	_line(377,55,386,76,"#262C2D")
	_line(615,75,607,92,"#30322F")
	_rect(348,78,292,6,"#292E2E")
	_rect(348,84,292,4,"#6C6250")
	_rect(359,92,267,33,"#242B2B")
	_rect(362,95,261,2,"#897152")
	_rect(362,121,261,2,"#63583F")
	# Symbol-only sign: avoids baking a locale into the environment.
	_line(486,100,486,116,"#B09B76")
	_line(474,104,498,104,"#B09B76")
	_line(475,104,470,113,"#A38D67")
	_line(475,104,480,113,"#A38D67")
	_line(496,104,491,113,"#A38D67")
	_line(496,104,501,113,"#A38D67")
	_rect(468,113,14,3,"#907C5C")
	_rect(489,113,14,3,"#907C5C")
	_rect(480,117,12,2,"#907C5C")
	# Rain-dark awning with torn edge and folded fabric planes.
	_poly([Vector2i(354,125),Vector2i(631,125),Vector2i(640,150),Vector2i(348,150)],"#514036")
	for x:int in range(357,631,29):
		_poly([Vector2i(x,125),Vector2i(x+5,125),Vector2i(x+10,149),Vector2i(x+3,149)],"#665044")
		_rect(x+7,148,4,4,"#362E2A")
	_rect(349,151,291,3,"#262A28")
	# Interior is intentionally the brightest local patch, not a global filter.
	_rect(367,159,166,83,"#202525")
	_rect(371,163,158,75,"#544332")
	_rect(375,166,150,70,"#5F4B35")
	_rect(375,166,149,7,"#43372B")
	_rect(379,177,143,2,"#8A6742")
	_rect(379,197,143,3,"#9A7045")
	_rect(379,218,143,3,"#765D3D")
	_rect(385,177,5,56,"#382E25")
	_rect(514,177,4,56,"#382E25")
	for row:int in range(2):
		for col:int in range(7):
			var xx:int=393+col*17
			var yy:int=184+row*20
			var height:int=7+(col+row)%3*2
			_rect(xx,yy-height+10,12,height,"#776045" if col%2==0 else "#4B3D30")
			_rect(xx+2,yy-height+12,7,1,"#99805A")
	_rect(371,231,158,7,"#825C3B")
	_rect(438,220,28,16,"#393A32")
	_rect(440,222,15,10,"#5F5C49")
	for y:int in range(223,232,2):
		_rect(442,y,11,1,"#292C29")
	_rect(458,224,5,5,"#BD9460")
	_rect(443,217,13,2,"#504F3F")
	# Lamp cone and window glass frames.
	_poly([Vector2i(466,174),Vector2i(439,232),Vector2i(513,232),Vector2i(483,174)],"#98714A")
	_rect(469,160,2,7,"#2E302A")
	_poly([Vector2i(469,166),Vector2i(479,166),Vector2i(488,175),Vector2i(461,175)],"#35342B")
	_rect(468,175,12,3,"#D2AB69")
	_rect(471,178,6,2,"#E9C68C")
	# Foreground objects occlude lamp cone.
	_rect(438,220,28,16,"#393A32")
	_rect(440,222,15,10,"#5F5C49")
	for y:int in range(223,232,2):
		_rect(442,y,11,1,"#292C29")
	_rect(458,224,5,5,"#BD9460")
	_rect(443,217,13,2,"#504F3F")
	_rect(478,218,21,13,"#6C5337")
	_rect(480,220,17,1,"#AB854D")
	_rect(367,159,166,4,"#242B2A")
	_rect(367,238,166,5,"#292C29")
	_rect(367,159,5,82,"#242B2A")
	_rect(527,159,6,82,"#242B2A")
	_rect(423,161,4,78,"#2E302B")
	_rect(482,161,4,78,"#2E302B")
	_rect(367,202,166,3,"#33342E")
	_rect(379,205,17,12,"#AAA08B")
	_rect(381,208,12,1,"#655D50")
	_rect(381,211,9,1,"#655D50")
	_rect(362,243,175,7,"#625646")
	_rect(366,251,4,6,"#383A34")
	# Door, transom, side drainpipe and a crate.
	_rect(546,157,78,110,"#262B2A")
	_rect(551,159,66,106,"#4E4235")
	_rect(555,162,58,21,"#82603E")
	_rect(558,165,52,15,"#9D754B")
	_rect(555,187,58,39,"#302E28")
	_rect(559,191,50,32,"#68533B")
	_rect(555,231,58,31,"#41382E")
	_rect(559,234,23,24,"#504435")
	_rect(585,234,24,24,"#4A3F32")
	_rect(550,220,6,3,"#B49B71")
	_rect(586,198,16,15,"#AA9D80")
	_rect(589,201,10,1,"#635C4B")
	_rect(589,205,8,1,"#635C4B")
	_rect(632,6,4,259,"#68655A")
	_rect(636,6,4,259,"#282D2D")
	for y:int in [28,89,151,216]:
		_rect(630,y,10,3,"#85806D")
	_rect(606,249,25,24,"#312F27")
	_rect(609,251,20,18,"#665440")
	_rect(613,252,2,17,"#3E392E")
	_rect(623,252,2,17,"#3E392E")
	# Street-level reflections and stone joints. Avoid glossy cinematic bloom.
	_poly([Vector2i(392,294),Vector2i(524,292),Vector2i(584,305),Vector2i(560,324),Vector2i(398,320),Vector2i(354,309)],"#343C3D")
	for row:int in range(9):
		var yy:int=298+row*2
		var xx:int=432+(row%3)*7-row
		_rect(xx,yy,44+(row%4)*11,1,"#7D6345" if row%3==0 else "#554C3C")
	for row:int in range(5):
		var yy:int=307+row*2
		_rect(553-row*3,yy,21+row*4,1,"#6A563F")
	for row:int in range(4):
		var yy:int=306+row*13
		_line(0,yy,279,yy+3,"#373C3C")
		_line(296,yy+4,639,yy+6,"#343735")
		for x:int in range(10+row*9,350,55):
			_line(x,yy,x-8,yy+13,"#1D2325")
	_line(303,282,270,302,"#1E2426")
	_line(270,302,278,313,"#1E2426")
	_line(278,313,248,337,"#1E2426")
	_poly([Vector2i(0,280),Vector2i(36,288),Vector2i(63,303),Vector2i(81,330),Vector2i(98,359),Vector2i(0,359)],"#1C2225")
	_rect(11,275,22,10,"#343A3A")
	_line(22,273,34,246,"#252B2D")
	_line(51,297,67,270,"#252B2D")
	# Foreground utility pole and sagging wire; silhouettes behind the UI.
	_rect(20,0,6,259,"#242C2F")
	_rect(17,20,34,4,"#20282B")
	_rect(7,18,5,6,"#20282B")
	_rect(45,18,5,6,"#20282B")
	for i:int in range(0,310,3):
		var y:int=17+int(float(i)*0.13)+int(9.0*sin(float(i)*PI/310.0))
		_rect(i,y,3,1,"#2B3335")
	# Subtle left-hand scrim keeps text independent of background artwork.
	for x:int in range(0,300,10):
		var darkness:float=0.47*(1.0-float(x)/300.0)
		for y:int in range(H):
			for px:int in range(x,x+10):
				var existing:Color=_img.get_pixel(px,y)
				_img.set_pixel(px,y,existing.lerp(Color("#10171B"),darkness))

func _process(delta:float)->void:
	if not animated or not is_visible_in_tree():
		return
	_accum+=delta
	if _accum>=0.083:
		_time+=_accum
		_accum=0.0
		queue_redraw()

func _draw()->void:
	if _texture==null:
		return
	var scale_factor:float=maxf(size.x/float(W),size.y/float(H))
	var origin:Vector2=(size-Vector2(W,H)*scale_factor)*0.5
	draw_set_transform(origin,0.0,Vector2(scale_factor,scale_factor))
	draw_texture(_texture,Vector2.ZERO)
	# Deliberately quiet environmental motion, independent of the game clock.
	var t:float=_time if animated else 0.0
	var pulse:float=0.022+0.013*sin(t*1.6)+0.006*sin(t*4.3)
	draw_rect(Rect2(429,178,91,58),Color(0.97,0.63,0.26,pulse))
	for i:int in range(3):
		var x:int=34+i*77+int(8.0*sin(t*0.17+float(i)*1.3))
		draw_rect(Rect2(x,237+i*3,58,2),Color(0.55,0.60,0.62,0.07))
		draw_rect(Rect2(x+13,239+i*3,34,1),Color(0.55,0.60,0.62,0.05))
	var paper_x:int=177+int(6.0*sin(t*0.44))
	var paper_y:int=310+int(1.5*sin(t*0.9))
	draw_rect(Rect2(paper_x,paper_y,10,3),Color("#777366"))
	draw_rect(Rect2(paper_x+2,paper_y+3,7,1),Color("#56564F"))
	draw_rect(Rect2(454+int(3.0*sin(t*0.8)),309,19,1),Color(0.65,0.45,0.22,0.09+0.025*sin(t)))
