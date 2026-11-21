extends ScrollContainer
const PublicObservationText=preload("res://src/presentation/public_observation_text.gd")
const AppraisalVisuals=preload("res://src/presentation/public_appraisal_visuals.gd")
const ReferenceGuide=preload("res://src/presentation/public_reference_guide.gd")
## P2-D2 reusable technical preview: renders only a public appraisal DTO.
## Host owns action IDs, revision validation, dispatch, persistence and feedback.
## Never reads private specimen state or mutates the game directly.
signal action_requested(kind: String, payload: Dictionary, expected_revision: int)
const DragSourceScript = preload("res://src/presentation/generic_deck_drag.gd")
const DropTargetScript = preload("res://src/presentation/generic_deck_drop.gd")

var _body: VBoxContainer
var _translator: Callable
var _ko: bool = true
var _epoch: int = 0
var _drag_tokens: Dictionary = {}
var _presentation_sent: bool = false
var _draft_visit: String = ""
var _draft_offer_count: int = -1
var _draft_amount: int = 0
var _checkout_offer: String = ""
var _checkout_choice: Dictionary = {}
var _paper_tokens:Dictionary={}
var _production:bool=false
var _paper_book:bool=false
var _statements_page:int=0
var _checkout_page:int=0
var _book_slot:int=0
var _book_section:String="judgment"
var _book_entry:int=0
# Set by the local spatial viewer; never persisted or sent to authority.
var comparison_observation_key:String=""

func _word(ko: String,en: String) -> String:
	return ko if _ko else en

func tool_title(id:String)->String:
	if id=="basic_function_v1":
		return _label("review.basic.function")
	return _label("ui.tool."+id) if id in ["wear_detail","casing_detail","material_detail","batch_detail","function_detail","display_damage_detail"] else _label("ui.tool.unknown")

func _label(key:String,arguments:Dictionary={})->String:
	if not _translator.is_valid():
		return key
	return str(_translator.call(key)) if arguments.is_empty() else str(_translator.call(key,arguments))

