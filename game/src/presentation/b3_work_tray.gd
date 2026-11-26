extends VBoxContainer

var slot_page := 0
var part_page := 0
var last_root := ""
var view_key := ""

# Keep the projected options on the actual drop target, not in transient loop
# closures. A drag is a read-only request tied to the displayed revision.
class AttachSocket extends Button:
	var options: Dictionary = {}
	var revision: int = -1
	var receiver: Callable

	func accepts(data: Variant) -> bool:
		return data is Dictionary and not data.has("detach") and data.get("origin","")=="player_stock" and data.get("revision",-1)==revision and options.has(str(data.get("item","")))

	func _can_drop_data(_at: Vector2,data: Variant) -> bool:
		return accepts(data)

	func _drop_data(_at: Vector2,data: Variant) -> void:
		if accepts(data) and receiver.is_valid():
			receiver.call(options[str(data.item)].duplicate(true),data)

## A visible slot accepts only candidates supplied by the composition authority.
func populate(root_id: String,composition: Dictionary,items: Dictionary,catalog: Resource,copy: Dictionary,translate: Callable,preview: Callable,restore_quote: Dictionary = {},drop_part: Callable = Callable(), drag_scale: float = 1.0) -> void:
	if root_id!=last_root:
		last_root = root_id
		slot_page = 0
		part_page = 0
	var slots: Array = composition.get("slots",[])
	slot_page = clampi(slot_page,0,maxi(0,slots.size()-1))
	var key := JSON.stringify([root_id,composition,slot_page,part_page,restore_quote])
	if key==view_key: return
	view_key = key
	for node in get_children():
		remove_child(node)
		node.queue_free()
	var work := self
	var header := HBoxContainer.new()
	work.add_child(header)
	var redraw := func()->void: populate(root_id,composition,items,catalog,copy,translate,preview,restore_quote,drop_part,drag_scale)
	var restore := Button.new()
	restore.name = "repair"
	restore.text = copy.repair
	restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not restore_quote.is_empty():
		restore.tooltip_text = "작업비 · %d VKC / %d USD"%[int(restore_quote.VKC),int(restore_quote.USD)]
		if int(restore_quote.USD)==0: restore.text = str(copy.repair)+" · %d VKC"%int(restore_quote.VKC)
	header.add_child(restore)
	restore.custom_minimum_size.y = 44
	restore.pressed.connect(func()->void:preview.call("spatial_restore_item",{"actor":"player","item_id":root_id}))
	var civilian_pair: bool = slots.size()==2 and str(slots[0].get("tag",""))=="f3_module_a" and str(slots[1].get("tag",""))=="f3_module_b"
	if civilian_pair:
		# Read only the authorized composition projection. Occupancy is not a functional judgment.
		for index: int in range(slots.size()):
			var slot_info: Dictionary = slots[index]
			var occupied: bool = not str(slot_info.get("item_id","")).is_empty()
			var selector := Button.new()
			selector.name = "work_slot_"+str(index)
			selector.text = ("A" if index==0 else "B")+(" 장착" if occupied else " 빈자리")
			selector.toggle_mode = true
			selector.set_pressed_no_signal(index==slot_page)
			selector.custom_minimum_size = Vector2(84,44)
			header.add_child(selector)
			selector.pressed.connect(func()->void:
				slot_page=index
				part_page=0
				view_key=""
				redraw.call())
	elif slots.size()>1:
		var next := Button.new()
		next.text = "작업 위치 %d/%d ›"%[slot_page+1,slots.size()]
		header.add_child(next)
		next.pressed.connect(func()->void:
			slot_page=(slot_page+1)%slots.size()
			part_page=0
			redraw.call())
	for slot: Dictionary in slots.slice(slot_page,slot_page+1):
		var child := str(slot.item_id)
		var tag := str(slot.get("tag",""))
		var slot_title: String = {"f3_module_a":"모듈 A","f3_module_b":"모듈 B"}.get(tag,"")
		var socket := AttachSocket.new() if child.is_empty() else Button.new()
		socket.custom_minimum_size = Vector2(0,44)
		socket.expand_icon = true
		socket.alignment = HORIZONTAL_ALIGNMENT_LEFT
		work.add_child(socket)
		if items.has(child):
			var model := str(items[child].def_id)
			socket.icon = catalog.call("model_texture",model,"stock",child)
			socket.text = str(copy.installed)+" · "+str(translate.call("b2.item."+model))
			var detach: Dictionary = slot.get("detach",{})
			socket.name = "detach_"+child
			socket.disabled = detach.is_empty()
			socket.tooltip_text = "창고로 끌어 놓거나 눌러 분리 위치를 미리 봅니다." if not detach.is_empty() else "분리할 수 있는 창고 자리 또는 권한 없음"
			socket.pressed.connect(func()->void:
				if not detach.is_empty(): preview.call("spatial_detach",detach.duplicate(true)))
			if civilian_pair and not detach.is_empty() and drop_part.is_valid():
				socket.set_drag_forwarding(func(_at:Vector2)->Variant:
					var piece := Button.new()
					piece.text = str(translate.call("b2.item."+model))
					piece.icon = socket.icon
					piece.custom_minimum_size = Vector2(156,44)*drag_scale
					piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
					socket.set_drag_preview(piece)
					return {"detach":detach.duplicate(true),"item":root_id,"origin":detach.inventory,"revision":composition.revision},Callable(),Callable())
		else:
			socket.name = "work_socket_"+tag if not tag.is_empty() else "work_socket"
			socket.text = str(copy.empty_slot) if slot_title.is_empty() else slot_title+" · 빈 자리"
			var target := socket as AttachSocket
			target.revision = int(composition.get("revision",-1))
			target.mouse_filter = Control.MOUSE_FILTER_STOP
			var alternatives := HBoxContainer.new()
			work.add_child(alternatives)
			var choices: Array = slot.get("attach",[])
			part_page = clampi(part_page,0,maxi(0,choices.size()-1))
			if choices.is_empty(): socket.tooltip_text = "이 위치에 넣을 수 있는 창고 물품이 없습니다."
			for option: Dictionary in choices:
				var part := str(option.child_id)
				target.options[part] = option.duplicate(true)
				if option!=choices[part_page]: continue
				var button := Button.new()
				button.name = "attach_"+part
				button.text = str(copy.attach)+" · "+str(translate.call("b2.item."+str(items[part].def_id)))
				button.icon = catalog.call("model_texture",str(items[part].def_id),"stock",part)
				button.expand_icon = true
				button.custom_minimum_size.y = 44
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				alternatives.add_child(button)
				button.pressed.connect(func()->void:preview.call("spatial_attach",option.duplicate(true)))
			if choices.size()>1:
				var cycle := Button.new()
				cycle.text = "%d/%d ›"%[part_page+1,choices.size()]
				alternatives.add_child(cycle)
				cycle.pressed.connect(func()->void:
					part_page=(part_page+1)%choices.size()
					redraw.call())
			target.receiver = func(payload:Dictionary,data:Variant)->void:
				if drop_part.is_valid(): drop_part.call(payload,data)
				else: preview.call("spatial_attach",payload)
