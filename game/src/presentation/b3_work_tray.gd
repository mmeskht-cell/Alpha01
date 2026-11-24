extends ScrollContainer
## A visible slot accepts only candidates supplied by the composition authority.
func populate(root_id: String,composition: Dictionary,items: Dictionary,catalog: Resource,copy: Dictionary,translate: Callable,preview: Callable) -> void:
	var work := VBoxContainer.new()
	work.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(work)
	var restore := Button.new()
	restore.name = "repair"
	restore.text = copy.repair
	work.add_child(restore)
	restore.pressed.connect(func()->void:preview.call("spatial_restore_item",{"actor":"player","item_id":root_id}))
	for slot: Dictionary in composition.get("slots",[]):
		var child := str(slot.item_id)
		var socket := Button.new()
		socket.custom_minimum_size = Vector2(0,50)
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
			var alternatives := VBoxContainer.new()
			work.add_child(alternatives)
			for option: Dictionary in slot.get("attach",[]):
				var part := str(option.child_id)
				candidates[part] = option
				var button := Button.new()
				button.name = "attach_"+part
				button.text = str(copy.attach)+" · "+str(translate.call("b2.item."+str(items[part].def_id)))
				button.icon = catalog.call("model_texture",str(items[part].def_id),"stock",part)
				button.expand_icon = true
				button.custom_minimum_size.y = 44
				alternatives.add_child(button)
				button.pressed.connect(func()->void:preview.call("spatial_attach",option.duplicate(true)))
			socket.set_drag_forwarding(Callable(),func(_at:Vector2,data:Variant)->bool:
				return data is Dictionary and candidates.has(data.get("item","")),func(_at:Vector2,data:Variant)->void:
				if data is Dictionary and candidates.has(data.get("item","")):
					preview.call("spatial_attach",candidates[data.item].duplicate(true)))
