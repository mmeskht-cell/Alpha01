extends SceneTree
const Fixture = preload("res://tests/fixtures/p2_watch_state.gd")
const GenericAppraisalPanelScript = preload("res://src/presentation/generic_appraisal_panel.gd")
var checks: int = 0
var failures: int = 0
var session: RefCounted
var panel: ScrollContainer
var last: Dictionary = {}
var serial: int = 0

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func _initialize() -> void:
	run.call_deferred()

func refresh(locked: bool = false) -> void:
	panel.configure(session.calendar_view().get("appraisal",{}),session.snapshot().revision,Callable(),"en",locked)

func receive(kind: String,p: Dictionary,revision: int) -> void:
	serial += 1
	last = session.execute({"action_id":"ui_"+str(serial),"expected_revision":revision,"type":kind,"payload":p})

func press(id: String) -> bool:
	var b: Button = panel.find_child(id,true,false) as Button
	if b == null or b.disabled:
		return false
	last = {}
	b.pressed.emit()
	return last.get("ok",false)

func disabled(id: String) -> bool:
	var b: Button = panel.find_child(id,true,false) as Button
	return b != null and b.disabled

func run() -> void:
	session = Fixture.fresh()
	check(session != null,"watch session")
	if session == null:
		quit(1)
		return
	panel = GenericAppraisalPanelScript.new()
	root.add_child(panel)
	panel.action_requested.connect(receive)
	refresh()
	check(panel.find_child("tool_wear_detail",true,false)==null,"no inactive controls")
	check(session.execute({"action_id":"admit","expected_revision":session.snapshot().revision,"type":"calendar_next_visit","payload":{}}).ok,"admit")
	refresh()
	var obsolete: Button = panel.find_child("pick_model_id_meridian_12",true,false) as Button
	check(press("pick_appearance_id_visible_wear"),"condition before identification")
	refresh()
	var before_serial: int = serial
	if is_instance_valid(obsolete):
		obsolete.pressed.emit()
	check(serial == before_serial,"detached stale UI callback cannot dispatch")
	check(press("tool_wear_detail"),"actual inspection")
	refresh()
	check(disabled("tool_wear_detail"),"known tool disabled")
	check(press("link_appearance_id_ui_2"),"link actual acquired evidence")
	refresh()
	check(press("prepare_appearance_id"),"prepare actual sourced card")
	refresh()
	check(session.calendar_view().appraisal.deck.presented.is_empty(),"private until press")
	var source: Button = panel.find_child("drag_ui_4",true,false) as Button
	var target: Button = panel.find_child("customer_drop",true,false) as Button
	check(source != null and target != null,"drag source and explicit target")
	var token: Dictionary = source.get("token").duplicate(true)
	var forged: Dictionary = token.duplicate(true)
	for field: String in ["owner","epoch","revision","visit_id","item_id","slot_id","card_id","kind"]:
		forged = token.duplicate(true)
		forged[field] = "forged"
		check(not target._can_drop_data(Vector2.ZERO,forged),"reject forged "+field)
	check(target._can_drop_data(Vector2.ZERO,token),"current prepared identity accepted")
	refresh()
	target = panel.find_child("customer_drop",true,false) as Button
	check(not target._can_drop_data(Vector2.ZERO,token),"reject previous render token")
	source = panel.find_child("drag_ui_4",true,false) as Button
	token = source.get("token").duplicate(true)
	target._drop_data(Vector2.ZERO,token)
	check(last.get("ok",false),"present actual card via drop")
	check(not target._can_drop_data(Vector2.ZERO,token),"same render duplicate blocked")
	check(not press("present_ui_4"),"same render click fallback cannot duplicate")
	refresh()
	check(session.calendar_view().appraisal.deck.presented.size()==1 and disabled("prepare_appearance_id"),"presented and duplicate disabled")
	check(press("pick_model_id_meridian_12"),"select model later")
	refresh()
	check(press("prepare_model_id"),"prepare model")
	refresh()
	check(press("pick_model_id_meridian_12a"),"revise model")
	refresh()
	check(disabled("present_ui_7") and disabled("drag_ui_7"),"stale presentation/drag disabled")
	check(press("remove_ui_7"),"remove stale card")
	refresh(true)
	check(disabled("pick_model_id_meridian_12") and disabled("customer_drop"),"lock respected")
	refresh()
	check(session.calendar_view().appraisal.deck.presented.size()==1,"old speech immutable")
	check(session.execute({"action_id":"decline","expected_revision":session.snapshot().revision,"type":"calendar_decline_visit","payload":{"visit_id":"watch_a"}}).ok,"close visit")
	refresh()
	check(panel.find_child("tool_wear_detail",true,false)==null,"closed visit hides controls")
	panel.queue_free()
	await process_frame
	print("GATE2_P2_GENERIC_PANEL: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
