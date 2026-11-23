extends "res://src/presentation/alpha_b1_host.gd"
## Inherit only the B3 session/save transport and contextual document actions.
const Art = preload("res://src/presentation/native_v23_art.gd")
const Front = preload("res://assets/art/items/r001_pixel_front_candidate.png")
const Back = preload("res://assets/art/items/r001_pixel_back_candidate.png")
const INTRO_FILE = "res://data/alpha_b3/spatial_intro_ko.json"
const BEATS = ["port","ledger","clinic","shutter","counter"]
var sound = preload("res://src/presentation/commit_feedback.gd").new()
var stage: Control
var captions: Dictionary
var drawer := ""
var zoom := false
var reverse := false
var chosen_tool := ""
var selected := ""
var storage := "player_stock"
var rotated := false
var hand_page := 0
var price_text := ""
var last_visit := ""
var reduce_motion := false
var last_cue := ""
var pending_save := false
var hint := ""

func _slot() -> String:
	return "spatial_week_v1"

func _week_source(seed_value: int) -> Dictionary:
	return preload("res://src/content/b3_spatial_week_seed.gd").content(seed_value)

func _ready() -> void:
	if save_directory_override.is_empty():
		save_directory_override = "user://zt_rebuild/spatial_week"
	var continuing := FileAccess.file_exists(save_directory_override.path_join(_slot()+".a.json")) or FileAccess.file_exists(save_directory_override.path_join(_slot()+".b.json"))
	captions = JSON.parse_string(FileAccess.get_file_as_string(INTRO_FILE))
	resized.connect(_scale_stage)
	super._ready()
	add_child(sound)
	if session != null: sound.prime(int(session.snapshot().revision))
	if continuing and not _blocked:
		_intro = false
		refresh()

func _scale_stage() -> void:
	if is_instance_valid(stage):
		var factor := minf(size.x / 1280.0,size.y / 720.0)
		stage.scale = Vector2.ONE * factor
		stage.position = (size - Vector2(1280,720)*factor)*0.5

func place(node: Control, x: float,y: float,w: float,h: float) -> void:
	stage.add_child(node)
	node.position = Vector2(x,y)
	node.size = Vector2(w,h)

func pic(tex: Texture2D,x: float,y: float,w: float,h: float,fill: bool=false) -> TextureRect:
	var node := TextureRect.new()
	node.texture = tex
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE if fill else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(node,x,y,w,h)
	return node

func paper(x: float,y: float,w: float,h: float,tint: Color=Color("#242322ed")) -> ColorRect:
	var node := ColorRect.new()
	node.color = tint
	place(node,x,y,w,h)
	return node

