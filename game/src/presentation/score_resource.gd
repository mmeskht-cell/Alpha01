extends RefCounted
## Approved provisional stereo master: preserve the original mix and full musical arc.
const PATH: String = "res://assets/audio/Before_the_Shutters_Cadence_v36.ogg"
const DURATION: float = 136.25

static func build() -> AudioStreamOggVorbis:
	if not ResourceLoader.exists(PATH, "AudioStreamOggVorbis"):
		return null
	var source := ResourceLoader.load(PATH, "AudioStreamOggVorbis", ResourceLoader.CACHE_MODE_IGNORE) as AudioStreamOggVorbis
	if source == null or absf(source.get_length() - DURATION) > 0.02:
		return null
	source.loop = true
	source.loop_offset = 0.0
	return source
