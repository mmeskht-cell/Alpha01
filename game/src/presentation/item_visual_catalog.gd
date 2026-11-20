extends Resource
## Presentation-only mapping of public item IDs to provisional artwork roles.
## Replace texture/regions in Inspector; no domain definitions or save mutation.
const Profile=preload("res://src/presentation/item_visual_profile.gd")
@export var profiles:Dictionary={}
@export var item_keys:Dictionary={}
@export var counter_keys:Dictionary={}
@export var inspection_keys:Dictionary={}
@export var counter_fallback:String="electronics"
@export var inspection_fallback:String="electronics"

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
