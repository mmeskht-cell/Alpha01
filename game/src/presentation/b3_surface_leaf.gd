extends VBoxContainer

signal turn(family: String, variant: int, judging: bool)
const Visuals = preload("res://src/presentation/surface_visuals.gd")

func link(row: Container, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 44
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(button)
	button.pressed.connect(callback)
	return button

func bind(family: String, variant: int, judging: bool, percent: int) -> void:
	var index := maxi(0,Visuals.MATERIALS.find(family))
	var controls := HBoxContainer.new()
	add_child(controls)
	if judging:
		link(controls,"‹  표본으로",func()->void: turn.emit(family,variant,false))
		return
	link(controls,str(Visuals.MATERIAL_NAMES[index])+" ›",func()->void:
		turn.emit(Visuals.MATERIALS[(index+1)%Visuals.MATERIALS.size()],variant,false))
	link(controls,"표본 %d/4 ›"%(variant+1),func()->void: turn.emit(family,(variant+1)%4,false))
	var plates := HBoxContainer.new()
	add_child(plates)
	for grade in range(3):
		var sample: Dictionary = Visuals.reference_sample(family,grade,variant)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		plates.add_child(column)
		var swatch := TextureRect.new()
		swatch.texture = Visuals.texture_for(sample)
		swatch.custom_minimum_size.y = 102
		swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		column.add_child(swatch)
		var label := Label.new()
		label.text = ["경미","보통","심함"][grade] if swatch.texture else "미반입"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",roundi(16*percent/100.0))
		column.add_child(label)
	link(self,"비교 예시  ·  내 판단 기록 ›",func()->void: turn.emit(family,variant,true))
