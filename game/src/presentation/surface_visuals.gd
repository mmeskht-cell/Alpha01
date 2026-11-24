extends RefCounted
## W15 presentation-only texture composition. The specimen DTO contains
## observed signals; this module never reads the game session or item truth.
const ROOT = "res://assets/art/items/surface_v01/"
const MATERIALS = ["metal","plastic","paper","fabric","glass"]
const MATERIAL_NAMES = ["금속","플라스틱","종이","직물","유리"]
const SLOTS = ["material_detail","wear_detail","display_damage_detail"]
const SLOT_NAMES = ["표면 무늬","외장 마모","표시부 훼손"]
static var _cache: Dictionary = {}

static func observation_slots(cards: Array) -> Array:
	var slots: Array = []
	for slot: String in SLOTS:
		for card: Dictionary in cards:
			if card.get("slot")==slot:
				slots.append(slot)
				break
	return slots

static func observed(cards: Array, slot: String, seed_value: int) -> Dictionary:
	if slot not in SLOTS:
		return {}
	var value: String = ""
	for card: Dictionary in cards:
		if card.get("slot")==slot:
			value = str(card.get("value",""))
			break
	if slot=="material_detail":
		if value not in ["parallel","cross"]:
			return {}
		return {"base":value,"overlay":"","opacity":0.0,"turns":0,"caption":"평행한 표면 무늬" if value=="parallel" else "교차하는 표면 무늬"}
	if not value.is_valid_float():
		return {}
	var intensity: float = value.to_float()
	if not is_finite(intensity) or intensity<0.0 or intensity>100.0:
		return {}
	var key: int = posmod(seed_value ^ slot.hash(),16)
	var caption: String = "이 관찰에서 뚜렷한 훼손 신호 없음" if intensity==0.0 else ("국소적인 훼손 흔적" if intensity<=25.0 else ("여러 곳의 훼손 흔적" if intensity<=65.0 else "넓은 훼손 흔적"))
	return {"base":"neutral","overlay":"neutral_wear_"+str(key%4+1) if intensity>0.0 else "","opacity":0.0 if intensity==0.0 else 0.24+0.76*intensity/100.0,"turns":floori(float(key)/4.0),"coverage":0.45+0.55*intensity/100.0,"caption":caption}

## These are labelled reference swatches, not an item-specific reading.
static func reference_sample(material: String, grade: int,variant_index: int=0) -> Dictionary:
	if material not in MATERIALS or grade<0 or grade>2 or variant_index<0 or variant_index>3:
		return {}
	return {"base":material,"overlay":material+"_wear_"+str(variant_index+1),"opacity":[0.4,0.75,1.0][grade],"coverage":[0.45,0.75,1.0][grade],"turns":0,"caption":["경미 예시","보통 예시","심함 예시"][grade]}

static func texture_for(sample: Dictionary) -> Texture2D:
	if sample.is_empty():
		return null
	var base_key: String = str(sample.get("base",""))
	if base_key not in MATERIALS+["neutral","parallel","cross"]:
		return null
	var path: String = ROOT+base_key+"_base.png"
	if not ResourceLoader.exists(path,"Texture2D"):
		return null
	var base: Texture2D = ResourceLoader.load(path,"Texture2D") as Texture2D
	if base==null:
		return null
	var overlay: String = str(sample.get("overlay",""))
	if overlay.is_empty():
		return base
	var allowed: Array = []
	for i: int in range(1,5):
		allowed.append(base_key+"_wear_"+str(i))
	if overlay not in allowed:
		return null
	path = ROOT+overlay+".png"
	if not ResourceLoader.exists(path,"Texture2D"):
		return null
	var overlay_texture: Texture2D = ResourceLoader.load(path,"Texture2D") as Texture2D
	if overlay_texture==null:
		return null
	var cache_key: String = JSON.stringify([base_key,overlay,sample.get("turns",0),sample.get("opacity",0.0),sample.get("coverage",1.0)])
	if _cache.has(cache_key):
		return _cache[cache_key] as Texture2D
	var image: Image = base.get_image()
	var marks: Image = overlay_texture.get_image()
	if image==null or marks==null or image.get_size()!=marks.get_size() or image.get_size()!=Vector2i(256,256):
		return null
	if image.is_compressed() and image.decompress()!=OK:
		return null
	if marks.is_compressed() and marks.decompress()!=OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	marks.convert(Image.FORMAT_RGBA8)
	for i: int in range(posmod(int(sample.get("turns",0)),4)):
		marks.rotate_90(CLOCKWISE)
	var extent: int = clampi(roundi(256.0*float(sample.get("coverage",1.0))),1,256)
	marks.resize(extent,extent,Image.INTERPOLATE_NEAREST)
	var opacity: float = clampf(float(sample.get("opacity",0.0)),0.0,1.0)
	for y: int in range(marks.get_height()):
		for x: int in range(marks.get_width()):
			var pixel: Color = marks.get_pixel(x,y)
			pixel.a *= opacity
			marks.set_pixel(x,y,pixel)
	var offset: int = floori(float(256-extent)/2.0)
	image.blend_rect(marks,Rect2i(Vector2i.ZERO,marks.get_size()),Vector2i(offset,offset))
	var texture: Texture2D = ImageTexture.create_from_image(image)
	# Bounded transient presentation cache; never serialized.
	if _cache.size()>=24:
		_cache.erase(_cache.keys()[0])
	_cache[cache_key] = texture
	return texture
