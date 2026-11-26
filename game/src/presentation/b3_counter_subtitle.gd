extends Control
## Bounded subtitle pages for the customer standing across the counter.
var _utterance := Label.new()
var _next := Button.new()
var _pages: Array[String] = []
var _page := 0
var _speech := ""
var _points := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_utterance.name = "Utterance"
	_utterance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_utterance.max_lines_visible = 2
	_utterance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_utterance.add_theme_color_override("font_color",Color("#eee7d8"))
	_utterance.add_theme_color_override("font_outline_color",Color("#171613"))
	_utterance.add_theme_constant_override("outline_size",6)
	add_child(_utterance)
	_next.name = "subtitle_next"
	_next.custom_minimum_size = Vector2(52,44)
	_next.pressed.connect(func()->void:
		_page = (_page+1)%_pages.size()
		_show_page())
	add_child(_next)

func bind(speech: String, reading_scale: int, next_label: String) -> void:
	var points := roundi(18.0*reading_scale/100.0)
	var font := _utterance.get_theme_font("font")
	_utterance.add_theme_font_size_override("font_size",points)
	_utterance.size = Vector2(size.x,ceilf(font.get_height(points)*2.0)+2)
	_next.position = Vector2(size.x-64,size.y-44)
	_next.size = Vector2(64,44)
	_next.tooltip_text = next_label
	if _speech!=speech or _points!=points:
		_page = 0 if _speech!=speech else _page
		_speech = speech
		_points = points
		_paginate(font)
		_page = mini(_page,_pages.size()-1)
	_show_page()

func _paginate(font: Font) -> void:
	_pages.clear()
	var row := ""
	var page := ""
	for word: String in _speech.replace("\n"," ").split(" ",false):
		var remaining := word
		var connector := " " if not row.is_empty() else ""
		while not remaining.is_empty():
			if font.get_string_size(row+connector+remaining,HORIZONTAL_ALIGNMENT_LEFT,-1,_points).x<=size.x-8:
				row += connector+remaining
				break
			if not row.is_empty():
				page = _append_row(page,row)
				row = ""
				connector = ""
				continue
			# Long unspaced text can span rows. Always consume at least one character.
			var count := 1
			while count<remaining.length() and font.get_string_size(remaining.left(count+1),HORIZONTAL_ALIGNMENT_LEFT,-1,_points).x<=size.x-8:
				count += 1
			page = _append_row(page,remaining.left(count))
			remaining = remaining.substr(count)
	page = _append_row(page,row) if not row.is_empty() else page
	if not page.is_empty() or _pages.is_empty(): _pages.append(page)

func _append_row(page: String,row: String) -> String:
	if page.is_empty(): return row
	_pages.append(page+"\n"+row)
	return ""

func _show_page() -> void:
	_utterance.text = _pages[_page]
	_next.visible = _pages.size()>1
	_next.text = "%d/%d ›"%[_page+1,_pages.size()]