func _line(parent: Control,value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _paper_book:
		label.add_theme_color_override("font_color",Color("#302D27"))
	parent.add_child(label)
	return label

func _button(parent: Control,id: String,label: String,kind: String,payload: Dictionary,revision: int,disabled: bool = false) -> void:
	var button := Button.new()
	button.name = id
	button.text = label
	button.disabled = disabled
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var epoch: int = _epoch
	button.pressed.connect(func() -> void:
		if epoch == _epoch and not button.disabled and not _presentation_sent:
			if kind == "subject_deck_action" and payload.get("op") in ["present","present_direct","withdraw"]:
				_presentation_sent = true
			action_requested.emit(kind,payload.duplicate(true),revision))
	parent.add_child(button)

func _payload(app: Dictionary,fields: Dictionary) -> Dictionary:
	var result: Dictionary = {"visit_id":app.visit_id,"item_id":app.item_id}
	result.merge(fields)
	return result

func _argument_text(arg: Dictionary)->String:
	if arg.get("statement_kind")=="observation":
		return _label("ui.format.observed_fact",{"reading":PublicObservationText.fact(str(arg.label_key),arg.observed_value,_translator)})
	return _label(arg.label_key)

func configure(app: Dictionary,revision: int,translator: Callable = Callable(),language: String = "ko",locked: bool = false,view_mode: String = "all") -> void:
	var paged_book:bool=view_mode=="production_book_paged"
	_paper_book=paged_book
	var spatial_book:bool=view_mode=="production_book" or paged_book
	var paged_checkout:bool=view_mode=="production_checkout_paged"
	var paged_statements:bool=view_mode=="production_statements_paged"
	var spatial_checkout:bool=view_mode=="production_checkout" or paged_checkout
	var spatial_statements:bool=view_mode=="production_statements" or paged_statements
	var requested_mode:String=view_mode
	_production=view_mode.begins_with("production_")
	if _production:
		view_mode="appraisal" if spatial_book else view_mode.trim_prefix("production_")
	_paper_tokens.clear()
	_epoch += 1
	var visit: String = str(app.get("visit_id",""))
	var offer_count: int = app.get("price_offer",{}).get("offers",[]).size()
	if visit != _draft_visit or offer_count != _draft_offer_count:
		if visit!=_draft_visit:
			_statements_page=0
			_book_slot=0
			_book_section="judgment"
			_book_entry=0
		_draft_visit = visit
		_draft_offer_count = offer_count
		_draft_amount = int(app.get("price_offer",{}).get("asking",0))
	var accepted_id: String = str(app.get("checkout",{}).get("offer_id",""))
	if accepted_id != _checkout_offer or visit.is_empty():
		_checkout_page=0
		_checkout_offer = accepted_id
		_checkout_choice.clear()
	_drag_tokens.clear()
	_presentation_sent = false
	_translator = translator
	_ko = language == "ko"
	if is_instance_valid(_body):
		remove_child(_body)
		_body.queue_free()
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if paged_checkout or paged_statements or paged_book else ScrollContainer.SCROLL_MODE_AUTO
	follow_focus = true
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_body)
	if app.is_empty():
		_line(_body,_label("ui.copy.no_active_appraisal_e67124a0"))
		return
	if paged_book:
		_build_paged_book(app,revision,locked)
		return
	if spatial_statements:
		_line(_body,_label("ui.copy.appraisal_sheet_public_assessments_9d1a1781"))
		_line(_body,_label("ui.copy.you_may_disclose_acquired_observations_sepa_4423d9f0"))
		var observations:Array=app.deck.get("observation_ready",[])
		var speeches:Array=app.deck.presented
		if paged_statements:
			var total:int=observations.size()+speeches.size()
			_statements_page=clampi(_statements_page,0,maxi(0,total-1))
			_page_controls("statements",_statements_page,total,func(index:int)->void:
				_statements_page=index
				configure(app,revision,translator,language,locked,requested_mode))
			if _statements_page<observations.size():
				observations=[observations[_statements_page]]
				speeches=[]
			else:
				var speech_index:int=_statements_page-observations.size()
				observations=[]
				speeches=[speeches[speech_index]] if speech_index<speeches.size() else []
		for observed: Dictionary in observations:
			_button(_body,"disclose_observation_"+observed.source_action,_argument_text(observed),"subject_deck_action",_payload(app,{"op":"present_observation","slot_id":observed.slot_id,"ref_id":observed.source_action}),revision,locked or app.deck.remaining_events<=0 or app.deck.remaining_presentations<=0)
		for speech:Dictionary in speeches:
			if speech.has("withdraws_presentation_id"):
				_line(_body,_label("ui.format.withdrawn",{"judgment":_argument_text(speech.argument)}))
			else:
				var active: bool = speech.presentation_id in app.deck.public_basis_ids
				var prefix: String = _label("ui.copy.earlier_hypothesis_af584293") if not active else (_label("ui.copy.correction_fe5aa275") if speech.has("corrects_presentation_id") else _label("ui.copy.current_hypothesis_6b5dc0fc"))
				if speech.argument.get("statement_kind")=="observation":
					prefix=_label("ui.copy.current_disclosure_439956a0") if active else _label("ui.copy.earlier_disclosure_3a8a0acb")
				_line(_body,prefix+_argument_text(speech.argument))
				if active:
					_button(_body,"withdraw_"+str(speech.argument.slot_id),_label("ui.copy.withdraw_this_judgment_d34bfe1b"),"subject_deck_action",_payload(app,{"op":"withdraw","slot_id":speech.argument.slot_id,"ref_id":speech.presentation_id}),revision,locked or app.deck.remaining_events<=0 or app.deck.remaining_presentations<=0)
			_show_response(speech)
			_show_rebuttal(speech)
		return
	if spatial_checkout:
		if app.has("checkout"):
			_checkout_controls(app,revision,locked,paged_checkout)
		return
	_line(_body,((_label("ui.copy.inspect_item_70038369") if view_mode=="appraisal" else _label("ui.copy.negotiate_aaca716")) if _production else _label("ui.copy.generic_appraisal_pilot_776dd0b4"))+str(app.item_id))
	if _production and view_mode=="customer":
		_line(_body,_label("ui.copy.present_an_assessment_card_or_offer_a_price_ee29b6ac"))
		if not app.deck.presented.is_empty():
			var latest:Dictionary=app.deck.presented.back()
			_line(_body,(_label("ui.copy.alexei_i_withdraw_this_18ff8bf6") if latest.has("withdraws_presentation_id") else _label("ui.copy.alexei_my_assessment_is_817169e8"))+_argument_text(latest.argument))
			_show_response(latest)
	if view_mode != "customer":
		if not spatial_book:
			_line(_body,_label("ui.copy.inspection_tools_6050cc0a"))
			for tool_id: String in app.tools:
				var tool: Dictionary = app.tools[tool_id]
				var known: bool = false
				for fact: Dictionary in app.evidence:
					if fact.current and not fact.is_claim and fact.observation_key == tool.evidence_id:
						known = true
				var title:String=tool_title(tool_id) if _production else _label(tool.text_key)
				_button(_body,"tool_"+tool_id,title+" · "+str(tool.minutes)+_label("ui.copy.min_a419b7d"),"inspect_subject",_payload(app,{"tool_id":tool_id,"target":tool.target}),revision,locked or known)
		_line(_body,_label("ui.copy.observations_7f06a163"))
		for fact: Dictionary in app.evidence:
			_line(_body,PublicObservationText.fact(str(fact.observation_key),fact.observed_value,_translator)+("" if fact.current else _label("ui.copy.stale_92e2fc99"))+(_label("ui.copy.claim_eff9e604") if fact.is_claim else ""))
		var assessment: Dictionary = app.assessment
		var selected: Dictionary = assessment.selected
		for slot: Dictionary in app.catalog.slots:
			var slot_id: String = slot.id
			_line(_body,_label("ui.format.hypothesis_category",{"category":str(slot.category)}))
			if _production:
				_paper_slot(app,slot,selected.get(slot_id),revision,locked)
			else:
				for choice: Dictionary in slot.candidates:
					var active: bool = selected.get(slot_id)==choice.id
					_button(_body,"pick_"+slot_id+"_"+choice.id,("✓ " if active else "")+_label(choice.label_key),"assess_subject",_payload(app,{"slot_id":slot_id,"candidate_id":choice.id}),revision,locked or active)
			_button(_body,"clear_"+slot_id,_label("ui.copy.clear_selection_e6cd7119"),"assess_subject",_payload(app,{"slot_id":slot_id,"candidate_id":null}),revision,locked or not selected.has(slot_id))
			if selected.has(slot_id):
				var suggested: Array = app.get("evidence_suggestions",{}).get(slot_id,[]) if _production else []
				var ordered: Array = []
				# Existing links first, then relevant observations, then remaining
				# observations. Nothing is selected or linked automatically.
				for fact: Dictionary in app.evidence:
					if fact.evidence_id in assessment.links.get(slot_id,[]):
						ordered.append(fact)
				for fact: Dictionary in app.evidence:
					if fact.evidence_id in suggested and fact not in ordered:
						ordered.append(fact)
				for fact: Dictionary in app.evidence:
					if fact not in ordered:
						ordered.append(fact)
				for fact: Dictionary in ordered:
					var linked: bool = fact.evidence_id in assessment.links.get(slot_id,[])
					if not linked and (not fact.current or fact.is_claim):
						continue
					var prefix: String = _label("ui.copy.unlink_66ae24e2") if linked else (_label("ui.copy.link_related_observation_c5c87266") if fact.evidence_id in suggested else _label("ui.copy.link_evidence_f73569d9"))
					var reading: String = PublicObservationText.label(str(fact.observation_key),_translator)
					if _production:
						reading = PublicObservationText.fact(str(fact.observation_key),fact.observed_value,_translator)
						if not fact.current:
							reading += _label("ui.copy.stale_92e2fc99")
					_button(_body,"link_"+slot_id+"_"+fact.evidence_id,prefix+reading,"link_subject_evidence",_payload(app,{"slot_id":slot_id,"evidence_id":fact.evidence_id}),revision,locked)
		var estimate: Variant = app.reference.get("estimate")
		_line(_body,_label("ui.format.reference_estimate",{"price":"—" if estimate==null else _label("inventory.format.offer_amount",{"amount":str(estimate),"currency":str(app.catalog.currency)})}))
	var deck: Dictionary = app.deck
	var exhausted: bool = deck.remaining_events <= 0
	if view_mode != "customer" and not _production:
		_line(_body,_label("ui.copy.available_hypotheses_bb25869f"))
		for candidate: Dictionary in deck.candidates:
			var arg: Dictionary = candidate.argument
			_button(_body,"prepare_"+arg.slot_id,_label("ui.format.prepare_claim",{"claim":_label(arg.label_key)}),"subject_deck_action",_payload(app,{"op":"prepare","slot_id":arg.slot_id,"ref_id":arg.source_action}),revision,locked or exhausted or candidate.already_ready or candidate.already_presented)
	_line(_body,_label("ui.copy.private_assessment_cards_8be73713") if _production else _label("ui.copy.prepared_cards_75964db5"))
	if view_mode != "appraisal":
		var target := DropTargetScript.new()
		target.name = "customer_drop"
		target.text = _label("ui.copy.drop_a_card_to_address_customer_fe4dc946")
		target.custom_minimum_size.y = 64
		target.disabled = locked or exhausted or deck.remaining_presentations <= 0
		target.accepts = _accept_drag
		target.commit = _commit_drag
		_body.add_child(target)
	var hand:Control=_body
	if _production and view_mode=="customer":
		for observed: Dictionary in deck.get("observation_ready",[]):
			_button(_body,"disclose_observation_"+observed.source_action,_argument_text(observed),"subject_deck_action",_payload(app,{"op":"present_observation","slot_id":observed.slot_id,"ref_id":observed.source_action}),revision,locked or exhausted or deck.remaining_presentations<=0)
		var flow:=HFlowContainer.new()
		_body.add_child(flow)
		hand=flow
	var visible_cards: Array = deck.direct_ready if _production else deck.ready
	for card: Dictionary in visible_cards:
		var arg: Dictionary = card.argument
		var op: String = "present_direct" if _production else "present"
		var ref_id: String = arg.source_action if _production else card.card_id
		var holder:Control=hand
		if _production and view_mode=="customer":
			var stack:=VBoxContainer.new()
			stack.custom_minimum_size.x=150
			hand.add_child(stack)
			holder=stack
		_line(holder,(_label("ui.copy.correction_df85060b") if card.get("correction",false) else "")+_label(arg.label_key)+("" if card.current else _label("ui.copy.stale_d90d0a15")))
		if view_mode != "appraisal":
			var blocked: bool = locked or exhausted or not card.current or deck.remaining_presentations <= 0
			var source := DragSourceScript.new()
			source.name = "drag_"+str(card.card_id)
			source.text = _label("ui.format.drag_claim",{"claim":_label(arg.label_key)})
			source.disabled = blocked
			source.token = {"kind":"generic_deck_card","owner":get_instance_id(),"epoch":_epoch,"revision":revision,"visit_id":app.visit_id,"item_id":app.item_id,"slot_id":arg.slot_id,"card_id":card.card_id,"op":op,"ref_id":ref_id}
			if not blocked:
				_drag_tokens[card.card_id] = source.token.duplicate(true)
			if _production:
				_paper_style(source)
				source.custom_minimum_size=Vector2(150,88)
				source.text=_label(arg.label_key)+"\n"+_label("ui.copy.hypothesis_links_2ea00e9e")+str(arg.evidence_ids.size())
			holder.add_child(source)
			_button(holder,"present_"+card.card_id,_label("ui.copy.present_fc2a476"),"subject_deck_action",_payload(app,{"op":op,"slot_id":arg.slot_id,"ref_id":ref_id}),revision,locked or exhausted or not card.current or deck.remaining_presentations <= 0)
			for option: Dictionary in card.get("rebuttal_options",[]):
				_button(holder,"rebut_"+card.card_id+"_"+option.claim_id,_label("ui.format.rebut_claim",{"claim":_label(option.claim_label_key)}),"subject_deck_action",_payload(app,{"op":op,"slot_id":arg.slot_id,"ref_id":ref_id,"claim_id":option.claim_id}),revision,blocked)
		if not _production:
			_button(holder,"remove_"+card.card_id,_label("ui.copy.remove_9f25f42f"),"subject_deck_action",_payload(app,{"op":"remove","slot_id":arg.slot_id,"ref_id":card.card_id}),revision,locked or exhausted)
	if view_mode != "appraisal" and app.has("price_offer"):
		_offer_controls(app,revision,locked)
		if app.has("checkout"):
			_checkout_controls(app,revision,locked)
	if view_mode != "appraisal":
		_line(_body,_label("ui.copy.disclosed_assessments_and_observations_59fe26d2"))
		for speech: Dictionary in deck.presented:
			_line(_body,_argument_text(speech.argument)+" · "+str(speech.argument.evidence_ids.size())+_label("ui.copy.evidence_links_d13b010c"))
			_show_response(speech)
			_show_rebuttal(speech)
	else:
		_line(_body,_label("ui.copy.customer_statements_unverified_ff613f53"))
		for speech: Dictionary in deck.presented:
			_show_response(speech)
	if _production and view_mode=="customer":
		_button(_body,"appraisal_decline",_label("ui.copy.decline_visit_aac393e"),"calendar_decline_visit",{"visit_id":app.visit_id},revision,locked)
		# Closing settlement belongs to the main counter, not a legacy empty command.

