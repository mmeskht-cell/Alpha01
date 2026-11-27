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
	var header := HBoxContainer.new()
	add_child(header)
	var title := Label.new()
	title.text = "Reference plates" if english else "재질 표본"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var next := Button.new()
	next.name = "next_surface_plate"
	next.text = ("Plate %d/4 ›" if english else "도판 %d/4 ›")%(variant+1)
	next.custom_minimum_size = Vector2(44,44)
	next.pressed.connect(func()->void: plate_requested.emit(family,(variant+1)%4))
	header.add_child(next)

	var index_strip := HBoxContainer.new()
	index_strip.add_theme_constant_override("separation",2)
	add_child(index_strip)
	for material: String in Visuals.MATERIALS:
		var tab := Button.new()
		tab.name = "reference_"+material
		tab.text = material_name(material,language)
		tab.toggle_mode = true
		tab.set_pressed_no_signal(material==family)
		tab.set_meta("book_tab",true)
		tab.custom_minimum_size = Vector2(44,44)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(func()->void: plate_requested.emit(material,variant))
		index_strip.add_child(tab)

	var plates := HBoxContainer.new()
	plates.add_theme_constant_override("separation",6)
	add_child(plates)
	_swatch(plates,"reference_base","Clean" if english else "기본",
		Visuals.texture_for({"base":family,"overlay":""}),language)
	var grades := ["Light","Medium","Heavy"] if english else ["경미","보통","심함"]
	for grade in range(grades.size()):
		var texture := Visuals.texture_for(Visuals.reference_sample(family,grade,variant))
		_swatch(plates,"reference_wear_"+str(grade),grades[grade],texture,language)

func _swatch(plates: HBoxContainer,id: String,caption: String,texture: Texture2D,language: String) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plates.add_child(column)
	var plate := preload("res://src/presentation/b3_desk_prop.gd").new()
	plate.name = id
	plate.kind = "reference_plate"
	plate.sample = texture
	plate.custom_minimum_size.y = 76
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	column.add_child(plate)
	var label := Label.new()
	label.text = caption if texture else ("Missing" if language=="en" else "미반입")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
