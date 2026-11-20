extends SceneTree
const Visit = preload("res://src/domain/visit_primitives.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	var ordinary: Dictionary = {"visit_id": "V1", "kind": "ordinary", "purpose": "purchase", "completed": false, "required_ids": []}
	var before: Dictionary = ordinary.duplicate(true)
	var items: Array = ["R001"]
	check(Visit.validate_scope(ordinary, "purchase", items).ok, "ordinary purchase")
	check(ordinary == before and items == ["R001"], "scope validation is pure")
	check(not Visit.validate_scope(ordinary, "sale", items).ok, "wrong purpose")
	check(not Visit.validate_scope(ordinary, "purchase", []).ok, "empty transaction")
	check(not Visit.validate_scope(ordinary, "purchase", ["A", "B"]).ok, "ordinary multiple objects")
	check(not Visit.validate_scope(ordinary, "purchase", ["A", "A"]).ok, "duplicate object")
	check(not Visit.validate_scope(ordinary, "purchase", ["bad id"]).ok, "invalid item ID")
	check(not Visit.validate_scope(ordinary, "purchase", "R001").ok, "non-array items")
	ordinary.completed = true
	check(Visit.validate_scope(ordinary, "purchase", items).error == "visit_completed", "completed ordinary visit")
	ordinary.visit_id = "V2"
	ordinary.completed = false
	check(Visit.validate_scope(ordinary, "purchase", items).ok, "later visit may reuse same item identity")
	ordinary.required_ids = ["R001"]
	check(not Visit.validate_scope(ordinary, "purchase", items).ok, "ordinary context cannot impersonate contract")
	var contract: Dictionary = {"visit_id": "K1", "kind": "special_contract", "purpose": "delivery", "completed": false, "required_ids": ["A", "B"]}
	check(Visit.validate_scope(contract, "delivery", ["A", "B"]).ok, "explicit fixed-ID contract")
	check(Visit.validate_scope(contract, "delivery", ["B", "A"]).ok, "order independent required IDs")
	check(not Visit.validate_scope(contract, "delivery", ["A"]).ok, "partial delivery refused")
	check(not Visit.validate_scope(contract, "delivery", ["A", "C"]).ok, "unmatched ID refused")
	check(not Visit.validate_scope(contract, "delivery", ["A", "B", "C"]).ok, "excess item refused")
	check(not Visit.validate_scope(contract, "sale", ["A", "B"]).ok, "contract purpose mismatch")
	contract.required_ids = ["A", "A"]
	check(not Visit.validate_scope(contract, "delivery", ["A", "B"]).ok, "malformed required IDs")
	contract.required_ids = ["A", "B"]
	contract.completed = true
	check(not Visit.validate_scope(contract, "delivery", ["A", "B"]).ok, "completed contract refused")
	check(not Visit.validate_scope({}, "purchase", ["A"]).ok, "missing context refused")
	var v: Dictionary = {"opens": 1440, "expires": 2040}
	check(Visit.in_window(v, 1440, "shop") and Visit.in_window(v, 2040, "shop"), "absolute window includes final decision")
	check(not Visit.in_window(v, 1439, "shop") and not Visit.in_window(v, 2041, "shop") and not Visit.in_window(v, 1500, "workshop"), "outside window or phase denied")
	check(not Visit.in_window({"opens": 20, "expires": 19}, 20, "shop"), "malformed window refused")
	print("VISIT_PRIMITIVES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
