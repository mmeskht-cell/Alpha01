extends RefCounted
## Retain view controls and their focus while the current desk is rebound.
## Callbacks are replaced on bind so that they never keep a previous visit's actions.

var _nodes: Dictionary = {}
var _used: Dictionary = {}
var _context := ""

func begin() -> void:
	_used.clear()

func scope(context: String) -> void:
	if context == _context: return
	for node: Control in _nodes.values():
		node.get_parent().remove_child(node)
		node.queue_free()
	_nodes.clear()
	_used.clear()
	_context = context

func mount(parent: Control, key: String, rect: Rect2, create: Callable) -> Control:
	var node := _nodes.get(key) as Control
	if not is_instance_valid(node):
		node = create.call()
		node.name = key
		node.set_meta("r2_desk_control",true)
		parent.add_child(node)
		_nodes[key] = node
	var slide := node.get_meta("shop_slide") as Tween if node.has_meta("shop_slide") else null
	if slide and slide.is_valid(): slide.kill()
	node.position = rect.position
	node.size = rect.size
	node.show()
	parent.move_child(node, -1)
	_used[key] = true
	return node

func button(parent: Control, key: String, rect: Rect2, caption: String, activate: Callable) -> Button:
	var control := mount(parent,key,rect,func()->Button:
		var created := Button.new()
		created.pressed.connect(func()->void:
			var callback: Callable = created.get_meta("activate")
			if created.is_visible_in_tree(): callback.call())
		return created) as Button
	control.text = caption
	control.set_meta("activate",activate)
	return control

func finish() -> void:
	for key: String in _nodes:
		if not _used.has(key): _nodes[key].hide()
