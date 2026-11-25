extends RefCounted
## Private art review only. Never changes items, models, visits or state.
## Dynamic loading allows the standard scene to run without private PNGs.
const ROOT = "res://assets/art/shop_r2_candidate/"
const SIZE = {"rear":Vector2i(640,360),"counter":Vector2i(640,360),"visitor":Vector2i(170,157),"book_closed":Vector2i(102,60),"lens":Vector2i(92,60)}

static func load_layers() -> Dictionary:
	var layers := {}
	for id: String in SIZE:
		var path: String = ROOT+id+".png"
		if not ResourceLoader.exists(path,"Texture2D"): return {}
		var image := load(path) as Texture2D
		if image==null or Vector2i(image.get_size())!=SIZE[id]: return {}
		layers[id]=image
	return layers