# Private book pages use only public catalog entries and acquired observations.
# Switching pages does not dispatch a command or change game state.
func _book_rebuild(app:Dictionary,revision:int,locked:bool)->void:
	configure(app,revision,_translator,"ko" if _ko else "en",locked,"production_book_paged")

func _book_tab(parent:Control,id:String,key:String,callback:Callable,selected:bool)->void:
	var b:=Button.new()
	b.name=id
	b.text=_label(key)
	b.custom_minimum_size.y=42
	b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	b.disabled=selected
	if _paper_book:
		for mode:String in ["normal","hover","pressed","disabled"]:
			var tab_style:=StyleBoxFlat.new()
			tab_style.bg_color=Color("#B4A385") if selected else Color("#E7DEC9")
			tab_style.border_color=Color("#8C795A")
			tab_style.set_border_width_all(1)
			tab_style.border_width_bottom=3 if selected else 1
			b.add_theme_stylebox_override(mode,tab_style)
		for color_key:String in ["font_color","font_hover_color","font_pressed_color","font_disabled_color","font_focus_color"]:
			b.add_theme_color_override(color_key,Color("#302D27"))
	var epoch:int=_epoch
	b.pressed.connect(func()->void:
		if epoch==_epoch:
			callback.call())
	parent.add_child(b)

