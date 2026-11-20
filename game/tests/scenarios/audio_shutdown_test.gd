extends SceneTree
const FeedbackScript = preload("res://src/presentation/commit_feedback.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func count_playing(node: Node) -> int:
	var count: int = 0
	for child: Node in node.get_children():
		if child is AudioStreamPlayer and child.playing:
			count += 1
	return count

func run() -> void:
	var feedback := FeedbackScript.new()
	feedback.enable_headless_audio_for_test = true
	root.add_child(feedback)
	await process_frame
	await create_timer(0.15,true,false,true).timeout
	check(feedback.diagnostic_view().music_starts == 1 and count_playing(feedback) == 3,"actual two ambient and one music playbacks")
	feedback.prime(0)
	check(feedback.committed("next_visit",0,1,true),"cue emitted")
	feedback.local_page()
	check(count_playing(feedback) >= 4,"active one-shot playback")
	feedback.set_phase("workshop")
	feedback.shutdown_audio()
	feedback.shutdown_audio()
	check(count_playing(feedback)==0,"all players stopped, idempotent")
	for child: Node in feedback.get_children():
		if child is AudioStreamPlayer:
			check(child.stream == null,"stream reference detached")
	check(not feedback.committed("next_visit",1,2,true),"closed cue guard")
	feedback.local_page()
	check(count_playing(feedback)==0,"no restart after stop")
	await create_timer(0.25,true,false,true).timeout
	feedback.queue_free()
	await process_frame
	await create_timer(0.10,true,false,true).timeout
	print("ZT_ACTIVE_AUDIO_SHUTDOWN: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
