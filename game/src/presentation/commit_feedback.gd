extends Control
## Presentation-only one-shot cues. Never reads truth, mutates the session, or advances game time.
## Original prototype mix, bounded voices and independent ambient/SFX/UI/music buses. No combat sound.
const Music = preload("res://src/presentation/score_resource.gd")
const RATE: int = 24000
const CUES: Dictionary = {"door": [0.19, 410.0, 0.36], "paper": [0.12, 180.0, 0.78], "observation": [0.11, 730.0, 0.42], "placement": [0.10, 110.0, 0.68], "settlement": [0.18, 520.0, 0.52], "service": [0.20, 270.0, 0.62], "closing": [0.23, 145.0, 0.48], "departure": [0.16, 310.0, 0.55], "component": [0.12, 210.0, 0.64], "cancel": [0.13, 130.0, 0.72], "news": [0.24, 630.0, 0.26], "page": [0.10, 220.0, 0.91], "select": [0.07, 300.0, 0.55]}
const ACTIONS: Dictionary = {"subject_deck_action":"paper","subject_price_offer":"paper","clean_exterior":"service","replace_component":"component","next_visit": "door", "day_one_next": "door", "accept_rad1_contract": "paper", "day_one_accept_service": "paper", "inspect_radio": "observation", "move": "placement", "confirm_purchase": "settlement", "trade": "settlement", "day_one_deliver_service": "settlement", "restore_item": "service", "day_one_close": "closing", "day_one_next_morning": "door", "decline_visit": "departure", "day_one_decline": "departure", "day_one_composite_decline": "departure", "day_one_cancel_service": "cancel", "day_one_pay_overhead": "settlement", "observe": "observation", "attach": "component", "detach": "component", "day_one_composite_offer": "door", "day_one_composite_request": "paper", "day_one_composite_close": "paper"}
var sound_enabled: bool = true
var motion_enabled: bool = true
const CHANNELS: Array[String] = ["music", "ambience", "sfx", "ui"]
const BUS_NAMES: Dictionary = {"music": "ZT Music", "ambience": "ZT Ambience", "sfx": "ZT SFX", "ui": "ZT UI"}
const MOTION_TIME: Dictionary = {"door": 0.40, "departure": 0.35, "paper": 0.20, "observation": 0.22, "placement": 0.18, "settlement": 0.34, "service": 0.45, "closing": 0.70, "component": 0.18, "cancel": 0.18}
var _levels: Dictionary = {"music": 60, "ambience": 60, "sfx": 80, "ui": 50}
var _ambient: Array[AudioStreamPlayer] = []
var _ui_player: AudioStreamPlayer
var _phase: String = "shop"
var _ambient_fade: Tween
var _music: AudioStreamPlayer
var _score: AudioStreamOggVorbis
var _music_starts: int = 0
var _music_fade: Tween
var _revision: int = -1
var _presented: int = 0
var _played: int = 0
var _motions: int = 0
var _last_cue: String = ""
var _streams: Dictionary = {}
var _player: AudioStreamPlayer
var _line: ColorRect
var _fade: Tween
var _audio_stopped: bool = false
# Explicit opt-in for the dedicated active-playback lifecycle test only.
var enable_headless_audio_for_test: bool = false
var _playback_enabled: bool = false

## Apply validated presentation settings before audio players start.
func configure_preferences(preferences: Dictionary) -> void:
	sound_enabled = preferences.sound
	motion_enabled = preferences.motion
	_levels = preferences.levels.duplicate()

