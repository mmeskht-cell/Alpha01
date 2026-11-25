extends PanelContainer
## Bound cover and fixed tab strip. The host mounts real model/surface/price pages.
signal page_requested(index: int)
signal closed
var scroll: ScrollContainer
var pages: VBoxContainer
var tabs: Array[Button] = []
var close_button: Button

func _ready() -> void:
	var cover := StyleBoxFlat.new()
	cover.bg_color = Color("#d6c9ae")
	cover.border_color = Color("#594b3c")
	cover.border_width_left = 10
	cover.border_width_bottom = 5
	cover.content_margin_left = 12
	cover.content_margin_right = 10
	cover.content_margin_top = 8
	cover.content_margin_bottom = 8
	add_theme_stylebox_override("panel",cover)
	var book := VBoxContainer.new()
	add_child(book)
	var header := HBoxContainer.new()
	book.add_child(header)
	var titles := ["모델","표면","가격·기록","덮기"]
	for index in range(titles.size()):
		var tab := Button.new()
		tab.name = ["book_models","book_surface","book_prices","r2_book_close_inactive"][index]
		tab.text = titles[index]
		tab.custom_minimum_size = Vector2(44,44)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = index<3
		tab.pressed.connect(func()->void:
			if index<3: page_requested.emit(index)
			else: closed.emit())
		header.add_child(tab)
		if index<3: tabs.append(tab)
		else: close_button = tab
	scroll = ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	book.add_child(scroll)
	pages = VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	visibility_changed.connect(_update_close_action)
	_update_close_action()

func _update_close_action() -> void:
	close_button.name = "close_drawer" if is_visible_in_tree() else "r2_book_close_inactive"

func select_page(index: int, percent: int) -> void:
	for i in range(tabs.size()):
		tabs[i].set_pressed_no_signal(i==index)
	for child: Button in tabs[0].get_parent().get_children():
		child.add_theme_font_size_override("font_size",roundi(16.0*percent/100.0))
