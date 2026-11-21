extends RefCounted
## Opt-in campaign_42 fixed-quote FX. No minted balances or new item ledger.
## Existing GameSession command receipts and full seeded replay are authority.
const Rules=preload("res://src/domain/value_rules.gd")
const Clock=preload("res://src/domain/business_clock.gd")
const ACTION:String="calendar_exchange"
const VERSION:int=1
const MAX_QUOTES:int=16

static func _valid_quotes(s:Dictionary,policy:Variant,profile:Dictionary)->bool:
	if profile.get("id")!="campaign_42" or not Rules.keys(policy,["version","quotes"]) or policy.version!=VERSION or not policy.quotes is Dictionary or policy.quotes.is_empty() or policy.quotes.size()>MAX_QUOTES:
		return false
	for id:Variant in policy.quotes:
		var q:Variant=policy.quotes[id]
		if not Rules.identifier(id) or not Rules.keys(q,["counterparty","give_currency","give_amount","receive_currency","receive_amount","first_day","last_day"]):
			return false
		if not Rules.identifier(q.counterparty) or q.counterparty=="player" or not s.wallets.has(q.counterparty):
			return false
		if q.give_currency not in ["VKC","USD"] or q.receive_currency not in ["VKC","USD"] or q.give_currency==q.receive_currency:
			return false
		if not Rules.integer(q.give_amount,1,100000000) or not Rules.integer(q.receive_amount,1,100000000) or not Rules.integer(q.first_day,1,42) or not Rules.integer(q.last_day,int(q.first_day),42):
			return false
	return true

static func seed(s:Dictionary,profile:Dictionary)->Dictionary:
	return {"version":VERSION,"settlements":{}} if _valid_quotes(s,profile.get("exchange_market"),profile) else {}

static func apply(s:Dictionary,p:Dictionary,action:String)->String:
	if not s.calendar.has("exchange_market") or not Rules.keys(p,["quote_id"]) or not Rules.identifier(p.quote_id) or not Clock.business_at(int(s.game_minutes),s.phase,false):
		return "exchange_permission"
	if s.calendar.has("queue") and not s.calendar.queue.get("active","").is_empty():
		return "exchange_visit_active"
	var qid:String=p.quote_id
	var quotes:Dictionary=s.calendar.profile.exchange_market.quotes
	if not quotes.has(qid) or s.calendar.exchange_market.settlements.has(qid):
		return "exchange_quote_unavailable"
	var q:Dictionary=quotes[qid]
	var day:int=Clock.day_index(int(s.game_minutes))
	if day<int(q.first_day) or day>int(q.last_day):
		return "exchange_quote_expired"
	var player:Dictionary=s.wallets.player
	var counter:Dictionary=s.wallets[q.counterparty]
	var pay:String=q.give_currency
	var receive:String=q.receive_currency
	var give:int=int(q.give_amount)
	var get:int=int(q.receive_amount)
	if int(player[pay])<give or int(counter[receive])<get:
		return "exchange_insufficient_funds"
	if not Rules.integer(int(counter[pay])+give) or not Rules.integer(int(player[receive])+get):
		return "exchange_capacity"
	player[pay]-=give
	counter[pay]+=give
	counter[receive]-=get
	player[receive]+=get
	s.calendar.exchange_market.settlements[qid]={"action_id":action,"minute":int(s.game_minutes),
		"counterparty":q.counterparty,"give_currency":pay,"give_amount":give,
		"receive_currency":receive,"receive_amount":get}
	return ""

## Only the written public quotes; never expose counterpart balances.
static func view(s:Dictionary)->Dictionary:
	var day:int=Clock.day_index(int(s.game_minutes))
	var quotes:Dictionary=s.calendar.profile.exchange_market.quotes
	var offers:Array=[]
	var ids:Array=quotes.keys()
	ids.sort()
	for id:String in ids:
		if s.calendar.exchange_market.settlements.has(id):
			continue
		var q:Dictionary=quotes[id]
		if day<int(q.first_day) or day>int(q.last_day):
			continue
		offers.append({"quote_id":id,"give_currency":q.give_currency,
			"give_amount":q.give_amount,"receive_currency":q.receive_currency,
			"receive_amount":q.receive_amount})
	return {"quotes":offers,"settled_count":s.calendar.exchange_market.settlements.size()}
