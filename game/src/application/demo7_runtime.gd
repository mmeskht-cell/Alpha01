extends RefCounted
## Production adapter. UI reads only projected state, commands revalidated by GameSession.
const Seed=preload("res://src/content/demo7_seed.gd")
const CivilianSeed=preload("res://src/content/civilian_candidate_seed.gd")
const Repo=preload("res://src/persistence/checkpoint_repository.gd")
const Objects=preload("res://src/domain/object_schema.gd")
const Grid=preload("res://src/domain/grid_primitives.gd")
const Clock=preload("res://src/domain/business_clock.gd")
const Locale=preload("res://src/presentation/localization_service.gd")
const SLOT="demo7_integrated3_v4"
const CIVILIAN_SLOT="demo7_civilian_candidate_v1"
const CONDITION_SLOT="demo7_civilian_condition_v1"
const CONDITION_SLOT_V2="demo7_civilian_condition_v2"
var _condition_version:int=1
var _condition_pricing:bool=false
var _civilian:bool=false
var _save_slot:String=SLOT
var _session:RefCounted
var _repo:RefCounted
var _defs:Dictionary={}
var localization:RefCounted
var blocked:bool=false
var pending:bool=false
var error:String=""
var recovered:bool=false
var _basic_review_visit:String=""
var _view_cache:Dictionary={}
var _view_cache_key:Array=[]

func _fresh()->RefCounted:
	return CivilianSeed.fresh(_condition_pricing,_condition_version) if _civilian else Seed.fresh()

func open(directory:String="user://zt_rebuild/demo7",civilian:bool=false,condition_pricing:bool=false,condition_version:int=1)->bool:
	if not directory.begins_with("user://zt_rebuild/demo7") or ".." in directory:
		return false
	_view_cache.clear()
	_view_cache_key.clear()
	_basic_review_visit=""
	_condition_pricing=condition_pricing and civilian
	if _condition_pricing and condition_version not in [1,2]:
		return false
	_condition_version=condition_version if _condition_pricing else 1
	_civilian=civilian
	_save_slot=(CONDITION_SLOT_V2 if _condition_version==2 else CONDITION_SLOT) if _condition_pricing else (CIVILIAN_SLOT if _civilian else SLOT)
	_session=_fresh()
	if _session==null:
		error="seed_invalid"
		return false
	_defs=(CivilianSeed.content(_condition_pricing,_condition_version) if _civilian else Seed.content()).defs
	localization=Locale.new()
	if not localization.initialize():
		error="locale_invalid"
		return false
	_repo=Repo.new(directory)
	var loaded:Dictionary=_repo.load_state(_save_slot,_fresh)
	if loaded.ok:
		recovered=loaded.get("recovered",false)
		blocked=not _session.restore(loaded.state)
		error="restore_invalid" if blocked else ""
	elif loaded.get("error")!="missing":
		blocked=true
		error=str(loaded.error)
	return true

func snapshot()->Dictionary:
	return _session.snapshot()

func retry()->bool:
	if blocked or _session==null:
		return false
	var state:Dictionary=_session.snapshot()
	var saved:Dictionary=_repo.save(_save_slot,state,[],state,_fresh)
	pending=not saved.ok
	error=str(saved.get("error",""))
	return saved.ok

func submit(kind:String,p:Dictionary,revision:int)->Dictionary:
	if blocked or pending or _session==null:
		return {"ok":false,"error":"save_blocked"}
	if revision!=int(_session.snapshot().revision):
		return {"ok":false,"error":"stale_revision"}
	_view_cache.clear()
	_view_cache_key.clear()
	var before:Dictionary=_session.snapshot()
	var command:Dictionary={"action_id":"demo_"+str(revision+1),"expected_revision":revision,"type":kind,"payload":p}
	var r:Dictionary=_session.execute(command)
	if r.ok:
		if not _schedule_world(kind,p):
			# Never persist a player action with a missing required world consequence.
			if not _session.restore(before):
				blocked=true
				error="world_rollback_failed"
			return {"ok":false,"error":"world_schedule_failed"}
		r["revision"]=_session.snapshot().revision
		r["persisted"]=retry()
		if pending:
			r["save_error"]=error
	return r

