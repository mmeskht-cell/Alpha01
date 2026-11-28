extends VBoxContainer
## Reference index and mounted swatches. Turning a plate only changes the book.
signal plate_requested(family: String, variant: int)

const Visuals = preload("res://src/presentation/surface_visuals.gd")
const ENGLISH_MATERIALS = ["Metal","Plastic","Paper","Fabric","Glass"]

static func material_name(family: String, language: String) -> String:
	var index := Visuals.MATERIALS.find(family)
	if index<0: return "Deferred" if language=="en" else "보류"
	return ENGLISH_MATERIALS[index] if language=="en" else Visuals.MATERIAL_NAMES[index]

func bind(family: String, variant: int, language: String) -> void:
	var english := language=="en"
	# Six equal cells across two rows: five families and the independent plate turn.
	# Avoid squeezing five translated labels into a single 376-unit row at 150%.
	add_theme_constant_override("separation",4)
	var index_strip := GridContainer.new()
	index_strip.columns = 3
	index_strip.add_theme_constant_override("h_separation",2)
	index_strip.add_theme_constant_override("v_separation",2)
	add_child(index_strip)
	for material: String in Visuals.MATERIALS:
		var tab := Button.new()
		tab.name = "reference_"+material
		tab.text = material_name(material,language)
		tab.toggle_mode = true
		tab.set_pressed_no_signal(material==family)
		tab.set_meta("book_tab",true)
		tab.set_meta("book_single_line",true)
		tab.custom_minimum_size = Vector2(44,44)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(func()->void: plate_requested.emit(material,variant))
		index_strip.add_child(tab)
	var next := Button.new()
	next.name = "next_surface_plate"
	next.text = "%d/4 ›"%(variant+1)
	next.tooltip_text = "Next reference plate" if english else "다음 도감 도판"
	next.set_meta("book_single_line",true)
	next.custom_minimum_size = Vector2(44,44)
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next.set_meta("book_tab",true)
	next.pressed.connect(func()->void: plate_requested.emit(family,(variant+1)%4))
	index_strip.add_child(next)

	var plates := GridContainer.new()
	plates.columns = 2
	plates.add_theme_constant_override("h_separation",8)
	plates.add_theme_constant_override("v_separation",2)
	add_child(plates)
	_swatch(plates,"reference_base","Base sample" if english else "기본 표본",
		Visuals.texture_for({"base":family,"overlay":""}),language)
	var grades := ["Light","Medium","Heavy"] if english else ["경미","보통","심함"]
	for grade in range(grades.size()):
		var texture := Visuals.texture_for(Visuals.reference_sample(family,grade,variant))
		_swatch(plates,"reference_wear_"+str(grade),grades[grade],texture,language)

func _swatch(plates: GridContainer,id: String,caption: String,texture: Texture2D,language: String) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plates.add_child(column)
	var plate := preload("res://src/presentation/b3_desk_prop.gd").new()
	plate.name = id
	plate.kind = "reference_plate"
	plate.sample = texture
	plate.custom_minimum_size = Vector2(130,130)
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	column.add_child(plate)
	var label := Label.new()
	label.name = id+"_caption"
	label.set_meta("book_single_line",true)
	label.text = caption if texture else ("Missing" if language=="en" else "미반입")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
