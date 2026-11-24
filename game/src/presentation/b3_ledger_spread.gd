extends HBoxContainer

signal receipt_selected(key: String)

func page(width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	var stock := StyleBoxFlat.new()
	stock.bg_color = Color("#403b32")
	stock.content_margin_left = 18
	stock.content_margin_right = 18
	stock.content_margin_top = 12
	stock.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel",stock)
	panel.custom_minimum_size.x = width
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	return column

func line(column: Container,caption: String) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = caption
	column.add_child(label)
	return label

func list(column: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	return rows

func open(wallet: Dictionary,entries: Array,selected: String) -> VBoxContainer:
	var journal := page(564)
	var register := page(560)
	line(journal,"거래 장부    /    보유 현금")
	line(journal,"%d VKC     %d USD"%[wallet.VKC,wallet.USD]).add_theme_font_size_override("font_size",24)
	var rows := list(journal)
	line(register,"선택한 영수증")
	var detail := line(register,"거래 기록이 없습니다." if entries.is_empty() else "왼쪽에서 거래를 선택하세요.")
	for entry: Dictionary in entries:
		var button := Button.new()
		button.name = "r_"+str(entry.key)
		button.text = entry.caption
		button.custom_minimum_size.y = 44
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(button)
		if entry.key==selected: detail.text = entry.facts
		button.pressed.connect(func()->void:
			detail.text = entry.facts
			receipt_selected.emit(entry.key))
	line(register,"의뢰 · 계약 기록")
	return list(register)
