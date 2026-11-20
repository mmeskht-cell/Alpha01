extends RefCounted
signal language_changed(locale: String)
const Rules = preload("res://src/domain/value_rules.gd")
const CONTENT_VERSION: String = "0.1.0"
const PACK_DIRECTORY: String = "user://localization"
const MAX_PACK_BYTES: int = 65536
var _official: Dictionary = {}
var _schema: Dictionary = {}
var _pack: Translation
var _locale: String = "ko"
var diagnostics: Array[String] = []

func initialize() -> bool:
	_schema = JSON.parse_string(FileAccess.get_file_as_string("res://locales/keys.json"))
	for locale: String in ["ko", "en"]:
		var translation := load("res://locales/%s/core.po" % locale) as Translation
		if translation == null or not _validate_official(translation, locale):
			return false
		_official[locale] = translation
	for translation: Translation in _official.values():
		TranslationServer.add_translation(translation)
	return select_language("ko")

func select_language(locale: String) -> bool:
	if not _official.has(locale) and (_pack == null or _pack.locale != locale):
		diagnostics.append("unsupported_locale:" + locale)
		return false
	_locale = locale
	TranslationServer.set_locale(locale)
	language_changed.emit(locale)
	return true

func current_locale() -> String:
	return _locale

func text(key: String, arguments: Dictionary = {}) -> String:
	if not _schema.has(key):
		diagnostics.append("missing_source_key:" + key)
		return key
	if arguments.size() != _schema[key].size():
		diagnostics.append("argument_mismatch:" + key)
		return key
	for name: String in _schema[key]:
		if not arguments.has(name) or not arguments[name] is String or not _plain(arguments[name], false):
			diagnostics.append("argument_mismatch:" + key)
			return key
	var rendered: String = ""
	if _pack != null and _pack.locale == _locale:
		rendered = str(_pack.get_message(key))
	elif _official.has(_locale):
		rendered = str(_official[_locale].get_message(key))
	if rendered.is_empty() or rendered == key:
		diagnostics.append("fallback_ko:" + key)
		rendered = str(_official.ko.get_message(key))
	return rendered.format(arguments)

func install_pack(filename: String) -> Dictionary:
	# Only a basename selected explicitly by the caller, never arbitrary paths/resources.
	if filename.get_file() != filename or not filename.ends_with(".json") or not Rules.identifier(filename.trim_suffix(".json")):
		return {"ok": false, "error": "pack_path"}
	var file := FileAccess.open(PACK_DIRECTORY.path_join(filename), FileAccess.READ)
	if file == null or file.get_length() > MAX_PACK_BYTES:
		return {"ok": false, "error": "pack_io"}
	var checked := validate_pack_text(file.get_as_text())
	if not checked.ok:
		return checked
	var candidate := Translation.new()
	candidate.locale = checked.pack.locale
	if candidate.locale != checked.pack.locale:
		return {"ok": false, "error": "pack_locale"}
	for key: String in checked.pack.strings:
		candidate.add_message(key, checked.pack.strings[key])
	# Mutate only after complete validation. Explicit install also selects this pack.
	if _pack != null:
		TranslationServer.remove_translation(_pack)
	_pack = candidate
	TranslationServer.add_translation(_pack)
	select_language(candidate.locale)
	return {"ok": true, "locale": _locale}

func clear_pack() -> void:
	if _pack != null:
		TranslationServer.remove_translation(_pack)
	_pack = null
	select_language("ko")

func shutdown() -> void:
	clear_pack()
	for translation: Translation in _official.values():
		TranslationServer.remove_translation(translation)

func validate_pack_text(raw: String) -> Dictionary:
	if raw.to_utf8_buffer().size() > MAX_PACK_BYTES:
		return {"ok": false, "error": "pack_size"}
	var json := JSON.new()
	if json.parse(raw) != OK:
		return {"ok": false, "error": "pack_json"}
	var pack: Variant = json.data
	if not Rules.keys(pack, ["format_version", "content_version", "locale", "author", "strings"]):
		return {"ok": false, "error": "pack_shape"}
	if not Rules.integer(pack.format_version, 1, 1) or pack.content_version != CONTENT_VERSION:
		return {"ok": false, "error": "pack_version"}
	var pattern := RegEx.new()
	pattern.compile("^[a-z]{2,3}(_[A-Z]{2})?$")
	if not pack.locale is String or pattern.search(pack.locale) == null:
		return {"ok": false, "error": "pack_locale"}
	if not pack.author is String or pack.author.is_empty() or pack.author.length() > 80 or not _plain(pack.author, false):
		return {"ok": false, "error": "pack_author"}
	if not pack.strings is Dictionary or pack.strings.is_empty() or pack.strings.size() > _schema.size():
		return {"ok": false, "error": "pack_strings"}
	for key: Variant in pack.strings:
		if not key is String or not _schema.has(key) or not _valid_message(key, pack.strings[key]):
			return {"ok": false, "error": "pack_message"}
	return {"ok": true, "pack": pack}

func _validate_official(translation: Translation, locale: String) -> bool:
	if translation.locale != locale:
		return false
	var messages: PackedStringArray = translation.get_message_list()
	if locale == "ko" and messages.size() != _schema.size():
		return false
	for key: String in messages:
		if not _schema.has(key) or not _valid_message(key, str(translation.get_message(key))):
			return false
	if locale == "ko":
		for key: String in _schema:
			if str(translation.get_message(key)).is_empty():
				return false
	return true

func _valid_message(key: String, value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 1024 or not _plain(value, true):
		return false
	var pattern := RegEx.new()
	pattern.compile("\\{([a-z_]+)\\}")
	var actual: Array[String] = []
	for found: RegExMatch in pattern.search_all(value):
		actual.append(found.get_string(1))
	var stripped: String = pattern.sub(value, "", true)
	if "{" in stripped or "}" in stripped:
		return false
	var expected: Array = _schema[key].duplicate()
	actual.sort()
	expected.sort()
	return actual == expected

func _plain(value: String, allow_placeholders: bool) -> bool:
	for character: String in value:
		var code: int = character.unicode_at(0)
		if (code < 32 and code != 10) or code == 127 or character in "[]<>":
			return false
		if code in [0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]:
			return false
		if not allow_placeholders and character in "{}":
			return false
	return true
