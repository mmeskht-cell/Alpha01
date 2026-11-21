extends RefCounted
## Finite opt-in campaign merchant obligations, with real item custody,
## escrow and currency conservation. Candidate state is committed only through
## GameSession's authoritative save/replay/geometry validation.
const Rules=preload("res://src/domain/value_rules.gd")
const Clock=preload("res://src/domain/business_clock.gd")
const Objects=preload("res://src/domain/object_schema.gd")
const Relations=preload("res://src/domain/object_relation_primitives.gd")
const Items=preload("res://src/domain/item_primitives.gd")
const ACTIONS:Array=["merchant_pawn_accept","merchant_pawn_redeem",
	"merchant_order_accept","merchant_order_deliver","merchant_order_cancel"]
const VERSION:int=1
const MAX_PAWNS:int=16
const MAX_ORDERS:int=16

static func _money(value:Variant)->bool:
	return Objects.money(value,false) and (int(value.VKC)>0 or int(value.USD)>0) and (int(value.VKC)==0 or int(value.USD)==0)

static func _good_family(s:Dictionary,defs:Dictionary,root:String,owner:String)->bool:
	if not s.items.has(root) or s.items[root].get("parent_id","")!="":
		return false
	var item:Dictionary=s.items[root]
	if item.owner_id!=owner or item.custodian_id!=owner or item.status!="stock" or item.protected or not item.reservation_id.is_empty() or item.service_permission:
		return false
	for id:String in Objects.family(s,root):
		var row:Dictionary=s.items[id]
		if row.owner_id!=owner or row.custodian_id!=owner or row.status!="stock" or row.protected or not row.reservation_id.is_empty() or row.service_permission or not defs.has(row.def_id) or not defs[row.def_id].inside.is_empty():
			return false
	return Objects.complete(s,defs,root)

static func _policy(s:Dictionary)->Dictionary:
	return s.calendar.profile.merchant_contracts

static func _funds(s:Dictionary,payer:String,receiver:String,amount:Dictionary)->bool:
	for c:String in ["VKC","USD"]:
		if int(s.wallets[payer][c])<int(amount[c]) or not Rules.integer(int(s.wallets[receiver][c])+int(amount[c])):
			return false
	return true

static func _send(s:Dictionary,payer:String,receiver:String,amount:Dictionary)->void:
	for c:String in ["VKC","USD"]:
		s.wallets[payer][c]-=int(amount[c])
		s.wallets[receiver][c]+=int(amount[c])

static func _event(s:Dictionary,id:String,kind:String,action:String,item_id:String,amount:Dictionary)->void:
	s.calendar.merchant_contracts.events.append({"contract_id":id,"kind":kind,"action_id":action,
		"minute":int(s.game_minutes),"item_id":item_id,"amount":amount.duplicate(true)})

static func _pawn_policy(s:Dictionary,defs:Dictionary,id:String,p:Dictionary)->bool:
	if not Rules.identifier(id) or not Rules.keys(p,["customer","visit_id","item_id","principal","repayment","due_day","placement"]):
		return false
	if not Rules.identifier(p.customer) or p.customer=="player" or not s.wallets.has(p.customer) or not Rules.identifier(p.visit_id) or not Rules.identifier(p.item_id):
		return false
	var visit:Dictionary=s.visits.get(p.visit_id,{})
	if visit.is_empty() or visit.scope.get("kind")!="ordinary" or visit.seller!=p.customer or visit.buyer!="player" or not visit.prices.has(p.item_id):
		return false
	if not _money(p.principal) or not _money(p.repayment):
		return false
	if (int(p.principal.VKC)>0)!=(int(p.repayment.VKC)>0) or (int(p.principal.USD)>0)!=(int(p.repayment.USD)>0):
		return false
	if int(p.repayment.VKC)<int(p.principal.VKC) or int(p.repayment.USD)<int(p.principal.USD):
		return false
	var first_day:int=Clock.day_index(int(visit.opens))
	if not Rules.integer(p.due_day,first_day,42):
		return false
	if not _good_family(s,defs,p.item_id,p.customer):
		return false
	if not Rules.keys(p.placement,["inventory","x","y","rotated"]) or not Objects.destination_accessible(s,p.placement.inventory,p.customer,"player") or not Rules.integer(p.placement.x,0,9) or not Rules.integer(p.placement.y,0,9) or not p.placement.rotated is bool:
		return false
	return s.inventories[p.placement.inventory].host_item==""

