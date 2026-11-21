extends ScrollContainer
const PublicObservationText=preload("res://src/presentation/public_observation_text.gd")
## Public DTO only. Viewing history is never a game command.
const Clock=preload("res://src/domain/business_clock.gd")
var _body: VBoxContainer
var _translator: Callable
var _ko: bool=true
# Opt-in presentation only; legacy viewers retain the historic flat layout.
var native_receipts:bool=false

func _word(ko: String,en: String) -> String:
	return ko if _ko else en

func _line(body: Control,value: String,id: String="") -> Label:
	var label:=Label.new()
	if not id.is_empty():
		label.name=id
	label.text=value
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(label)
	return label

func _receipt(parent:VBoxContainer,id:String)->VBoxContainer:
	if not native_receipts:
		return parent
	var panel:=PanelContainer.new()
	panel.name=id
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var column:=VBoxContainer.new()
	panel.add_child(column)
	return column

func _receipt_detail(parent:VBoxContainer,id:String)->VBoxContainer:
	if not native_receipts:
		return parent
	var toggle:=Button.new()
	toggle.name="history_receipt_toggle_"+id
	toggle.text=_label("history.receipt.open")
	toggle.custom_minimum_size.y=48
	toggle.clip_text=true
	toggle.tooltip_text=toggle.text
	parent.add_child(toggle)
	var detail:=VBoxContainer.new()
	detail.name="history_receipt_detail_"+id
	parent.add_child(detail)
	detail.hide()
	toggle.pressed.connect(func()->void:
		detail.visible=not detail.visible
		toggle.text=_label("history.receipt.close" if detail.visible else "history.receipt.open")
		toggle.tooltip_text=toggle.text)
	return detail

func _label(key:String,arguments:Dictionary={})->String:
	if not _translator.is_valid():
		return key
	return str(_translator.call(key)) if arguments.is_empty() else str(_translator.call(key,arguments))

