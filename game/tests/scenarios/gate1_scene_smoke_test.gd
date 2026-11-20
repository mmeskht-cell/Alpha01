extends SceneTree
## Initialization/DTO smoke only. Never opens the persistent campaign slot.
const PATHS: Array = [
	"res://scenes/app/gate1_day_one.tscn",
	"res://scenes/app/gate1_counter.tscn",
	"res://scenes/app/gate1_inspection_preview.tscn",
	"res://scenes/app/component_workshop_preview.tscn",
	"res://scenes/app/customer_inspection_preview.tscn",
	"res://scenes/app/customer_inspection_refusal_preview.tscn",
	"res://scenes/app/component_market_preview.tscn"
]
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for path: String in PATHS:
		var packed := load(path) as PackedScene
		check(packed != null, "load " + path)
		if packed == null:
			continue
		var scene: Node = packed.instantiate()
		var counter: bool = path.contains("gate1_")
		if counter:
			scene.set("inspection_preview", true)
			scene.set("isolated_day_one_preview", true)
		root.add_child(scene)
		await process_frame
		await process_frame
		var runtime: Variant = scene.get("_runtime" if counter else "_rt")
		var ready: bool = runtime != null and runtime.persistence_view().ready
		check(ready and scene.get_child_count() > 0, "initialized controls " + path)
		if ready:
			check(runtime.snapshot().revision == 0, "fresh isolated state " + path)
			check(runtime.localization.diagnostics.is_empty(), "initial labels resolve " + path)
		scene.free()
		await process_frame
	print("GATE1_SCENE_SMOKE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
