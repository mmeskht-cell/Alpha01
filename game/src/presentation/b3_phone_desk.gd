extends Control

signal selected_contact(actor: String)
signal confirm_order(actor: String,id: String,command: String,revision: int)

var book := VBoxContainer.new()
var sheet := VBoxContainer.new()
var footer := HBoxContainer.new()
var options: Array
var payments: Dictionary
var revision: int
var selected := ""
var preview := ""
var percent := 100
var contact_key := ""
var sheet_key := ""
var sheet_scroll: ScrollContainer
var preview_revision := -1
var headings: Array[Label] = []
var language := "ko"

func _copy(ko: String,en: String) -> String:
	return en if language=="en" else ko

func _paper(rect: Rect2, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var stock := StyleBoxFlat.new()
	stock.bg_color = Color("#cbb898") if headings.is_empty() else Color("#ddcbb0")
	stock.border_width_left = 6
	stock.border_width_bottom = 3
	stock.border_color = Color("#aa9373")
	stock.content_margin_left = 14
	stock.content_margin_right = 14
	stock.content_margin_top = 12
	stock.content_margin_bottom = 12
	stock.shadow_color = Color("#231b1680")
	stock.shadow_size = 5
	panel.add_theme_stylebox_override("panel",stock)
	add_child(panel)
	panel.position = rect.position
	panel.size = rect.size
	var column := VBoxContainer.new()
	panel.add_child(column)
	headings.append(body(column,title,20))
	return column

func _scroll(column: VBoxContainer, content: VBoxContainer) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll

func body(parent: Control, caption: String, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",roundi(font_size*percent/100.0))
	label.add_theme_color_override("font_color",Color("#30271f"))
	parent.add_child(label)
	return label

func link(parent: Control,id: String,caption: String,callback: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = caption
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size",roundi(16*percent/100.0))
	button.custom_minimum_size = Vector2(44,44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func _ready() -> void:
	var address := _paper(Rect2(32,176,346,386),"연락처 수첩")
	_scroll(address,book)
	var docket := _paper(Rect2(777,171,469,400),"회수 의뢰 전표")
	sheet_scroll = _scroll(docket,sheet)
	docket.add_child(footer)

func _clear(parent: Control) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func populate(contacts: Array,terms: Array,receipts: Dictionary,actor: String,rev: int,scale_percent: int,locale: String="ko") -> void:
	language = locale
	options = terms
	payments = receipts
	revision = rev
	percent = scale_percent
	for heading in headings:
		heading.add_theme_font_size_override("font_size",roundi(20*percent/100.0))
	if headings.size()==2:
		headings[0].text=_copy("연락처 수첩","Address book")
		headings[1].text=_copy("회수 의뢰 전표","Recovery order slip")
	var next_selected: String = actor if contacts.any(func(row:Dictionary)->bool:return row.actor==actor) else ""
	if selected!=next_selected or (not preview.is_empty() and preview_revision!=rev):
		preview=""
		preview_revision=-1
	selected=next_selected
	var next_key := JSON.stringify([contacts,percent,language])
	if contact_key!=next_key:
		contact_key = next_key
		_clear(book)
		for contact: Dictionary in contacts:
			var id := str(contact.actor)
			var button := link(book,"contact_"+id,contact.caption,func()->void:
				if selected==id:
					_show_contact_selection()
					return
				selected = id
				selected_contact.emit(id)
				preview = ""
				show_sheet())
			button.toggle_mode = true
		if contacts.is_empty(): body(book,_copy("교환한 연락처가 없습니다.","No exchanged contacts."))
	show_sheet()

func _show_contact_selection() -> void:
	for child in book.get_children():
		if child is Button: child.set_pressed_no_signal(str(child.name)=="contact_"+selected)

func show_sheet() -> void:
	_show_contact_selection()
	var next_key := JSON.stringify([selected,preview,options,payments.get(selected,[]),percent,revision,language])
	if sheet_key==next_key: return
	sheet_key = next_key
	var scroll_offset := sheet_scroll.scroll_vertical
	_clear(sheet)
	_clear(footer)
	if selected.is_empty():
		body(sheet,_copy("수첩에서 연락처를 고르세요.","Select a contact in the address book."))
		return
	var match_count := 0
	for option: Dictionary in options:
		if option.actor!=selected: continue
		match_count += 1
		var id := str(option.id)
		var command := str(option.command)
		var dispatch := command=="alpha_salvage_dispatch"
		if preview.is_empty():
			link(sheet,"terms_"+id,_copy("회수 조건 보기","Review recovery terms") if dispatch else _copy("의뢰 취소 조건","Review cancellation terms"),func()->void:
				preview=id
				preview_revision=revision
				show_sheet()
				sheet_scroll.scroll_vertical=0)
		elif preview==id:
			body(sheet,_copy("발주 조건","Order terms") if dispatch else _copy("취소와 환급","Cancellation and refund"),20)
			body(sheet,option.body)
			link(footer,"phone_"+id,_copy("의뢰 확정","Confirm order") if dispatch else _copy("취소 확정","Confirm cancellation"),func()->void:
				if preview!=id: return
				preview=""
				confirm_order.emit(selected,id,command,preview_revision))
	if not preview.is_empty() and footer.get_child_count()==0:
		body(sheet,_copy("조건이 바뀌었습니다. 전표를 접고 다시 확인하세요.","Terms changed. Close the slip and review again."))
	if not preview.is_empty():
		link(footer,"cancel_call",_copy("전표 접기","Close slip"),func()->void:
			preview=""
			show_sheet())
	else:
		var lines: PackedStringArray = payments.get(selected,PackedStringArray())
		if not lines.is_empty():
			body(sheet,_copy("수첩에 남은 영수증","Recorded receipts"),20)
			for row in lines: body(sheet,row)
		elif match_count==0:
			body(sheet,_copy("지금 확인할 의뢰 조건이 없습니다.","No order terms are currently available."))
		sheet_scroll.set_deferred("scroll_vertical",scroll_offset)