func _build_paged_book(app:Dictionary,revision:int,locked:bool)->void:
	_body.add_theme_constant_override("separation",4)
	var slots:Array=app.catalog.slots
	if slots.is_empty():
		_line(_body,_label("ui.copy.observations_7f06a163"))
		return
	_book_slot=clampi(_book_slot,0,slots.size()-1)
	var slot:Dictionary=slots[_book_slot]
	var slot_id:String=slot.id
	var chapters:Array[String]=[]
	for chapter:Dictionary in slots:
		chapters.append(_label("book.category."+str(chapter.category)))
	_page_controls("book_slot",_book_slot,slots.size(),func(index:int)->void:
		_book_slot=index
		_book_entry=0
		_book_section="judgment"
		_book_rebuild(app,revision,locked),chapters,ReferenceGuide.related_chapters(app.catalog,comparison_observation_key))
	var tabs:=HBoxContainer.new()
	_body.add_child(tabs)
	for section:String in ["judgment","reference","evidence"]:
		_book_tab(tabs,"book_"+section,"book.tab."+section,func()->void:
			_book_section=section
			_book_entry=0
			_book_rebuild(app,revision,locked),_book_section==section)
	var selected:Dictionary=app.assessment.selected
	if _book_section=="judgment":
		_paper_slot(app,slot,selected.get(slot_id),revision,locked)
		_button(_body,"clear_"+slot_id,_label("ui.copy.clear_selection_e6cd7119"),"assess_subject",_payload(app,{"slot_id":slot_id,"candidate_id":null}),revision,locked or not selected.has(slot_id))
		var estimate:Variant=app.reference.get("estimate")
		_line(_body,_label("ui.format.reference_estimate",{"price":"—" if estimate==null else _label("inventory.format.offer_amount",{"amount":str(estimate),"currency":str(app.catalog.currency)})}))
		return
	if _book_section=="reference":
		var candidates:Array=slot.candidates
		if candidates.is_empty():
			return
		_book_entry=clampi(_book_entry,0,candidates.size()-1)
		_page_controls("book_entry",_book_entry,candidates.size(),func(index:int)->void:
			_book_entry=index
			_book_rebuild(app,revision,locked))
		var entry:Dictionary=candidates[_book_entry]
		var key:String=entry.label_key
		var heading:=_line(_body,_label(key)+_public_reference_suffix(slot,entry,str(app.catalog.currency)))
		heading.name="book_reference_heading"
		# Data-defined public alternatives; no hidden specimen or actual price.
		var description:String=ReferenceGuide.description_key(entry)
		_line(_body,_label("book.reference.no_detail" if description.is_empty() else description))
		_reference_comparison(app.catalog,slot,func(index:int)->void:
			_book_entry=index
			_book_rebuild(app,revision,locked),app.evidence)
		var source:String=str(app.catalog.get("source_key",""))
		if not source.is_empty():
			_line(_body,_label(source))
		return
	var ordered:Array=[]
	var linked_ids:Array=app.assessment.links.get(slot_id,[])
	var suggested:Array=app.get("evidence_suggestions",{}).get(slot_id,[])
	for fact:Dictionary in app.evidence:
		if fact.evidence_id in linked_ids:
			ordered.append(fact)
	for fact:Dictionary in app.evidence:
		if fact.evidence_id in suggested and fact not in ordered:
			ordered.append(fact)
	for fact:Dictionary in app.evidence:
		if fact not in ordered:
			ordered.append(fact)
	if ordered.is_empty():
		_line(_body,_label("book.evidence.empty"))
		return
	_book_entry=clampi(_book_entry,0,ordered.size()-1)
	_page_controls("book_entry",_book_entry,ordered.size(),func(index:int)->void:
		_book_entry=index
		_book_rebuild(app,revision,locked))
	var fact:Dictionary=ordered[_book_entry]
	var copy:String=PublicObservationText.fact(str(fact.observation_key),fact.observed_value,_translator)
	if not fact.current:
		copy+=_label("ui.copy.stale_92e2fc99")
	if fact.is_claim:
		copy+=_label("ui.copy.claim_eff9e604")
	_line(_body,copy)
	var sample:Control=AppraisalVisuals.acquired_display(fact,_translator)
	if sample!=null:
		_line(_body,_label(str(sample.get_meta("caption_key"))))
		sample.custom_minimum_size=Vector2(84,56)
		_body.add_child(sample)
	if selected.has(slot_id):
		var linked:bool=fact.evidence_id in linked_ids
		if linked or (fact.current and not fact.is_claim):
			var prefix:String=_label("ui.copy.unlink_66ae24e2") if linked else _label("ui.copy.link_evidence_f73569d9")
			_button(_body,"link_"+slot_id+"_"+fact.evidence_id,prefix+PublicObservationText.label(str(fact.observation_key),_translator),"link_subject_evidence",_payload(app,{"slot_id":slot_id,"evidence_id":fact.evidence_id}),revision,locked)

