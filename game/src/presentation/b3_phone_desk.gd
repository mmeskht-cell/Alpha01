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

func slip(rect: Rect2) -> Panel:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#403b32")
	style.border_width_left = 6
	style.border_color = Color("#ac9670")
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	panel.position = rect.position
	panel.size = rect.size
	return panel

func body(parent: Control, caption: String) -> Label:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",roundi(18*percent/100.0))
	parent.add_child(label)
	return label

func link(parent: Control,id: String,caption: String,callback: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = caption
	button.custom_minimum_size.y = 44
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func populate(contacts: Array,terms: Array,receipts: Dictionary,actor: String,rev: int,scale_percent: int) -> void:
	options = terms
	payments = receipts
	revision = rev
	percent = scale_percent
	selected = actor
	var address := slip(Rect2(36,200,330,338))
	address.add_child(book)
	book.position = Vector2(16,12)
	book.size.x = 298
	body(book,"연락처 수첩")
	for contact: Dictionary in contacts:
		var id := str(contact.actor)
		link(book,"contact_"+id,contact.caption,func()->void:
			selected = id
			selected_contact.emit(id)
			preview = ""
			show_sheet())
	if contacts.is_empty(): body(book,"교환한 연락처가 없습니다.")
	var docket := slip(Rect2(780,186,466,365))
	docket.add_child(sheet)
	sheet.position = Vector2(16,12)
	sheet.size.x = 434
	docket.add_child(footer)
	footer.position = Vector2(16,306)
	footer.size.x = 434
	show_sheet()

func show_sheet() -> void:
	for region: Container in [sheet,footer]:
		for child in region.get_children():
			region.remove_child(child)
			child.queue_free()
	body(sheet,"회수 의뢰 전표")
	if selected.is_empty():
		body(sheet,"수첩에서 연락처를 고르세요.")
		return
	for option: Dictionary in options:
		if option.actor!=selected: continue
		var id := str(option.id)
		var command := str(option.command)
		var dispatch := command=="alpha_salvage_dispatch"
		if preview.is_empty():
			link(sheet,"terms_"+id,"회수 조건 보기" if dispatch else "의뢰 취소 조건",func()->void:
				preview=id
				show_sheet())
		elif preview==id:
			body(sheet,option.body)
			link(footer,"phone_"+id,"의뢰 확정" if dispatch else "취소 확정",func()->void:
				if preview==id:
					preview=""
					confirm_order.emit(selected,id,command,revision))
			link(footer,"cancel_call","전표 접기",func()->void:
				preview=""
				show_sheet())
	if preview.is_empty():
		var lines: PackedStringArray = payments.get(selected,PackedStringArray())
		if not lines.is_empty(): body(sheet,"\n".join(lines))
