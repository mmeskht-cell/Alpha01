extends SceneTree
## Windowed UI integration probe: sends Control pointer events, reads public UI/runtime state,
## captures the actual viewport. No direct game-state mutations. Isolated XDG directory in CI.
const Counter = preload("res://scenes/app/gate1_day_one.tscn")
const PagedRows = preload("res://src/presentation/paged_rows.gd")
const Inventory = preload("res://src/presentation/day_one_inventory.gd")
const Surface = preload("res://src/presentation/day_one_service_mat.gd")
const Preferences = preload("res://src/presentation/ui_preferences.gd")
var scene: Control
var preview_id: String
var out: String
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func frames() -> void:
	await process_frame
	await process_frame
	await process_frame

func read_view() -> Dictionary:
	return scene.get("_runtime").counter_view()

func tr_key(key: String, values: Dictionary = {}) -> String:
	return scene.get("_runtime").localization.text(key, values)

func nodes(parent: Node, script: Script = null) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in parent.get_children():
		if script == null or child.get_script() == script:
			found.append(child)
		found.append_array(nodes(child, script))
	return found

func button(key: String, values: Dictionary = {}) -> Button:
	var label: String = tr_key(key, values)
	var modal: Variant = scene.get("_modal")
	var parent: Node = modal if is_instance_valid(modal) else scene
	for node: Node in nodes(parent):
		if node is Button and node.text == label and node.is_visible_in_tree() and not node.disabled:
			return node
	return null

func reveal(control: Control) -> void:
	var parent: Node = control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(control)
		parent = parent.get_parent()
	await frames()