# Reference values already exist in the public catalog. These are not
# the actual item's value, an accepted offer, or a new calculation.
func _public_reference_suffix(slot:Dictionary,entry:Dictionary,currency:String)->String:
	var value:Variant=entry.get("value")
	if value==null:
		return ""
	var n:int=int(value)
	match str(slot.get("effect","")):
		"base":
			return _label("ui.format.reference_base",{"price":_label("inventory.format.offer_amount",{"amount":str(n),"currency":str(currency)})})
		"percent":
			return _label("ui.format.reference_factor",{"factor":str(n)})
		"delta":
			return _label("ui.format.reference_adjustment",{"amount":("+" if n>0 else "")+str(n),"currency":currency})
	return ""

# Schematic swatches illustrate the public reference text, not a specimen image.
# Only already acquired texture observations may use an observation swatch.
func _texture_swatch(pattern:String)->TextureRect:
	var view:=AppraisalVisuals.texture_control(AppraisalVisuals.texture_sample(pattern))
	view.custom_minimum_size=Vector2(84,56)
	return view

func _reference_comparison(catalog:Dictionary,slot:Dictionary,change:Callable,evidence:Array=[])->void:
	var comparison:Dictionary=ReferenceGuide.comparison(catalog,slot)
	if comparison.is_empty():
		return
	var guidance:=_line(_body,_label(comparison.caption_key))
	if catalog.get("def_id")=="fictional_watch_p2" and slot.get("id")=="material_id":
		# Authored case-grain references are public, not a specimen answer.
		# Any candidate comparison remains an explicit player judgment.
		guidance.name="book_watch_case_reasoning"
		for fact:Dictionary in evidence:
			if fact.get("observation_key")=="case_texture" and fact.get("current",false) and not fact.get("is_claim",true):
				var reading:String=PublicObservationText.fact("case_texture",fact.get("observed_value"),_translator)
				var measured:=_line(_body,_label("book.watch.case.observed_limit",{"reading":reading}))
				measured.name="book_watch_case_observation"
				break
	var row:=HBoxContainer.new()
	row.name=comparison.id
	_body.add_child(row)
	for index:int in range(comparison.entries.size()):
		var entry:Dictionary=comparison.entries[index]
		var column:=VBoxContainer.new()
		column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(column)
		var sample:Control
		match comparison.kind:
			"radio":
				sample=AppraisalVisuals.texture_control(AppraisalVisuals.radio_reference(entry.sample))
				sample.custom_minimum_size=Vector2(100,64)
			"texture":
				sample=_texture_swatch(entry.sample)
			"stamp":
				sample=AppraisalVisuals.mark_transcription(entry.sample)
				sample.custom_minimum_size=Vector2(72,48)
			"wear":
				sample=AppraisalVisuals.texture_control(AppraisalVisuals.wear_reference(entry.sample))
				sample.custom_minimum_size=Vector2(84,56)
			"text":
				# Public comparative statements, not invented specimen images.
				var copy:=Label.new()
				copy.name="reference_comparative_text"
				copy.text=_label(str(entry.sample))
				copy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
				copy.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
				copy.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
				copy.add_theme_color_override("font_color",Color("#302D27"))
				copy.custom_minimum_size=Vector2(84,48)
				sample=copy
		if sample!=null:
			# Open the public example, not a hypothesis. Never dispatch an action.
			var browse:=Button.new()
			browse.name="reference_sample_"+str(slot.candidates[index].id)
			# More of the available paper is used for the comparison illustration.
			browse.custom_minimum_size=Vector2(sample.custom_minimum_size.x,60 if comparison.kind in ["stamp","text"] else 84)
			browse.tooltip_text=_label("book.reference.browse")+" · "+_label(entry.label_key)
			browse.set_meta("reference_entry",index)
			browse.set_meta("reference_page_selected",index==_book_entry)
			for mode:String in ["normal","hover","pressed"]:
				var frame:=StyleBoxFlat.new()
				frame.bg_color=Color("#C6BA9F")
				frame.border_color=Color("#8C795A") if index!=_book_entry and mode=="normal" else Color("#51412B")
				frame.set_border_width_all(3 if index==_book_entry or mode!="normal" else 1)
				browse.add_theme_stylebox_override(mode,frame)
			var epoch:int=_epoch
			browse.pressed.connect(func()->void:
				if epoch==_epoch and index!=_book_entry:
					change.call(index))
			column.add_child(browse)
			browse.add_child(sample)
			sample.custom_minimum_size=Vector2.ZERO
			sample.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			sample.offset_left=4
			sample.offset_top=4
			sample.offset_right=-4
			sample.offset_bottom=-4
			sample.mouse_filter=Control.MOUSE_FILTER_IGNORE
		_line(column,_label(entry.label_key))

