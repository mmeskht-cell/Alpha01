extends RefCounted
## Application boundary: validated commands, explicit save outcome, detached reads.
const Catalog = preload("res://src/content/catalog_loader.gd")
const Documents = preload("res://src/content/packaged_documents.gd")
const Session = preload("res://src/domain/game_session.gd")
const Opening = preload("res://src/domain/gate1_opening.gd")
const DayOne = preload("res://src/domain/day_one.gd")
const ComponentMarket = preload("res://src/domain/component_market.gd")
const ComponentAppraisal = preload("res://src/domain/component_appraisal.gd")
const CustomerInspection = preload("res://src/domain/customer_inspection.gd")
const GATE1_SCENARIO: String = "res://data/campaign/gate1_1/scenario.json"
const GATE1_CATALOG: String = "res://data/campaign/gate1_1/catalog.json"
const Saves = preload("res://src/persistence/save_repository.gd")
const CampaignSaves = preload("res://src/persistence/campaign_registry_store.gd")
const Rules = preload("res://src/domain/value_rules.gd")
const Localization = preload("res://src/presentation/localization_service.gd")
var _session: RefCounted
var _saves: RefCounted
var localization: RefCounted
var _slot: String
var _save_pending: bool = false
var _load_failed: bool = false
var _last_save_error: String = ""
var _registry_storage: bool = false

func initialize(initial: Dictionary, slot: String = "foundation", save_directory: String = "user://zt_rebuild/saves", catalog_path: String = "res://data/catalog/foundation.json", composite_pilot: bool = false, registry_storage: bool = false) -> bool:
	if _session != null or not Rules.identifier(slot) or not catalog_path.begins_with("res://data/") or not catalog_path.ends_with(".json") or ".." in catalog_path:
		return false
	var catalog := Catalog.load_file(catalog_path)
	if not catalog.ok:
		return false
	var candidate := Session.new()
	if not candidate.initialize(catalog.definitions, initial, composite_pilot):
		return false
	var languages := Localization.new()
	if not languages.initialize():
		return false
	_session = candidate
	_saves = Saves.new(save_directory)
	localization = languages
	_slot = slot
	# Once a campaign migration starts, an older scene/config flag cannot
	# reopen its frozen legacy generations as the writable current slot.
	var existing_registry: bool = false
	if slot in ["gate1_day_one_v3", "gate1_composite_pilot_v3"]:
		for suffix: String in [".registry.active", ".registry.a.json", ".registry.b.json"]:
			existing_registry = existing_registry or FileAccess.file_exists(save_directory.path_join(slot + suffix))
	if registry_storage or existing_registry:
		_registry_storage = true
		var factory: Callable = func() -> RefCounted:
			var fresh := Session.new()
			return fresh if fresh.initialize(catalog.definitions, initial, composite_pilot) else null
		var content_binding: String = Rules.canonical({"seed": candidate.snapshot(), "definitions": catalog.definitions, "composite": composite_pilot, "contract": "campaign-registry-runtime-1"}).sha256_text()
		_saves = CampaignSaves.new()
		var opened: Dictionary = _saves.open(_session, save_directory, slot, factory, content_binding)
		_load_failed = not opened.ok
		_last_save_error = str(opened.get("error", ""))
	return true

## Explicit development-only campaign entry. Dedicated schema3 slot; no old-save migration.
func initialize_gate1_opening(slot: String = "gate1_1_v3", save_directory: String = "user://zt_rebuild/saves") -> bool:
	if slot != "gate1_1_v3":
		return false
	var raw: Variant = Documents.read_object(GATE1_SCENARIO)
	if not raw is Dictionary:
		return false
	var initial: Dictionary = Opening.seed(raw)
	if initial.is_empty():
		return false
	return initialize(initial, slot, save_directory, GATE1_CATALOG)

## New continuation slot; original opening saves remain unchanged.
func initialize_day_one(save_directory: String = "user://zt_rebuild/day_one", registry_storage: bool = false) -> bool:
	if save_directory != "user://zt_rebuild/day_one" and not save_directory.begins_with("user://zt_rebuild/day_one/"):
		return false
	if ".." in save_directory:
		return false
	var initial: Dictionary = Opening.seed(Documents.read_object(GATE1_SCENARIO))
	if initial.is_empty():
		return false
	initial["day_one"] = DayOne.marker()
	return initialize(initial, "gate1_day_one_v3", save_directory, "res://data/campaign/gate1_day_one/catalog.json", false, registry_storage)