func _ready() -> void:
	_playback_enabled = DisplayServer.get_name() != "headless" or enable_headless_audio_for_test
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 80
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_setup_buses()
	_player = AudioStreamPlayer.new()
	_player.bus = BUS_NAMES.sfx
	_player.volume_db = -12.0
	add_child(_player)
	for key: String in CUES:
		_streams[key] = _synthesize(CUES[key], key.hash())
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = BUS_NAMES.ui
	_ui_player.volume_db = -18.0
	add_child(_ui_player)
	for index: int in range(2):
		var layer := AudioStreamPlayer.new()
		layer.bus = BUS_NAMES.ambience
		layer.stream = _ambient_loop(index)
		layer.volume_db = -15.0 if index == 0 else -23.0
		add_child(layer)
		_ambient.append(layer)
		if _playback_enabled:
			layer.play()
	_score = Music.build() if ResourceLoader.exists(Music.PATH) else null
	if _score != null:
		_music = AudioStreamPlayer.new()
		_music.bus = BUS_NAMES.music
		_music.volume_db = -10.0
		_music.stream = _score
		add_child(_music)
		if _playback_enabled:
			_music.play(float(get_tree().get_meta("spatial_score_position",0.0)))
			if get_tree().has_meta("spatial_score_position"):
				get_tree().remove_meta("spatial_score_position")
			_music_starts += 1
	_line = ColorRect.new()
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_line)
	_line.anchor_right = 1.0
	_line.offset_bottom = 3.0
	_line.color = Color(0.74, 0.68, 0.46, 0.0)

## Stop streaming playback before the parent is freed. Do not leave an Ogg
## decoder, its packet sequence, or tweens attached during shutdown/reload.
func _exit_tree() -> void:
	shutdown_audio()

## Call while the tree/audio driver is still running, before requesting quit.
## Safe on repeated calls and on fall-back scene destruction.
func shutdown_audio() -> void:
	if _audio_stopped:
		return
	_audio_stopped = true
	for tween: Tween in [_music_fade, _ambient_fade, _fade]:
		if tween != null and tween.is_valid():
			tween.kill()
	for node: Node in get_children():
		if node is AudioStreamPlayer:
			var player := node as AudioStreamPlayer
			player.stop()
			player.stream = null
	_score = null
	_streams.clear()
	_ambient.clear()
	_music_fade = null
	_ambient_fade = null
	_fade = null

func _setup_buses() -> void:
	for channel: String in CHANNELS:
		var name: String = BUS_NAMES[channel]
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
		set_level(channel, int(_levels[channel]))

func set_level(channel: String, percent: int) -> void:
	if channel not in CHANNELS or percent < 0 or percent > 100:
		return
	_levels[channel] = percent
	var index: int = AudioServer.get_bus_index(BUS_NAMES[channel])
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, float(percent) / 100.0)))
		AudioServer.set_bus_mute(index, not sound_enabled or percent == 0)

func level(channel: String) -> int:
	return int(_levels.get(channel, 0))

