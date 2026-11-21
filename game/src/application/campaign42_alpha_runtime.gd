extends "res://src/application/demo7_runtime.gd"
## Separate 42-day alpha slot; exact same GameSession persistence and UI DTO.
const Candidate=preload("res://src/content/alpha42_mechanics_seed.gd")
const Repository=preload("res://src/persistence/checkpoint_repository.gd")
const CAMPAIGN_SLOT="campaign42_mechanics_alpha_v1"
const PREFIX="user://zt_rebuild/campaign42_mechanics_alpha"

func _fresh()->RefCounted:
	return Candidate.fresh()

func open(directory:String=PREFIX,civilian:bool=false,
	condition_pricing:bool=false,condition_version:int=1)->bool:
	if not directory.begins_with(PREFIX) or ".." in directory or (directory!=PREFIX and not directory.begins_with(PREFIX+"/slot_")):
		return false
	_view_cache.clear()
	_view_cache_key.clear()
	_basic_review_visit=""
	_condition_version=1
	_condition_pricing=false
	_civilian=false
	_save_slot=CAMPAIGN_SLOT
	_session=_fresh()
	if _session==null:
		error="alpha42_seed_invalid"
		return false
	_defs=Candidate.content().defs
	localization=Locale.new()
	if not localization.initialize():
		error="locale_invalid"
		return false
	_repo=Repository.new(directory)
	var recovered_state:Dictionary=_repo.load_state(_save_slot,_fresh)
	if recovered_state.ok:
		recovered=recovered_state.get("recovered",false)
		blocked=not _session.restore(recovered_state.state)
		error="restore_invalid" if blocked else ""
	elif recovered_state.get("error")!="missing":
		blocked=true
		error=str(recovered_state.error)
	return true

func view()->Dictionary:
	var result:Dictionary=super.view()
	result["campaign42_alpha"]=true
	return result

func item_history(id:String)->Dictionary:
	var history:Dictionary=_session.calendar_item_history(id)
	var items:Array=[]
	if not history.get("records",[]).is_empty() or not history.get("work_records",[]).is_empty() or not history.get("contract_records",[]).is_empty():
		items.append({"item_id":id,"history":history})
	return {"items":items,"omitted":0}