func pointer_at(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.position = point
	event.global_position = point
	root.push_input(event, true)

func move_pointer(point: Vector2, previous: Vector2, held: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - previous
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)

func click_point(control: Control, local: Vector2) -> void:
	var point: Vector2 = control.get_global_transform_with_canvas() * local
	pointer_at(point, true)
	pointer_at(point, false)
	await frames()

func click_key(key: String, values: Dictionary = {}) -> bool:
	var control: Button = button(key, values)
	if control == null:
		printerr("UI_BUTTON_NOT_FOUND ", key)
		return false
	await reveal(control)
	await click_point(control, control.size * 0.5)
	return true

func capture(name: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	var ok: bool = pixels != null and not pixels.is_empty()
	if ok:
		ok = pixels.save_png(out.path_join(name + ".png")) == OK
	check(ok, "capture " + name)
	if ok:
		print("ZT_CAPTURE ", name, " ", pixels.get_size())

func require(ok: bool, label: String) -> bool:
	check(ok, label)
	if not ok:
		print("GATE1_4_WINDOW: %d checks, %d failures" % [checks, failures])
		quit(1)
	return ok

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	scene = Counter.instantiate()
	scene.set("isolated_day_one_preview", true)
	preview_id = "window_" + str(Time.get_ticks_usec())
	scene.set("isolated_preview_id", preview_id)
	root.add_child(scene)
	await frames()
	if not require(scene.get("_runtime") != null and scene.get("_runtime").persistence_view().ready, "fresh window runtime"):
		return
	check(scene.get_theme_default_font().has_char(0xD55C) and scene.get_theme_default_font().has_char(0xAE00), "Korean glyph coverage")
	check(scene.get("_commit_feedback").diagnostic_view().cue_count == 13 and scene.get("_commit_feedback").diagnostic_view().presented == 0 and scene.get("_commit_feedback").diagnostic_view().ambience_layers == 2, "thirteen available cues and two ambient loops, no replayed result")
	await capture("01-opening-ko")
	if not require(await click_key("ui.contract_document"), "open contract via pointer"):
		return
	await capture("02-contract")
	var scale_before: Dictionary = read_view().duplicate(true)
	if not require(await click_key("ui.document_scale", {"percent": "100"}) and scene.get("_document_font_size") == 20, "document native font 125 percent"):
		return
	await capture("14-contract-ko-125")
	if not require(await click_key("ui.document_scale", {"percent": "125"}) and scene.get("_document_font_size") == 24, "document native font 150 percent"):
		return
	root.size = Vector2i(1024, 768)
	await frames()
	await capture("15-contract-ko-150-4x3")
	check(read_view() == scale_before and button("ui.contract_accept") != null and button("ui.close_document") != null, "scale and resize preserve contract and controls")
	root.size = Vector2i(1536, 720)
	await frames()
	await capture("16-contract-ko-150-wide")
	if not require(await click_key("ui.document_scale", {"percent": "150"}) and scene.get("_document_font_size") == 16, "return to 100 percent"):
		return
	root.size = Vector2i(1280, 720)
	await frames()
	if not require(await click_key("ui.contract_accept") and read_view().contract.status == "reserved", "reserve from UI"):
		return
	if not require(await click_key("ui.close_document"), "close contract"):
		return
	if not require(await click_key("ui.door") and read_view().customer != null, "admit first customer"):
		return
	check(read_view().item_history.records.is_empty(), "no invented pre-shop provenance")
	await capture("03-appraisal-ko")
	var guide_before: Dictionary = read_view().duplicate(true)
	if not require(await click_key("ui.tool_guide"), "open native inspection guide"):
		return
	await capture("17-tool-guide-ko")
	if not require(await click_key("ui.close_document") and read_view() == guide_before, "guide is read only"):
		return
	var bench: Control = scene.get("_workbench")
	if not require(is_instance_valid(bench), "appraisal bench active"):
		return
	var base_view: Dictionary = read_view().duplicate(true)
	var original_rect: Rect2 = bench._radio()
	var original_region: Rect2 = bench._feature(original_rect, bench._region_rect("display", 0))
	if not require(bench.view_state().art_key == "radio_face_probe_a" and bench.select_art("radio_face_probe_b"), "replace actual texture resource"):
		return
	check(bench._radio() == original_rect and bench._feature(bench._radio(), bench._region_rect("display", 0)) == original_region, "art swap preserves normalized interaction geometry")
	check(read_view() == base_view and not bench.select_art("unknown") and bench.view_state().art_key == "radio_face_probe_b", "art swap and invalid key leave authority unchanged")
	await capture("11-radio-alternate")
	await click_point(bench, bench._origin() + Vector2(100, 121) * bench._scale())
	await click_point(bench, bench._origin() + bench._feature(bench._radio(), bench._region_rect("scratch", 0)).get_center() * bench._scale())
	if not require(read_view().minute == 5, "pointer wear inspection consumes five minutes"):
		await capture("failure-wear")
		return
	var feedback: Control = scene.get("_commit_feedback")
	check(feedback.diagnostic_view().music_tracks == 1 and feedback.diagnostic_view().music_starts == 1, "single original master, single start")
	var score: AudioStreamOggVorbis = feedback.get("_score")
	if not require(score != null, "Cadence v3.6 master loaded"):
		return
	check(score.loop and is_zero_approx(score.loop_offset), "complete score loops including cadence and silence")
	check(absf(score.get_length() - 136.25) < 0.02, "approved master duration")
	check(score.resource_path.is_empty() or score.resource_path.ends_with("Before_the_Shutters_Cadence_v36.ogg"), "approved score resource")
	var observed: Dictionary = feedback.diagnostic_view()
	check(observed.last_cue == "observation" and observed.played > 0 and observed.motions > 0, "fresh observation triggers audiovisual cue")
	check(not feedback.committed("inspect_radio", read_view().revision - 1, read_view().revision, true) and feedback.diagnostic_view() == observed, "duplicate committed revision silent")
	bench = scene.get("_workbench")
	check(bench.view_state().art_key == "radio_face_probe_b", "texture selection survives UI rebuild")
	if not require(bench.select_art("radio_face_probe_a"), "restore base texture"):
		return
	await click_point(bench, bench._origin() + Vector2(100, 195) * bench._scale())
	await click_point(bench, bench._origin() + bench._feature(bench._radio(), bench._region_rect("casing", 0)).get_center() * bench._scale())
	if not require(read_view().minute == 15, "pointer casing inspection consumes ten minutes"):
		return
	var revision: int = read_view().revision
	if not require(await click_key("ui.language") and read_view().revision == revision, "free language change"):
		return
	await capture("04-appraisal-en")
	var resize_before: Dictionary = read_view().duplicate(true)
	root.size = Vector2i(1024, 768)
	await frames()
	await capture("05-appraisal-4x3")
	var rendered: Vector2i = root.get_texture().get_size()
	check(absf(float(rendered.x) / float(rendered.y) - 4.0 / 3.0) < 0.02, "actual 4:3 render without letterbox")
	check(read_view() == resize_before, "resize preserves domain view")
	root.size = Vector2i(1280, 720)
	await frames()
	# Actual windowed input: two free gaze toggles, build a wear card, drag to customer.
	var gaze_before: Dictionary = read_view().duplicate(true)
	if not require(await click_key("appraisal.look_down"),"touch-equivalent gaze control"):
		return
	await create_timer(0.45).timeout
	await frames()
	if not require(scene.get("_gaze_down") and read_view() == gaze_before,"look down changes presentation only"):
		return
	var appearance_card: Button
	for n: Node in nodes(scene):
		if n is Button and n.get_script() == preload("res://src/presentation/appraisal_attribute_card.gd") and n.attribute_id == "appearance_id" and n.attribute_value == "visible_wear":
			appearance_card = n
	if not require(is_instance_valid(appearance_card),"appearance candidate"):
		return
	await reveal(appearance_card)
	await click_point(appearance_card,appearance_card.size*0.5)
	if not require(read_view().appraisal.hypothesis.appearance_id == "visible_wear","actual card click"):
		return
	# Link actual observation via the existing slip controls; exact localized label.
	if not require(await click_key("ui.appraisal_document"),"open appraisal slip"):
		return
	var fact_label: String = ""
	for fact: Dictionary in read_view().appraisal.evidence:
		if fact.evidence_id == "R001.wear":
			fact_label = "+ " + tr_key(fact.text_key)
	var link: Button
	for n: Node in nodes(scene.get("_modal")):
		if n is Button and n.text == fact_label:
			link = n
	if not require(is_instance_valid(link),"known wear link button"):
		return
	await reveal(link)
	await click_point(link,link.size*0.5)
	if not require(read_view().appraisal.card_links.get("appearance_id",[]) == ["R001.wear"],"actual evidence link"):
		return
	if not require(await click_key("ui.close_document"),"return to desk"):
		return
	var candidate_label: String = ""
	for candidate: Dictionary in read_view().appraisal.argument_candidates:
		if candidate.argument.slot == "appearance_id":
			candidate_label = tr_key(candidate.label_key)
	if not require(await click_key("appraisal.argument_prepare",{"value":candidate_label,"count":"1"}) and read_view().negotiation_deck.ready.size() == 1,"create deck card at desk"):
		return
	var prepared_view: Dictionary = read_view().duplicate(true)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	root.push_input(space,true)
	space.pressed = false
	root.push_input(space,true)
	await create_timer(0.45).timeout
	await frames()
	if not require(not scene.get("_gaze_down") and read_view() == prepared_view,"space looks up without authority change"):
		return
	var deck_card: Button
	for n: Node in nodes(scene):
		if n is Button and n.get_script() == preload("res://src/presentation/negotiation_deck_card.gd"):
			deck_card = n
	var deck_target: Control = scene.find_child("NegotiationDropTarget",true,false)
	if not require(is_instance_valid(deck_card) and is_instance_valid(deck_target),"deck source and customer target"):
		return
	await reveal(deck_card)
	var source_point: Vector2 = deck_card.get_global_rect().get_center()
	var target_point: Vector2 = deck_target.get_global_rect().get_center()
	pointer_at(source_point,true)
	move_pointer(source_point + Vector2(25,-25),source_point,true)
	await frames()
	move_pointer(target_point,source_point + Vector2(25,-25),true)
	await frames()
	pointer_at(target_point,false)
	await frames()
	if not require(read_view().negotiation_deck.ready.is_empty() and read_view().negotiation_deck.presented.size() == 1 and read_view().minute == 15 and read_view().negotiation.remaining_offers == 3,"pointer drag presents one argument without price offer"):
		return
	await capture("27-deck-presented")
	if not require(await click_key("ui.offer"), "open negotiation"):
		return
	var modal: Node = scene.get("_modal")
	var amount: SpinBox
	var evidence: OptionButton
	for n: Node in nodes(modal):
		if n is SpinBox:
			amount = n
		elif n is OptionButton:
			evidence = n
	if not require(amount != null and evidence != null and evidence.item_count >= 2, "offer amount and evidence controls"):
		return
	# Set widget values through its public UI properties, then activate the visible submit control via pointer.
	check(amount.max_value == float(read_view().wallet.VKC), "offer editor bounded by available cash")
	amount.value = 100
	evidence.select(1)
	var draft_before: Dictionary = read_view().duplicate(true)
	if not require(await click_key("ui.document_scale", {"percent": "100"}), "rebuild negotiation at larger font"):
		return
	amount = null
	evidence = null
	for n: Node in nodes(scene.get("_modal")):
		if n is SpinBox:
			amount = n
		elif n is OptionButton:
			evidence = n
	if not require(amount != null and evidence != null and amount.value == 100 and evidence.selected == 1 and read_view() == draft_before, "uncommitted draft survives refresh without transaction"):
		return
	if not require(await click_key("ui.document_scale", {"percent": "125"}) and await click_key("ui.document_scale", {"percent": "150"}), "restore original document scale"):
		return
	await capture("19-offer-draft")
	if not require(await click_key("ui.close_document"),"return to inline customer offer"):
		return
	var inline_amount: SpinBox = scene.get("_offer_amount")
	if not require(is_instance_valid(inline_amount) and inline_amount.value == 100,"price draft survives return to customer"):
		return
	# Toggle again after actual presentation; no history, cash, clock or accepted offer change.
	var before_return: Dictionary = read_view().duplicate(true)
	if not require(await click_key("appraisal.look_down"),"reinspect after customer response"):
		return
	await create_timer(0.45).timeout
	await frames()
	if not require(scene.get("_gaze_down") and read_view() == before_return,"return to appraisal preserves spoken cards"):
		return
	if not require(await click_key("appraisal.look_up"),"return from appraisal"):
		return
	await create_timer(0.45).timeout
	await frames()
	if not require(read_view() == before_return and scene.get("_offer_amount").value == 100,"return preserves prepared price"):
		return
	if not require(await click_key("appraisal.counter_propose") and read_view().negotiation.can_confirm and read_view().negotiation.offers.back().get("presented_ids",[]).size() == 1, "evidence-supported inline offer accepted"):
		return
	check(scene.get("_commit_feedback").diagnostic_view().last_cue == "observation", "negotiation acceptance is not settlement sound")
	await capture("06-offer")
	if not require(await click_key("appraisal.counter_confirm",{"amount":"100"}) and read_view().wallet.VKC == 80, "confirmed purchase"):
		return
	check(scene.get("_commit_feedback").diagnostic_view().last_cue == "settlement", "actual purchase creates settlement cue")
	check(read_view().item_history.records.size() == 1 and read_view().item_history.records[0].amounts.VKC == 100, "confirmed purchase history")
	if not require(await click_key("dayone.begin") and read_view().day_one.started, "first-day continuation"):
		return
	var navigation_before: Dictionary = read_view().duplicate(true)
	for key: String in ["counter", "stock", "workshop", "ledger"]:
		var tab: Button = button("dayone.tab_" + key)
		check(is_instance_valid(tab) and not tab.clip_text and tab.size.x + 0.5 >= maxf(96.0, tab.get_minimum_size().x) and tab.size.y >= 48.0, "readable full-size management tab " + key)
	if not require(await click_key("ui.document_scale", {"percent": "100"}) and await click_key("ui.document_scale", {"percent": "125"}), "large management text"):
		return
	root.size = Vector2i(1024, 768)
	await frames()
	for key: String in ["counter", "stock", "workshop", "ledger"]:
		var tab: Button = button("dayone.tab_" + key)
		check(is_instance_valid(tab) and not tab.clip_text and tab.size.x + 0.5 >= maxf(96.0, tab.get_minimum_size().x) and tab.size.y >= 48.0, "readable 150 percent 4:3 tab " + key)
	await capture("22-management-150-4x3")
	if not require(await click_key("ui.document_scale", {"percent": "150"}), "restore management text"):
		return
	root.size = Vector2i(1280, 720)
	await frames()
	check(read_view() == navigation_before, "management scale resize leaves domain unchanged")
	if not require(await click_key("dayone.tab_stock") and read_view() == navigation_before, "stock navigation free and read-only"):
		return
	var grid: Control
	for n: Node in nodes(scene, Inventory):
		grid = n
	if not require(is_instance_valid(grid), "stock grid"):
		return
	await reveal(grid)
	check(grid.displayed_art("R001") == "radio_face_probe_a", "stock renders the same canonical radio face resource as appraisal")
	await capture("07-stock")
	var stock: Dictionary = {}
	for row: Dictionary in read_view().day_one.stock:
		if row.id == "R001":
			stock = row
	if not require(not stock.is_empty(), "owned item in grid DTO"):
		return
	await click_point(grid, grid._rect_for(stock).get_center())
	if not require(await click_key("dayone.tab_ledger") and await click_key("dayone.tab_stock") and read_view() == navigation_before, "ledger and stock navigation preserve state"):
		return
	for n: Node in nodes(scene, Inventory):
		grid = n
	if not require(is_instance_valid(grid) and grid.draft_view().selected == "R001", "stock selection survives screen change"):
		return
	await click_point(grid, grid._origin("player_display") + Vector2.ONE * grid._cell() * 0.5)
	var moved: bool = false
	for row: Dictionary in read_view().day_one.stock:
		if row.id == "R001" and row.inventory == "player_display":
			moved = true
	if not require(moved, "pointer select and place in display"):
		return
	var quick_before: Dictionary = read_view().duplicate(true)
	if not require(await click_key("dayone.quick_stock") and read_view().revision == quick_before.revision + 1 and read_view().minute == quick_before.minute, "one explicit quick transfer with no time cost"):
		return
	if not require(await click_key("dayone.quick_display") and read_view().revision == quick_before.revision + 2 and read_view().wallet == quick_before.wallet, "quick return to display preserves economy"):
		return
	if not require(await click_key("dayone.tab_counter") and await click_key("ui.door"), "return to counter and next buyer"):
		return
	if not require(await click_key("dayone.retail", {"price": "170"}) and read_view().wallet.VKC == 250, "retail sale"):
		return
	var history_before: Dictionary = read_view().duplicate(true)
	if not require(await click_key("dayone.tab_ledger") and await click_key("lineage.open"), "open ledger history without domain command"):
		return
	check(read_view() == history_before and read_view().item_history.records.size() == 2 and read_view().item_history.records[0].amounts.VKC == 170, "history read preserves confirmed sale and state")
	for node: Node in nodes(scene, PagedRows):
		check(node.page_view().rendered <= PagedRows.PAGE_SIZE, "visible ledger and history pages are bounded")
	await capture("10-item-history-en")
	if not require(await click_key("lineage.open"), "close history"):
		return
	if not require(await click_key("dayone.tab_counter") and await click_key("ui.door"), "next service visit"):
		return
	if not require(await click_key("dayone.accept_service"), "service accepted"):
		return
	if not require(await click_key("dayone.close") and read_view().wallet.VKC == 235 and read_view().minute == 600, "close with overhead"):
		return
	check(scene.get("_commit_feedback").diagnostic_view().last_cue == "closing" and scene.get("_commit_feedback").diagnostic_view().phase == "workshop", "successful close cue and evening ambience mix")
	var mat: Control
	for n: Node in nodes(scene, Surface):
		mat = n
	if not require(is_instance_valid(mat), "evening work surface"):
		return
	await reveal(mat)
	check(mat.displayed_art() == "fictional_gear", "workshop uses public object art and independent abstract gesture zones")
	await capture("08-workshop")
	var workshop_before: Dictionary = read_view().duplicate(true)
	var transform: Transform2D = mat.get_global_transform_with_canvas()
	var previous: Vector2 = transform * mat._tool().get_center()
	pointer_at(previous, true)
	for i: int in range(3):
		var target: Vector2 = transform * mat._zone(i).get_center()
		move_pointer(target, previous, true)
		previous = target
		await frames()
	pointer_at(previous, false)
	await frames()
	if not require(button("dayone.commit_work", {"cost": "10"}) != null and read_view() == workshop_before, "direct surface gesture enables commit without domain mutation"):
		return
	await capture("12-workshop-prepared")
	if not require(await click_key("dayone.tab_ledger") and await click_key("dayone.tab_workshop") and read_view() == workshop_before, "uncommitted preparation survives free navigation"):
		return
	if not require(button("dayone.commit_work", {"cost": "10"}) != null and not button("dayone.commit_work", {"cost": "10"}).disabled, "prepared work remains ready"):
		return
	if not require(await click_key("dayone.commit_work", {"cost": "10"}) and read_view().wallet.VKC == 225 and read_view().minute == 600, "work cost and frozen clock"):
		return
	check(scene.get("_commit_feedback").diagnostic_view().last_cue == "service", "completed work cue")
	var settings_before: Dictionary = read_view().duplicate(true)
	if not require(await click_key("ui.feedback_settings") and await click_key("ui.sound_on") and await click_key("ui.motion_on"), "mute and reduce motion controls"):
		return
	check(read_view() == settings_before and not scene.get("_commit_feedback").diagnostic_view().sound and not scene.get("_commit_feedback").diagnostic_view().motion, "preferences leave domain unchanged")
	var mix: Control = scene.get("_commit_feedback")
	var mix_before: Dictionary = mix.diagnostic_view().levels
	check(mix.diagnostic_view().music_starts == 1, "state changes and document navigation never restart music")
	var music_slider: HSlider
	var amb_slider: HSlider
	for n: Node in nodes(scene):
		if n is HSlider and n.name == "Volume_music":
			music_slider = n
		if n is HSlider and n.name == "Volume_ambience":
			amb_slider = n
	if not require(is_instance_valid(amb_slider), "separate ambience slider"):
		return
	if not require(is_instance_valid(music_slider), "independent music slider"):
		return
	music_slider.value = 0
	amb_slider.value = 35
	await frames()
	check(mix.level("music") == 0 and mix.level("ambience") == 35 and mix.level("sfx") == mix_before.sfx and mix.level("ui") == mix_before.ui and read_view() == settings_before, "independent channel adjustment is presentation only")
	await capture("18-feedback-settings")
	if not require(await click_key("ui.close_document") and await click_key("dayone.management"), "return to management"):
		return
	var muted: Dictionary = scene.get("_commit_feedback").diagnostic_view()
	if not require(await click_key("dayone.morning") and read_view().minute == 1440, "next day"):
		return
	if not require(await click_key("dayone.deliver") and read_view().wallet.VKC == 255, "actual delivery fee"):
		return
	var after_muted: Dictionary = scene.get("_commit_feedback").diagnostic_view()
	check(after_muted.presented == muted.presented + 2 and after_muted.played == muted.played and after_muted.motions == muted.motions, "mute and reduced motion preserve results without sound or animation")
	await capture("09-next-day")
	check(scene.get("_runtime").localization.diagnostics.is_empty(), "no localization diagnostics")
	var completed: Dictionary = read_view().duplicate(true)
	if not require(await click_key("ui.document_scale", {"percent": "100"}) and read_view() == completed, "persist document scale without domain changes"):
		return
	var stored: Dictionary = Preferences.read(str(scene.get("_preferences_path")))
	check(stored.language == "en" and stored.font_size == 20 and not stored.sound and not stored.motion and stored.levels.music == 0 and stored.levels.ambience == 35 and scene.get("_preferences_saved"), "actual preferences file contains all chosen values")
	check(Preferences.normalize({"version": 2, "language": "en"}) == Preferences.defaults(), "unknown settings version uses defaults")
	var malformed: Dictionary = Preferences.normalize({"version": 1, "language": "bad", "font_size": 999, "motion": false, "levels": {"music": -1, "ambience": 45}})
	check(malformed.language == "ko" and malformed.font_size == 16 and malformed.levels.music == 60 and malformed.levels.ambience == 45 and not malformed.motion, "invalid fields cannot poison valid settings")
	root.remove_child(scene)
	scene.queue_free()
	await frames()
	scene = Counter.instantiate()
	scene.set("isolated_day_one_preview", true)
	scene.set("isolated_preview_id", preview_id)
	root.add_child(scene)
	await frames()
	if not require(scene.get("_runtime") != null and not scene.get("_runtime").persistence_view().load_failed and read_view() == completed, "real scene restart restores complete day and lineage"):
		return
	check(is_instance_valid(scene.get("_modal")) and scene.get("_document") == "day_one", "restored management UI opens")
	check(scene.get("_commit_feedback").diagnostic_view().presented == 0 and scene.get("_commit_feedback").diagnostic_view().revision == completed.revision, "load does not replay prior cues")
	var restored_settings: Dictionary = scene.get("_commit_feedback").diagnostic_view()
	check(scene.get("_runtime").localization.current_locale() == "en" and scene.get("_document_font_size") == 20, "language and font survive scene restart")
	check(not restored_settings.sound and not restored_settings.motion and restored_settings.levels == stored.levels, "sound, motion and all four channels survive scene restart")
	await capture("13-reloaded-en-preferences")
	check(not scene.get("_runtime").persistence_view().save_pending, "persistent actions saved")
	root.remove_child(scene)
	scene.queue_free()
	await frames()
	scene = preload("res://scenes/app/gate1_composite_pilot.tscn").instantiate()
	scene.set("composite_pilot_id", "window_" + str(Time.get_ticks_usec()))
	root.add_child(scene)
	await frames()
	# Setup via authority commands, then real pointer interactions in the host scene.
	var rt: RefCounted = scene.get("_runtime")
	var ready: bool = true
	for kind: String in ["accept_rad1_contract", "next_visit", "decline_visit", "begin_day_one", "day_one_next", "day_one_decline", "day_one_next", "day_one_decline"]:
		var rev: int = rt.counter_view().revision
		ready = ready and rt.submit({"action_id": "setup_" + str(rev + 1), "expected_revision": rev, "type": kind, "payload": {}}).ok
	if not require(ready, "composite pilot real counter setup"):
		return
	scene.call("_open", "day_one")
	await frames()
	if not require(await click_key("pilot.offer") and await click_key("consent.request"), "pilot consent UI through same counter"):
		return
	await capture("20-composite-consent")
	if not require(await click_key("consent.close") and await click_key("consent.buy") and read_view().wallet.VKC == 100, "pilot purchase shared wallet"):
		return
	if not require(await click_key("dayone.close") and read_view().minute == 600, "pilot real evening transition"):
		return
	if not require(await click_key("pilot.detach", {"part": "D001_B"}) and await click_key("pilot.restore", {"part": "D001_B", "cost": "5"}) and read_view().wallet.VKC == 80, "pilot owned work UI"):
		return
	await capture("21-composite-workshop")
	check(rt.localization.diagnostics.is_empty() and not rt.persistence_view().save_pending, "pilot localized and persisted")
	root.remove_child(scene)
	scene.queue_free()
	await frames()
	if not await probe_generic_watch():
		return
	print("GATE1_4_WINDOW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

# This adapter is fixture-only; the preview never gains direct session or save access.
var watch_session: RefCounted
var watch_locale: RefCounted
var watch_serial: int = 0
var watch_feedback: String = ""

func watch_refresh() -> void:
	scene.configure(watch_session.calendar_view(),watch_session.snapshot().revision,watch_locale.text,watch_locale.current_locale(),false,watch_feedback)

func watch_action(kind: String,payload: Dictionary,revision: int) -> void:
	watch_serial += 1
	var result: Dictionary = watch_session.execute({"action_id":"window_watch_"+str(watch_serial),"expected_revision":revision,"type":kind,"payload":payload})
	watch_feedback = "" if result.ok else str(result.get("error","rejected"))
	watch_refresh.call_deferred()

func watch_language(locale: String) -> void:
	watch_locale.select_language(locale)
	watch_refresh.call_deferred()

func watch_button(id: String) -> Button:
	return scene.find_child(id,true,false) as Button

func watch_click(id: String) -> bool:
	var b: Button = watch_button(id)
	if b == null or b.disabled or not b.is_visible_in_tree():
		return false
	await reveal(b)
	await click_point(b,b.size*0.5)
	await watch_wait_transition()
	return watch_feedback.is_empty()

func watch_space() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_SPACE
	e.pressed = true
	root.push_input(e)
	e = InputEventKey.new()
	e.keycode = KEY_SPACE
	e.pressed = false
	root.push_input(e)
	await frames()
	await watch_wait_transition()

func watch_wait_transition() -> void:
	if scene.transition_active():
		await create_timer(0.42,true,false,true).timeout
		await frames()

func watch_drag(id: String,cancel: bool = false) -> bool:
	var source: Button = watch_button(id)
	var target: Button = watch_button("customer_drop")
	if source == null or target == null or source.disabled or target.disabled:
		return false
	await reveal(source)
	var origin: Vector2 = source.get_global_rect().get_center()
	var destination: Vector2 = scene.get("_header").get_global_rect().get_center() if cancel else target.get_global_rect().get_center()
	pointer_at(origin,true)
	move_pointer(origin+Vector2(25,-25),origin,true)
	await frames()
	var dragging: bool = root.gui_is_dragging()
	move_pointer(destination,origin+Vector2(25,-25),true)
	await frames()
	pointer_at(destination,false)
	await frames()
	return dragging and not root.gui_is_dragging() and watch_feedback.is_empty()

func probe_generic_watch() -> bool:
	watch_session = preload("res://tests/fixtures/p2_watch_state.gd").fresh(true,false,true)
	watch_locale = preload("res://src/presentation/localization_service.gd").new()
	if not require(watch_session != null and watch_locale.initialize(),"generic watch fixture and locale"):
		return false
	scene = preload("res://src/presentation/generic_counter_preview.gd").new()
	root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.action_requested.connect(watch_action)
	scene.language_requested.connect(watch_language)
	watch_refresh()
	await frames()
	if not require(await watch_click("admit_visit") and watch_session.calendar_view().visits.active=="watch_a","generic pointer admit"):
		return false
	if not require(await watch_click("pick_appearance_id_visible_wear") and await watch_click("tool_wear_detail") and watch_session.calendar_view().minute==5,"generic pointer hypothesis and inspection"):
		return false
	if not require(await watch_click("link_appearance_id_window_watch_3") and await watch_click("prepare_appearance_id"),"generic pointer evidence and preparation"):
		return false
	check(watch_session.calendar_view().appraisal.deck.presented.is_empty() and watch_button("present_window_watch_5")==null,"down view never presents")
	await capture("28-generic-watch-appraisal-ko")
	var before: Dictionary = watch_session.snapshot()
	scene.toggle_gaze()
	check(scene.transition_active() and watch_button("decline_active").disabled and watch_button("tool_wear_detail").disabled,"animated transition locks visit and appraisal input")
	scene.toggle_gaze()
	await watch_wait_transition()
	if not require(not scene.transition_active() and scene.gaze_mode()=="customer" and watch_session.snapshot()==before and watch_button("tool_wear_detail")==null,"SPACE gaze free and customer-only controls"):
		return false
	if not require(await watch_drag("drag_window_watch_5",true) and watch_session.snapshot()==before,"cancelled pointer drag leaves authority unchanged"):
		return false
	if not require(await watch_drag("drag_window_watch_5") and watch_session.calendar_view().appraisal.deck.presented.size()==1,"customer view actual drag presentation"):
		return false
	check(scene.find_child("claim_a_wear_claim",true,false)!=null,"customer claim rendered after pointer drag")
	await capture("29-generic-watch-customer-ko")
	before = watch_session.snapshot()
	if not require(await watch_click("toggle_motion") and watch_button("toggle_motion").text == "모션 감소" and watch_session.snapshot()==before,"reduced motion is presentation only"):
		return false
	for i: int in range(10):
		await watch_space()
	check(scene.gaze_mode()=="customer" and not scene.transition_active() and watch_session.snapshot()==before,"ten reduced-motion SPACE transitions are free")
	if not require(await watch_click("toggle_gaze") and scene.gaze_mode()=="appraisal" and watch_session.snapshot()==before,"touch/click gaze fallback"):
		return false
	if not require(await watch_click("pick_model_id_meridian_12") and await watch_click("prepare_model_id"),"return for independent appraisal"):
		return false
	before = watch_session.snapshot()
	if not require(await watch_click("switch_language") and watch_locale.current_locale()=="en" and watch_session.snapshot()==before,"language leaves authority unchanged"):
		return false
	await capture("30-generic-watch-appraisal-en")
	root.size = Vector2i(1024,768)
	await frames()
	if not require(await watch_click("toggle_gaze") and watch_session.snapshot()==before,"4:3 customer transition"):
		return false
	await capture("31-generic-watch-customer-4x3")
	if not require(await watch_click("present_window_watch_8") and watch_session.calendar_view().appraisal.deck.presented.size()==2,"second distinct claim"):
		return false
	if not require(scene.find_child("claim_a_model_claim",true,false)!=null and await watch_click("toggle_gaze") and scene.find_child("claim_a_model_claim",true,false)!=null,"claim persists when returning to investigation"):
		return false
	if not require(await watch_click("tool_batch_detail") and await watch_click("link_model_id_window_watch_10") and await watch_click("prepare_model_id"),"independent model observation for rebuttal"):
		return false
	if not require(await watch_click("toggle_gaze") and await watch_click("rebut_window_watch_12_a_model_claim"),"actual pointer explicit rebuttal"):
		return false
	check(watch_session.calendar_view().appraisal.deck.presented.size()==3 and watch_session.calendar_view().appraisal.deck.presented[2].rebuttal.claim_id=="a_model_claim" and scene.find_child("rebuttal_window_watch_13",true,false)!=null,"rebuttal citation visible and durable")
	await capture("32-generic-watch-rebuttal-en")
	var price_input: SpinBox = scene.find_child("price_offer_amount",true,false) as SpinBox
	if not require(price_input != null,"price input in actual customer view"):
		return false
	price_input.value = 80
	before = watch_session.snapshot()
	if not require(await watch_click("toggle_gaze") and await watch_click("toggle_gaze") and int(scene.find_child("price_offer_amount",true,false).value)==80 and watch_session.snapshot()==before,"price draft survives gaze"):
		return false
	if not require(await watch_click("price_offer_public") and not watch_session.calendar_view().appraisal.price_offer.offers[0].accepted and watch_session.snapshot().wallets==before.wallets,"actual rejected price offer"):
		return false
	price_input = scene.find_child("price_offer_amount",true,false) as SpinBox
	price_input.value = 90
	if not require(await watch_click("price_offer_public") and watch_session.calendar_view().appraisal.price_offer.accepted_offer_id!=null,"actual accepted price offer"):
		return false
	before = watch_session.snapshot()
	if not require(watch_button("confirm_checkout").disabled and await watch_click("place_player_grid_2_1") and not watch_button("confirm_checkout").disabled and watch_session.snapshot()==before,"pointer placement is private selection"):
		return false
	if not require(await watch_click("toggle_gaze") and await watch_click("toggle_gaze") and not watch_button("confirm_checkout").disabled and watch_session.snapshot()==before,"checkout draft survives gaze"):
		return false
	await capture("33-generic-watch-checkout-en")
	if not require(await watch_click("confirm_checkout") and watch_session.calendar_view().appraisal.is_empty(),"explicit pointer purchase closes visit"):
		return false
	var settled: Dictionary = watch_session.snapshot()
	check(settled.wallets.player.VKC==90 and settled.items.W001.owner_id=="player" and settled.items.W001.x==2 and settled.items.W001.y==1 and settled.ledger.size()==1,"actual wallet ownership placement and ledger")
	check(settled.calendar.appraisal_offers.watch_a[1].presented_ids.size()==3 and settled.calendar.appraisal_offers.watch_a[1].accepted,"purchase preserves frozen public claims")
	if not require(await watch_click("toggle_history") and scene.find_child("history_item_W001",true,false)!=null and watch_session.snapshot()==settled,"actual history opens read-only"):
		return false
	check(scene.find_child("history_trade_window_watch_16_W001",true,false)!=null and scene.find_child("history_evidence_window_watch_16_window_watch_3",true,false)!=null,"accepted trade and acquired evidence visible")
	check(scene.find_child("history_item_W002",true,false)==null and watch_button("admit_visit").disabled,"unknown specimen excluded and history blocks gameplay input")
	await capture("34-generic-watch-trade-history-en")
	if not require(await watch_click("switch_language") and watch_session.snapshot()==settled and await watch_click("toggle_history") and watch_session.snapshot()==settled,"history bilingual close free"):
		return false
	if not require(await watch_click("admit_visit") and watch_session.calendar_view().appraisal.item_id=="W002","next specimen isolated"):
		return false
	check(watch_session.calendar_view().appraisal.deck.presented.is_empty() and watch_session.calendar_view().appraisal.assessment.selected.is_empty() and scene.gaze_mode()=="appraisal","new visit clears UI-only gaze and prior active deck")
	check(await watch_click("decline_active") and watch_session.calendar_view().appraisal.is_empty(),"second visit decline closes appraisal")
	check(watch_locale.diagnostics.is_empty(),"watch locale has no missing keys")
	root.remove_child(scene)
	scene.queue_free()
	watch_locale.shutdown()
	await frames()
	return true