# Private deterministic authored schedule. Every change gets a replay receipt.
# The complete player+world result is saved in the same validated generation.
func _world(kind:String,p:Dictionary)->bool:
	var revision:int=_session.snapshot().revision
	var r:Dictionary=_session.execute_world({"action_id":"demo_world_"+str(revision+1),"expected_revision":revision,"type":kind,"payload":p})
	if not r.ok:
		print("ZT_DEMO_WORLD_REJECT ",kind," ",r.get("error",""))
	return r.ok

func _schedule_world(kind:String,p:Dictionary)->bool:
	var s:Dictionary=_session.snapshot()
	if kind=="trade" and p.get("visit_id") in ["visit_g01","visit_g02_buy","watch_a","watch_sale","radio_return","radio_return_sale"]:
		var id:String=p.item_id
		if not s.calendar.tracking.has(id) and not _world("world_track_promote",{"item_id":id}):
			return false
		if not _world("world_track_reference",{"item_id":id,"event_id":"demo_"+str(s.revision)}):
			return false
	if kind!="calendar_morning" or s.game_minutes>=10080:
		return true
	var day:int=Clock.day_index(int(s.game_minutes))
	if day==3 and s.visits.visit_g02_buy.scope.completed and s.items.get("R001",{}).get("owner_id")=="G02":
		return _world("world_sleep_family",{"root_id":"R001"})
	if day==7 and s.calendar.dormant.has("R001"):
		return _world("world_open_visit",{"rule_id":"radio_return"})
	return true

func _placement(state:Dictionary,id:String,owner:String)->Dictionary:
	var size:Array=Objects.footprint(state,_defs,id)
	var ids:Array=state.inventories.keys()
	ids.sort()
	for inv:String in ids:
		var g:Dictionary=state.inventories[inv]
		if g.owner_id!=owner or not g.host_item.is_empty() or inv=="service_grid":
			continue
		var occupied:Array=[]
		for existing:String in state.items:
			var row:Dictionary=state.items[existing]
			if row.inventory==inv and row.parent_id.is_empty() and existing!=id:
				var es:Array=Objects.footprint(state,_defs,existing)
				occupied.append({"item_id":existing,"x":row.x,"y":row.y,"width":es[0],"height":es[1],"rotated":row.rotated})
		var pos:Dictionary=Grid.first_fit(g.width,g.height,occupied,{"item_id":id,"width":size[0],"height":size[1],"rotated":false})
		if pos.ok:
			return {"inventory":inv,"x":pos.x,"y":pos.y,"rotated":pos.rotated}
	return {}

func open_basic_review(visit_id:String,revision:int)->bool:
	if blocked or pending or _session==null or revision!=int(_session.snapshot().revision):
		return false
	var projected:Dictionary=_session.calendar_view()
	if not projected.get("basic_review_available",false) or projected.visits.active!=visit_id:
		return false
	_basic_review_visit=visit_id
	return true

