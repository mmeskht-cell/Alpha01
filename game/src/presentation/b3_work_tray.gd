extends VBoxContainer

var slot_page := 0
var part_page := 0
var last_root := ""
var view_key := ""
## A visible slot accepts only candidates supplied by the composition authority.
func populate(root_id: String,composition: Dictionary,items: Dictionary,catalog: Resource,copy: Dictionary,translate: Callable,preview: Callable,restore_quote: Dictionary = {},drop_part: Callable = Callable()) -> void:
	if root_id!=last_root:
		last_root = root_id
		slot_page = 0
		part_page = 0
	var key := JSON.stringify([root_id,composition,slot_page,part_page,restore_quote])
	if key==view_key: return
	view_key = key
	for node in get_children():
		remove_child(node)
		node.queue_free()
	var work := self
	var header := HBoxContainer.new()
	work.add_child(header)
	var slots: Array = composition.get("slots",[])
	var redraw := func()->void: populate(root_id,composition,items,catalog,copy,translate,preview,restore_quote,drop_part)
	var restore := Button.new()
	restore.name = "repair"
	restore.text = copy.repair
	restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not restore_quote.is_empty():
		restore.tooltip_text = "작업비 · %d VKC / %d USD"%[int(restore_quote.VKC),int(restore_quote.USD)]
	header.add_child(restore)
	restore.custom_minimum_size.y = 44
	restore.pressed.connect(func()->void:preview.call("spatial_restore_item",{"actor":"player","item_id":root_id}))
	slot_page = clampi(slot_page,0,maxi(0,slots.size()-1))
	if slots.size()>1:
		var next := Button.new()
		next.text = "작업 위치 %d/%d ›"%[slot_page+1,slots.size()]
		header.add_child(next)
		next.pressed.connect(func()->void:
			slot_page=(slot_page+1)%slots.size()
			part_page=0
			redraw.call())
	for slot: Dictionary in slots.slice(slot_page,slot_page+1):
		var child := str(slot.item_id)
		var socket := Button.new()
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
			socket.tooltip_text = str(copy.detach) if not detach.is_empty() else "분리할 수 있는 창고 자리 또는 권한 없음"
			socket.pressed.connect(func()->void:preview.call("spatial_detach",detach.duplicate(true)))
		else:
			socket.text = copy.empty_slot
			var candidates := {}
			var alternatives := HBoxContainer.new()
			work.add_child(alternatives)
			var choices: Array = slot.get("attach",[])
			part_page = clampi(part_page,0,maxi(0,choices.size()-1))
			if choices.is_empty(): socket.tooltip_text = "이 위치에 넣을 수 있는 창고 물품이 없습니다."
			for option: Dictionary in choices:
				var part := str(option.child_id)
				candidates[part] = option
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
			socket.set_drag_forwarding(Callable(),func(_at:Vector2,data:Variant)->bool:
				return data is Dictionary and candidates.has(data.get("item","")),func(_at:Vector2,data:Variant)->void:
				if data is Dictionary and candidates.has(data.get("item","")):
					var payload: Dictionary = candidates[data.item].duplicate(true)
					if drop_part.is_valid(): drop_part.call(payload,data)
					else: preview.call("spatial_attach",payload))