# Paper-like draggable reference cards use only scoped public candidate IDs.
# Tapping uses the identical command and validation.
func _paper_style(button:Button)->void:
	for mode:String in ["normal","hover","pressed"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("#d8cdb1") if mode=="normal" else Color("#efe0bd")
		style.border_color=Color("#84785d")
		style.set_border_width_all(2)
		style.content_margin_left=8
		style.content_margin_right=8
		style.content_margin_top=6
		style.content_margin_bottom=6
		button.add_theme_stylebox_override(mode,style)
	for key:String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		button.add_theme_color_override(key,Color("#292d25"))

func _paper_slot(app:Dictionary,slot:Dictionary,selected:Variant,revision:int,locked:bool)->void:
	var epoch:int=_epoch
	var target:=DropTargetScript.new()
	target.name="assessment_slot_"+slot.id
	var chosen:String=_label("ui.copy.unknown_a150fe4")
	for candidate:Dictionary in slot.candidates:
		if selected==candidate.id:
			chosen=_label(candidate.label_key)
	target.text=_label("ui.format.assessment_selection",{"judgment":chosen})
	target.custom_minimum_size.y=56
	target.disabled=locked
	target.accepts=func(data:Variant)->bool:
		return epoch==_epoch and not _presentation_sent and data is Dictionary and data.get("slot_id")==slot.id and _paper_tokens.get(data.get("token",""),{})==data
	target.commit=func(data:Variant)->void:
		if epoch!=_epoch or _presentation_sent:
			return
		_presentation_sent=true
		action_requested.emit("assess_subject",_payload(app,{"slot_id":slot.id,"candidate_id":data.candidate_id}),revision)
	_body.add_child(target)
	var shelf:=HFlowContainer.new()
	_body.add_child(shelf)
	for candidate:Dictionary in slot.candidates:
		var source:=DragSourceScript.new()
		var id:String="pick_"+slot.id+"_"+candidate.id
		source.name=id
		source.text=("✓ " if selected==candidate.id else "")+_label(candidate.label_key)
		source.custom_minimum_size=Vector2(136,64)
		source.disabled=locked or selected==candidate.id
		source.token={"kind":"assessment_card","token":id,"slot_id":slot.id,"candidate_id":candidate.id,"revision":revision,"epoch":epoch,"owner":get_instance_id()}
		_paper_style(source)
		if not source.disabled:
			_paper_tokens[id]=source.token.duplicate(true)
		source.pressed.connect(func()->void:
			if epoch==_epoch and not source.disabled and not _presentation_sent:
				_presentation_sent=true
				action_requested.emit("assess_subject",_payload(app,{"slot_id":slot.id,"candidate_id":candidate.id}),revision))
		shelf.add_child(source)

## Exact equality to a currently enabled prepared card in this panel only.
func _accept_drag(data: Variant) -> bool:
	if _presentation_sent or not data is Dictionary or not data.get("card_id") is String:
		return false
	var token: Dictionary = _drag_tokens.get(data.card_id,{})
	return not token.is_empty() and token == data

func _commit_drag(data: Variant) -> void:
	if not _accept_drag(data):
		return
	_presentation_sent = true
	action_requested.emit("subject_deck_action",{"op":data.op,"visit_id":data.visit_id,"item_id":data.item_id,"slot_id":data.slot_id,"ref_id":data.ref_id},data.revision)

func _show_response(speech: Dictionary) -> void:
	var response: Dictionary = speech.get("customer_response",{})
	if response.is_empty():
		return
	var relation: String = _label("ui.copy.agrees_cb6cdb85") if response.relation == "agrees" else _label("ui.copy.disagrees_430f6fac")
	var label := Label.new()
	label.name = "claim_"+str(response.beat_id)
	label.text = relation+" · "+_label("ui.copy.customer_recollection_unverified_b603fb29")+_label(response.label_key)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)

func _show_rebuttal(speech: Dictionary) -> void:
	var rebuttal: Dictionary = speech.get("rebuttal",{})
	if rebuttal.is_empty():
		return
	var label := Label.new()
	label.name = "rebuttal_"+str(speech.presentation_id)
	label.text = _label("ui.copy.rebuttal_hypothesis_unverified_70f1ad55")+_argument_text(speech.argument)+" / "+_label("ui.copy.against_36877636")+_label(rebuttal.claim_label_key)+" · "+str(rebuttal.new_evidence_ids.size())+_label("ui.copy.new_evidence_links_b00e811b")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)

