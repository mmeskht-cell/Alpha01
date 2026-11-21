extends SceneTree
const Trace = preload("res://src/domain/world_causal_trace.gd")
const Rules = preload("res://src/domain/value_rules.gd")
var checks:int=0
var failures:int=0

func check(ok:bool, label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func _receipt(command:Dictionary,revision:int)->Dictionary:
	return {"fingerprint":Rules.canonical(command),"result":{"ok":true,"revision":revision}}

func _fixture()->Dictionary:
	var trade:Dictionary={"action_id":"paid_one","expected_revision":0,"type":"trade","payload":{"visit_id":"V01","item_id":"R001"}}
	var opening:Dictionary={"action_id":"day_two","expected_revision":1,"type":"calendar_morning","payload":{}}
	var money:Dictionary={"VKC":100,"USD":0}
	return {
		"wallets":{"player":money,"G02":money,"G03":money},
		"ledger":[{"event_id":"paid_one","visit_id":"V01","revision":1,"from":"G02","to":"player","game_minutes":40,"item_ids":["R001"]}],
		"receipts":{"paid_one":_receipt(trade,1),"day_two":_receipt(opening,2)},
		"receipt_archive":{},
		"calendar":{"commands":[trade,opening],"reaction":{"events":{
			"clinic_d2":{"day":2,"external_event":"clinic_supply_disruption","cause":"paid_one","opening_action":"day_two","result":"limited_service"}
		}}}
	}

func _initialize()->void:
	var s:Dictionary=_fixture()
	var initial:Dictionary=s.duplicate(true)
	check(Trace.trade_for_visit(s,"V01").get("event_id")=="paid_one","actual paid receipt is indexed")
	check(Trace.trade_for_visit(s,"V99").is_empty(),"no projected deal without a receipt")
	var memory:Dictionary=Trace.customer_memory(s,"G02")
	check(memory.get("trades")==1 and memory.get("last_day")==1 and memory.get("last_direction")=="customer_bought","customer firsthand paid history")
	check(Trace.customer_memory(s,"G03").is_empty() and Trace.customer_memory(s,"player").is_empty(),"no unrelated or player memory")
	check(Trace.customer_memory(s,"G99").is_empty(),"unknown entity stays private")
	var public:Array=Trace.public_events(s)
	check(public.size()==1 and public[0].player_contribution and public[0].cause_refs==["clinic_supply_disruption","paid_one"],"world report trace has real cause and independent disruption")
	check(s==initial,"read-model queries do not mutate authority")
	var altered:Dictionary=s.duplicate(true)
	altered.receipts.paid_one.fingerprint="forged"
	check(Trace.trade_for_visit(altered,"V01").is_empty() and Trace.customer_memory(altered,"G02").is_empty(),"tampered receipt cannot produce customer history")
	check(Trace.public_events(altered).is_empty(),"tampered paid receipt cannot become world aid")
	altered=s.duplicate(true)
	altered.calendar.reaction.events.clinic_d2.cause=""
	altered.calendar.reaction.events.clinic_d2.result="interrupted"
	public=Trace.public_events(altered)
	check(public.size()==1 and not public[0].player_contribution and public[0].cause_refs==["clinic_supply_disruption"],"independent disruption is not attributed to player")
	altered=s.duplicate(true)
	altered.receipts.day_two.fingerprint="forged"
	check(Trace.public_events(altered).is_empty(),"unverified opening never publishes an event")
	altered=s.duplicate(true)
	altered.ledger[0].from="G03"
	check(Trace.customer_memory(altered,"G02").is_empty(),"other actor cannot inherit a trade")
	altered=s.duplicate(true)
	altered.ledger.clear()
	check(Trace.trade_for_visit(altered,"V01").is_empty() and Trace.public_events(altered).is_empty(),"orphan receipt is not a completed trade")
	print("WORLD_CAUSAL_TRACE: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