static func _order_policy(s:Dictionary,defs:Dictionary,id:String,p:Dictionary)->bool:
	if not Rules.identifier(id) or not Rules.keys(p,["customer","def_id","price","offer_day","due_day"]):
		return false
	if not Rules.identifier(p.customer) or p.customer=="player" or not s.wallets.has(p.customer) or not Rules.identifier(p.def_id) or not defs.has(p.def_id) or not _money(p.price):
		return false
	return Rules.integer(p.offer_day,1,42) and Rules.integer(p.due_day,int(p.offer_day),42)

static func seed(s:Dictionary,defs:Dictionary,profile:Dictionary)->Dictionary:
	var m:Variant=profile.get("merchant_contracts")
	if profile.get("id")!="campaign_42" or not Rules.keys(m,["version","escrow_actor","pawns","orders"]) or m.version!=VERSION or not Rules.identifier(m.escrow_actor) or m.escrow_actor=="player" or not s.wallets.has(m.escrow_actor) or not m.pawns is Dictionary or not m.orders is Dictionary or m.pawns.size()>MAX_PAWNS or m.orders.size()>MAX_ORDERS or (m.pawns.is_empty() and m.orders.is_empty()):
		return {}
	if s.wallets[m.escrow_actor]!={"VKC":0,"USD":0}:
		return {}
	for item:Dictionary in s.items.values():
		if item.owner_id==m.escrow_actor or item.custodian_id==m.escrow_actor:
			return {}
	for visit:Dictionary in s.visits.values():
		if visit.seller==m.escrow_actor or visit.buyer==m.escrow_actor:
			return {}
	var seen_items:Dictionary={}
	var result:Dictionary={"version":VERSION,"pawns":{},"orders":{},"events":[]}
	for id:String in m.pawns:
		var pawn:Dictionary=m.pawns[id]
		if not _pawn_policy(s,defs,id,pawn) or seen_items.has(pawn.item_id):
			return {}
		seen_items[pawn.item_id]=true
		result.pawns[id]={"status":"offered","original":{},"open_action":"","close_action":""}
	for id:String in m.orders:
		var order:Dictionary=m.orders[id]
		if m.pawns.has(id) or not _order_policy(s,defs,id,order):
			return {}
		result.orders[id]={"status":"offered","open_action":"","close_action":"","item_id":""}
	return result

static func _pawn_forfeit(s:Dictionary,defs:Dictionary,id:String,action:String)->void:
	var t:Dictionary=_policy(s).pawns[id]
	var row:Dictionary=s.calendar.merchant_contracts.pawns[id]
	var root:String=t.item_id
	var ids:Array=Objects.family(s,root)
	var weights:Dictionary={}
	for item_id:String in ids:
		weights[item_id]=defs[s.items[item_id].def_id].weight
	var cost:Dictionary={}
	for currency:String in ["VKC","USD"]:
		cost[currency]=Items.allocate_cost(int(t.principal[currency]),weights)
	# Previous custody is already in the player's physical grid.
	for item_id:String in ids:
		var item:Dictionary=s.items[item_id]
		item.owner_id="player"
		item.custodian_id="player"
		item.status="stock"
		item.version+=1
		for currency:String in ["VKC","USD"]:
			item.basis[currency]=cost[currency].get(item_id,0)
	row.status="forfeited"
	row.close_action=action
	_event(s,id,"pawn_forfeit",action,root,{"VKC":0,"USD":0})