func _offer_controls(app: Dictionary,revision: int,locked: bool) -> void:
	var offer: Dictionary = app.price_offer
	_line(_body,_label("ui.format.asking_price",{"price":_label("inventory.format.offer_amount",{"amount":str(offer.asking),"currency":str(offer.currency)})}))
	_line(_body,_label("ui.format.remaining_offers",{"count":str(offer.remaining)}))
	for row: Dictionary in offer.offers:
		_line(_body,_label("ui.format.offer_history_row",{"price":_label("inventory.format.offer_amount",{"amount":str(row.amount),"currency":str(row.currency)}),"status":_label("ui.copy.accepted_b23c0c2b") if row.accepted else _label("ui.copy.rejected_a87ae7cd"),"count":str(row.presented_ids.size())}))
	var amount := SpinBox.new()
	amount.name = "price_offer_amount"
	amount.min_value = 1
	amount.max_value = 1000000000
	amount.step = 1
	amount.value = _draft_amount if _draft_amount > 0 else offer.asking
	var draft_epoch: int = _epoch
	amount.value_changed.connect(func(value: float) -> void:
		if draft_epoch == _epoch:
			_draft_amount = int(value))
	amount.editable = not locked and offer.can_offer
	_body.add_child(amount)
	var ids: Array = []
	if _production:
		ids = app.deck.public_basis_ids.duplicate()
	else:
		for speech: Dictionary in app.deck.presented:
			ids.append(speech.presentation_id)
	for include_claims: bool in [false,true]:
		if include_claims and ids.is_empty():
			continue
		var b := Button.new()
		b.name = "price_offer_public" if include_claims else "price_offer_blank"
		b.text = _label("ui.copy.offer_with_public_statements_a1f16ddc") if include_claims else _label("ui.copy.offer_price_only_8752ad1")
		b.disabled = locked or not offer.can_offer
		_body.add_child(b)
		var epoch: int = _epoch
		var refs: Array = ids.duplicate() if include_claims else []
		b.pressed.connect(func() -> void:
			if epoch == _epoch and not b.disabled and not _presentation_sent:
				_presentation_sent = true
				var payload: Dictionary = _payload(app,{"currency":offer.currency,"amount":int(amount.value),"presented_ids":refs})
				if _production:
					payload["basis_version"] = "current_public_v1"
				action_requested.emit("subject_price_offer",payload,revision))

	if _production and not offer.get("quality_option",{}).is_empty():
		var condition: Dictionary = offer.quality_option
		var quality := Button.new()
		quality.name = "price_offer_quality"
		quality.text = _label("ui.format.trade_condition",{"condition":(_label("ui.copy.working_8ec30d03") if condition.observed_value=="serviceable" else _label("ui.copy.inoperable_b9430e79"))})
		quality.disabled = locked or not offer.can_offer
		_body.add_child(quality)
		var quality_epoch: int = _epoch
		quality.pressed.connect(func() -> void:
			if quality_epoch == _epoch and not quality.disabled and not _presentation_sent:
				_presentation_sent = true
				action_requested.emit("subject_price_offer",_payload(app,{"currency":offer.currency,"amount":int(amount.value),"presented_ids":ids.duplicate(),"basis_version":"current_public_v1","quality_evidence_id":condition.evidence_id}),revision))

# The checkout remains a local preview until the existing trade confirmation.
const CheckoutDrag=preload("res://src/presentation/management_drag_cell.gd")

func _page_controls(prefix:String,index:int,total:int,change:Callable,chapters:Array[String]=[],related:Array[int]=[])->void:
	var nav:=HBoxContainer.new()
	_body.add_child(nav)
	var previous:=Button.new()
	previous.name=prefix+"_previous"
	previous.text="‹"
	previous.custom_minimum_size=Vector2(48,48)
	previous.disabled=index<=0
	previous.pressed.connect(func()->void: change.call(index-1))
	nav.add_child(previous)
	# Book chapters jump directly; existing previous/next actions remain.
	# The menu is generated only from public catalog slots, never hidden truth.
	if not chapters.is_empty() and chapters.size()==total:
		var chapter:=OptionButton.new()
		chapter.name=prefix+"_index"
		chapter.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		chapter.custom_minimum_size.y=48
		chapter.fit_to_longest_item=false
		chapter.clip_text=true
		for i:int in range(chapters.size()):
			var copy:String=_label("book.compare.related_chapter",{"chapter":chapters[i]}) if i in related else chapters[i]
			chapter.add_item(str(i+1)+"/"+str(total)+" · "+copy,i)
			if i in related:
				chapter.get_popup().set_item_tooltip(i,_label("book.compare.related_hint"))
		chapter.select(index)
		chapter.tooltip_text=_label("book.compare.related_chapter",{"chapter":chapters[index]})+" · "+_label("book.compare.related_hint") if index in related else chapters[index]
		chapter.set_meta("related_chapters",related.duplicate())
		var epoch:int=_epoch
		chapter.item_selected.connect(func(chosen:int)->void:
			if epoch==_epoch and chosen!=index and chosen>=0 and chosen<total:
				change.call(chosen))
		nav.add_child(chapter)
	else:
		var number:=Label.new()
		number.text=str(index+1)+"/"+str(maxi(1,total))
		number.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		number.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if _paper_book:
			number.add_theme_color_override("font_color",Color("#302D27"))
		nav.add_child(number)
	var next:=Button.new()
	next.name=prefix+"_next"
	next.text="›"
	next.custom_minimum_size=Vector2(48,48)
	next.disabled=index>=total-1
	next.pressed.connect(func()->void: change.call(index+1))
	nav.add_child(next)

# Only the local checkout preview uses the highlighted footprint.
# This never changes inventory, validity, price, action ID or saved state.
func _paint_checkout_preview(tiles:Dictionary,choice:Dictionary,inventory:String,rotated:bool,footprint:Array)->void:
	var selected:bool=not choice.is_empty() and choice.get("inventory","")==inventory and choice.get("rotated",null)==rotated
	var w:int=int(footprint[1]) if rotated else int(footprint[0])
	var h:int=int(footprint[0]) if rotated else int(footprint[1])
	var x0:int=int(choice.get("x",-1))
	var y0:int=int(choice.get("y",-1))
	for point:Vector2i in tiles:
		var tile:Button=tiles[point]
		var covered:bool=selected and point.x>=x0 and point.x<x0+w and point.y>=y0 and point.y<y0+h
		tile.set_meta("checkout_preview_covered",covered)
		var frame:=StyleBoxFlat.new()
		frame.bg_color=Color("#786A4B") if covered else (Color("#344447") if not tile.disabled else Color("#23292B"))
		frame.border_color=Color("#E3D29C") if covered else (Color("#74898A") if not tile.disabled else Color("#485253"))
		frame.set_border_width_all(2 if covered else 1)
		frame.set_corner_radius_all(2)
		for mode:String in ["normal","pressed","hover","focus","disabled"]:
			tile.add_theme_stylebox_override(mode,frame)

