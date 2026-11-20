extends VBoxContainer
## Shared native history index; no game commands, no persistent game state.
const History=preload("res://src/presentation/generic_trade_history.gd")
const LEDGER_PAGE_SIZE:int=3
signal navigation_changed(page:int,item_id:String)
var _index:Dictionary={}
var _translate:Callable
var _locale:String="ko"
var _epoch:int=0
var _slot:int=-1
var _ledger_page:int=0
var _ledger_item:String=""

func configure(index:Dictionary,translator:Callable,locale:String,slot:int)->void:
	if slot!=_slot:
		_slot=slot
		_ledger_page=0
		_ledger_item=""
	_index=index.duplicate(true)
	_translate=translator
	_locale=locale
	_build()

func _navigate()->void:
	_build()
	navigation_changed.emit(_ledger_page,_ledger_item)

func _build()->void:
	_epoch+=1
	for child:Node in get_children():
		remove_child(child)
		child.queue_free()
	_ledger(self)

func _label(key:String,arguments:Dictionary={})->String:
	if not _translate.is_valid():
		return key
	return str(_translate.call(key)) if arguments.is_empty() else str(_translate.call(key,arguments))

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

func _ledger(parent:Control)->void:
	var index:Dictionary=_index
	var items:Array=index.get("items",[])
	var selected:Dictionary={}
	for item:Dictionary in items:
		if str(item.item_id)==_ledger_item:
			selected=item
			break
	if not selected.is_empty():
		var bar:=HBoxContainer.new()
		bar.name="office_ledger_detail_header"
		parent.add_child(bar)
		var back:=_button(bar,"office_ledger_back",_label("menu.back"),func()->void:
			_ledger_item=""
			_navigate())
		back.custom_minimum_size.x=48
		var heading:=_line(bar,_ledger_item)
		heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		heading.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		var history:=History.new()
		history.name="office_ledger"
		history.native_receipts=true
		history.size_flags_vertical=Control.SIZE_EXPAND_FILL
		var frame:=PanelContainer.new()
		frame.size_flags_vertical=Control.SIZE_EXPAND_FILL
		parent.add_child(frame)
		frame.add_child(history)
		# Keep every transaction, disclosure, work record and omitted-record
		# notice for this item. Optional long reading remains scrollable.
		history.configure({"items":[selected],"omitted":0},_translate,_locale)
		return
	_ledger_item=""
	var summary:=VBoxContainer.new()
	summary.name="office_ledger_summary"
	summary.size_flags_vertical=Control.SIZE_EXPAND_FILL
	parent.add_child(summary)
	_line(summary,_label("history.summary.select"))
	if items.is_empty():
		_ledger_page=0
		_line(summary,_label("ui.copy.no_completed_transactions_or_work_d389140d"))
		return
	var pages:int=maxi(1,ceili(float(items.size())/LEDGER_PAGE_SIZE))
	_ledger_page=clampi(_ledger_page,0,pages-1)
	var nav:=HBoxContainer.new()
	nav.name="office_ledger_navigation"
	summary.add_child(nav)
	var previous:=_button(nav,"office_ledger_previous","‹",func()->void:
		_ledger_page-=1
		_navigate(),_ledger_page==0)
	previous.custom_minimum_size.x=48
	previous.tooltip_text=_label("history.summary.previous")
	var counter:=_line(nav,str(_ledger_page+1)+" / "+str(pages))
	counter.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	counter.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	counter.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var next:=_button(nav,"office_ledger_next","›",func()->void:
		_ledger_page+=1
		_navigate(),_ledger_page+1>=pages)
	next.custom_minimum_size.x=48
	next.tooltip_text=_label("history.summary.next")
	for i:int in range(_ledger_page*LEDGER_PAGE_SIZE,mini(items.size(),(_ledger_page+1)*LEDGER_PAGE_SIZE)):
		var item:Dictionary=items[i]
		var identity:String=str(item.item_id)
		var history:Dictionary=item.history
		var caption:String=_label("ui.format.history_summary",{"item":identity,"trades":str(history.get("records",[]).size()),"work":str(history.get("work_records",[]).size())})
		var entry:=_button(summary,"history_item_"+identity,caption,func()->void:
			_ledger_item=identity
			_navigate())
		entry.clip_text=true
		entry.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		entry.tooltip_text=caption
		entry.alignment=HORIZONTAL_ALIGNMENT_LEFT
		entry.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if index.get("omitted",0)>0:
		_line(summary,_label("ui.format.older_items",{"count":str(index.omitted)}))
	_line(summary,_label("history.summary.recorded_only"))

