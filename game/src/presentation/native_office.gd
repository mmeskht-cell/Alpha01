extends VBoxContainer
## Opt-in office: public DTO and existing contract commands only.
signal action_requested(kind:String,payload:Dictionary,revision:int)
const HistoryBrowser=preload("res://src/presentation/native_history_browser.gd")
const Art=preload("res://src/presentation/native_v23_art.gd")
var _view:Dictionary={}
var _translate:Callable
var _locale:String="ko"
var _tab:String="ledger"
var _content:Control
var _key:String=""
var _epoch:int=0
var _slot:int=-1
var _ledger_page:int=0
var _ledger_item:String=""

func word(ko:String,en:String)->String:
	return ko if _locale=="ko" else en

func _label(key:String,arguments:Dictionary={})->String:
	if not _translate.is_valid():
		return key
	return str(_translate.call(key)) if arguments.is_empty() else str(_translate.call(key,arguments))

func configure(view:Dictionary,translator:Callable,locale:String,slot:int)->void:
	var key:String=str(slot)+":"+str(view.revision)+":"+locale+":"+str(view.get("locked",true))+":"+str(view.get("locale_epoch",0))
	if key==_key:
		return
	_key=key
	if slot!=_slot:
		_slot=slot
		_ledger_page=0
		_ledger_item=""
	_view=view.duplicate(true)
	_translate=translator
	_locale=locale
	_build()

func _line(parent:Control,caption:String,id:String="")->Label:
	var label:=Label.new()
	if not id.is_empty():
		label.name=id
	label.text=caption
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if parent.has_meta("native_paper"):
		label.add_theme_color_override("font_color",Color("#252A2D"))
	parent.add_child(label)
	return label

func _button(parent:Control,id:String,caption:String,callback:Callable,disabled:bool=false)->Button:
	var b:=Button.new()
	b.name=id
	b.text=caption
	b.custom_minimum_size.y=48
	b.disabled=disabled
	parent.add_child(b)
	var epoch:int=_epoch
	b.pressed.connect(func()->void:
		if epoch==_epoch and not b.disabled and is_visible_in_tree():
			callback.call())
	return b

func _paper(parent:Control,document:bool=false)->VBoxContainer:
	var panel:=PanelContainer.new()
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("#C4C0B2" if document else "#2A3032")
	style.border_color=Color("#716052")
	style.set_border_width_all(2)
	style.content_margin_left=12
	style.content_margin_right=12
	style.content_margin_top=10
	style.content_margin_bottom=10
	panel.add_theme_stylebox_override("panel",style)
	parent.add_child(panel)
	var body:=VBoxContainer.new()
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_child(body)
	if document:
		body.set_meta("native_paper",true)
	return body

func _build()->void:
	_epoch+=1
	for child:Node in get_children():
		remove_child(child)
		child.queue_free()
	# Art and controls remain distinct, with the existing public data on the right.
	var split:=HBoxContainer.new()
	split.size_flags_vertical=Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation",16)
	add_child(split)
	var left:=VBoxContainer.new()
	left.custom_minimum_size.x=320
	left.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio=0.8
	left.add_theme_constant_override("separation",8)
	split.add_child(left)
	var scene:=Art.space_preview("office",_view,Vector2(320,180))
	scene.size_flags_vertical=Control.SIZE_EXPAND_FILL
	left.add_child(scene)
	var heading:=_line(left,_label("ui.copy.shop_office_bf373655"))
	heading.add_theme_font_size_override("font_size",22)
	_line(left,_label("ui.format.office_cash",{"cash":_label("inventory.format.money_pair",{"vkc":str(_view.wallet.VKC),"usd":str(_view.wallet.USD)})}),"office_cash")
	_line(left,_label("ui.copy.closed_work_lamp_c39ab77b") if _view.phase=="workshop" else _label("ui.copy.open_fc52508"))
	var tabs:=VBoxContainer.new()
	left.add_child(tabs)
	for id:String in ["ledger","contracts","news"]:
		var caption:String=_label("ui.copy.ledger_a9dad261") if id=="ledger" else (_label("ui.copy.contracts_8d973b95") if id=="contracts" else _label("ui.copy.terminal_230d7be0"))
		_button(tabs,"office_tab_"+id,caption,func()->void:
			_tab=id
			_ledger_item=""
			_build(),_tab==id)
	var right:=VBoxContainer.new()
	right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio=1.2
	right.size_flags_vertical=Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var title:=_line(right,_label("ui.copy.transaction_ledger_261b8677") if _tab=="ledger" else (_label("ui.copy.contracts_8d973b95") if _tab=="contracts" else _label("ui.copy.local_terminal_896458a8")))
	title.add_theme_font_size_override("font_size",22)
	if _tab=="ledger":
		_ledger(right)
		return
	var scroll:=ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var body:=VBoxContainer.new()
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",12)
	scroll.add_child(body)
	if _tab=="contracts":
		_contracts(body)
	else:
		_news(body)

