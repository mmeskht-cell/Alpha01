extends PanelContainer
## Bound cover and fixed tab strip. The host mounts real model/surface/price pages.
const PaperProp = preload("res://src/presentation/b3_paper_prop.gd")
signal page_requested(index: int)
signal closed
var scroll: ScrollContainer
var pages: VBoxContainer
## Keep the fold and page margins while wrapping the longest entry within the paper.
const PAGE_MIN_WIDTH := 376.0
var tabs: Array[Button] = []
var close_button: Button

func _ready() -> void:
	var cover := StyleBoxEmpty.new()
	cover.content_margin_left = 49
	cover.content_margin_right = 17
	cover.content_margin_top = 12
	cover.content_margin_bottom = 19
	add_theme_stylebox_override("panel",cover)
	var book := VBoxContainer.new()
	book.add_theme_constant_override("separation",4)
	add_child(book)
	var header := HBoxContainer.new()
	book.add_child(header)
	for index in range(4):
		var tab := Button.new()
		tab.name = ["book_models","book_surface","book_prices","r2_book_close_inactive"][index]
		tab.custom_minimum_size = Vector2(44,44)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = index<3
		tab.pressed.connect(func()->void:
			if index<3: page_requested.emit(index)
			else: closed.emit())
		PaperProp.ink_action(tab)
		tab.autowrap_mode = TextServer.AUTOWRAP_OFF
		header.add_child(tab)
		if index<3: tabs.append(tab)
		else: close_button = tab
	scroll = ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	book.add_child(scroll)
	pages = VBoxContainer.new()
	pages.add_theme_constant_override("separation",4)
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.custom_minimum_size.x = PAGE_MIN_WIDTH
	scroll.add_child(pages)
	visibility_changed.connect(_update_close_action)
	_update_close_action()

func _draw() -> void:
	PaperProp.draw_on(self,size,"book")

func _update_close_action() -> void:
	close_button.name = "close_drawer" if is_visible_in_tree() else "r2_book_close_inactive"

func select_page(index: int, percent: int, language: String, claims: bool = false) -> void:
	var titles := ["Models","Surface","Prices","Close"] if language=="en" else ["모델","표면","시세","덮기"]
	if claims: titles[1] = "Claims" if language=="en" else "손님 말"
	close_button.text = titles[3]
	for i in range(tabs.size()):
		tabs[i].text = titles[i]
		tabs[i].set_pressed_no_signal(i==index)
		PaperProp.ink_action(tabs[i],i==index,6.0)
	PaperProp.ink_action(close_button,false,6.0)
	for child: Button in tabs[0].get_parent().get_children():
		child.add_theme_font_size_override("font_size",roundi(16.0*percent/100.0))
