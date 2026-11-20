extends SceneTree
const Localization = preload("res://src/presentation/localization_service.gd")
const Catalog = preload("res://src/content/catalog_loader.gd")
const Session = preload("res://src/domain/game_session.gd")
const Fixture = preload("res://tests/fixtures/foundation_state.gd")
var failures: int = 0
var checks: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	var localization := Localization.new()
	check(localization.initialize(), "official PO initialization")
	var session := Session.new()
	session.initialize(Catalog.load_file("res://data/catalog/foundation.json").definitions, Fixture.make())
	var before := session.snapshot()
	check(localization.text("app.ready") == "준비 완료", "Korean default")
	check(localization.text("book.tab.reference")=="도감" and localization.text("catalog.radio.wear.light.description")!="catalog.radio.wear.light.description","book keys registered in Korean")
	check(localization.select_language("en") and localization.text("app.ready") == "Ready", "English switch")
	check(localization.text("book.tab.reference")=="Reference" and localization.text("review.basic.working.description")!="review.basic.working.description","book keys registered in English")
	check(localization.text("wallet.balance", {"amount": "180", "currency": "VKC"}) == "Balance: 180 VKC", "named placeholders")
	check(localization.text("inventory.format.money_pair",{"vkc":"75","usd":"—"})=="75 VKC / — USD","inventory money pair preserves unknown vs zero")
	check(localization.text("inventory.format.restore_both",{"vkc":"5","usd":"2"})=="Restore · 5 VKC/2 USD","complete two-currency work caption")
	check(localization.text("ui.format.native_hud",{"day":"1","time":"08:00","vkc":"180","usd":"0"})=="Day 1  08:00  ·  180 VKC  /  0 USD","native HUD exact English cash/day/time")
	check(localization.text("wallet.balance", {"amount": "180"}) == "wallet.balance", "wrong arguments refused")
	check(not localization.select_language("../../bad") and localization.current_locale() == "en", "unsupported locale preserves selection")
	var pack := {"format_version": 1, "content_version": "0.1.0", "locale": "en", "author": "Test", "strings": {"app.ready": "R e a d y — expanded pseudo-localization", "inventory.format.stock_counts":"{custody} custody / {owned} owned", "ui.format.receipt_headline":"{price} | {time} | {day} | {direction}"}}
	check(localization.validate_pack_text(JSON.stringify(pack)).ok, "partial known-key pack accepted")
	var path: String = "gate0b_test_" + str(Time.get_ticks_usec()) + ".json"
	DirAccess.make_dir_recursive_absolute("user://localization")
	var file := FileAccess.open("user://localization/" + path, FileAccess.WRITE)
	file.store_string(JSON.stringify(pack))
	file.close()
	check(localization.install_pack(path).ok and localization.text("app.ready") == pack.strings["app.ready"], "explicit pack install and selection")
	check(localization.text("error.save") == "저장하지 못했습니다.", "missing pack key falls back to Korean")
	check(localization.text("inventory.format.stock_counts",{"owned":"3","custody":"1"})=="1 custody / 3 owned","community pack reorders named inventory arguments")
	check(localization.text("ui.format.receipt_headline",{"direction":"Purchase","day":"1","time":"08:00","price":"100 VKC / 0 USD"})=="100 VKC / 0 USD | 08:00 | 1 | Purchase","community pack reorders public receipt fields")
	check(localization.text("inventory.format.restore_vkc",{"vkc":"5"})=="정비 · 5 VKC","missing new sentence in older partial pack falls back with arguments")
	check(localization.diagnostics.has("fallback_ko:error.save"), "fallback logged")
	check(session.snapshot() == before, "language and pack do not mutate game domain")
	check(not localization.install_pack("../" + path).ok, "pack traversal rejected")
	var invalid := pack.duplicate(true)
	invalid.strings["logic.money"] = "99999"
	check(not localization.validate_pack_text(JSON.stringify(invalid)).ok, "unknown keys refused")
	invalid = pack.duplicate(true)
	invalid.strings["app.ready"] = "[img]res://exploit[/img]"
	check(not localization.validate_pack_text(JSON.stringify(invalid)).ok, "markup refused")
	invalid.strings = {"wallet.balance": "{amount} {unknown}"}
	check(not localization.validate_pack_text(JSON.stringify(invalid)).ok, "unknown placeholders refused")
	invalid.strings = {"wallet.balance": "{amount} {amount} {currency}"}
	check(not localization.validate_pack_text(JSON.stringify(invalid)).ok, "duplicate placeholders refused")
	invalid.strings = {"app.ready": 4}
	check(not localization.validate_pack_text(JSON.stringify(invalid)).ok, "non-string refused")
	invalid = pack.duplicate(true)
	invalid.format_version = 2
	check(not localization.validate_pack_text(JSON.stringify(invalid)).ok, "future pack rejected")
	check(not localization.validate_pack_text("x".repeat(65537)).ok, "oversized pack rejected")
	check(not localization.validate_pack_text("{").ok, "broken JSON rejected")
	file = FileAccess.open("user://localization/" + path, FileAccess.WRITE)
	file.store_string("{")
	file.close()
	check(not localization.install_pack(path).ok and localization.text("app.ready") == pack.strings["app.ready"], "failed install preserves active translation")
	check(localization.text("not.a.key") == "not.a.key" and localization.diagnostics.has("missing_source_key:not.a.key"), "missing source key logged")
	localization.clear_pack()
	check(localization.current_locale() == "ko" and localization.text("app.ready") == "준비 완료", "restore official default")
	check(localization.select_language("en") and localization.text("app.ready") == "Ready", "official English restored")
	check(session.snapshot() == before, "domain unchanged after all switches")
	DirAccess.remove_absolute("user://localization/" + path)
	localization.shutdown()
	print("LOCALIZATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