## Separate integration slot uses the actual day-one session and a bounded extension.
func initialize_composite_pilot(save_directory: String, registry_storage: bool = false) -> bool:
	if not save_directory.begins_with("user://zt_rebuild/composite_pilots/") or ".." in save_directory:
		return false
	var initial: Dictionary = Opening.seed(Documents.read_object(GATE1_SCENARIO))
	if initial.is_empty():
		return false
	initial["day_one"] = DayOne.marker()
	return initialize(initial, "gate1_composite_pilot_v3", save_directory, "res://data/campaign/gate1_day_one/composite_pilot_catalog.json", true, registry_storage)

## Independent owned-stock workshop fixture. Never opens the campaign slot.
func initialize_component_preview(save_directory: String) -> bool:
	if not save_directory.begins_with("user://zt_rebuild/component_previews/") or ".." in save_directory:
		return false
	return initialize(ComponentAppraisal.seed(), "component_preview_v3", save_directory, "res://data/catalog/component_preview.json")

func initialize_component_market_preview(save_directory: String) -> bool:
	if not save_directory.begins_with("user://zt_rebuild/component_market_previews/") or ".." in save_directory:
		return false
	var initial: Dictionary = ComponentAppraisal.seed()
	if initial.is_empty():
		return false
	initial["component_market"] = ComponentMarket.marker()
	return initialize(initial, "component_market_v3", save_directory, "res://data/catalog/component_preview.json")

func component_market_view() -> Dictionary:
	return _session.component_market_view() if _session != null else {}

func initialize_customer_inspection_preview(save_directory: String, policy: String = "cooperative") -> bool:
	if not save_directory.begins_with("user://zt_rebuild/customer_inspection_previews/") or ".." in save_directory:
		return false
	return initialize(CustomerInspection.seed(ComponentAppraisal.seed(), policy), "customer_inspection_v3", save_directory, "res://data/catalog/component_preview.json")

func save_capacity_view() -> Dictionary:
	return _session.save_capacity_view() if _session != null else {}

func component_workshop_view() -> Dictionary:
	return _session.component_workshop_view() if _session != null else {}

func component_recovery_view(ids: Array) -> Dictionary:
	return _session.component_recovery_view(ids) if _session != null else {}

func counter_view() -> Dictionary:
	return _session.counter_view() if _session != null else {}

## Trusted persistence/test snapshot only; presentation must use item_view.
func snapshot() -> Dictionary:
	return _session.snapshot()

func persistence_view() -> Dictionary:
	return {"ready": _session != null, "save_pending": _save_pending, "load_failed": _load_failed, "error": _last_save_error, "registry_storage": _registry_storage}

func submit(command: Dictionary) -> Dictionary:
	if _session == null:
		return {"ok": false, "error": "session_uninitialized"}
	if _load_failed:
		return {"ok": false, "error": "load_blocked"}
	if _save_pending:
		return {"ok": false, "error": "save_pending"}
	var result: Dictionary = _session.execute(command)
	if result.ok:
		if _registry_storage:
			_saves.remember(command)
		_save_pending = true
		var saved: Dictionary = retry_save()
		result["persisted"] = saved.ok
		if not saved.ok:
			result["save_error"] = saved.error
	return result

func retry_save() -> Dictionary:
	if _session == null:
		return {"ok": false, "error": "session_uninitialized"}
	if _load_failed:
		return {"ok": false, "error": "load_blocked"}
	var result: Dictionary = _saves.save_session(_session, _slot)
	_save_pending = not result.ok
	_last_save_error = str(result.get("error", ""))
	return result

func load_saved() -> Dictionary:
	if _session == null:
		return {"ok": false, "error": "session_uninitialized"}
	if _save_pending:
		return {"ok": false, "error": "save_pending"}
	var result: Dictionary = _saves.load_session(_session, _slot)
	_load_failed = not result.ok
	_last_save_error = str(result.get("error", ""))
	return result

func shutdown() -> void:
	if localization != null:
		localization.shutdown()

func item_view(item_id: String) -> Dictionary:
	return _session.knowledge_view(item_id, "player")

func discard_preview(item_id: String) -> Dictionary:
	return _session.discard_preview(item_id, "player")
