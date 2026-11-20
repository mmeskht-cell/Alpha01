extends RefCounted
const Rules = preload("res://src/domain/value_rules.gd")
const SCHEMA_VERSION: int = 3
const CONTENT_VERSION: String = "0.1.0"
const MAX_BYTES: int = 1048576

static func encode(state: Dictionary, slot: String) -> String:
	var payload: String = Rules.canonical(state)
	return JSON.stringify({"schema_version": SCHEMA_VERSION, "content_version": CONTENT_VERSION, "slot_id": slot, "revision": state.revision, "payload": payload, "checksum": payload.sha256_text()})

static func encoded_size(state: Dictionary) -> int:
	# Worst permitted slot name, measured after JSON escaping and UTF-8 encoding.
	return encode(state, "s".repeat(64)).to_utf8_buffer().size()

static func capacity(state: Dictionary) -> Dictionary:
	var used: int = encoded_size(state)
	return {"bytes": used, "limit_bytes": MAX_BYTES, "remaining_bytes": maxi(0, MAX_BYTES - used), "warning": used >= int(MAX_BYTES * 0.8), "fits": used <= MAX_BYTES}

static func fits(state: Dictionary) -> bool:
	return encoded_size(state) <= MAX_BYTES