static func close(s:Dictionary,defs:Dictionary,action:String)->void:
	var day:int=Clock.day_index(int(s.game_minutes))
	var rows:Dictionary=s.calendar.merchant_contracts
	for id:String in rows.pawns:
		if rows.pawns[id].status=="pledged" and _policy(s).pawns[id].due_day==day:
			_pawn_forfeit(s,defs,id,action)
		elif rows.pawns[id].status=="offered":
			var t:Dictionary=_policy(s).pawns[id]
			if Clock.day_index(int(s.visits[t.visit_id].opens))==day:
				rows.pawns[id].status="missed"
				rows.pawns[id].close_action=action
	for id:String in rows.orders:
		var t:Dictionary=_policy(s).orders[id]
		var row:Dictionary=rows.orders[id]
		if row.status=="accepted" and t.due_day==day:
			_send(s,_policy(s).escrow_actor,t.customer,t.price)
			row.status="expired"
			row.close_action=action
			_event(s,id,"order_refund_expiry",action,"",t.price)
		elif row.status=="offered" and t.offer_day==day:
			row.status="missed"
			row.close_action=action

static func apply(s:Dictionary,defs:Dictionary,kind:String,p:Dictionary,action:String)->String:
	if not s.calendar.has("merchant_contracts") or not Clock.business_at(int(s.game_minutes),s.phase,false):
		return "merchant_permission"
	if not Rules.keys(p,["contract_id"]) or not Rules.identifier(p.contract_id):
		if kind!="merchant_order_deliver" or not Rules.keys(p,["contract_id","item_id","placement"]) or not Rules.identifier(p.contract_id):
			return "merchant_shape"
	var id:String=p.contract_id
	var rows:Dictionary=s.calendar.merchant_contracts
	var pol:Dictionary=_policy(s)
	var day:int=Clock.day_index(int(s.game_minutes))
	if kind=="merchant_pawn_accept":
		if not rows.pawns.has(id) or rows.pawns[id].status!="offered":
			return "pawn_not_offered"
		var t:Dictionary=pol.pawns[id]
		if s.calendar.queue.active!=t.visit_id or not _good_family(s,defs,t.item_id,t.customer) or not _funds(s,"player",t.customer,t.principal):
			return "pawn_permission_or_funds"
		var root:Dictionary=s.items[t.item_id]
		rows.pawns[id].original={"inventory":root.inventory,"x":root.x,"y":root.y,"rotated":root.rotated}
		var family:Array=Objects.family(s,t.item_id)
		for item_id:String in family:
			s.items[item_id].custodian_id="player"
			s.items[item_id].status="custody_pawn"
			s.items[item_id].version+=1
		for key:String in t.placement:
			root[key]=t.placement[key]
		_send(s,"player",t.customer,t.principal)
		rows.pawns[id].status="pledged"
		rows.pawns[id].open_action=action
		_event(s,id,"pawn_loan",action,t.item_id,t.principal)
		s.calendar.queue.outcomes[t.visit_id]="pawned"
		s.calendar.queue.active=""
		return ""
	if kind=="merchant_pawn_redeem":
		if not rows.pawns.has(id) or rows.pawns[id].status!="pledged":
			return "pawn_not_held"
		var t:Dictionary=pol.pawns[id]
		if day>int(t.due_day) or (s.calendar.has("queue") and not s.calendar.queue.active.is_empty()) or not _funds(s,t.customer,"player",t.repayment):
			return "pawn_redeem_funds_or_time"
		var original:Dictionary=rows.pawns[id].original
		if not Objects.destination_accessible(s,original.inventory,t.customer,t.customer):
			return "pawn_return_inventory"
		for item_id:String in Objects.family(s,t.item_id):
			var row:Dictionary=s.items[item_id]
			if row.owner_id!=t.customer or row.custodian_id!="player" or row.status!="custody_pawn":
				return "pawn_custody_changed"
			row.custodian_id=t.customer
			row.status="stock"
			row.version+=1
		for key:String in original:
			s.items[t.item_id][key]=original[key]
		_send(s,t.customer,"player",t.repayment)
		rows.pawns[id].status="redeemed"
		rows.pawns[id].close_action=action
		_event(s,id,"pawn_repayment",action,t.item_id,t.repayment)
		return ""
	if kind=="merchant_order_accept":
		if not rows.orders.has(id) or rows.orders[id].status!="offered":
			return "order_not_offered"
		var t:Dictionary=pol.orders[id]
		if day!=int(t.offer_day) or (s.calendar.has("queue") and not s.calendar.queue.active.is_empty()) or not _funds(s,t.customer,pol.escrow_actor,t.price):
			return "order_offer_or_liquidity"
		_send(s,t.customer,pol.escrow_actor,t.price)
		rows.orders[id].status="accepted"
		rows.orders[id].open_action=action
		_event(s,id,"order_escrow",action,"",t.price)
		return ""
	if kind=="merchant_order_cancel":
		if not rows.orders.has(id) or rows.orders[id].status!="accepted":
			return "order_not_accepted"
		var t:Dictionary=pol.orders[id]
		if not _funds(s,pol.escrow_actor,t.customer,t.price):
			return "order_escrow_broken"
		_send(s,pol.escrow_actor,t.customer,t.price)
		rows.orders[id].status="cancelled"
		rows.orders[id].close_action=action
		_event(s,id,"order_refund",action,"",t.price)
		return ""
	if kind=="merchant_order_deliver":
		if not rows.orders.has(id) or rows.orders[id].status!="accepted" or not Rules.keys(p,["contract_id","item_id","placement"]) or not Rules.identifier(p.item_id):
			return "order_delivery_shape"
		var t:Dictionary=pol.orders[id]
		if day>int(t.due_day) or (s.calendar.has("queue") and not s.calendar.queue.active.is_empty()) or not s.items.has(p.item_id):
			return "order_delivery_unavailable"
		var root:Dictionary=s.items[p.item_id]
		if root.def_id!=t.def_id or not _good_family(s,defs,p.item_id,"player") or not Rules.keys(p.placement,["inventory","x","y","rotated"]) or not Objects.destination_accessible(s,p.placement.inventory,"player",t.customer) or not Rules.integer(p.placement.x,0,9) or not Rules.integer(p.placement.y,0,9) or not p.placement.rotated is bool:
			return "order_item_or_placement"
		if not _funds(s,pol.escrow_actor,"player",t.price):
			return "order_escrow_broken"
		var items:Array=Objects.family(s,p.item_id)
		for item_id:String in items:
			s.items[item_id].owner_id=t.customer
			s.items[item_id].custodian_id=t.customer
			s.items[item_id].version+=1
		for key:String in p.placement:
			root[key]=p.placement[key]
		_send(s,pol.escrow_actor,"player",t.price)
		rows.orders[id].status="delivered"
		rows.orders[id].close_action=action
		rows.orders[id].item_id=p.item_id
		_event(s,id,"order_delivery",action,p.item_id,t.price)
		return ""
	return "merchant_command"

## Reconciliation view for shop/office, never expose future orders or wallets.
static func view(s:Dictionary)->Dictionary:
	var output:Dictionary={"pawns":{},"orders":{},"events":[]}
	var day:int=Clock.day_index(int(s.game_minutes))
	var c:Dictionary=s.calendar.merchant_contracts
	for id:String in c.pawns:
		var t:Dictionary=_policy(s).pawns[id]
		if day<Clock.day_index(int(s.visits[t.visit_id].opens)):
			continue
		output.pawns[id]={"status":c.pawns[id].status,"customer":t.customer,
			"item_id":t.item_id,"principal":t.principal.duplicate(true),
			"repayment":t.repayment.duplicate(true),"due_day":t.due_day}
	for id:String in c.orders:
		var t:Dictionary=_policy(s).orders[id]
		if day<int(t.offer_day):
			continue
		output.orders[id]={"status":c.orders[id].status,"customer":t.customer,
			"def_id":t.def_id,"price":t.price.duplicate(true),
			"due_day":t.due_day,"delivered_item":c.orders[id].item_id}
	output.events=c.events.duplicate(true)
	return output
