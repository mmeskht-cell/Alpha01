extends RefCounted
## Presentation-only illustrations of public reference descriptions and acquired
## observation records. No specimen files, hidden state, candidate evaluation,
## new observations or numerical interpretation.
const ObservationText=preload("res://src/presentation/public_observation_text.gd")

static func texture_sample(pattern:String)->ImageTexture:
	if pattern not in ["pits","parallel","cross"]:
		return null
	var sample:=Image.create(80,36,false,Image.FORMAT_RGBA8)
	sample.fill(Color("#596362"))
	for y:int in range(2,34):
		for x:int in range(2,78):
			var marked:bool=false
			if pattern=="pits":
				marked=(x%11==3 and y%7==3) or (x%13==6 and y%9==6)
			elif pattern=="parallel":
				marked=posmod(x+y*2,9)==0
			else:
				marked=posmod(x+y*2,11)==0 or posmod(x-y*2,11)==0
			if marked:
				sample.set_pixel(x,y,Color("#C2BEAA"))
	return ImageTexture.create_from_image(sample)

# Representative public candidate sketches, not photos or actual item identity.
# The second accent line and separate badge are examples from the R-18S
# description, not a claim that every production run has them.
static func radio_reference(candidate:String)->ImageTexture:
	if candidate not in ["selvar_r18","selvar_r18s"]:
		return null
	var sample:=Image.create(100,48,false,Image.FORMAT_RGBA8)
	sample.fill(Color("#313739"))
	var edge:=Color("#242C2D")
	var body:=Color("#737D7B")
	var dark:=Color("#465250")
	var accent:=Color("#BDAD8E")
	sample.fill_rect(Rect2i(4,7,73,35),edge)
	sample.fill_rect(Rect2i(7,9,67,30),body)
	sample.fill_rect(Rect2i(10,13,42,22),dark)
	for i:int in range(5):
		sample.fill_rect(Rect2i(13,15+i*4,36,2),edge)
	# Adjacent side-view swatch, separate from the common front silhouette.
	sample.fill_rect(Rect2i(80,7,16,35),edge)
	sample.fill_rect(Rect2i(82,9,12,31),body)
	sample.fill_rect(Rect2i(85,12,2,25),accent)
	if candidate=="selvar_r18s":
		sample.fill_rect(Rect2i(89,12,2,25),accent)
		sample.fill_rect(Rect2i(56,13,14,5),accent)
	return ImageTexture.create_from_image(sample)

# Original public teaching examples of cosmetic wear. These sketches are
# intentionally not indexed by a damage number, actual item, or condition.
static func wear_reference(pattern:String)->ImageTexture:
	if pattern not in ["light","visible","heavy"]:
		return null
	var img:=Image.create(100,52,false,Image.FORMAT_RGBA8)
	img.fill(Color("#313739"))
	img.fill_rect(Rect2i(5,5,90,42),Color("#555D59"))
	img.fill_rect(Rect2i(8,8,84,36),Color("#78817A"))
	img.fill_rect(Rect2i(9,9,82,2),Color("#9CA397"))
	img.fill_rect(Rect2i(9,41,82,2),Color("#414A45"))
	# Disjoint, hand-authored examples; no truth-to-image conversion.
	var marks:Array=[Rect2i(13,15,11,1),Rect2i(74,34,9,1)]
	if pattern in ["visible","heavy"]:
		marks.append_array([Rect2i(32,23,20,2),Rect2i(47,30,13,1),Rect2i(8,10,3,12),Rect2i(87,32,5,8)])
	if pattern=="heavy":
		marks.append_array([Rect2i(14,30,19,3),Rect2i(58,14,25,2),Rect2i(67,22,4,14),Rect2i(27,8,14,4),Rect2i(9,38,31,5),Rect2i(83,8,9,7)])
	for mark:Rect2i in marks:
		img.fill_rect(mark,Color("#C2BEAA"))
	return ImageTexture.create_from_image(img)

static func texture_control(texture:Texture2D)->TextureRect:
	var image:=TextureRect.new()
	image.texture=texture
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return image

# A typographic transcript preserves the acquired characters and uncertainty.
# It is never advertised as an actual magnified photograph of the item.
static func mark_transcription(value:String)->Control:
	var panel:=Panel.new()
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("#363B38")
	style.border_color=Color("#8F9D90")
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel",style)
	var reading:=Label.new()
	reading.name="transcribed_mark"
	reading.text=value
	reading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	reading.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	reading.clip_text=true
	reading.add_theme_font_size_override("font_size",24)
	reading.add_theme_color_override("font_color",Color("#D5D0C3"))
	reading.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_child(reading)
	reading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reading.offset_left=6
	reading.offset_right=-6
	return panel

# Unsupported, stale, claimed, or absent readings have no graphic.
# A readout is not an image of a physical inscription and must be captioned.
static func acquired_display(fact:Dictionary,tr_key:Callable)->Control:
	if not fact.get("current",false) or fact.get("is_claim",true) or str(fact.get("evidence_id","")).is_empty():
		return null
	var key:String=str(fact.get("observation_key",""))
	var value:Variant=fact.get("observed_value")
	var display:Control
	if key in ["R001.material","case_texture"] and value in ["parallel","cross"]:
		display=texture_control(texture_sample(str(value)))
		display.set_meta("caption_key","book.texture.observation")
	elif key in ["R001.casing_detail","R001.batch","back_mark"] and value is String and not str(value).is_empty():
		display=mark_transcription(str(value))
		display.set_meta("caption_key","inspection.mark_transcription")
	elif key in ["R001.function","function_status"] and value in ["serviceable","inoperable"]:
		var panel:=Panel.new()
		panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("#1C2526")
		style.border_color=Color("#8F9D90")
		style.set_border_width_all(2)
		panel.add_theme_stylebox_override("panel",style)
		var reading:=Label.new()
		reading.text=ObservationText.reading(key,value,tr_key)
		reading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		reading.clip_text=true
		reading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		reading.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		reading.add_theme_color_override("font_color",Color("#C1CDB7"))
		reading.mouse_filter=Control.MOUSE_FILTER_IGNORE
		panel.add_child(reading)
		reading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		reading.offset_left=8
		reading.offset_right=-8
		display=panel
		display.set_meta("caption_key","inspection.readout_caption")
	else:
		return null
	display.name="inspection_acquired_visual"
	display.set_meta("evidence_id",fact.evidence_id)
	return display
