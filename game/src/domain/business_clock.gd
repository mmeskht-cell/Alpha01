extends RefCounted
## Absolute minutes counted from campaign Day 1, 08:00.
const Rules = preload("res://src/domain/value_rules.gd")
const DAY_MINUTES: int = 1440
const BUSINESS_MINUTES: int = 600
const START_HOUR: int = 8
const CAMPAIGN_END: int = 60480

static func day_index(minute: int) -> int:
	@warning_ignore("integer_division")
	return minute / DAY_MINUTES + 1

static func clock_text(minute: int) -> String:
	var local: int = posmod(minute + START_HOUR * 60, DAY_MINUTES)
	@warning_ignore("integer_division")
	var hour: int = local / 60
	return "%02d:%02d" % [hour, local % 60]

static func business_at(minute: int, phase: String, include_close: bool = true) -> bool:
	if not Rules.integer(minute, 0, CAMPAIGN_END - 1) or phase != "shop":
		return false
	var elapsed: int = minute % DAY_MINUTES
	return elapsed <= BUSINESS_MINUTES if include_close else elapsed < BUSINESS_MINUTES

static func inspection_at(minute: Variant, duration: Variant, new_evidence: Variant, phase: String = "shop") -> Dictionary:
	if not Rules.integer(minute, 0, CAMPAIGN_END - 1) or not Rules.integer(duration, 0, BUSINESS_MINUTES) or not new_evidence is bool or not business_at(int(minute), phase):
		return {"ok": false, "error": "inspection_shape"}
	if not new_evidence:
		return {"ok": true, "minutes": 0, "end_minute": int(minute)}
	var elapsed: int = int(minute) % DAY_MINUTES
	if elapsed == BUSINESS_MINUTES:
		return {"ok": false, "error": "business_closed"}
	if duration <= 0:
		return {"ok": false, "error": "inspection_duration"}
	if elapsed + int(duration) > BUSINESS_MINUTES:
		return {"ok": false, "error": "inspection_time_short"}
	return {"ok": true, "minutes": int(duration), "end_minute": int(minute) + int(duration)}
