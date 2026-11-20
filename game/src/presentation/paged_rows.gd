extends VBoxContainer
## Bounded native labels over a read-only public list. No records are discarded.
const PAGE_SIZE: int = 20
var _rows: Array = []
var _translate: Callable
var _format: Callable
var _page: int = 0
var _body: VBoxContainer
var _summary: Label
var _previous: Button
var _next: Button

func configure(rows: Array, translator: Callable, formatter: Callable) -> void:
	_rows = rows
	_translate = translator
	_format = formatter
	var bar := HBoxContainer.new()
	add_child(bar)
	_previous = Button.new()
	_previous.text = _translate.call("ui.page_previous", {})
	_previous.custom_minimum_size.y = 44
	_previous.pressed.connect(change_page.bind(-1))
	bar.add_child(_previous)
	_summary = Label.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_summary)
	_next = Button.new()
	_next.text = _translate.call("ui.page_next", {})
	_next.custom_minimum_size.y = 44
	_next.pressed.connect(change_page.bind(1))
	bar.add_child(_next)
	_body = VBoxContainer.new()
	add_child(_body)
	_page = 0
	_render()

func page_count() -> int:
	return maxi(1, ceili(float(_rows.size()) / PAGE_SIZE))

func page_view() -> Dictionary:
	return {"page": _page, "pages": page_count(), "total": _rows.size(), "first": _page * PAGE_SIZE, "end": mini((_page + 1) * PAGE_SIZE, _rows.size()), "rendered": _body.get_child_count()}

func change_page(delta: int) -> void:
	var next_page: int = clampi(_page + delta, 0, page_count() - 1)
	if next_page != _page:
		_page = next_page
		_render()

func _render() -> void:
	for node: Node in _body.get_children():
		_body.remove_child(node)
		node.queue_free()
	var first: int = _page * PAGE_SIZE
	var end: int = mini(first + PAGE_SIZE, _rows.size())
	_summary.text = _translate.call("ui.page_range", {"first": str(first + 1 if end > first else 0), "last": str(end), "total": str(_rows.size())})
	_previous.disabled = _page == 0
	_next.disabled = _page + 1 >= page_count()
	for i: int in range(first, end):
		var label := Label.new()
		label.text = str(_format.call(_rows[i]))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_body.add_child(label)
