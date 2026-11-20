extends SceneTree
const Primitives = preload("res://src/domain/item_primitives.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	var weights := {"X01": 2, "X01_A": 3, "X01_B": 1, "X01_C": 1}
	var before := weights.duplicate(true)
	check(Primitives.allocate_cost(70, weights) == {"X01": 20, "X01_A": 30, "X01_B": 10, "X01_C": 10}, "C02 fixture allocation")
	check(weights == before, "input weights unchanged")
	check(Primitives.allocate_cost(2, {"z": 1, "a": 1, "m": 1}) == {"a": 1, "m": 1, "z": 0}, "remainder deterministic by ID")
	check(Primitives.allocate_cost(0, {"x": 2}) == {"x": 0}, "zero basis valid")
	check(Primitives.allocate_cost(1.0, {"x": 1.0}) == {"x": 1}, "JSON integer values normalize")
	check(Primitives.allocate_cost(1000000000, {"x": 1000000000}) == {"x": 1000000000}, "integer product within limit")
	check(Primitives.allocate_cost(7, {"x": 3, "y": 2}) == {"x": 5, "y": 2}, "weighted remainder")
	check(Primitives.allocate_cost(-1, weights).is_empty(), "negative amount refused")
	check(Primitives.allocate_cost(1.5, weights).is_empty(), "fractional amount refused")
	check(Primitives.allocate_cost(true, weights).is_empty(), "boolean amount refused")
	check(Primitives.allocate_cost(1, {}).is_empty(), "empty weights refused")
	check(Primitives.allocate_cost(1, {"x": 0}).is_empty(), "zero weight refused")
	check(Primitives.allocate_cost(1, {"x": 1.5}).is_empty(), "fractional weight refused")
	check(Primitives.allocate_cost(1, {"bad id": 1}).is_empty(), "invalid ID refused")
	check(Primitives.allocate_cost(1, {"x": 1000000000, "y": 1}).is_empty(), "weight sum overflow guard")
	check(Primitives.quality_from_observations({}) == "unknown", "unknown stays unknown")
	check(Primitives.quality_from_observations({"functional": true, "complete": true}) == "unknown", "missing restoration evidence stays unknown")
	check(Primitives.quality_from_observations({"functional": true, "complete": true, "restored": false}) == "serviceable", "serviceable")
	check(Primitives.quality_from_observations({"functional": true, "complete": true, "restored": true}) == "refurbished", "refurbished")
	check(Primitives.quality_from_observations({"functional": false, "complete": true, "restored": true}) == "inoperable", "failure overrides restoration")
	check(Primitives.quality_from_observations({"complete": false}) == "inoperable", "known incomplete")
	check(Primitives.quality_from_observations({"functional": "true", "complete": true, "restored": false}) == "unknown", "malformed evidence stays unknown")
	var basis: Dictionary = {"X01": {"VKC": 20, "USD": 0}, "X01_A": {"VKC": 30, "USD": 0}, "X01_B": {"VKC": 10, "USD": 0}, "X01_C": {"VKC": 10, "USD": 0}}
	var basis_before: Dictionary = basis.duplicate(true)
	check(Primitives.sum_basis(basis, ["X01", "X01_A", "X01_B", "X01_C"]) == {"ok": true, "basis": {"VKC": 70, "USD": 0}}, "whole object basis")
	check(Primitives.sum_basis(basis, ["X01", "X01_C"]).basis.VKC == 30, "remaining discard loss basis")
	check(Primitives.sum_basis(basis, ["X01_A", "X01_B"]).basis.VKC == 40, "retained parts basis")
	check(basis == basis_before, "basis preview pure")
	check(not Primitives.sum_basis(basis, ["X01", "X01"]).ok, "duplicate basis refused")
	check(not Primitives.sum_basis(basis, ["missing"]).ok, "missing basis refused")
	check(not Primitives.sum_basis(basis, []).ok, "empty preview refused")
	basis.X01.USD = 3
	check(Primitives.sum_basis(basis, ["X01", "X01_A"]).basis == {"VKC": 50, "USD": 3}, "separate currencies")
	basis.X01.VKC = null
	check(Primitives.sum_basis(basis, ["X01", "X01_A"]).basis == {"VKC": null, "USD": 3}, "unknown historic basis preserved")
	basis.X01_A.USD = -1
	check(not Primitives.sum_basis(basis, ["X01", "X01_A"]).ok, "negative basis refused even with unknown")
	check(not Primitives.sum_basis({"x": {"VKC": 1000000000, "USD": 0}, "y": {"VKC": 1, "USD": 0}}, ["x", "y"]).ok, "basis cap")
	print("ITEM_PRIMITIVES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
