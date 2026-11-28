extends RefCounted
## M5 launcher bootstrap: a random seed is chosen once for a NEW save and
## recovered from CHECKSUM-VALID A/B generations before session creation.
## The complete save is later validated by GameSession's strict command replay.
## This reader never deletes, repairs, or overwrites old save files.
const Rules = preload("res://src/domain/value_rules.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const PRODUCT_SLOT := "b3_campaign_v1"
const EXPECTED_LOCKS: Array = ["alpha_marcus_intro", "alpha_ian_hygiene_offer_d1", "hygiene_buy", "hygiene_sale"]

static func _saved_seed(path: String, slot: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > Repo.MAX_BYTES:
		return {}
	# Corrupted A/B generations are an expected recovery case. Do not call
	# JSON.parse_string here: Godot prints an ERROR for invalid JSON and strict
	# CI treats that diagnostic as a runtime failure. Parser.parse returns a
	# bounded failure code without turning safe recovery into an engine error.
	var decoder := JSON.new()
	var encoded: String = f.get_as_text()
	f.close()
	if decoder.parse(encoded) != OK:
		return {}
	var raw: Variant = decoder.data
	if not Rules.keys(raw, ["schema_version", "content_version", "slot_id", "revision", "payload", "checksum"]):
		return {}
	if raw.schema_version != Repo.SCHEMA_VERSION or raw.content_version != Repo.CONTENT_VERSION or raw.slot_id != slot or not Rules.integer(raw.revision) or not raw.payload is String or not raw.checksum is String:
		return {}
	if raw.payload.sha256_text() != raw.checksum:
		return {}
	var payload_decoder := JSON.new()
	if payload_decoder.parse(raw.payload) != OK:
		return {}
	var snapshot: Variant = payload_decoder.data
	if not snapshot is Dictionary or not Rules.integer(snapshot.get("revision")) or snapshot.revision!=raw.revision or not snapshot.get("alpha_shop") is Dictionary:
		return {}
	var profile: Variant = snapshot.alpha_shop.get("profile", {})
	if not profile is Dictionary or not profile.get("visit_random") is Dictionary:
		return {}
	var random_policy: Variant = profile.visit_random
	if not Rules.keys(random_policy, ["version", "seed", "locked_ids"]) or random_policy.version != 1 or random_policy.locked_ids != EXPECTED_LOCKS or not Rules.integer(random_policy.seed, 1, Rules.LIMIT):
		return {}
	if snapshot.alpha_shop.get("binding") != Rules.canonical(profile).sha256_text():
		return {}
	var result := {"seed": int(random_policy.seed), "revision": int(raw.revision)}
	# Product source descriptors are read from the checksum-bound profile.
	# Legacy callers retain their existing seed-only contract.
	if slot==PRODUCT_SLOT:
		if not Rules.integer(profile.get("integrated_catalog"),1,1) or profile.has("civilian_supply"):
			return {}
		var planner: Variant = profile.get("visit_plan_policy",1)
		if not Rules.integer(planner,1,3) or (profile.has("visit_plan_policy") and planner not in [2,3]):
			return {}
		result["campaign_version"] = int(planner)
		result["binding"] = snapshot.alpha_shop.binding
	return result

static func select_seed(directory: String, slot: String) -> Dictionary:
	if not Rules.identifier(slot):
		return {"ok": false, "error": "seed_slot"}
	var seen: bool = false
	var found: Array = []
	for gen: String in ["a", "b"]:
		var file: String = directory.path_join(slot + "." + gen + ".json")
		if FileAccess.file_exists(file):
			seen = true
			var seed: Dictionary = _saved_seed(file, slot)
			if not seed.is_empty():
				found.append(seed)
	if seen:
		if found.is_empty():
			return {"ok": false, "error": "seed_save_invalid"}
		for row: Dictionary in found:
			if row.seed != found[0].seed:
				return {"ok": false, "error": "seed_save_conflict"}
		var result := {"ok": true, "seed": int(found[0].seed), "new": false}
		if slot==PRODUCT_SLOT:
			for row: Dictionary in found:
				if row.campaign_version!=found[0].campaign_version or row.binding!=found[0].binding:
					return {"ok":false,"error":"campaign_source_conflict"}
			result["campaign_version"]=int(found[0].campaign_version)
		return result
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return {"ok": true, "seed": int(rng.randi_range(1, Rules.LIMIT)), "new": true}
