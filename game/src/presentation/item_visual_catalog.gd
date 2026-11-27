extends Resource
## Presentation-only mapping of public item IDs to provisional artwork roles.
## Replace texture/regions in Inspector; no domain definitions or save mutation.
const Profile=preload("res://src/presentation/item_visual_profile.gd")
const FoodVisuals=preload("res://src/presentation/preserved_food_visuals.gd")
const CivilianVisuals=preload("res://src/presentation/approved_civilian_visuals.gd")
@export var profiles:Dictionary={}
@export var item_keys:Dictionary={}
@export var counter_keys:Dictionary={}
@export var inspection_keys:Dictionary={}
@export var counter_fallback:String=""
@export var inspection_fallback:String=""

func profile_for(item_id:String,role:String)->Profile:
	var key:String=str(item_keys.get(item_id,""))
	if role=="counter":
		key=str(counter_keys.get(item_id,key if not key.is_empty() else counter_fallback))
	elif role=="inspection":
		key=str(inspection_keys.get(item_id,key if not key.is_empty() else inspection_fallback))
	elif role!="stock":
		return null
	var profile:Profile=profiles.get(key) as Profile
	if profile!=null and profile.valid(false):
		return profile
	return null

@export var model_art: Dictionary = {}

# The isolated civilian receiver uses the approved new radio model, never R001.
# Module B uses the approved control-module image. Module A has a separate model entry.
# These bindings are presentation only and cannot alter the definition or item identity.
const CIVILIAN_MODEL_ART = {
	"f3_receiver_v1":"utility_01_field_radio",
	"battery":"utility_03_aa_batteries",
	"demo_tool":"utility_05_wrench",
	"demo_hygiene":"medical_06_soap",
	"demo_electronics":"utility_08_multimeter",
	"f3_module_b":"utility_10_control_module"
}

func model_texture(model: String,role: String,item_id: String="",back: bool=false) -> Texture2D:
	var entry: Dictionary = model_art.get(model,{})
	# R001 and R003 share a historical definition but have distinct specimens.
	if model=="portable_radio" and item_id=="R003":
		if role=="overhead" or back: return null
		var specimen := profile_for(item_id,role)
		return specimen.texture if specimen else null
	if role=="overhead":
		# A distinct approved take of the same model. No generic or stock art fallback.
		return entry.get("overhead_back" if back else "overhead") as Texture2D
	# Keep the same approved model in all three presentation roles.
	if CIVILIAN_MODEL_ART.has(model): return CivilianVisuals.texture_for(str(CIVILIAN_MODEL_ART[model]),role,back)
	if FoodVisuals.LABELS.has(model): return FoodVisuals.texture_for(model,role,back)
	if CivilianVisuals.LABELS.has(model): return CivilianVisuals.texture_for(model,role,back)
	if back and entry.has("back"): return entry.back as Texture2D
	if entry.has(role): return entry[role] as Texture2D
	if entry.has("base"): return entry.base as Texture2D
	if item_id.is_empty(): return null
	var legacy := profile_for(item_id,role)
	return legacy.texture if legacy else null

func reference_entries() -> Dictionary:
	var result := {}
	for key: String in FoodVisuals.available_keys():
		result[key] = FoodVisuals.LABELS[key].ko
	for key: String in CivilianVisuals.available_keys():
		result[key] = CivilianVisuals.LABELS[key].ko
	return result