func view()->Dictionary:
	var state:Dictionary=_session.snapshot()
	var cache_key:Array=[state.revision,_basic_review_visit,blocked,pending,error,recovered]
	if cache_key==_view_cache_key and not _view_cache.is_empty():
		return _view_cache.duplicate(true)
	var result:Dictionary=_session.calendar_view(_basic_review_visit)
	if result.get("visits",{}).get("active","")!=_basic_review_visit:
		_basic_review_visit=""
	result["revision"]=state.revision
	result["civilian_candidate"]=_civilian
	result["condition_pricing"]=_condition_pricing
	result["condition_version"]=_condition_version if _condition_pricing else 0
	result["wallet"]=state.wallets.player.duplicate()
	result["stock"]=[]
	result["stock_grids"]=[]
	for id:String in ["player_stock","service_grid"]:
		var grid:Dictionary=state.inventories[id]
		result.stock_grids.append({"id":id,"width":grid.width,"height":grid.height})
	result["recovered"]=recovered
	result["work"]=[]
	result["locked"]=blocked or pending
	result["error"]=error
	for id:String in state.items:
		var item:Dictionary=state.items[id]
		if item.custodian_id!="player" or not item.parent_id.is_empty():
			continue
		var d:Dictionary=Objects.definition(_defs[item.def_id])
		var size:Array=Objects.footprint(state,_defs,id)
		# Stock DTO dimensions are occupied dimensions, not base definition dimensions.
		# The placement authority retains the original footprint and rotation flag.
		if item.rotated:
			size=[size[1],size[0]]
		result.stock.append({"id":id,"label":d.localization_key,"inventory":item.inventory,"owned":item.owner_id=="player","basis":item.basis.duplicate() if item.owner_id=="player" else {},"x":item.x,"y":item.y,"width":size[0],"height":size[1],"rotated":item.rotated})
		if item.owner_id=="player":
			result.stock.back()["family_basis"]=Objects.basis(state,Objects.family(state,id)).get("basis",{})
		var care: Dictionary = _session.exterior_care_view(id)
		if not care.is_empty():
			result.stock.back()["exterior_care"] = care
		if state.phase=="workshop" and d.restorable:
			var plan:Dictionary=_session.restoration_preview(id)
			if not plan.is_empty():
				result.stock.back()["restoration"]=plan.duplicate(true)
				if plan.status=="attempt":
					result.work.append({"id":id,"cost":plan.cost.duplicate(true)})
	result["trade"]={}
	result["trade_can_pay"]=false
	var v:Dictionary=result.get("visits",{}).get("terms",{})
	if str(v.get("kind",""))=="service_offer" and state.items.has(v.get("item_id","")):
		var definition:Dictionary=_defs[state.items[v.item_id].def_id]
		result["service_cost_preview"]=definition.restore_cost.duplicate(true) if definition.restorable else {}
	if v.get("scope",{}).get("kind")=="ordinary" and v.prices.size()==1:
		var id:String=v.prices.keys()[0]
		if state.items.has(id):
			var price:Dictionary=v.prices[id]
			var currency:String="VKC" if price.VKC>0 else "USD"
			var destination:Dictionary=_placement(state,id,v.buyer)
			result.trade={"item_id":id,"seller":v.seller,"buyer":v.buyer,"amount":price[currency],"currency":currency,"visit_id":v.scope.visit_id,"label":Objects.definition(_defs[state.items[id].def_id]).localization_key,"placement":destination}
			result["trade_can_pay"]=int(state.wallets[v.buyer][currency])>=int(price[currency])
	if not result.has("trade_history"):
		result["trade_history"]=_session.calendar_history_index()
	_view_cache=result.duplicate(true)
	_view_cache_key=[state.revision,_basic_review_visit,blocked,pending,error,recovered]
	return result

# Targeted history uses the authority's bounded per-ID query, not the recent index.
func item_history(id:String)->Dictionary:
	var history:Dictionary=_session.calendar_item_history(id)
	var items:Array=[]
	if not history.records.is_empty() or not history.work_records.is_empty():
		items.append({"item_id":id,"history":history})
	return {"items":items,"omitted":0}

func inventory_appraisal(id:String)->Dictionary:
	return _session.inventory_appraisal(id) if _session!=null else {}

func discard_preview(id:String)->Dictionary:
	return _session.discard_preview(id) if _session!=null and not blocked and not pending else {}

func composition_options(id:String)->Dictionary:
	return _session.composition_options(id,"player_stock")

func close()->void:
	if localization!=null:
		localization.shutdown()
		localization=null
	_session=null
	_repo=null
	_view_cache.clear()
	_view_cache_key.clear()