func _checkout_controls(app: Dictionary,revision: int,locked: bool,paged:bool=false) -> void:
	var checkout: Dictionary = app.checkout
	var placement_hint:=_line(_body,_label("checkout.place.choose") if paged else _label("ui.copy.choose_stock_location_a32e0265"))
	placement_hint.name="checkout_placement_hint"
	if checkout.has("quality_condition"):
		_line(_body,_label("ui.copy.agreed_trade_condition_ee639037")+(_label("ui.copy.working_8ec30d03") if checkout.quality_condition.observed_value=="serviceable" else _label("ui.copy.inoperable_b9430e79"))+_label("ui.copy.at_transaction_only_c7402a31"))
	_line(_body,_label("ui.format.checkout_balance",{"amount":str(checkout.amount),"balance":str(checkout.balance),"currency":str(checkout.currency)}))
	_line(_body,_label("ui.format.checkout_footprint",{"width":str(checkout.footprint[0]),"height":str(checkout.footprint[1])}))
	var possible: Array = []
	for store: Dictionary in checkout.grids:
		possible.append_array(store.options)
	if _checkout_choice not in possible:
		_checkout_choice.clear()
	var confirm := Button.new()
	confirm.name = "confirm_checkout"
	confirm.text = _label("ui.copy.confirm_purchase_4f429f57")
	confirm.disabled = locked or not checkout.affordable or _checkout_choice.is_empty()
	var epoch: int = _epoch
	var group := ButtonGroup.new()
	var token:Dictionary={"kind":"checkout_item","id":app.item_id,"epoch":epoch,"revision":revision,"owner":get_instance_id()}
	var source:=CheckoutDrag.new()
	source.name="checkout_drag_item"
	source.text=str(app.item_id)+" · "+_label("ui.copy.drag_item_to_stock_a562ce7d")
	source.custom_minimum_size.y=48
	source.disabled=locked
	source.token=token if not locked else {}
	_body.add_child(source)
	var orientations:int=0
	for store:Dictionary in checkout.grids:
		orientations+=store.orientations.size()
	if paged:
		_checkout_page=clampi(_checkout_page,0,maxi(0,orientations-1))
		_page_controls("checkout",_checkout_page,orientations,func(index:int)->void:
			_checkout_page=index
			configure(app,revision,_translator,"ko" if _ko else "en",locked,"production_checkout_paged"))
		confirm.custom_minimum_size.y=48
	var page_index:int=-1
	for store: Dictionary in checkout.grids:
		for rotated: bool in store.orientations:
			page_index+=1
			if paged and page_index!=_checkout_page:
				continue
			_line(_body,(_label("ui.copy.player_owned_stock_632e1d7a") if store.inventory=="player_stock" else str(store.inventory))+(" · "+_label("ui.copy.rotated_809425c0") if rotated else "")).name="checkout_grid_heading"
			var visible_tiles:Dictionary={}
			var cells := GridContainer.new()
			cells.columns = int(store.width)
			_body.add_child(cells)
			for y: int in range(int(store.height)):
				for x: int in range(int(store.width)):
					var candidate: Dictionary = {"inventory":store.inventory,"x":x,"y":y,"rotated":rotated}
					var cell := CheckoutDrag.new()
					cell.name = "place_"+str(store.inventory)+"_"+str(x)+"_"+str(y)+("_r" if rotated else "")
					cell.text = ("·" if candidate in store.options else "×") if paged else (str(x+1)+","+str(y+1) if candidate in store.options else "×")
					if paged:
						cell.tooltip_text=_label("checkout.place.position",{"column":str(x+1),"row":str(y+1)}) if candidate in store.options else _label("ui.copy.no_available_placement_ed72b32b")
					cell.custom_minimum_size = Vector2(32,32)
					cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					cell.toggle_mode = true
					cell.button_group = group
					cell.disabled = locked or candidate not in store.options
					cells.add_child(cell)
					visible_tiles[Vector2i(x,y)]=cell
					cell.set_pressed_no_signal(candidate == _checkout_choice)
					var choose:=func() -> void:
						if epoch != _epoch or cell.disabled or _presentation_sent:
							return
						_checkout_choice = candidate.duplicate(true)
						cell.set_pressed_no_signal(true)
						confirm.disabled = not checkout.affordable
						if paged:
							placement_hint.text=_label("checkout.place.selected")
							_paint_checkout_preview(visible_tiles,_checkout_choice,str(store.inventory),rotated,checkout.footprint)
					cell.pressed.connect(choose)
					cell.accepts=func(data:Variant)->bool:
						return epoch==_epoch and not _presentation_sent and not locked and data is Dictionary and data==token and candidate in possible
					cell.commit=func(_data:Variant)->void:
						choose.call()
			if paged:
				_paint_checkout_preview(visible_tiles,_checkout_choice,str(store.inventory),rotated,checkout.footprint)
				if not _checkout_choice.is_empty() and _checkout_choice.get("inventory","")==store.inventory and _checkout_choice.get("rotated",null)==rotated:
					placement_hint.text=_label("checkout.place.selected")
	if possible.is_empty():
		_line(_body,_label("ui.copy.no_available_placement_ed72b32b"))
	if not checkout.affordable:
		_line(_body,_label("ui.copy.insufficient_funds_e40e5f71"))
	_body.add_child(confirm)
	confirm.pressed.connect(func() -> void:
		if epoch != _epoch or confirm.disabled or _presentation_sent or _checkout_choice not in possible:
			return
		_presentation_sent = true
		var payload: Dictionary = _payload(app,{"seller":checkout.seller,"buyer":checkout.buyer,"currency":checkout.currency,"amount":checkout.amount,"offer_id":checkout.offer_id})
		payload.merge(_checkout_choice)
		action_requested.emit("trade",payload,revision))
