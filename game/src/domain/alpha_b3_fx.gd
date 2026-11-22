extends RefCounted
## B3 opt-in exchange: the already-authored 42-day mechanics broker quote,
## 30 VKC for 1 USD, transferred through real source-bound actor wallets.
## No free FX credit, random rate, double settlement or new item is created.
const Rules=preload("res://src/domain/value_rules.gd")
const PATH: String = "res://data/alpha_b3/fx_m3.json"
const VERSION: String = "b3-finite-market-fx-m3"

static func config() -> Dictionary:
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not Rules.keys(raw,["version","source_profile","visit_id","day","quote_id","counterparty","give_currency","give_amount","receive_currency","receive_amount"]):
		return {}
	if raw.version!=1 or raw.source_profile!="alpha42_mechanics" or raw.visit_id!="alpha_b3_fx_broker_d7" or raw.day!=7 or raw.quote_id!="alpha_broker_quote" or raw.counterparty!="alpha_broker":
		return {}
	if raw.give_currency!="VKC" or raw.give_amount!=30 or raw.receive_currency!="USD" or raw.receive_amount!=1:
		return {}
	return raw

static func profile_valid(profile: Dictionary, state: Dictionary) -> bool:
	var c: Dictionary=config()
	if c.is_empty() or str(profile.get("content_version",""))!=VERSION or not profile.has("fx_profile") or Rules.canonical(profile.fx_profile)!=Rules.canonical(c):
		return false
	if not state.wallets.has(c.counterparty) or not state.inventories.has(c.counterparty+"_grid") or state.inventories[c.counterparty+"_grid"].owner_id!=c.counterparty:
		return false
	if not Rules.integer(int(state.wallets[c.counterparty].get(c.receive_currency, -1)),int(c.receive_amount),100000000):
		return false
	if not Rules.integer(int(state.wallets.player.get(c.give_currency, -1)),int(c.give_amount),100000000):
		return false
	if profile.days.size()!=7:
		return false
	var count: int=0
	for row: Dictionary in profile.days[int(c.day)-1]:
		if row.id==c.visit_id and row.actor_id==c.counterparty and row.kind=="named" and row.purpose_key=="b3.fx.visit" and row.contact_offer==false:
			count+=1
	return count==1

static func seed() -> Dictionary:
	return {"version":1,"settlements":{}}

static func apply(state: Dictionary, command: Dictionary) -> String:
	if not state.alpha_shop.has("fx") or not Rules.keys(command.payload,["quote_id"]) or not Rules.identifier(command.payload.quote_id):
		return "b3_fx_command_shape"
	var a: Dictionary=state.alpha_shop
	var c: Dictionary=a.profile.fx_profile
	if a.phase!="CUSTOMER_ACTIVE" or a.day!=c.day or a.active!=c.visit_id or command.payload.quote_id!=c.quote_id:
		return "b3_fx_counter_context"
	if a.fx.settlements.has(c.quote_id):
		return "b3_fx_already_settled"
	var client: Dictionary=state.wallets.player
	var broker: Dictionary=state.wallets[c.counterparty]
	if int(client[c.give_currency])<int(c.give_amount) or int(broker[c.receive_currency])<int(c.receive_amount):
		return "b3_fx_insufficient_money"
	if not Rules.integer(int(client[c.receive_currency])+int(c.receive_amount)) or not Rules.integer(int(broker[c.give_currency])+int(c.give_amount)):
		return "b3_fx_overflow"
	client[c.give_currency]-=int(c.give_amount)
	broker[c.give_currency]+=int(c.give_amount)
	broker[c.receive_currency]-=int(c.receive_amount)
	client[c.receive_currency]+=int(c.receive_amount)
	a.fx.settlements[c.quote_id]={"event_id":command.action_id,"day":a.day,
		"counterparty":c.counterparty,"give_currency":c.give_currency,"give_amount":c.give_amount,
		"receive_currency":c.receive_currency,"receive_amount":c.receive_amount}
	return ""

static func view(state: Dictionary) -> Dictionary:
	var a: Dictionary=state.alpha_shop
	if not a.has("fx"):
		return {}
	var c: Dictionary=a.profile.fx_profile
	var done: bool=a.fx.settlements.has(c.quote_id)
	var allowed: bool=a.phase=="CUSTOMER_ACTIVE" and a.day==c.day and a.active==c.visit_id and not done
	var funded: bool=int(state.wallets.player[c.give_currency])>=int(c.give_amount) and int(state.wallets[c.counterparty][c.receive_currency])>=int(c.receive_amount)
	return {"quote_id":c.quote_id,"counterparty":c.counterparty,
		"give_currency":c.give_currency,"give_amount":c.give_amount,
		"receive_currency":c.receive_currency,"receive_amount":c.receive_amount,
		"at_counter":a.phase=="CUSTOMER_ACTIVE" and a.active==c.visit_id,
		"can_exchange":allowed and funded,"funded":funded,"settled":done}
