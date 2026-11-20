extends RefCounted
const Rules = preload("res://src/domain/value_rules.gd")
## Bounded reader for packaged, immutable JSON objects. Never accepts user paths.
const MAX_BYTES: int = 65536
const PATHS: Array = [
	"res://data/campaign/gate2/watch_public_catalog.json",
	"res://data/campaign/gate2/watch_inspection_profile.json",
	"res://data/campaign/gate2/demo_radio_inspection.json",
	"res://data/campaign/gate2/demo_radio_catalog.json",
	"res://data/campaign/gate2/demo_customer_policy_v1.json",
	"res://data/campaign/gate2/public_evidence_relevance_v1.json",
	"res://data/campaign/gate1_1/scenario.json",
	"res://data/campaign/gate1_1/appraisal_reference.json",
	"res://data/campaign/gate1_1/inspection_profiles_v1.json",
	"res://data/campaign/gate1_1/material_reference.json",
	"res://data/campaign/component_preview/profiles.json",
	"res://data/campaign/component_preview/customer_inspection_policy.json",
	"res://data/presentation/radio_regions.json",
	"res://data/presentation/radio_art.json",
	"res://data/presentation/stock_art.json",
	"res://data/presentation/public_reference_guide.json"
]
static var _cache: Dictionary = {}

static func read_object(path: String) -> Dictionary:
	if path not in PATHS:
		return {}
	if _cache.has(path):
		return _cache[path].duplicate(true)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return {}
	var parsed := JSON.new()
	if parsed.parse(file.get_as_text()) != OK or not parsed.data is Dictionary:
		return {}
	_cache[path] = Rules.normalized(parsed.data)
	return _cache[path].duplicate(true)
