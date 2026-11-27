extends RefCounted
## Presentation-only replacement contract. Body rectangle is defined in normalized texture space.
## Physical placement, observation regions and evidence are not derived from a texture.
const Documents = preload("res://src/content/packaged_documents.gd")
const PATH: String = "res://data/presentation/radio_art.json"

static func resolve(key: String = "") -> Dictionary:
	var profile: Dictionary = Documents.read_object(PATH)
	if profile.get("version") != 1 or not profile.get("assets") is Dictionary:
		return {}
	if key.is_empty():
		key = str(profile.get("default_key", ""))
	var raw: Variant = profile.assets.get(key)
	if not raw is Dictionary or not raw.get("texture") is String or not raw.get("body") is Array or not raw.get("dimensions") is Array:
		return {}
	var path: String = raw.texture
	if not path.begins_with("res://tests/fixtures/art/legacy_gate1/") or ".." in path or not path.ends_with(".svg"):
		return {}
	var b: Array = raw.body
	if b.size() != 4 or raw.dimensions.size() != 2:
		return {}
	for v: Variant in b:
		if (not v is int and not v is float) or not is_finite(float(v)) or v < 0 or v > 1:
			return {}
	var body := Rect2(float(b[0]), float(b[1]), float(b[2]), float(b[3]))
	if not body.has_area() or body.end.x > 1.0 or body.end.y > 1.0:
		return {}
	var tex := load(path) as Texture2D
	if tex == null or tex.get_width() != int(raw.dimensions[0]) or tex.get_height() != int(raw.dimensions[1]):
		return {}
	return {"key": key, "texture": tex, "body": body}

static func draw_rect_for(body_rect: Rect2, body_uv: Rect2) -> Rect2:
	var extent := body_rect.size / body_uv.size
	return Rect2(body_rect.position - extent * body_uv.position, extent)
