extends RefCounted
## Presentation-only candidate art registry. Keys are art keys, not approved
## gameplay definitions. No seed, price, ownership or save changes.
## Missing binary files fail closed; a preview is not a texture import.
const ROOT = "res://assets/art/items/preserved_food_v03/"
const LABELS = {
	"food_01_sardines": {"ko":"정어리 통조림","en":"Sardines in Oil"},
	"food_02_canned_meat": {"ko":"소고기 통조림","en":"Canned Beef"},
	"food_03_hardtack": {"ko":"건빵","en":"Hardtack Biscuits"},
	"food_04_canned_beans": {"ko":"콩 통조림","en":"Baked Beans"},
	"food_05_oats": {"ko":"귀리","en":"Rolled Oats"},
	"food_06_pasta": {"ko":"건조 파스타","en":"Dried Pasta"},
	"food_07_instant_soup": {"ko":"즉석 수프","en":"Instant Soup"},
	"food_08_pickled_vegetables": {"ko":"오이 피클","en":"Pickled Cucumbers"},
	"food_09_milk_powder": {"ko":"분유","en":"Milk Powder"},
	"food_10_instant_coffee": {"ko":"인스턴트 커피","en":"Instant Coffee"}
}

static func available(key: String) -> bool:
	if not LABELS.has(key):
		return false
	return ResourceLoader.exists(ROOT+key+"_128.png","Texture2D") and ResourceLoader.exists(ROOT+key+"_256.png","Texture2D")

static func texture_for(key: String, role: String, back: bool=false) -> Texture2D:
	if back or role not in ["stock","counter","inspection"] or not available(key):
		return null
	var suffix: String = "_128.png" if role=="stock" else "_256.png"
	return ResourceLoader.load(ROOT+key+suffix,"Texture2D") as Texture2D

static func available_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	for key: String in LABELS:
		if available(key):
			keys.append(key)
	return keys
