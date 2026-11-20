extends SceneTree
const Gesture = preload("res://src/presentation/inspection_gesture.gd")
const Bench = preload("res://src/presentation/radio_workbench.gd")
var checks: int = 0
var failures: int = 0
var requests: Array = []

func check(value: bool, name: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", name)

func dto(known: bool = false) -> Dictionary:
	return {"tools": [
		{"tool_id": "wear_detail", "known": known, "available": not known, "minutes": 5},
		{"tool_id": "casing_detail", "known": false, "available": true, "minutes": 10},
		{"tool_id": "material_detail", "known": false, "available": true, "minutes": 5},
		{"tool_id": "batch_detail", "known": false, "available": true, "minutes": 5},
		{"tool_id": "function_detail", "known": false, "available": true, "minutes": 5},
		{"tool_id": "display_damage_detail", "known": false, "available": true, "minutes": 5}
	], "catalog": {"model_candidates": []}}

func translate(key: String, _args: Dictionary) -> String:
	return key

func _initialize() -> void:
	var gesture := Gesture.new()
	check(not gesture.begin("fake", Vector2.ZERO), "unknown tool")
	check(gesture.begin("wear_detail", Vector2.ZERO), "pickup")
	check(gesture.release("visible_wear_detail") == {"item_id": "R001", "tool_id": "wear_detail", "target": "visible_wear_detail"}, "single direct placement, no scan or hold threshold")
	check(gesture.release("visible_wear_detail").is_empty(), "release only once")
	gesture.begin("casing_detail", Vector2.ZERO)
	check(gesture.release("").is_empty(), "off-object drop cancelled")
	var bench := Bench.new()
	bench.configure(dto(), translate, false, true)
	bench.inspection_requested.connect(func(payload: Dictionary) -> void: requests.append(payload))
	var loupe := Vector2(90, 130)
	var light := Vector2(90, 195)
	var item := Vector2(416, 195)
	var scratch := bench._feature(bench._radio(), bench._region_rect("scratch", 0)).get_center()
	var shell := bench._feature(bench._radio(), bench._region_rect("casing", 0)).get_center()
	bench._press(loupe)
	bench._release(loupe)
	check(requests.is_empty(), "click pickup alone is free")
	bench._move(scratch)
	bench._press(scratch)
	bench._release(scratch)
	check(requests.size() == 1 and requests[0].tool_id == "wear_detail", "click and place on specimen")
	bench._press(light)
	bench._release(Vector2(800, 150))
	check(requests.size() == 1, "reference book is not a specimen")
	bench._press(light)
	bench._release(item)
	check(requests.size() == 1, "wrong region cannot inspect casing")
	bench._press(light)
	bench._release(shell)
	check(requests.size() == 2 and requests[1].tool_id == "casing_detail", "direct drop works on default face")
	bench._turn(1)
	bench.zoom_by(0.1)
	check(requests.size() == 2 and bench.view_state().face == 1, "rotation and zoom free")
	bench.configure(dto(true), translate, false, true)
	bench._press(loupe)
	bench._release(scratch)
	check(requests.size() == 2 and bench.view_state().last_tool == "wear_detail", "known evidence reviewed without submission")
	bench.configure(dto(), translate, true, true)
	bench._press(loupe)
	bench._release(item)
	check(requests.size() == 2, "locked save blocks new inspection")
	bench.configure(dto(), translate, false, true)
	bench._press(Vector2(90, 270))
	bench._release(bench._feature(bench._radio(), bench._region_rect("material", 0)).get_center())
	check(requests.size() == 3 and requests[2].tool_id == "material_detail", "material sampler placement")
	bench._press(Vector2(90, 345))
	bench._release(item)
	check(requests.size() == 3, "wrong face cannot read batch")
	bench._turn(1)
	bench._press(Vector2(90, 345))
	bench._release(bench._feature(bench._radio(), bench._region_rect("side", 1)).get_center())
	bench._turn(-1)
	check(requests.size() == 4 and requests[3].tool_id == "batch_detail", "batch reader placement")
	bench._press(Vector2(90, 130))
	bench._release(Vector2(538, 135))
	check(requests.size() == 5 and requests[4].tool_id == "display_damage_detail" and requests[4].target == "display_damage_sample", "same damage tool selects visible display region")
	bench._press(Vector2(550, 30))
	bench._release(item)
	check(requests.size() == 6 and requests[5].tool_id == "function_detail", "whole-device functional instrument direct placement")
	bench.free()
	print("INSPECTION_INTERACTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
