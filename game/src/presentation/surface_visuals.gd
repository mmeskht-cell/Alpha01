extends RefCounted
## W15 presentation-only texture composition. The specimen DTO contains
## observed signals; this module never reads the game session or item truth.
const ROOT = "res://assets/art/items/surface_v01/"
const MATERIALS = ["metal","plastic","paper","fabric","glass"]
const MATERIAL_NAMES = ["금속","플라스틱","종이","직물","유리"]
const SLOTS = ["material_detail","wear_detail","display_damage_detail"]
const SLOT_NAMES = ["표면 무늬","외장 마모","표시부 훼손"]
const SURFACE_SIZE := 256
static var _cache: Dictionary = {}

static func observation_slots(cards: Array) -> Array:
	var slots: Array = []
	for slot: String in SLOTS:
		for card: Dictionary in cards:
			if card.get("slot")==slot and card.get("surface_current",true):
				slots.append(slot)
				break
	return slots

static func observed(cards: Array, slot: String, seed_value: int, profiles: Dictionary = {}) -> Dictionary:
	if slot not in SLOTS:
		return {}
	var value: String = ""
	for card: Dictionary in cards:
		if card.get("slot")==slot and card.get("surface_current",true):
			value = str(card.get("value",""))
			break
	var profile: Dictionary = profiles.get(slot,{})
	var family: String = str(profile.get("family",""))
	var target := str(profile.get("target",""))
	if family in MATERIALS and not target.is_empty() and not value.is_empty():
		if slot=="material_detail":
			# Only combine wear from the same already-observed surface.
			var wear: Dictionary = profiles.get("wear_detail",{})
			if wear.get("family")==family and wear.get("target")==target:
				var combined: Dictionary = observed(cards,"wear_detail",seed_value,profiles)
				if not combined.is_empty(): return combined
			return {"base":family,"overlay":"","caption":"표면 질감 관찰","caption_en":"Observed texture"}
		if value.is_valid_float():
			var observed_intensity := value.to_float()
			if is_finite(observed_intensity) and observed_intensity>=0.0 and observed_intensity<=100.0:
				return _material_wear(family,target,seed_value,observed_intensity)
	if slot=="material_detail":
		if value not in ["parallel","cross"]:
			return {}
		return {"base":value,"overlay":"","opacity":0.0,"turns":0,
			"caption":"평행한 표면 무늬" if value=="parallel" else "교차하는 표면 무늬",
			"caption_en":"Parallel pattern" if value=="parallel" else "Crossed pattern"}
	if not value.is_valid_float():
		return {}
	var intensity: float = value.to_float()
	if not is_finite(intensity) or intensity<0.0 or intensity>100.0:
		return {}
	var key: int = posmod(seed_value ^ slot.hash(),16)
	var sample := _wear_caption(intensity)
	sample.merge({"base":"neutral","overlay":"neutral_wear_"+str(key%4+1) if intensity>0.0 else "",
		"opacity":0.0 if intensity==0.0 else 0.24+0.76*intensity/100.0,
		"turns":key >> 2,"coverage":0.45+0.55*intensity/100.0})
	return sample

static func _wear_caption(intensity: float) -> Dictionary:
	if intensity==0.0:
		return {"caption":"뚜렷한 훼손 흔적 없음","caption_en":"No distinct marks"}
	if intensity<=25.0:
		return {"caption":"한 부분에 모인 흔적","caption_en":"Localized marks"}
	if intensity<=65.0:
		return {"caption":"여러 곳에 흩어진 흔적","caption_en":"Scattered marks"}
	return {"caption":"넓게 퍼진 흔적","caption_en":"Widespread marks"}

## Leave room for different placements even at the top of the observed range.
static func _material_wear(family: String,target: String,seed_value: int,intensity: float) -> Dictionary:
	var sample := _wear_caption(intensity)
	sample["base"] = family
	sample["overlay"] = ""
	if intensity==0.0: return sample
	var geometry := ("%d/%s"%[seed_value,target]).sha256_text()
	var key := geometry.left(2).hex_to_int()
	var proportion := intensity/100.0
	sample.merge({"overlay":family+"_wear_"+str((key & 3)+1),
		"turns":(key >> 2) & 3,"mirrored":bool(key & 16),
		"coverage":lerpf(0.39,0.88,proportion)+0.04*float(geometry.substr(2,2).hex_to_int())/255.0,
		"opacity":lerpf(0.30,1.0,proportion),
		"offset_x":float(geometry.substr(4,2).hex_to_int())/255.0,
		"offset_y":float(geometry.substr(6,2).hex_to_int())/255.0},true)
	return sample

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
	var turns := posmod(int(sample.get("turns",0)),4)
	var mirrored := bool(sample.get("mirrored",false))
	var extent := clampi(roundi(SURFACE_SIZE*float(sample.get("coverage",1.0))),1,SURFACE_SIZE)
	var available := SURFACE_SIZE-extent
	var offset := Vector2i(roundi(available*clampf(float(sample.get("offset_x",0.5)),0.0,1.0)),
		roundi(available*clampf(float(sample.get("offset_y",0.5)),0.0,1.0)))
	var opacity := clampf(float(sample.get("opacity",0.0)),0.0,1.0)
	var cache_key := JSON.stringify([base_key,overlay,turns,mirrored,opacity,extent,offset.x,offset.y])
	if _cache.has(cache_key):
		return _cache[cache_key] as Texture2D
	var image: Image = base.get_image()
	var marks: Image = overlay_texture.get_image()
	if image==null or marks==null or image.get_size()!=marks.get_size() or image.get_size()!=Vector2i(SURFACE_SIZE,SURFACE_SIZE):
		return null
	if image.is_compressed() and image.decompress()!=OK:
		return null
	if marks.is_compressed() and marks.decompress()!=OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	marks.convert(Image.FORMAT_RGBA8)
	if mirrored: marks.flip_x()
	for i: int in range(turns):
		marks.rotate_90(CLOCKWISE)
	marks.resize(extent,extent,Image.INTERPOLATE_NEAREST)
	# Reduce abrupt seams from overlays that have paint at their crop edge.
	var feather := maxi(1,roundi(extent*0.025))
	for y in range(extent):
		var edge_y := mini(y,extent-1-y)
		for x in range(extent):
			var edge := mini(edge_y,mini(x,extent-1-x))
			var pixel := marks.get_pixel(x,y)
			if pixel.a==0.0: continue
			pixel.a *= opacity*minf(1.0,float(edge)/float(feather))
			marks.set_pixel(x,y,pixel)
	image.blend_rect(marks,Rect2i(Vector2i.ZERO,marks.get_size()),offset)
	var texture: Texture2D = ImageTexture.create_from_image(image)
	# Bounded transient presentation cache; never serialized.
	if _cache.size()>=24:
		_cache.erase(_cache.keys()[0])
	_cache[cache_key] = texture
	return texture
