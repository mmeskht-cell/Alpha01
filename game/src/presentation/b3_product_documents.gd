extends VBoxContainer
## A bounded document spread. Tabs and columns stay mounted while contents change.

signal record_selected(key: String)
var tabs := HBoxContainer.new()
var left := VBoxContainer.new()
var right := VBoxContainer.new()
var summary := Label.new()
var current_tab := ""
var current_record := ""
var data: Dictionary = {}
var view_key := ""
var scrolls: Array[ScrollContainer] = []
var offsets: Dictionary = {}
var heading_size := 20
var body_size := 18
var language := "ko"

func _copy(ko: String,en: String) -> String:
	return en if language=="en" else ko

func _ready() -> void:
	add_theme_constant_override("separation",8)
	add_child(summary)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(tabs)
	var folio := HBoxContainer.new()
	folio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	folio.add_theme_constant_override("separation",6)
	add_child(folio)
	_make_page(folio,left)
	_make_page(folio,right)

func _make_page(folio: HBoxContainer,page: VBoxContainer) -> void:
	var cover := PanelContainer.new()
	var stock := StyleBoxFlat.new()
	stock.bg_color = Color("#cbbc9e") if page==left else Color("#dfd1b3")
	stock.border_color = Color("#8b7352")
	stock.border_width_left = 4
	stock.border_width_bottom = 4
	stock.shadow_color = Color("#100d0a99")
	stock.shadow_size = 6
	for side: String in ["left","right","top","bottom"]:
		stock.set("content_margin_"+side,16)
	cover.add_theme_stylebox_override("panel",stock)
	cover.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folio.add_child(cover)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scrolls.append(scroll)
	cover.add_child(scroll)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation",8)
	scroll.add_child(page)

func _clear(parent: Control) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _line(parent: Control,text: String,size_px: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size_px)
	label.add_theme_color_override("font_color",Color("#30271f"))
	parent.add_child(label)
	return label

func _button(parent: Control,id: String,text: String,activate: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size",body_size)
	button.custom_minimum_size = Vector2(44,44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	button.pressed.connect(activate)
	return button

func _record_face(button: Button) -> void:
	var edge := StyleBoxFlat.new()
	edge.bg_color = Color("#cbbc9e")
	edge.border_color = Color("#a38b68")
	edge.border_width_bottom = 1
	edge.content_margin_left = 10
	edge.content_margin_right = 10
	var selected_face := edge.duplicate() as StyleBoxFlat
	selected_face.bg_color = Color("#bfa779")
	selected_face.border_width_left = 3
	for state: String in ["normal","hover","pressed","hover_pressed"]:
		button.add_theme_stylebox_override(state,edge if state=="normal" else selected_face)
	for state: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]:
		button.add_theme_color_override(state,Color("#30271f"))

func open(header: String,groups: Dictionary,percent: int,revision_key: String,locale: String="ko") -> void:
	if not data.is_empty() and revision_key==view_key: return
	if not current_tab.is_empty():
		offsets[current_tab] = [scrolls[0].scroll_vertical,scrolls[1].scroll_vertical]
	view_key = revision_key
	language = locale
	body_size = roundi(16*percent/100.0)
	heading_size = roundi(20*percent/100.0)
	summary.text = header
	summary.add_theme_font_size_override("font_size",heading_size)
	var keys_changed := data.keys()!=groups.keys()
	data = groups
	if not data.has(current_tab): current_tab = str(groups.keys()[0])
	if keys_changed:
		_clear(tabs)
		for key: String in data:
			var tab := _button(tabs,"folio_"+key,str(data[key].caption),func()->void:_change_tab(key))
			tab.toggle_mode = true
	tabs.visible = data.size()>1
	for tab: Button in tabs.get_children():
		tab.add_theme_font_size_override("font_size",body_size)
		var key := str(tab.name).trim_prefix("folio_")
		tab.text = str(data[key].caption)
	_draw_pages()

func _change_tab(key: String) -> void:
	if key!=current_tab:
		offsets[current_tab] = [scrolls[0].scroll_vertical,scrolls[1].scroll_vertical]
		current_tab = key
		current_record = ""
		_draw_pages()
	else:
		_highlight_tab()

func _highlight_tab() -> void:
	for tab: Button in tabs.get_children(): tab.set_pressed_no_signal(str(tab.name)=="folio_"+current_tab)

func _draw_pages() -> void:
	_highlight_tab()
	_clear(left)
	var group: Dictionary = data[current_tab]
	_line(left,str(group.caption),heading_size)
	var rows: Array = group.get("rows",[])
	if rows.is_empty():
		current_record = ""
		_line(left,str(group.get("empty",_copy("기록 없음","No records"))),body_size)
	elif not rows.any(func(row:Dictionary)->bool:return str(row.key)==current_record):
		current_record = str(rows[0].key)
	for row: Dictionary in rows:
		var key := str(row.key)
		var button := _button(left,key,str(row.caption),func()->void:
			current_record = key
			_highlight_record()
			record_selected.emit(key)
			_draw_detail(group,rows)
			scrolls[1].scroll_vertical=0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		_record_face(button)
	_highlight_record()
	_draw_detail(group,rows)
	var saved: Array = offsets.get(current_tab,[0,0])
	for index in range(scrolls.size()):
		scrolls[index].set_deferred("scroll_vertical",saved[index])

func _highlight_record() -> void:
	for row in left.get_children():
		if row is Button: row.set_pressed_no_signal(str(row.name)==current_record)

func _draw_detail(group: Dictionary,rows: Array) -> void:
	_clear(right)
	_line(right,_copy("기록 상세","Record details"),heading_size)
	for row: Dictionary in rows:
		if str(row.key)==current_record:
			if row.has("sections"):
				var sections: Array = row.sections
				for index in range(sections.size()):
					var section: Dictionary = sections[index]
					if index>0: right.add_child(HSeparator.new())
					var heading := _line(right,str(section.heading),heading_size)
					heading.name = "section_heading_"+str(index)
					heading.set_meta("document_heading",true)
					var body := _line(right,str(section.body),body_size)
					body.name = "section_body_"+str(index)
			else:
				_line(right,str(row.get("detail","")),body_size)
			break
	var details: Callable = group.get("render",Callable())
	if details.is_valid(): details.call(right)
	elif current_record.is_empty(): _line(right,_copy("왼쪽에서 기록을 고르세요.","Select a record on the left."),body_size)
	for label: Label in right.find_children("*","Label",true,false):
		label.add_theme_font_size_override("font_size",heading_size if label.has_meta("document_heading") else body_size)
		label.add_theme_color_override("font_color",Color("#30271f"))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for button: Button in right.find_children("*","Button",true,false):
		button.add_theme_font_size_override("font_size",body_size)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
