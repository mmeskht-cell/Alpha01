extends VBoxContainer

var slot_page := 0
var part_page := 0
## A visible slot accepts only candidates supplied by the composition authority.
func populate(root_id: String,composition: Dictionary,items: Dictionary,catalog: Resource,copy: Dictionary,translate: Callable,preview: Callable) -> void:
	for node in get_children():
		remove_child(node)
		node.queue_free()
	var work := self
	var header := HBoxContainer.new()
	work.add_child(header)
	var slots: Array = composition.get("slots",[])
	var redraw := func()->void: populate(root_id,composition,items,catalog,copy,translate,preview)
	var restore := Button.new()
	restore.name = "repair"
	restore.text = copy.repair
	header.add_child(restore)
	restore.custom_minimum_size.y = 44
	restore.pressed.connect(func()->void:preview.call("spatial_restore_item",{"actor":"player","item_id":root_id}))
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
			socket.tooltip_text = copy.detach
			socket.pressed.connect(func()->void:preview.call("spatial_detach",detach.duplicate(true)))
		else:
			socket.text = copy.empty_slot
			var candidates := {}
			var alternatives := HBoxContainer.new()
			work.add_child(alternatives)
			var choices: Array = slot.get("attach",[])
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
					preview.call("spatial_attach",candidates[data.item].duplicate(true)))
