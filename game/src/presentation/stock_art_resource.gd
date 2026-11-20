extends RefCounted
## Public presentation mapping, independent of catalog and save bindings.
## Never derives geometry or item state from a texture. No hidden condition art.
const Documents = preload("res://src/content/packaged_documents.gd")
const Radio = preload("res://src/presentation/radio_art_resource.gd")
const PROFILE: String = "res://data/presentation/stock_art.json"

static func resolve(visual_id: String) -> Dictionary:
	if visual_id == "portable_radio":
		var radio: Dictionary = Radio.resolve()
		if radio.is_empty():
			return {}
		return {"key": radio.key, "texture": radio.texture}
	var profile: Dictionary = Documents.read_object(PROFILE)
	if profile.get("version") != 1 or not profile.get("assets") is Dictionary:
		return {}
	var raw: Variant = profile.assets.get(visual_id)
	if not raw is Dictionary or not raw.get("texture") is String or not raw.get("dimensions") is Array or raw.dimensions.size() != 2:
		return {}
	var path: String = raw.texture
	if not path.begins_with("res://assets/art/items/") or ".." in path or not path.ends_with(".svg"):
		return {}
	var texture := load(path) as Texture2D
	if texture == null or texture.get_width() != int(raw.dimensions[0]) or texture.get_height() != int(raw.dimensions[1]):
		return {}
	return {"key": visual_id, "texture": texture}

static func fit(bounds: Rect2, texture: Texture2D) -> Rect2:
	var extent: Vector2 = texture.get_size()
	var scale: float = minf(bounds.size.x / extent.x, bounds.size.y / extent.y)
	var fitted: Vector2 = extent * maxf(0.0, scale)
	return Rect2(bounds.get_center() - fitted * 0.5, fitted)

static func paint(canvas: Control, bounds: Rect2, art: Dictionary, rotated: bool = false) -> void:
	if art.is_empty() or not bounds.has_area():
		return
	var texture: Texture2D = art.texture
	if rotated:
		var swapped: Rect2 = Rect2(-Vector2(bounds.size.y, bounds.size.x) * 0.5, Vector2(bounds.size.y, bounds.size.x))
		canvas.draw_set_transform(bounds.get_center(), PI * 0.5)
		canvas.draw_texture_rect(texture, fit(swapped, texture), false)
		canvas.draw_set_transform(Vector2.ZERO)
	else:
		canvas.draw_texture_rect(texture, fit(bounds, texture), false)