func configure(index: Dictionary,translator: Callable,locale: String) -> void:
	_translator=translator
	_ko=locale=="ko"
	if is_instance_valid(_body):
		remove_child(_body)
		_body.queue_free()
	_body=VBoxContainer.new()
	_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_body)
	_line(_body,_label("ui.copy.known_transaction_and_work_history_2d7614b9"))
	# A receipt describes the recorded past, never present external condition.
	if native_receipts:
		_line(_body,_label("ui.copy.unrecorded_external_history_and_current_con_5b18354a"),"history_scope_notice")
	if index.get("items",[]).is_empty():
		_line(_body,_label("ui.copy.no_completed_transactions_or_work_d389140d"))
	for item: Dictionary in index.get("items",[]):
		_line(_body,str(item.item_id),"history_item_"+str(item.item_id))
		for row: Dictionary in item.history.records:
			var direction: String=_word("주문 납품","Order fulfilled") if row.get("contract_kind")=="order" else (_label("ui.copy.purchase_974ce25d") if row.direction=="purchase" else _label("ui.copy.sale_1b445528"))
			var price: String=_label("ui.copy.group_price_individual_price_unknown_a66a6e3b")
			if row.amounts!=null:
				price=_label("inventory.format.money_pair",{"vkc":str(row.amounts.VKC),"usd":str(row.amounts.USD)})
			var receipt:=_receipt(_body,"history_receipt_"+str(row.event_id)+"_"+str(item.item_id))
			var headline:=_line(receipt,_label("ui.format.receipt_headline",{"direction":direction,"day":str(Clock.day_index(int(row.minute))),"time":Clock.clock_text(int(row.minute)),"price":price}),"history_trade_"+str(row.event_id)+"_"+str(item.item_id))
			if native_receipts:
				headline.add_theme_color_override("font_color",Color("#C4B28B"))
			var offer: Dictionary=row.get("offer",{})
			var sheet: Dictionary = row.get("appraisal_sheet",{})
			if sheet.is_empty() and offer.is_empty():
				continue
			var detail:=_receipt_detail(receipt,str(row.event_id)+"_"+str(item.item_id))
			if not offer.is_empty():
				# Internal offer IDs remain in the authority and are not product copy.
				var suffix:String="" if native_receipts else " · "+str(offer.offer_id)
				_line(detail,_label("ui.format.accepted_offer",{"price":_label("inventory.format.offer_amount",{"amount":str(offer.amount),"currency":str(offer.currency)})})+suffix,"history_accepted_offer_"+str(row.event_id))
			if not sheet.is_empty():
				_line(detail,_label("ui.copy.transaction_appraisal_sheet_public_assessme_7cf0b256"),"history_appraisal_"+str(row.event_id))
				if sheet.statements.is_empty():
					_line(detail,_label("ui.copy.no_disclosed_assessments_f225e2f2"))
				if sheet.has("quality_condition"):
					var condition: Dictionary = sheet.quality_condition
					_line(detail,_label("ui.format.receipt_condition",{"condition":_label("ui.copy.working_8ec30d03") if condition.observed_value=="serviceable" else _label("ui.copy.inoperable_b9430e79")}))
				else:
					_line(detail,_label("ui.copy.no_separate_quality_commitment_6843d1f"))
			var accepted_ids:Array=[]
			for accepted:Dictionary in offer.get("presentations",[]):
				accepted_ids.append(accepted.presentation_id)
			var statements: Array = offer.get("presentations",[]) if sheet.is_empty() else sheet.statements
			for speech: Dictionary in statements:
				var statement_key:String="history.statement.hypothesis"
				if speech.has("withdraws_presentation_id"):
					statement_key="history.statement.withdrawal"
				elif not sheet.is_empty():
					statement_key="history.statement.superseded_hypothesis" if speech.presentation_id not in sheet.current_ids else ("history.statement.corrected_hypothesis" if speech.has("corrects_presentation_id") else statement_key)
				if speech.argument.get("statement_kind")=="observation" and not speech.has("withdraws_presentation_id"):
					statement_key="history.statement.superseded_observation" if not sheet.is_empty() and speech.presentation_id not in sheet.current_ids else "history.statement.disclosure"
				var statement_text:String=_label(statement_key,{"statement":_argument_text(speech.argument)})
				var accepted_basis:bool=speech.presentation_id in accepted_ids
				if accepted_basis:
					statement_text=_label("history.statement.accepted_basis",{"statement":statement_text})
				var statement_line:=_line(detail,statement_text,"history_statement_"+str(speech.presentation_id))
				statement_line.set_meta("statement_key",statement_key)
				statement_line.set_meta("accepted_basis",accepted_basis)
				var response: Dictionary=speech.get("customer_response",{})
				if not response.is_empty():
					_line(detail,_label("ui.format.receipt_customer_claim",{"claim":_label(response.label_key)}))
				if speech.has("rebuttal"):
					_line(detail,_label("ui.format.receipt_rebuttal",{"claim":_label(speech.rebuttal.claim_label_key)}))
			var facts: Array = offer.get("observations",[]) if sheet.is_empty() else sheet.observations
			for fact: Dictionary in facts:
				_line(detail,_label("ui.format.receipt_observation",{"reading":PublicObservationText.fact(str(fact.observation_key),fact.observed_value,_translator)}),"history_evidence_"+str(row.event_id)+"_"+str(fact.evidence_id))
		for contract:Dictionary in item.history.get("contract_records",[]):
			var name:String=""
			match str(contract.kind):
				"pawn_loan": name=_word("담보 대출금 지급","Pawn loan paid")
				"pawn_repayment": name=_word("고객 상환·담보 반환","Loan repaid, collateral returned")
				"pawn_forfeit": name=_word("미상환 담보 귀속","Unredeemed collateral forfeited")
				"pawn_extension": name=_word("담보 기한 유예·수수료","Pawn extension fee")
			if name.is_empty():
				continue
			var amount_text:String=_word("현물 귀속, 추가 현금 수입 없음","Asset forfeit; no additional cash") if contract.kind=="pawn_forfeit" else _money(contract.amounts)
			var receipt:=_receipt(_body,"history_contract_receipt_"+str(contract.event_id)+"_"+str(item.item_id))
			_line(receipt,"D"+str(Clock.day_index(int(contract.minute)))+" "+Clock.clock_text(int(contract.minute))+
				" · "+name+" · "+amount_text,"history_contract_"+str(contract.event_id)+"_"+str(item.item_id))
		for work: Dictionary in item.history.get("work_records",[]):
			_show_work(work,str(item.item_id))
		if item.history.get("work_omitted",0)>0:
			_line(_body,_label("ui.format.older_work",{"count":str(item.history.work_omitted)}))
		if item.history.omitted>0:
			_line(_body,_label("ui.format.older_transactions",{"count":str(item.history.omitted)}))
	if index.get("omitted",0)>0:
		_line(_body,_label("ui.format.older_items",{"count":str(index.omitted)}))
	if not native_receipts:
		_line(_body,_label("ui.copy.unrecorded_external_history_and_current_con_5b18354a"))

func _argument_text(arg: Dictionary)->String:
	if arg.get("statement_kind")=="observation":
		return _label("ui.format.observed_fact",{"reading":PublicObservationText.fact(str(arg.label_key),arg.observed_value,_translator)})
	return _label(arg.label_key)

func _money(value: Dictionary) -> String:
	return _label("inventory.format.money_pair",{"vkc":str(value.VKC if value.VKC!=null else "—"),"usd":str(value.USD if value.USD!=null else "—")})

func _show_work(row: Dictionary,item_id: String) -> void:
	var description: String = ""
	match row.kind:
		"attach","detach":
			description=_label("ui.copy.assembly_d235871e") if row.kind=="attach" else _label("ui.copy.disassembly_95945c61")
			description=_label("history.work.relation",{"operation":description,"role":_label("ui.copy.root_49448c67") if row.role=="root" else _label("ui.copy.component_411f045"),"item":str(row.related_item_id)})
		"replace_component":
			description=_label("ui.format.history_exchange",{"root":str(row.root_id),"outgoing":str(row.old_child_id),"incoming":str(row.child_id)})
		"clean_exterior":
			description=_label("ui.copy.exterior_care_no_function_or_value_bonus_2aeb08c4")
		"restore_item":
			description=_label("ui.format.maintenance_expense",{"cost":_money(row.expense)})
		"discard":
			description=_label("ui.format.disposal_loss",{"loss":_money(row.loss)}) if row.loss!=null else _label("ui.copy.group_disposal_individual_loss_unknown_3fefe596")
	var receipt:=_receipt(_body,"history_work_receipt_"+str(row.event_id)+"_"+item_id)
	_line(receipt,_label("ui.format.work_record",{"revision":str(row.revision),"description":description}),"history_work_"+row.event_id+"_"+item_id)
