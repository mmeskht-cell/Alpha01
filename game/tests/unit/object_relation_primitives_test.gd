extends SceneTree
const Relations = preload("res://src/domain/object_relation_primitives.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func node(kind: String = "atomic", parent: String = "", container: String = "", capable: bool = false) -> Dictionary:
	return {"kind": kind, "parent_id": parent, "container_id": container, "owner_id": "player", "custodian_id": "player", "container_capable": capable, "locked": false}

func _initialize() -> void:
	var objects: Dictionary = {"device": node("composite", "", "box"), "insert_a": node("atomic", "device"), "insert_b": node("atomic", "device"), "box": node("atomic", "", "", true)}
	var before: Dictionary = objects.duplicate(true)
	check(Relations.validate({}).ok, "empty projection")
	check(Relations.validate(objects).ok, "composite in independent container")
	check(Relations.disposition_family(objects, "device", "player") == {"ok": true, "item_ids": ["device", "insert_a", "insert_b"]}, "exact independent family")
	check(objects == before, "pure")
	check(Relations.disposition_family(objects, "insert_a", "player").error == "relation_not_root", "no attached sale")
	check(Relations.disposition_family(objects, "box", "player").error == "relation_filled_container", "filled box refused")
	check(not Relations.disposition_family(objects, "device", "other").ok, "wrong actor")
	var bad: Dictionary = objects.duplicate(true)
	bad.insert_a.locked = true
	check(Relations.disposition_family(bad, "device", "player").error == "relation_protected", "locked descendant")
	bad = objects.duplicate(true)
	bad.box.locked = true
	check(Relations.disposition_family(bad, "device", "player").error == "relation_protected", "locked containing box")
	bad = objects.duplicate(true)
	bad.insert_a.owner_id = "other"
	check(not Relations.validate(bad).ok, "child ownership inconsistent")
	bad = objects.duplicate(true)
	bad.insert_a.custodian_id = "other"
	check(not Relations.validate(bad).ok, "child custody inconsistent")
	bad = objects.duplicate(true)
	bad.insert_a.parent_id = "missing"
	check(not Relations.validate(bad).ok, "missing parent")
	bad = objects.duplicate(true)
	bad.insert_a.parent_id = "insert_a"
	check(not Relations.validate(bad).ok, "self parent")
	bad = objects.duplicate(true)
	bad.insert_a.container_id = "box"
	check(not Relations.validate(bad).ok, "attached and stored simultaneously")
	bad = objects.duplicate(true)
	bad.insert_a.parent_id = "insert_b"
	check(not Relations.validate(bad).ok, "atomic parent forbidden")
	bad = objects.duplicate(true)
	bad.device.parent_id = "insert_a"
	bad.device.container_id = ""
	check(not Relations.validate(bad).ok, "cycle forbidden")
	bad = objects.duplicate(true)
	bad.insert_a.kind = "composite"
	check(not Relations.validate(bad).ok, "nested composite outside first gate")
	bad = objects.duplicate(true)
	bad.box.container_id = "device"
	check(not Relations.validate(bad).ok, "nested or invalid box")
	bad = objects.duplicate(true)
	bad.device.container_id = "missing"
	check(not Relations.validate(bad).ok, "missing container")
	bad = objects.duplicate(true)
	bad.box.container_capable = false
	check(not Relations.validate(bad).ok, "container capability required")
	bad = objects.duplicate(true)
	bad.box.custodian_id = "other"
	check(not Relations.validate(bad).ok, "container custody mismatch")
	var custody: Dictionary = {"gift": node()}
	custody.gift.owner_id = "other"
	check(Relations.validate(custody).ok and not Relations.disposition_family(custody, "gift", "player").ok, "custodial property not owned")
	check(Relations.disposition_family({"box": node("atomic", "", "", true)}, "box", "player").ok, "empty box allowed")
	check(not Relations.validate({"bad": {}}).ok, "malformed row")
	print("OBJECT_RELATIONS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