## Periodic, quiet stereo room and exterior-wind textures. Integer cycles
## keep the sample seam continuous; not recorded city/war sound or finished OST.
func _ambient_loop(layer: int) -> AudioStreamWAV:
	var n: int = RATE * 8
	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	for i: int in range(n):
		var angle: float = TAU * float(i) / float(n)
		for side: int in range(2):
			var phase: float = 0.43 * side
			var sample: float
			if layer == 0:
				sample = (sin(angle * 400.0 + phase) * 0.045 + sin(angle * 800.0 + phase) * 0.016 + sin(angle * 17.0) * 0.009) * (0.80 + 0.20 * sin(angle * 2.0))
			else:
				sample = (sin(angle * 53.0 + phase) * 0.030 + sin(angle * 137.0 - phase) * 0.021 + sin(angle * 277.0) * 0.012) * (0.65 + sin(angle * 3.0 + phase) * 0.30)
			bytes.encode_s16((i * 2 + side) * 2, roundi(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = true
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = n
	return stream

func set_phase(phase: String) -> void:
	if _audio_stopped or phase == _phase or phase not in ["shop", "workshop"]:
		return
	_phase = phase
	if _ambient.size() != 2:
		return
	if _ambient_fade != null and _ambient_fade.is_valid():
		_ambient_fade.kill()
	_ambient_fade = create_tween().set_parallel(true)
	_ambient_fade.tween_property(_ambient[0], "volume_db", -20.0 if phase == "workshop" else -15.0, 0.65)
	_ambient_fade.tween_property(_ambient[1], "volume_db", -18.0 if phase == "workshop" else -23.0, 0.65)
	if _music != null:
		if _music_fade != null and _music_fade.is_valid():
			_music_fade.kill()
		_music_fade = create_tween()
		_music_fade.tween_property(_music, "volume_db", -17.0 if phase == "workshop" else -10.0, 1.2)

func _notification(what: int) -> void:
	if _audio_stopped or what not in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED]:
		return
	var paused: bool = what == NOTIFICATION_APPLICATION_PAUSED
	for layer: AudioStreamPlayer in _ambient:
		layer.stream_paused = paused
	if is_instance_valid(_music):
		_music.stream_paused = paused

func local_page() -> void:
	if not _audio_stopped and _playback_enabled and sound_enabled and _ui_player != null:
		_ui_player.stop()
		_ui_player.stream = _streams.page
		_ui_player.play()

## Deterministic local RNG only, independent of campaign RNG. Short attack and full fade.
func _synthesize(recipe: Array, seed_value: int) -> AudioStreamWAV:
	var n: int = roundi(float(recipe[0]) * RATE)
	var hz: float = float(recipe[1])
	var noise_mix: float = float(recipe[2])
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(seed_value)
	var data := PackedByteArray()
	data.resize(n * 2)
	var filtered: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / RATE
		var progress: float = float(i) / maxf(1.0, float(n - 1))
		var envelope: float = minf(1.0, t / 0.008) * pow(1.0 - progress, 2.3)
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.32)
		var tone: float = sin(TAU * hz * t) * 0.72 + sin(TAU * hz * 1.53 * t) * 0.28
		var sample: float = envelope * lerpf(tone, filtered, noise_mix) * 0.38
		data.encode_s16(i * 2, roundi(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream

## Prime after loading. A viewed/replayed/failed action never emits an old result.
func prime(revision: int) -> void:
	_revision = revision

func committed(kind: String, before: int, after: int, persisted: bool) -> bool:
	if _audio_stopped or before != _revision or after != before + 1:
		return false
	_revision = after
	if not persisted or not ACTIONS.has(kind):
		return false
	_last_cue = ACTIONS[kind]
	_presented += 1
	if _playback_enabled and sound_enabled:
		_player.stop()
		_player.stream = _streams[_last_cue]
		_player.play()
		_played += 1
	if motion_enabled:
		if _fade != null and _fade.is_valid():
			_fade.kill()
		_line.color = Color(0.74, 0.68, 0.46, 0.9)
		_fade = create_tween()
		_fade.tween_property(_line, "color:a", 0.0, float(MOTION_TIME.get(_last_cue, 0.28)))
		_motions += 1
	return true

func set_sound(enabled: bool) -> void:
	if _audio_stopped:
		return
	sound_enabled = enabled
	for channel: String in CHANNELS:
		set_level(channel, level(channel))
	if not enabled:
		_player.stop()
		_ui_player.stop()

func set_motion(enabled: bool) -> void:
	if _audio_stopped:
		return
	motion_enabled = enabled
	if not enabled:
		if _fade != null and _fade.is_valid():
			_fade.kill()
		_line.color.a = 0.0

func diagnostic_view() -> Dictionary:
	return {"revision": _revision, "presented": _presented, "played": _played, "motions": _motions, "last_cue": _last_cue, "sound": sound_enabled, "motion": motion_enabled, "cue_count": _streams.size(), "levels": _levels.duplicate(), "ambience_layers": _ambient.size(), "phase": _phase, "music_tracks": 1 if _score != null else 0, "music_starts": _music_starts}


func remember_score_position() -> void:
	if is_instance_valid(_music) and _music.playing:
		get_tree().set_meta("spatial_score_position",_music.get_playback_position())
