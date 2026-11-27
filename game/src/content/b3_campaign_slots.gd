extends RefCounted
## Product slots use the same strict seed binding and A/B replay as the shop.
const Campaign = preload("res://src/content/b3_integrated_campaign_seed.gd")
const Seeds = preload("res://src/content/alpha_b3_seed_authority.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const ROOT := "user://zt_rebuild/b3_campaign"
const KEY := "b3_campaign_v1"
const COUNT := 3

static func directory(root: String,index: int) -> String:
	return root.path_join("slot_"+str(index+1))

static func preferences_path(root: String) -> String:
	return root.path_join("ui_preferences.json")

static func inspect(root: String,index: int) -> Dictionary:
	var location := directory(root,index)
	var stamp := 0
	var occupied := FileAccess.file_exists(location.path_join(KEY+".registry.active"))
	for generation: String in ["a","b"]:
		var path := location.path_join(KEY+"."+generation+".json")
		if FileAccess.file_exists(path):
			occupied = true
			stamp = maxi(stamp,int(FileAccess.get_modified_time(path)))
	if not occupied:
		return {"status":"empty","stamp":0}
	var selected := Seeds.select_seed(location,KEY)
	if not selected.get("ok",false) or selected.new:
		return {"status":"damaged","stamp":stamp}
	var source := Campaign.content(int(selected.seed))
	var session := Session.new()
	if source.is_empty() or not session.initialize(source.defs,source.state,false,false,{},source.alpha_profile):
		return {"status":"damaged","stamp":stamp}
	var loaded: Dictionary = Repo.new(location).load_session(session,KEY)
	return {"status":"valid" if loaded.get("ok",false) else "damaged","stamp":stamp}