# The index is a bounded public projection, not a new financial ledger.
# Counts are counts of available per-item records, never summed revenue.
func _ledger(parent:Control)->void:
	var browser:=HistoryBrowser.new()
	browser.name="office_history_browser"
	browser.size_flags_vertical=Control.SIZE_EXPAND_FILL
	parent.add_child(browser)
	# Office rebuilds its children on locale/revision changes. Keep only
	# UI navigation state, never a game record or an authority reference.
	browser._slot=_slot
	browser._ledger_page=_ledger_page
	browser._ledger_item=_ledger_item
	browser.navigation_changed.connect(func(page:int,id:String)->void:
		_ledger_page=page
		_ledger_item=id)
	browser.configure(_view.get("trade_history",{}),_translate,_locale,_slot)
	_ledger_page=browser._ledger_page
	_ledger_item=browser._ledger_item

func _contract_action(parent:Control,id:String,kind:String,caption:String)->void:
	var revision:int=int(_view.revision)
	_button(parent,"office_contract_"+kind.trim_prefix("calendar_").trim_suffix("_contract")+"_"+id,caption,func()->void:
		action_requested.emit(kind,{"contract_id":id},revision))

func _contracts(parent:Control)->void:
	var contracts:Dictionary=_view.get("obligations",{}).get("contracts",{})
	if contracts.is_empty():
		_line(parent,_label("ui.copy.no_known_contracts_2bc9a316"))
	for id:String in contracts:
		var c:Dictionary=contracts[id]
		var panel:=_paper(parent,true)
		var contract_heading:=_line(panel,_label("ui.format.contract_price",{"price":_label("inventory.format.offer_amount",{"amount":str(c.price.VKC),"currency":str("VKC")})}),"office_contract_"+id)
		contract_heading.add_theme_font_size_override("font_size",22)
		# The authored first RAD-1 contract has 18:00 due/delivery deadlines.
		# This is presentation only; other future contracts retain their own terms.
		var hour:String=" 18:00" if id=="rad1_first" else ""
		var deadline:=_line(panel,_label("ui.format.contract_status",{"due":str(c.due_day)+hour,"delivery":str(c.delivery_day)+hour,"status":_label("ui.contract.status."+str(c.status))}))
		deadline.name="office_contract_schedule_"+id
		if _view.phase!="shop" or _view.get("locked",true) or _view.get("complete",false):
			continue
		var actions:=HFlowContainer.new()
		panel.add_child(actions)
		if c.status=="offered":
			_contract_action(actions,id,"calendar_accept_contract",_label("ui.copy.accept_marcus_s_offer_db96d1c3"))
			_contract_action(actions,id,"calendar_decline_contract",_label("ui.copy.decline_ed1fb32f"))
		elif c.status=="reserved":
			_contract_action(actions,id,"calendar_pay_contract",_label("ui.copy.pay_contract_e37ce3dd"))
			if c.get("can_extend",false):
				_contract_action(actions,id,"calendar_extend_contract",_label("ui.copy.extend_7853d8ec"))

func _news(parent:Control)->void:
	var terminal:=_paper(parent)
	var terminal_heading:=_line(terminal,_label("ui.copy.local_terminal_known_news_c72fbad6"),"office_news_heading")
	terminal_heading.add_theme_color_override("font_color",Color("#A0B3BF"))
	terminal_heading.add_theme_font_size_override("font_size",20)
	var news:Array=_view.get("world_news",{}).get("news",[])
	if news.is_empty():
		_line(terminal,_label("ui.copy.no_confirmed_news_3a511909"))
	for n:Dictionary in news:
		_line(terminal,"D"+str(n.day)+" · "+str(n.get(_locale,"")))
	var messages:=_paper(parent)
	_line(messages,_label("ui.copy.messages_ee1edf9b"))
	match int(_view.day):
		1:
			_line(messages,_label("ui.copy.sora_are_you_open_i_sent_someone_your_way_fbc8270b"))
			_line(messages,_label("ui.copy.ian_you_ll_be_all_right_for_a_few_days_but__6be4d982"))
		2:
			_line(messages,_label("ui.copy.sora_more_people_are_looking_for_winter_sup_86c1ac8d"))
		4:
			_line(messages,_label("ui.copy.marcus_payment_reserves_the_supply_you_do_n_403b17a0"))
		7:
			_line(messages,_label("ui.copy.tan_people_do_get_out_who_and_when_that_s_a_35e3682"))
	var facts:Dictionary=_view.get("obligations",{}).get("facts",{})
	if facts.has("clinic_supply_confirmed"):
		_line(messages,_label("ui.copy.ian_thank_you_for_helping_a5e77da9"))
	elif _view.day>=6:
		_line(messages,_label("ui.copy.additional_clinic_supplies_have_not_been_co_4d04311"))
	if facts.has("rad1_delivered"):
		_line(messages,_label("ui.copy.marcus_your_medicine_has_arrived_b406e251"))
	elif facts.has("rad1_defaulted"):
		_line(messages,_label("ui.copy.marcus_this_delivery_did_not_go_through_1d0dcbc8"))
