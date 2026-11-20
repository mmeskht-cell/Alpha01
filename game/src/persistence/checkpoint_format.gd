extends RefCounted
## Experimental v4 envelope, deliberately separate from live schema3.
## Checksum detects corruption, not adversarial edits. No authority of its own.
const Rules = preload("res://src/domain/value_rules.gd")
const Legacy = preload("res://src/domain/snapshot_format.gd")
const Lifecycle = preload("res://src/domain/campaign_lifecycle.gd")
const Selection = preload("res://src/domain/calendar_tracking.gd")
const VERSION: int = 4
const MAX_BYTES: int = Legacy.MAX_BYTES
const MAX_JOURNAL: int = 16
const MAX_COMMAND_BYTES: int = 4096
const CONTRACT: String = "checkpoint-pilot-1"

static func error(code: String) -> Dictionary:
	return {"ok": false, "error": code}

static func encode(slot: String, checkpoint: Dictionary, journal: Array, terminal: Dictionary) -> String:
	if not Rules.identifier(slot) or not Rules.integer(checkpoint.get("revision")) or not Rules.integer(terminal.get("revision")) or journal.size() > MAX_JOURNAL or int(checkpoint.revision) + journal.size() != int(terminal.revision):
		return ""
	var body: Dictionary = {"schema_version": VERSION, "content_version": Legacy.CONTENT_VERSION, "contract": CONTRACT, "slot_id": slot, "revision": terminal.revision, "checkpoint": checkpoint, "journal": journal, "terminal_hash": Rules.canonical(terminal).sha256_text()}
	var envelope: Dictionary = {"body": body, "checksum": Rules.canonical(body).sha256_text()}
	var encoded: String = Rules.canonical(envelope)
	return encoded if encoded.to_utf8_buffer().size() <= MAX_BYTES else ""

## factory MUST create a fresh initialized GameSession, never the live session.
## The same authoritative command rules validate the checkpoint and bounded tail.
static func decode(encoded: String, slot: String, factory: Callable) -> Dictionary:
	if not Rules.identifier(slot) or encoded.to_utf8_buffer().size() > MAX_BYTES:
		return error("save_size_or_slot")
	var parser := JSON.new()
	if parser.parse(encoded) != OK or not Rules.keys(parser.data, ["body", "checksum"]):
		return error("save_shape")
	var env: Dictionary = Rules.normalized(parser.data)
	var b: Variant = env.body
	if not b is Dictionary or not Rules.integer(b.get("schema_version"), 1):
		return error("save_shape")
	if b.schema_version > VERSION:
		return error("future_schema")
	if b.schema_version != VERSION:
		return error("unsupported_schema")
	if b.get("content_version") != Legacy.CONTENT_VERSION or b.get("contract") != CONTRACT:
		return error("content_version")
	if not Rules.keys(b, ["schema_version", "content_version", "contract", "slot_id", "revision", "checkpoint", "journal", "terminal_hash"]) or b.slot_id != slot or not env.checksum is String or env.checksum != Rules.canonical(b).sha256_text():
		return error("checksum_or_shape")
	if not b.checkpoint is Dictionary or not b.journal is Array or b.journal.size() > MAX_JOURNAL or not Rules.integer(b.revision) or not Rules.integer(b.checkpoint.get("revision")) or b.revision != int(b.checkpoint.revision) + b.journal.size() or not b.terminal_hash is String:
		return error("journal_shape")
	var session: RefCounted = factory.call()
	if session == null or not session.restore(b.checkpoint):
		return error("checkpoint_invalid")
	var revision: int = b.checkpoint.revision
	for command: Variant in b.journal:
		if not Rules.keys(command, ["action_id", "expected_revision", "type", "payload"]) or not Rules.identifier(command.action_id) or not Rules.integer(command.expected_revision) or command.expected_revision != revision or Rules.canonical(command).to_utf8_buffer().size() > MAX_COMMAND_BYTES:
			return error("journal_command")
		var result: Dictionary = session.execute_world(command) if command.type in Lifecycle.ACTIONS or command.type in Selection.ACTIONS else session.execute(command)
		revision += 1
		if not result.get("ok", false) or result.get("revision") != revision or session.snapshot().revision != revision:
			return error("journal_replay")
	var final: Dictionary = session.snapshot()
	if final.revision != b.revision or Rules.canonical(final).sha256_text() != b.terminal_hash:
		return error("terminal_mismatch")
	return {"ok": true, "state": final, "checkpoint_revision": b.checkpoint.revision, "journal_count": b.journal.size()}