func words(value: String,x: float,y: float,w: float,h: float,points: int=20) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",points)
	label.add_theme_constant_override("outline_size",4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(label,x,y,w,h)
	return label

func action(id: String,caption: String,x: float,y: float,w: float,h: float,callback: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = caption
	button.pressed.connect(callback)
	place(button,x,y,w,h)
	return button

func command_button(kind: String,caption: String,x: float,y: float,w: float,payload: Dictionary={}) -> Button:
	return action(kind,caption,x,y,w,42,func()->void: _submit(kind,payload))

func open_drawer(which: String) -> void:
	drawer = which
	hint = ""
	refresh()

func _room(index: int,npc: bool) -> void:
	pic(Art.WINDOWS[index],0,0,1280,720,true)
	pic(Art.ROOM,0,0,1280,720,true)
	if npc:
		var actor: String = str(session.alpha_view().active.get("actor_id",""))
		var portrait := pic(Art.scene_texture("customer.opening" if actor=="G01" else "customer.watch" if actor=="G04" else "customer.neutral"),525,70,260,395)
		if not reduce_motion and last_cue != last_visit:
			last_cue = last_visit
			portrait.modulate.a = 0
			create_tween().tween_property(portrait,"modulate:a",1.0,0.24)
	pic(Art.COUNTER,0,0,1280,720,true)
	pic(Art.AMBER,0,0,1280,720,true)
	pic(Art.LAMP,0,0,1280,720,true)

func intro_next() -> void:
	if _intro_page == BEATS.size()-1:
		intro_skip()
	else:
		_intro_page += 1
		refresh()

func _intro_scene() -> void:
	match _intro_page:
		0:
			var street := preload("res://src/presentation/menu_street.gd").new()
			street.animated = not reduce_motion
			place(street,0,0,1280,720)
		1: pic(Art.OFFICE_ROOM,0,0,1280,720,true)
		2:
			pic(Art.OFFICE_ROOM,0,0,1280,720,true)
			pic(Art.OFFICE_FOREGROUND,0,0,1280,720,true)
			pic(Art.OFFICE_LAMP,0,0,1280,720,true)
		_: _room(0,false)
	if _intro_page == 3 and not reduce_motion:
		var shutter := paper(0,0,1280,410,Color("#24292c"))
		create_tween().tween_property(shutter,"position:y",-420,0.65)
	if _intro_page in [1,2]:
		paper(135,82,530,218,Color("#b4a688"))
		paper(146,93,5,185,Color("#89745a"))
		var ink := words("크라벤스크   /   " + ("중고상점 영업부" if _intro_page==1 else "진료 기록"),169,106,473,48,23)
		ink.add_theme_color_override("font_color",Color("#332e27"))
		ink.add_theme_constant_override("outline_size",0)
		var entry := words("7.26   재고 0   /   미결 정리\n7.28   이송 승인 취소" if _intro_page==1 else "10.31   알렉세이 바린 · 38세\nRAD-1   1회분",169,163,455,92)
		entry.add_theme_color_override("font_color",Color("#43392e"))
		entry.add_theme_constant_override("outline_size",0)
	var beat: Array = captions[BEATS[_intro_page]]
	paper(56,360,1168,318)
	words(beat[0],92,380,1040,46,32)
	words(beat[1],92,442,1080,168)
	action("intro_motion","동작 줄이기" if not reduce_motion else "동작 줄임",90,610,160,45,func()->void:
		reduce_motion = not reduce_motion
		sound.set_motion(not reduce_motion)
		refresh())
	action("intro_mute","음소거",264,610,120,45,func()->void:AudioServer.set_bus_mute(0,not AudioServer.is_bus_mute(0)))
	action("intro_next","개점 준비" if _intro_page == 4 else "다음",998,610,168,48,intro_next)
	action("intro_skip","건너뛰기",810,610,168,48,intro_skip)

func refresh() -> void:
	if is_instance_valid(stage):
		remove_child(stage)
		stage.queue_free()
	stage = Control.new()
	stage.size = Vector2(1280,720)
	add_child(stage)
	_scale_stage()
	if _blocked or session == null:
		words(_message,70,320,1120,90)
		if pending_save: action("retry_save","현재 거래 저장 다시 시도",70,438,380,48,_retry_save)
		action("leave_blocked","제목으로",480,438,170,48,_return_to_title)
		return
	if _intro:
		_intro_scene()
		return
	var v: Dictionary = session.alpha_view()
	var visit: String = str(v.active.get("id",""))
	if visit != last_visit:
		last_visit = visit
		zoom = false
		reverse = false
		chosen_tool = ""
		hand_page = 0
		price_text = ""
		hint = ""
	_room(5 if v.phase == "EVENING_WORK" else 1,not v.active.is_empty())
	words("크라벤스크   /   "+str(v.day)+"일",30,18,320,38)
	action("preferences","설정",1160,16,90,36,func()->void: open_drawer("settings"))
	if not drawer.is_empty():
		_drawer(v)
		return
	if not _message.is_empty() or not hint.is_empty():
		words(_message if not _message.is_empty() else hint,28,660,940,48)
	match v.phase:
		"DAY_PREP": command_button("alpha_open","셔터 올리기",520,514,240)
		"OPEN_IDLE":
			if v.remaining > 0: command_button("alpha_next_customer","문 열어 손님 맞기",485,400,310)
			command_button("alpha_close","영업 마감",1010,580,205)
		"CUSTOMER_ENTER": command_button("alpha_ack_entry",str(captions.reply) if visit=="visit_g01" else "어서 오세요",548,355,185)
		"CUSTOMER_EXIT": command_button("alpha_ack_exit","손님 배웅",548,355,185)
		"CUSTOMER_ACTIVE": _counter(v)
		"CLOSE_SETTLE": command_button("alpha_settle","장부 마감 · 저녁으로",496,400,290)
		"EVENING_WORK": command_button("alpha_next_day","하루 마치기",995,560,225)
		"NEXT_DAY": command_button("alpha_prepare_day","다음 날 아침",520,435,240)
		"COMPLETE": words("첫 주 영업 종료",480,380,420,80,36)
	if v.phase == "CUSTOMER_ENTER":
		var greet := action("greet_visitor","",535,92,225,242,func()->void:_submit("alpha_ack_entry"))
		greet.flat = true
		greet.tooltip_text = _actor_label(v.active.actor_id)
		if visit=="visit_g01":
			pic(Art.RADIO_COUNTER,500,415,245,100)
			words(captions.g01,774,244,420,64)
	if v.phase != "CUSTOMER_ACTIVE" or not zoom:
		action("stockroom","재고 서랍",36,597,154,46,func()->void: open_drawer("stock"))
		action("ledger","장부 · 계약",203,597,164,46,func()->void: open_drawer("ledger"))
	if v.phase == "EVENING_WORK":
		action("phone","전화기",389,597,145,46,func()->void: open_drawer("phone"))

func _counter(v: Dictionary) -> void:
	var a: Dictionary = v.appraisal
	var actor: String = _actor_label(str(v.active.actor_id))
	var speech: String = _b2_npc_line(v)
	if speech.is_empty(): speech = _text(v.active.purpose_key)
	paper(292,45,704,82,Color("#1c2023c9"))
	words(actor+"   "+speech,316,50,656,72)
	if v.active.id == "alpha_marcus_intro":
		var terms := VBoxContainer.new()
		place(terms,420,365,440,180)
		_add_contract_actions(terms,v)
	elif not a.is_empty():
		_specimen(v,a)
	else:
		var visit: Dictionary = session.snapshot().visits.get(str(v.active.id),{})
		if not visit.is_empty() and not visit.prices.is_empty() and not bool(visit.scope.get("completed",false)):
			_ordinary_trade(v,visit)
		else:
			for job: Dictionary in v.services.entries:
				if job.actor_id==v.active.actor_id and job.has("item_id"):
					var sample = Art.item_profile(str(job.item_id),"counter")
					if sample != null: pic(sample.texture,476,336,300,95)
					break
			action("visitor_papers","의뢰서 · 견적 보기",475,426,300,54,func()->void: open_drawer("ledger"))
	if not zoom:
		if v.can_exchange: command_button("alpha_exchange_contact","연락처 교환",850,437,170,{"actor_id":v.active.actor_id,"accepted":true})
		if v.active.id == "watch_a": command_button("week_pledge","시계 전당 · 40 VKC",850,492,215)
		if v.active.id != "alpha_marcus_intro" or not v.contracts.get("rad1_first",{}).get("can_accept",false):
			command_button("alpha_finish_customer","응대 마치기",1030,596,194)

## Ordinary pre-card B3 visitors still have real goods and finite quoted terms.
## Do not hide their existing purchase/sale authority behind the dossier drawer.
## This is a fixed-term fallback, not a fabricated appraisal or bargaining result.
func _ordinary_trade(v: Dictionary, visit: Dictionary) -> void:
	var id: String = str(visit.prices.keys()[0])
	var state: Dictionary = session.snapshot()
	if not state.items.has(id):
		words("방문 물품을 확인할 수 없습니다.",466,352,400,90)
		return
	var item: Dictionary = state.items[id]
	var profile = Art.item_profile(id,"inspection" if zoom else "counter")
	var texture: Texture2D = profile.texture if profile != null else null
	var label: String = _text("b2.item."+str(item.def_id))
	if zoom:
		paper(52,144,1170,493,Color("#262724f5"))
		if texture != null: pic(texture,290,170,700,315)
		words(label+" · "+id,110,496,940,72,25)
		action("ordinary_close","카운터로",1055,158,146,45,func()->void:
			zoom = false
			refresh())
		return
	if texture != null: pic(texture,470,343,335,147)
	var view_item := action("ordinary_item","",470,343,335,147,func()->void:
		zoom = true
		refresh())
	view_item.flat = true
	view_item.tooltip_text = label+" 살펴보기"
	words(label,470,491,320,48,20)
	var quote: Dictionary = visit.prices[id]
	var currency: String = "VKC" if int(quote.get("VKC",0)) != 0 else "USD"
	var amount: int = int(quote.get(currency,0))
	var buying: bool = str(visit.buyer) == "player"
	var available: bool = buying or (id in v.displayed_items and str(item.inventory)=="storefront_grid")
	words(("상점 매입 · " if buying else "매대 판매 · ") + str(amount)+" "+currency,819,356,342,54,23)
	if not available:
		words("판매하려면 먼저 이 물건을 외부 매대에 진열해야 합니다.",810,417,375,80,18)
		return
	action("ordinary_trade",("매입 확정" if buying else "판매 확정")+" · "+str(amount)+" "+currency,829,432,344,56,func()->void:
		var destination: String = "player_stock" if buying else str(visit.buyer)+"_grid"
		var fit: Dictionary = session.spatial_fit(id,destination)
		if not fit.get("ok",false):
			hint = "물건을 놓을 빈 공간이 없습니다."
			refresh()
			return
		_submit("alpha_trade",{"visit_id":str(v.active.id),"item_id":id,
			"seller":str(visit.seller),"buyer":str(visit.buyer),"currency":currency,
			"amount":amount,"inventory":destination,"x":fit.x,"y":fit.y,"rotated":fit.rotated}))

func _specimen(v: Dictionary,a: Dictionary) -> void:
	var id: String = a.item_id
	var profile = Art.item_profile(id,"inspection" if zoom else "counter")
	var texture: Texture2D = profile.texture if profile != null else null
	if id == "R001": texture = (Back if reverse else Front) if zoom else Art.RADIO_COUNTER
	if id=="WAT02" and zoom and reverse: texture = preload("res://assets/art/items/watch_spatial_back_pilot.svg")
	if not zoom:
		pic(texture,470,348,332,145)
		var inspect := action("specimen","",470,348,332,145,func()->void:
			zoom = true
			refresh())
		inspect.flat = true
		inspect.tooltip_text = _text("b2.item."+str(a.def_id))+" 조사"
		words(_text("b2.item."+str(a.def_id)),535,485,390,48)
		return
	paper(50,145,1180,502,Color("#272927f4"))
	pic(texture,292,186,450,248)
	action("close_mat","카운터",1055,153,146,38,func()->void:
		zoom = false
		refresh())
	if id in ["R001","WAT02"]:
		action("turn_item","뒤집기",550,430,128,38,func()->void:
			reverse = not reverse
			refresh())
	var tool_index := 0
	for tool: Dictionary in a.tools:
		var slot: String = tool.id
		action("tool_"+slot,_text(tool.text_key),66,164+tool_index*43,202,40,func()->void:
			chosen_tool = slot
			refresh())
		tool_index += 1
	if not chosen_tool.is_empty() and a.tools.any(func(t:Dictionary)->bool:return t.id==chosen_tool):
		var regions: Dictionary = profile.regions if profile != null else {}
		if id == "R001":
			regions = preload("res://src/presentation/spatial_radio_counter.gd").R001_PIXEL_BACK_REGIONS if reverse else preload("res://src/presentation/spatial_radio_counter.gd").R001_PIXEL_FRONT_REGIONS
		if id=="R001":
			var back_regions: Dictionary = preload("res://src/presentation/spatial_radio_counter.gd").R001_PIXEL_BACK_REGIONS
			if back_regions.has(chosen_tool) != reverse:
				regions = {}
		var region: Rect2 = regions.get(chosen_tool,Rect2(0.34,0.36,0.3,0.25))
		var at := Vector2(292,186)+region.get_center()*Vector2(450,248)-Vector2(56,22)
		var flip_required: bool = id=="R001" and regions.is_empty()
		action("apply_tool","뒤집어 조사" if flip_required else "◎  조사",at.x,at.y,125,45,func()->void:
			if flip_required:
				reverse = not reverse
				refresh()
			else: _submit("alpha_inspect",{"slot":chosen_tool}))
	words("확인한 단서",69,465,210,34)
	var start := mini(hand_page*3,maxi(0,a.cards.size()-1))
	for i: int in range(start,mini(start+3,a.cards.size())):
		var card: Dictionary = a.cards[i]
		var slot: String = card.slot
		var fact: String = str(card.value)
		if _strings.has("b2.value."+fact): fact = _text("b2.value."+fact)
		var note := action("fact_"+slot,("공개 예정" if card.selected else "내 기록")+"\n"+_text(card.text_key)+" · "+fact,68+(i-start)*196,502,190,87,func()->void: _submit("alpha_card_toggle",{"slot":slot,"selected":not card.selected}))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.set_drag_forwarding(func(_at: Vector2)->Variant: return {"slot":slot,"visit":v.active.id},Callable(),Callable())
	if a.cards.size()>3:
		action("more_facts","카드 넘기기",69,594,170,38,func()->void:
			hand_page = (hand_page+1)%ceili(float(a.cards.size())/3.0)
			refresh())
	var target := words("공개 영역 · "+str(a.cards.filter(func(c:Dictionary)->bool:return c.selected).size())+"장",788,225,370,62)
	target.mouse_filter = Control.MOUSE_FILTER_STOP
	target.set_drag_forwarding(Callable(),func(_at:Vector2,data:Variant)->bool: return data is Dictionary and data.get("visit")==v.active.id,func(_at:Vector2,data:Variant)->void: _submit("alpha_card_toggle",{"slot":data.slot,"selected":true}))
	if not a.customer_claims.is_empty(): words("손님 주장 · "+_text(a.customer_claims[0].text_key),788,290,384,72)
	var money := LineEdit.new()
	money.name = "price"
	money.placeholder_text = "제안할 금액"
	money.text = price_text
	money.text_changed.connect(func(value:String)->void: price_text=value)
	place(money,790,378,208,46)
	var currency: String = str(v.currency_terms.get("trade",{}).get("currency","VKC"))
	action("offer","제안 · "+currency,1004,378,178,46,func()->void:
		# Read the actual edited control. Programmatic caret insertion and IME
		# composition need not emit text_changed before the button is pressed.
		var proposed: String = money.text.strip_edges()
		if proposed.is_valid_int() and int(proposed)>0:
			price_text = proposed
			_submit("alpha_price_offer",{"amount":int(proposed)})
		else:
			hint = "제안할 금액을 양의 정수로 입력해 주세요."
			refresh())
	if not a.accepted.is_empty():
		action("settle_trade","거래 확정 · %d %s"%[a.accepted.amount,a.accepted.currency],790,452,386,52,func()->void:
			var trade: Dictionary = session.snapshot().visits[v.active.id]
			var dest: String = "player_stock" if a.we_buy else str(trade.buyer)+"_grid"
			var fit: Dictionary = session.spatial_fit(id,dest)
			if fit.get("ok",false):
				_submit("alpha_trade",{"visit_id":v.active.id,"item_id":id,"seller":trade.seller,"buyer":trade.buyer,"currency":a.accepted.currency,"amount":a.accepted.amount,"inventory":dest,"x":fit.x,"y":fit.y,"rotated":fit.rotated})
			else:
				hint = "물건을 놓을 빈 공간이 없습니다."
				refresh())
	elif not a.offers.is_empty(): words("그 가격에는 거래하기 어렵습니다.",790,448,400,64)
	action("notes","진술 · 개인 추정",790,541,250,40,func()->void: open_drawer("notes"))

func _drawer(v: Dictionary) -> void:
	var current: Dictionary = session.snapshot()
	pic(Art.STOCK_ROOM if drawer=="stock" else Art.OFFICE_ROOM,0,0,1280,720,true)
	paper(44,50,1192,625,Color("#241f1deb"))
	action("close_drawer","카운터로",1045,64,165,44,func()->void: open_drawer(""))
	if drawer=="stock":
		_inventory(v,current)
		return
	var scroll := ScrollContainer.new()
	place(scroll,84,126,1100,510)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	match drawer:
		"settings":
			_button(pages,"motion","동작 줄이기 · "+("켜짐" if reduce_motion else "꺼짐"),func()->void:
				reduce_motion = not reduce_motion
				refresh())
			_button(pages,"mute","음소거 전환",func()->void: AudioServer.set_bus_mute(0,not AudioServer.is_bus_mute(0)))
			_button(pages,"return_title","제목 화면",_return_to_title)
		"notes":
			for claim: Dictionary in v.appraisal.get("customer_claims",[]):
				_board_line(pages,"claim_"+str(claim.claim_key),"손님 주장 · "+_text(claim.text_key))
				if claim.can_challenge:
					_button(pages,"query_"+str(claim.claim_key),"확인한 단서로 되묻기",func()->void:_submit("alpha_claim_challenge",{"claim_key":claim.claim_key}))
			for guess: Dictionary in v.appraisal.get("hypotheses",[]):
				_board_line(pages,"guess_status_"+str(guess.slot),_text("b2.inspect."+str(guess.slot))+" · "+_text("b2.hypothesis."+str(guess.judgment)))
				var slot: String = guess.slot
				for value: String in ["serviceable","inoperable","unknown"]:
					_button(pages,"guess_"+slot+"_"+value,"내 추정 · "+_text("b2.inspect."+slot)+" · "+_text("b2.value."+value),func()->void: _submit("alpha_hypothesis",{"slot":slot,"judgment":value}))
			for fact: Dictionary in v.appraisal.get("cards",[]):
				if fact.ever_disclosed:
					var slot: String = fact.slot
					var kind := "alpha_statement_retract" if fact.public_active else "alpha_statement_reaffirm"
					_button(pages,"spoken_"+slot,("공개 진술 철회 · " if fact.public_active else "진술 재확인 · ")+_text(fact.text_key),func()->void: _submit(kind,{"slot":slot}))
		"phone":
			for contact: Dictionary in v.contacts:
				_board_line(pages,"contact_"+str(contact.actor_id),_actor_label(contact.actor_id))
				for option: Dictionary in v.get("outbound_options",[]):
					if option.actor == contact.actor_id:
						_button(pages,"phone_"+option.id,_text(option.label),func()->void: _submit(option.command,{"request_id":option.id}))
			if v.contacts.is_empty(): _board_line(pages,"empty","교환한 연락처가 없습니다.")
		"ledger":
			_board_line(pages,"cash","보유 현금   %d VKC   /   %d USD"%[current.wallets.player.VKC,current.wallets.player.USD])
			_add_contract_actions(pages,v)
			_add_b2_commission_actions(pages,v)
			_add_b2_service_actions(pages,v)
			_add_b3_fx_actions(pages,v)
			var pawn: Dictionary = current.alpha_shop.week_pawn
			if pawn.status != "available":
				_board_line(pages,"pledge","WAT02 · "+_text("week."+str(pawn.status))+" · D"+str(pawn.due))
				if pawn.status=="pledged" and v.phase=="CLOSE_SETTLE" and v.day==pawn.due:
					_button(pages,"week_redeem",_text("week.redeem"),func()->void:_submit("week_redeem"))
					if pawn.due==4: _button(pages,"week_extend",_text("week.extend"),func()->void:_submit("week_extend"))
			for order: Dictionary in current.alpha_shop.get("outbound",{}).values():
				_board_line(pages,"order",_text("week.order")%_text("week."+str(order.status)))
				for payment: Dictionary in order.payments:
					_board_line(pages,"p_"+str(payment.action_id),"D%d · %s → %s · %d %s"%[payment.day,payment.from,payment.to,payment.amount,payment.currency])
			for entry: Dictionary in current.ledger:
				_board_line(pages,"r_"+str(entry.event_id),"%s → %s   %d VKC / %d USD   ·   %s"%[entry.from,entry.to,entry.amounts.VKC,entry.amounts.USD,", ".join(entry.root_ids)])

func _inventory(v: Dictionary,s: Dictionary) -> void:
	var grids := ["player_stock","storefront_grid","service_grid","pawn_grid"]
	var titles := ["창고","외부 매대","수탁 보관","담보 보관"]
	for n: int in range(grids.size()):
		var destination: String = grids[n]
		if s.inventories.has(destination):
			action("tab_"+destination,titles[n],76+n*165,77,152,42,func()->void:
				storage = destination
				refresh())
	var spec: Dictionary = s.inventories[storage]
	var cell := minf(68,630.0/float(spec.width))
	for y: int in range(int(spec.height)):
		for x: int in range(int(spec.width)):
			var target := Vector2i(x,y)
			var button := action("cell_%d_%d"%[x,y],"",76+x*cell,160+y*cell,cell-2,cell-2,func()->void: _place_selection(target))
			button.set_drag_forwarding(Callable(),func(_at:Vector2,data:Variant)->bool:return data is Dictionary and data.get("item")==selected,func(_at:Vector2,_data:Variant)->void:_place_selection(target))
	for id: String in s.items:
		var item: Dictionary = s.items[id]
		if item.inventory != storage or not item.parent_id.is_empty(): continue
		var dims: Array = session.spatial_dimensions(id)
		var w := int(dims[1] if item.rotated else dims[0])
		var h := int(dims[0] if item.rotated else dims[1])
		var token := action("stock_"+id,"",76+item.x*cell,160+item.y*cell,cell*w-2,cell*h-2,func()->void:
			selected = id
			rotated = item.rotated
			refresh())
		token.icon = Art.stock_texture({"id":id})
		token.expand_icon = true
		token.tooltip_text = _text("b2.item."+str(item.def_id))
		if token.icon == null: token.text = token.tooltip_text
		token.set_drag_forwarding(func(_at:Vector2)->Variant:
			selected = id
			rotated = item.rotated
			return {"item":id},Callable(),Callable())
	if not s.items.has(selected):
		words("물건을 골라 살펴보세요.",760,211,400,84)
		return
	var item: Dictionary = s.items[selected]
	words(_text("b2.item."+str(item.def_id))+"   ·   "+selected,746,152,434,54)
	pic(Art.stock_texture({"id":selected}),760,210,378,136)
	words("소유 "+_actor_label(item.owner_id)+"  /  보관 "+_actor_label(item.custodian_id),747,350,435,47)
	action("rotate","배치 방향 전환 · "+("90°" if rotated else "0°"),746,406,400,40,func()->void:
		rotated = not rotated
		refresh())
	if v.phase=="EVENING_WORK" and item.inventory=="player_stock":
		var work := VBoxContainer.new()
		place(work,746,459,420,150)
		_button(work,"repair","정비 · 재생",func()->void:_submit("spatial_restore_item",{"actor":"player","item_id":selected}))
		var composition: Dictionary = session.composition_options(selected,"player_stock")
		for slot: Dictionary in composition.get("slots",[]):
			var child: String = str(slot.item_id)
			var detach_payload: Dictionary = slot.get("detach",{})
			if not child.is_empty() and not detach_payload.is_empty():
				var detach_command: Dictionary = detach_payload.duplicate(true)
				_button(work,"detach_"+child,"분리 · "+str(slot.tag),func()->void:_submit("spatial_detach",detach_command))
			elif child.is_empty():
				for option: Dictionary in slot.get("attach",[]):
					var attach_command: Dictionary = option.duplicate(true)
					var part: String = str(attach_command.child_id)
					_button(work,"attach_"+part,"장착 · "+part,func()->void:_submit("spatial_attach",attach_command))
	if v.phase=="EVENING_WORK" and item.status=="custody_service":
		var jobs := VBoxContainer.new()
		place(jobs,746,453,420,164)
		_add_b2_service_actions(jobs,v)
	if not _message.is_empty(): words(_message,74,608,1090,46)

func _place_selection(target: Vector2i) -> void:
	var items: Dictionary = session.snapshot().items
	if not items.has(selected): return
	var origin: String = items[selected].inventory
	var payload := {"item_id":selected,"x":target.x,"y":target.y,"rotated":rotated}
	if origin=="player_stock" and storage=="storefront_grid":
		_submit("alpha_display",payload)
	elif origin=="storefront_grid" and storage=="player_stock":
		_submit("alpha_withdraw_display",payload)
	elif origin in ["player_stock","pawn_grid"] and storage=="player_stock":
		payload.actor = "player"
		payload.inventory = storage
		_submit("spatial_move",payload)

func _return_to_title() -> void:
	sound.remember_score_position()
	get_tree().change_scene_to_file("res://scenes/app/main_menu.tscn")

func _submit(kind: String,payload: Dictionary={}) -> void:
	var before: int = session.snapshot().revision
	super._submit(kind,payload)
	var after: int = session.snapshot().revision
	if after != before+1: return
	if _blocked:
		pending_save = true
		refresh()
	var cues := {"alpha_open":"next_visit","alpha_next_customer":"next_visit","alpha_finish_customer":"decline_visit","alpha_inspect":"observe","alpha_price_offer":"subject_price_offer","alpha_trade":"trade","alpha_settle":"day_one_close","alpha_display":"move","week_pledge":"accept_rad1_contract","alpha_salvage_dispatch":"accept_rad1_contract"}
	sound.committed(str(cues.get(kind,kind.trim_prefix("spatial_"))),before,after,not _blocked)
	sound.set_phase("workshop" if session.alpha_view().phase=="EVENING_WORK" else "shop")

func _retry_save() -> void:
	if not pending_save or session==null: return
	var saved: Dictionary = _repo.save_session(session,_slot())
	if saved.get("ok",false):
		pending_save = false
		_blocked = false
		_message = ""
		sound.prime(int(session.snapshot().revision))
	refresh()
