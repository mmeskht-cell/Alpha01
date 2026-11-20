extends RefCounted
## Isolated C2-C4 technical format; never substituted for the live save repo.
const Rules = preload("res://src/domain/value_rules.gd")
const Registry = preload("res://src/domain/dormant_registry.gd")
const Tracking = preload("res://src/domain/selective_tracking.gd")
const Finance = preload("res://src/domain/campaign_accounting_audit.gd")
const Format = preload("res://src/domain/snapshot_format.gd")
const CONTRACT: String = "registry-pilot-1"

static func pack(partition: Dictionary, authority: RefCounted, seed: Dictionary) -> String:
	var full: Dictionary = Registry.materialize(partition, authority)
	if full.is_empty() or not Tracking.valid(partition, full) or (full.has("campaign") and not Finance.reconcile(full, seed)):
		return ""
	var body: Dictionary = {"contract": CONTRACT, "revision": full.revision, "state_hash": Rules.canonical(full).sha256_text(), "partition": partition}
	var encoded: String = Rules.canonical({"body": body, "checksum": Rules.canonical(body).sha256_text()})
	return encoded if encoded.to_utf8_buffer().size() <= Format.MAX_BYTES else ""

static func unpack(encoded: String, authority: RefCounted, seed: Dictionary) -> Dictionary:
	if encoded.to_utf8_buffer().size() > Format.MAX_BYTES:
		return {}
	var json := JSON.new()
	if json.parse(encoded) != OK or not Rules.keys(json.data, ["body", "checksum"]):
		return {}
	var envelope: Dictionary = Rules.normalized(json.data)
	var body: Variant = envelope.body
	if not Rules.keys(body, ["contract", "revision", "state_hash", "partition"]) or body.contract != CONTRACT or not envelope.checksum is String or envelope.checksum != Rules.canonical(body).sha256_text() or not body.partition is Dictionary:
		return {}
	var full: Dictionary = Registry.materialize(body.partition, authority)
	if full.is_empty() or full.revision != body.revision or Rules.canonical(full).sha256_text() != body.state_hash or not Tracking.valid(body.partition, full) or (full.has("campaign") and not Finance.reconcile(full, seed)):
		return {}
	return {"state": full, "partition": body.partition}
