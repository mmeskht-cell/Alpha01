extends VBoxContainer
## Native price control candidate; no editable amount field and no authority calls.
## Host owns the visit-scoped draft and supplies a player-visible basis.
signal ratio_changed(value: int)
const Quote = preload("res://src/presentation/b3_ratio_offer.gd")
var _basis: Dictionary = {}
var _ratio: int = 1000
var _amount: Label
var _percent: Label
var _buttons: Array[Button] = []

func _ready() -> void:
	name = "ratio_offer_control"
	add_theme_constant_override("separation",4)
	var row := HBoxContainer.new()
	add_child(row)
	row.add_theme_constant_override("separation",4)
	for delta: int in [-50,-1,1,50]:
		if delta==1:
			var center := VBoxContainer.new()
			center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			center.add_theme_constant_override("separation",0)
			row.add_child(center)
			_amount = Label.new()
			_amount.name = "offer_amount"
			_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_amount.add_theme_font_size_override("font_size",20)
			center.add_child(_amount)
			_percent = Label.new()
			_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_percent.add_theme_font_size_override("font_size",14)
			center.add_child(_percent)
		var button := Button.new()
		button.name = "ratio_" + ("minus_" if delta<0 else "plus_") + ("5" if absi(delta)==50 else "fine")
		button.text = ("%+d%%" % int(delta/10) if absi(delta)==50 else "%+.1f%%" % (float(delta)/10.0))
		button.custom_minimum_size = Vector2(44,44)
		button.pressed.connect(func()->void: _change(delta))
		row.add_child(button)
		_buttons.append(button)
	_render()

func bind(base: Dictionary, ratio: int) -> void:
	_basis = base.duplicate(true)
	_ratio = ratio
	if is_node_ready(): _render()

func proposed_amount() -> int:
	return Quote.amount(_basis,_ratio)

func _change(delta: int) -> void:
	var next: int = Quote.shift(_basis,_ratio,delta)
	if next==_ratio: return
	_ratio = next
	_render()
	ratio_changed.emit(_ratio)

func _render() -> void:
	var valid: bool = proposed_amount()>0
	var title: String = "감정가 자료 부족"
	match str(_basis.get("source","")):
		"appraisal_range": title = "내 감정가 기준"
		"catalog_reference": title = "도감 참고가 기준"
		"posted_ask": title = "내 매대 표시가 기준"
		"public_quote": title = "손님 공개 요구가 기준"
		"personal_provisional": title = "내 임시 평가액 기준"
	tooltip_text = ("%s · %d %s" % [title,int(_basis.amount),str(_basis.currency)]) if not _basis.is_empty() else title
	_amount.text = ("%d %s" % [proposed_amount(),str(_basis.get("currency",""))]) if valid else "제안 기준 없음"
	_percent.text = "%.1f%%" % (float(_ratio)/10.0) if valid else "—"
	for i: int in range(_buttons.size()):
		var delta: int = [-50,-1,1,50][i]
		_buttons[i].disabled = not valid or Quote.shift(_basis,_ratio,delta)==_ratio


func present_as_receipt(enabled: bool) -> void:
	if enabled==_amount.has_theme_color_override("font_color"): return
	_amount.add_theme_font_size_override("font_size",24 if enabled else 20)
	if enabled:
		_amount.add_theme_color_override("font_color",Color("#302820"))
		_percent.add_theme_color_override("font_color",Color("#554734"))
	else:
		_amount.remove_theme_color_override("font_color")
		_percent.remove_theme_color_override("font_color")
