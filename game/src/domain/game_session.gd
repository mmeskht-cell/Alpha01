extends RefCounted
## Sole authority. All reads are detached copies; mutations commit a validated candidate.
const Rules = preload("res://src/domain/value_rules.gd")
const CommandRoute = preload("res://src/domain/command_route.gd")
const Lifecycle = preload("res://src/domain/campaign_lifecycle.gd")
const Calendar = preload("res://src/domain/campaign_calendar.gd")
const Future=preload("res://src/domain/calendar_future_events.gd")
const CalendarLife = preload("res://src/domain/calendar_lifecycle.gd")
const CalendarTracking = preload("res://src/domain/calendar_tracking.gd")
const CalendarReaction = preload("res://src/domain/calendar_reaction.gd")
const WorldTrace = preload("res://src/domain/world_causal_trace.gd")
const VisitQueue = preload("res://src/domain/campaign_visit_queue.gd")
const Service = preload("res://src/domain/campaign_service.gd")
const Contract = preload("res://src/domain/campaign_contract.gd")
const Medicine = preload("res://src/domain/campaign_medicine.gd")
const Identity = preload("res://src/domain/campaign_identity_directory.gd")
const Composite = preload("res://src/domain/campaign_composite_pilot.gd")
const Clock = preload("res://src/domain/business_clock.gd")
const Receipt = preload("res://src/domain/receipt_primitives.gd")
const SnapshotFormat = preload("res://src/domain/snapshot_format.gd")
const Objects = preload("res://src/domain/object_schema.gd")
const Items = preload("res://src/domain/item_primitives.gd")
const CivilianPrice=preload("res://src/domain/civilian_condition_price.gd")
const BasicSaleQuality=preload("res://src/domain/basic_sale_quality.gd")
const Relations = preload("res://src/domain/object_relation_primitives.gd")
const Visits = preload("res://src/domain/visit_primitives.gd")
const Evidence = preload("res://src/domain/evidence_primitives.gd")
const InspectionAccess = preload("res://src/domain/inspection_access.gd")
const Observation = preload("res://src/domain/observation_record.gd")
const VisitObservation = preload("res://src/domain/visit_appraisal_observation.gd")
const AppraisalRetention=preload("res://src/domain/appraisal_history_retention.gd")
const RegionalWorld=preload("res://src/domain/regional_world_state.gd")
const NpcContinuity=preload("res://src/domain/npc_continuity.gd")
const NpcPopulation=preload("res://src/domain/npc_population.gd")
const RegionalMarket=preload("res://src/domain/regional_market_flow.gd")
const Finance=preload("res://src/domain/calendar_exchange_market.gd")
const Merchant=preload("res://src/domain/calendar_merchant_contracts.gd")
const VisitAssessment = preload("res://src/domain/visit_appraisal_assessment.gd")
const VisitDeck = preload("res://src/domain/visit_negotiation_deck.gd")
const VisitPrice = preload("res://src/domain/visit_price_offer.gd")
const VisitClaims = preload("res://src/domain/visit_customer_claims.gd")
const ComponentAppraisal = preload("res://src/domain/component_appraisal.gd")
const ComponentHistory = preload("res://src/domain/component_history.gd")
const ItemLineage = preload("res://src/domain/item_lineage.gd")
const CustomerInspection = preload("res://src/domain/customer_inspection.gd")
const Opening = preload("res://src/domain/gate1_opening.gd")
const DayOne = preload("res://src/domain/day_one.gd")
const ComponentMarket = preload("res://src/domain/component_market.gd")
const Negotiation = preload("res://src/domain/gate1_negotiation.gd")
const WeekPawn = preload("res://src/domain/alpha_b3_week_pawn.gd")
const AlphaShop = preload("res://src/domain/alpha_shop_cycle.gd")
const AlphaCards = preload("res://src/domain/alpha_card_trade.gd")
const AlphaCommission = preload("res://src/domain/alpha_commission.gd")
const AlphaServiceCustody = preload("res://src/domain/alpha_service_custody.gd")
const COMMAND_TYPES: Array = ["merchant_pawn_accept", "merchant_pawn_redeem", "merchant_pawn_extend", "merchant_order_accept", "merchant_order_deliver", "merchant_order_cancel", "calendar_exchange", "clean_exterior", "replace_component", "trade", "deliver", "move", "advance_time", "detach", "attach", "discard", "restore_item", "observe", "accept_rad1_contract", "next_visit", "inspect_radio", "record_hypothesis", "deck_action", "make_offer", "confirm_purchase", "decline_visit", "record_component_hypothesis", "request_open_inspection", "close_inspection", "decline_component_visit", "finish_component_visit", "begin_day_one", "day_one_next", "day_one_decline", "day_one_accept_service", "day_one_cancel_service", "day_one_close", "day_one_next_morning", "day_one_deliver_service", "day_one_pay_overhead", "open_component_sale", "day_one_composite_offer", "day_one_composite_request", "day_one_composite_close", "day_one_composite_decline", "world_sleep_family", "world_wake_family", "world_spawn_stock", "world_open_visit", "world_track_promote", "world_track_reference", "world_track_suspend", "calendar_close", "calendar_morning", "calendar_pay_overhead", "rad_reserve", "rad_decline", "rad_extend", "rad_pay", "rad_use", "rad_auto", "calendar_next_visit", "calendar_decline_visit", "calendar_accept_service", "calendar_deliver_service", "calendar_return_unpaid", "calendar_accept_contract", "calendar_decline_contract", "calendar_extend_contract", "calendar_pay_contract", "inspect_subject", "assess_subject", "link_subject_evidence", "subject_deck_action", "subject_price_offer"]
const MAX_RECEIPTS: int = 32
const STATE_KEYS: Array = ["revision", "game_minutes", "wallets", "inventories", "items", "ledger", "receipts", "receipt_archive", "object_schema", "tombstones", "object_events", "visits", "phase", "knowledge"]
var _state: Dictionary = {}
var _initialization_error: String = ""
var _validation_error: String = ""
var _definitions: Dictionary = {}
var _campaign_mode: bool = false
var _day_one_mode: bool = false
var _component_market_mode: bool = false
var _customer_policy: String = ""
var _composite_pilot_mode: bool = false
# Only exact outputs of successful deterministic replay are cached per session.
# Never persisted, never initialized from a checksum or unvalidated save.
var _alpha_mode: bool = false
var _alpha_seed: Dictionary = {}
var _calendar_mode: bool = false
var _calendar_seed: Dictionary = {}
var _calendar_checkpoint: Dictionary = {}
var _lifecycle_mode: bool = false
var _lifecycle_seed: Dictionary = {}
var _replay_checkpoint: Dictionary = {}
var _replay_steps: int = 0

func initialize(definitions: Dictionary, initial: Dictionary, composite_pilot: bool = false, lifecycle_mode: bool = false, calendar_profile: Dictionary = {}, alpha_profile: Dictionary = {}) -> bool:
	if not _state.is_empty():
		_initialization_error = "already_initialized"
		return false
	_initialization_error = ""
	_definitions = {}
	_customer_policy = ""
	_campaign_mode = false
	for id: Variant in definitions:
		if not Rules.identifier(id) or not definitions[id] is Dictionary:
			_initialization_error = "definition_shape"
			return false
		var definition: Dictionary = Objects.definition(definitions[id])
		if definition.is_empty() or definition.def_id != id:
			_initialization_error = "definition_invalid"
			return false
		_definitions[id] = definition
	var prepared: Dictionary = upgrade_state(initial)
	_campaign_mode = prepared.has("campaign")
	_day_one_mode = _campaign_mode and prepared.has("day_one")
	_composite_pilot_mode = composite_pilot and _day_one_mode
	if composite_pilot and not _composite_pilot_mode:
		_initialization_error = "composite_mode"
		return false
	_component_market_mode = not _campaign_mode and prepared.has("component_market")
	if _component_market_mode and prepared.has("customer_inspection"):
		_initialization_error = "market_customer_conflict"
		return false
	if prepared.has("customer_inspection"):
		if not prepared.customer_inspection is Dictionary or not prepared.customer_inspection.get("policy") is String or not CustomerInspection.has_policy(prepared.customer_inspection.policy):
			_initialization_error = "customer_policy"
			return false
		_customer_policy = prepared.customer_inspection.policy
	_lifecycle_mode = lifecycle_mode
	_alpha_mode = not alpha_profile.is_empty()
	_calendar_mode = not calendar_profile.is_empty()
	if _alpha_mode:
		if _campaign_mode or _component_market_mode or _lifecycle_mode or _calendar_mode or not _customer_policy.is_empty() or prepared.has("alpha_shop") or prepared.has("calendar"):
			_initialization_error = "alpha_mode_conflict"
			return false
		prepared = AlphaShop.seed(prepared, alpha_profile)
		if prepared.is_empty():
			_initialization_error = "alpha_seed"
			return false
		_alpha_seed = prepared.duplicate(true)
	if _calendar_mode:
		if _campaign_mode or _component_market_mode or _lifecycle_mode or not _customer_policy.is_empty() or prepared.has("component_hypotheses") or prepared.has("calendar"):
			_initialization_error = "calendar_mode_conflict"
			return false
		prepared = Calendar.seed(prepared, _definitions, calendar_profile)
		if prepared.is_empty():
			_initialization_error = "calendar_seed"
			return false
		_calendar_seed = prepared.duplicate(true)
		_calendar_checkpoint = {}
	if _lifecycle_mode:
		if _campaign_mode or _component_market_mode or not _customer_policy.is_empty() or prepared.revision != 0 or prepared.has("component_hypotheses"):
			_initialization_error = "lifecycle_mode_conflict"
			return false
		var dormant: Variant = prepared.get("lifecycle", {}).get("dormant", {})
		if not dormant is Dictionary:
			_initialization_error = "lifecycle_dormant"
			return false
		prepared["lifecycle"] = {"version": 2, "seed_hash": "", "dormant": dormant, "events": [], "waits": {}}
		prepared.lifecycle.seed_hash = Rules.canonical({"seed": prepared, "definitions": _definitions, "mode": "lifecycle-2"}).sha256_text()
		prepared = Rules.normalized(prepared)
		_lifecycle_seed = prepared.duplicate(true)
	if not validate(prepared):
		_initialization_error = "validation" + ":" + _validation_error
		return false
	_state = Rules.normalized(prepared)
	return true

## Diagnostic only: never part of a save, command, or public customer DTO.
func initialization_error() -> String:
	return _initialization_error

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func restore(candidate: Dictionary) -> bool:
	if _state.is_empty():
		return false
	var prepared: Dictionary = upgrade_state(candidate)
	if not validate(prepared) or not SnapshotFormat.fits(prepared):
		return false
	_state = Rules.normalized(prepared)
	return true

func clock_view() -> Dictionary:
	if _alpha_mode:
		return {"day": _state.alpha_shop.day, "phase": _state.alpha_shop.phase}
	var minutes: int = _state.game_minutes
	var date := Time.get_datetime_dict_from_unix_time(1982908800 + minutes * 60)
	return {"day": Clock.day_index(minutes), "date": "%04d-%02d-%02d" % [date.year, date.month, date.day], "hour": date.hour, "minute": date.minute}

func execute(command: Dictionary) -> Dictionary:
	return _execute(command, false)

## Internal world authority only, never routed from FoundationRuntime.submit.
func execute_world(command: Dictionary) -> Dictionary:
	return _execute(command, true)

func _execute(command: Dictionary, world: bool) -> Dictionary:
	if _state.is_empty():
		return _error("session_uninitialized")
	if not Rules.keys(command, ["action_id", "expected_revision", "type", "payload"]):
		return _error("command_shape")
	if not Rules.identifier(command.action_id) or not Rules.integer(command.expected_revision) or not command.type is String or not command.payload is Dictionary:
		return _error("command_shape")
	if world != (command.type in Lifecycle.ACTIONS or command.type in CalendarTracking.ACTIONS) or (world and not ((command.type in Lifecycle.ACTIONS and _lifecycle_mode) or (_calendar_mode and CalendarLife.enabled(_state) and command.type in CalendarLife.ACTIONS))):
		return _error("world_permission")
	if _alpha_mode and command.type not in AlphaShop.ACTIONS:
		return _error("alpha_command_unavailable")
	if _lifecycle_mode and not world and command.type not in ["trade", "deliver", "move", "advance_time", "detach", "attach", "discard", "restore_item", "observe"]:
		return _error("lifecycle_command_unavailable")
	if _lifecycle_mode and command.type == "observe" and ComponentAppraisal.recognizes(command.payload.get("key")):
		return _error("lifecycle_profile_unavailable")
	command = Rules.normalized(command)
	var fingerprint: String = Rules.canonical(command)
	if _state.receipts.has(command.action_id):
		var receipt: Dictionary = _state.receipts[command.action_id]
		if receipt.fingerprint != fingerprint:
			return _error("action_id_reused")
		return receipt.result.duplicate(true)
	if _state.receipt_archive.has(command.action_id):
		var archived: Array = _state.receipt_archive[command.action_id]
		if archived[0] != fingerprint.sha256_text():
			return _error("action_id_reused")
		return {"ok": true, "revision": archived[1]}
	if command.expected_revision != _state.revision:
		return _error("stale_revision")
	if fingerprint.to_utf8_buffer().size() > 4096:
		return _error("command_size")
	if _calendar_mode and command.type==VisitPrice.ACTION and not command.payload.has("basis_version"):
		var p: Dictionary = command.payload
		if Rules.identifier(p.get("visit_id")) and Rules.identifier(p.get("item_id")) and p.get("presented_ids") is Array:
			var statements: Array = VisitDeck.row_for(_state,p.visit_id,p.item_id).presented
			var corrected: bool = false
			for speech: Dictionary in statements:
				if speech.has("corrects_presentation_id") or speech.has("withdraws_presentation_id"):
					corrected=true
			if corrected:
				var live_ids: Array = VisitDeck.public_basis(statements)
				for id: Variant in p.presented_ids:
					if id not in live_ids:
						return _error("subject_offer_reference")
	# Historical receipt retries above and deterministic replay below retain old semantics.
	var selected: Dictionary = {"ok": true, "route": "alpha_shop"} if _alpha_mode else CommandRoute.choose(_state, command.type, command.payload, _campaign_mode, _day_one_mode, _component_market_mode)
	if not selected.ok:
		return _error(selected.error)
	var continuation: bool = selected.route == "day_one"
	var candidate: Dictionary = snapshot()
	var error: String
	if _alpha_mode:
		error = _apply_alpha(candidate, command)
	elif _calendar_mode:
		error = _apply_calendar(candidate, command)
	elif world:
		candidate = Lifecycle.apply(candidate, _definitions, command)
		if candidate.is_empty():
			return _error("lifecycle_transition")
	elif continuation:
		error = _apply_day_one(candidate, command)
	elif selected.route == "component_market":
		error = _apply_component_market(candidate, command)
	else:
		match command.type:
			"accept_rad1_contract", "next_visit", "inspect_radio", "record_hypothesis", "deck_action", "make_offer", "decline_visit": error = Opening.apply(candidate, command.type, command.payload, command.action_id)
			"confirm_purchase": error = _confirm_purchase(candidate, command.payload, command.action_id)
			"trade": error = _trade(candidate, command.payload, command.action_id)
			"deliver": error = _deliver(candidate, command.payload, command.action_id)
			"detach", "attach": error = _composition(candidate, command.payload, command.action_id, command.type)
			"replace_component": error = _replace_component(candidate, command.payload, command.action_id)
			"discard": error = _discard(candidate, command.payload, command.action_id)
			"restore_item": error = _restore_item(candidate, command.payload, command.action_id)
			"observe": error = _observe(candidate, command.payload, command.action_id)
			"record_component_hypothesis": error = ComponentAppraisal.record_hypothesis(candidate, command.payload, command.action_id)
			"request_open_inspection", "close_inspection", "decline_component_visit", "finish_component_visit": error = CustomerInspection.apply(candidate, command.type, command.payload, command.action_id)
			"move": error = _move(candidate, command.payload)
			"advance_time": error = _advance(candidate, command.payload, command.action_id)
			_: error = "unknown_command"
	if not error.is_empty():
		return _error(error)
	candidate.revision += 1
	var result: Dictionary = {"ok": true, "revision": candidate.revision}
	candidate.receipts[command.action_id] = {"fingerprint": fingerprint, "result": result.duplicate(true)}
	if _lifecycle_mode and command.type == "advance_time":
		candidate.lifecycle.waits[command.action_id] = int(command.payload.minutes)
	if continuation:
		candidate.day_one.commands.append(Rules.normalized(command))
	if _calendar_mode:
		candidate.calendar.commands.append(Rules.normalized(command))
	if _alpha_mode:
		candidate.alpha_shop.commands.append(Rules.normalized(command))
	if not _campaign_mode and (command.type == "record_component_hypothesis" or (command.type == "observe" and ComponentAppraisal.recognizes(command.payload.get("key")))):
		ComponentHistory.compact(candidate, ComponentAppraisal.observation_keys())
	_compact(candidate)
	if not SnapshotFormat.fits(candidate):
		return _error("save_capacity")
	if not validate(candidate):
		return _error("invariant")
	_state = candidate
	return result

## Opt-in calendar pilot reuses the existing transaction primitives.
## B2 candidate uses original transfer/move and accounting internals. Only the
## opt-in profile supplies new phase/real-shelf admission permissions.
## Read-only quotation for the spatial shop. Run the same permission and
## transaction rules on a detached state without issuing a command or receipt.
func spatial_action_preview(kind: String, payload: Dictionary) -> Dictionary:
	if not _alpha_mode or kind not in ["alpha_service_repair","alpha_trade","alpha_display","alpha_withdraw_display","spatial_move","spatial_restore_item","spatial_attach","spatial_detach"]:
		return {"ok":false,"error":"spatial_work_permission"}
	var draft := snapshot()
	var before: Dictionary = draft.wallets.player.duplicate()
	var error := _apply_alpha(draft,{"type":kind,"payload":payload.duplicate(true),"action_id":"alpha_b1_"+str(draft.revision+1),"expected_revision":draft.revision})
	if not error.is_empty():
		return {"ok":false,"error":error}
	# _place defers geometry to execute()'s final invariant check. Use the
	# same grid validator here so a draft cannot advertise a rejected drop.
	if kind in ["alpha_trade","alpha_display","alpha_withdraw_display","spatial_move","spatial_attach","spatial_detach"] and not Objects.grids_valid(draft,_definitions):
		return {"ok":false,"error":"inventory_placement"}
	return {"ok":true,"revision":draft.revision,"VKC":int(draft.wallets.player.VKC)-int(before.VKC),"USD":int(draft.wallets.player.USD)-int(before.USD)}

func _apply_alpha(state: Dictionary, command: Dictionary) -> String:
	if str(command.type).begins_with("spatial_"):
		var a: Dictionary = state.alpha_shop
		var work: Dictionary = command.payload
		var root: String = str(work.get("root_id",work.get("item_id","")))
		var shelf_move: bool = command.type=="spatial_move" and root in a.get("displayed",[]) and state.items.get(root,{}).get("inventory")=="storefront_grid" and work.get("inventory")=="storefront_grid"
		if not a.profile.has("spatial_opening") or work.get("actor") != "player" or not state.items.has(root) or (state.items[root].inventory not in ["player_stock","pawn_grid"] and not shelf_move):
			return "spatial_work_permission"
		if command.type == "spatial_move":
			if a.phase not in ["OPEN_IDLE","EVENING_WORK"] or (work.get("inventory") != "player_stock" and not shelf_move):
				return "spatial_storage"
			return _move(state,work)
		if a.phase != "EVENING_WORK" or state.items[root].inventory != "player_stock" or not _can_change(state,root,"player"):
			return "spatial_evening"
		var previous: String = state.phase
		state.phase = "workshop"
		var error: String = "spatial_work"
		match command.type:
			"spatial_restore_item":
				error = _restore_item(state,work,command.action_id)
			"spatial_detach":
				if work.get("inventory") == "player_stock":
					error = _composition(state,work,command.action_id,"detach")
			"spatial_attach":
				if state.items.get(work.get("child_id",""),{}).get("inventory") == "player_stock":
					error = _composition(state,work,command.action_id,"attach")
		state.phase = previous
		return error
	if command.type in WeekPawn.ACTIONS:
		return WeekPawn.apply(state,_definitions,command)
	if command.type == "alpha_settle" and state.alpha_shop.phase == "CLOSE_SETTLE":
		WeekPawn.expire(state,_definitions,command.action_id)
	var p: Dictionary = command.payload
	if command.type == "alpha_service_repair":
		if not state.alpha_shop.has("services"):
			return "alpha_service_unavailable"
		var guard: String = AlphaServiceCustody.work_gate(state, p)
		if not guard.is_empty():
			return guard
		# The existing restoration primitive owns functional flags, cost and
		# object events. Only a detached command candidate temporarily enters
		# the legacy workshop phase; player-facing Alpha day remains unchanged.
		var original_phase: String = str(state.phase)
		state.phase = "workshop"
		var error: String = _restore_item(state, {"actor":"player","item_id":str(p.item_id)}, command.action_id)
		state.phase = original_phase
		if error.is_empty():
			AlphaServiceCustody.after_work(state, str(p.job_id), command.action_id)
		return error
	if command.type == "alpha_commission_deliver":
		if not state.alpha_shop.has("commissions"):
			return "alpha_commission_unavailable"
		var delivery_guard: String = AlphaCommission.delivery_gate(state, command)
		if not delivery_guard.is_empty():
			return delivery_guard
		var request_id: String = p.request_id
		var transfer: Dictionary = AlphaCommission.transfer_payload(state, request_id)
		# Reservation is unlocked only on this detached transaction candidate;
		# _transfer validates buyer's actual wallet and family/placement before
		# the state, ledger and commission fulfilment commit atomically.
		state.items[transfer.item_id].reservation_id = ""
		var delivery_error: String = _trade(state, transfer, command.action_id)
		if delivery_error.is_empty():
			AlphaCommission.after_delivery(state, request_id, command.action_id)
		return delivery_error
	if command.type == "alpha_trade":
		var trade_guard: String = AlphaShop.trade_gate(state, p)
		if not trade_guard.is_empty():
			return trade_guard
		if state.alpha_shop.has("appraisal"):
			var appraisal_guard: String = AlphaCards.trade_gate(state, p)
			if not appraisal_guard.is_empty():
				return appraisal_guard
		var trade_error: String = _trade(state, p, command.action_id)
		if trade_error.is_empty():
			AlphaShop.after_trade(state, p)
		return trade_error
	if command.type in ["alpha_display", "alpha_withdraw_display"]:
		var withdraw: bool = command.type == "alpha_withdraw_display"
		var display_guard: String = AlphaShop.display_gate(state, p, withdraw)
		if not display_guard.is_empty():
			return display_guard
		var target: String = "player_stock" if withdraw else "storefront_grid"
		var move: Dictionary = {"item_id": p.item_id, "actor": "player", "inventory": target, "x": p.x, "y": p.y, "rotated": p.rotated}
		var move_error: String = _move(state, move)
		if move_error.is_empty():
			AlphaShop.after_display(state, p.item_id, withdraw)
		return move_error
	return AlphaShop.apply(state, command)

func _apply_calendar(state: Dictionary, command: Dictionary) -> String:
	var active_before: String = state.calendar.get("queue",{}).get("active","")
	var error: String = _apply_calendar_action(state,command)
	if error.is_empty() and not active_before.is_empty() and state.calendar.get("queue",{}).get("active","") != active_before:
		VisitDeck.finish(state,active_before)
	if error.is_empty() and command.type=="discard" and state.calendar.has("tracking"):
		return CalendarTracking.reconcile_terminal(state)
	return error

func _apply_calendar_action(state: Dictionary, command: Dictionary) -> String:
	if Calendar.complete(state):
		return "calendar_complete"
	var kind: String = command.type
	var p: Dictionary = command.payload
	if kind in CalendarLife.ACTIONS:
		return CalendarLife.apply(state,_definitions,command) if CalendarLife.enabled(state) else "calendar_world_permission"
	if kind == "inspect_subject":
		return VisitObservation.apply(state,p,command.action_id)
	if kind in VisitAssessment.ACTIONS:
		return VisitAssessment.apply(state,kind,p,command.action_id)
	if kind == VisitDeck.ACTION:
		return VisitDeck.apply(state,p,command.action_id)
	if kind == VisitPrice.ACTION:
		return VisitPrice.apply(state,p,command.action_id)
	if kind in Calendar.ACTIONS:
		var calendar_error:String=Calendar.apply(state, kind, p, command.action_id)
		if calendar_error.is_empty() and kind=="calendar_close" and state.calendar.has("merchant_contracts"):
			Merchant.close(state,_definitions,command.action_id)
		return calendar_error
	if kind in Medicine.ACTIONS:
		return Medicine.apply(state, kind, p, command.action_id)
	if kind in Contract.ACTIONS:
		return Contract.apply(state, kind, p, command.action_id)
	if kind == Finance.ACTION:
		return Finance.apply(state,p,command.action_id)
	if kind in Merchant.ACTIONS:
		return Merchant.apply(state,_definitions,kind,p,command.action_id)
	if kind in VisitQueue.ACTIONS:
		return VisitQueue.apply(state, kind, p)
	if kind in Service.ACTIONS:
		var service_error: String = Service.apply(state, _definitions, kind, p, command.action_id)
		if service_error.is_empty():
			VisitQueue.finish(state, "service_accepted" if kind == "calendar_accept_service" else ("service_delivered" if kind == "calendar_deliver_service" else "service_returned"))
		return service_error
	var queued: bool = state.calendar.has("queue")
	var service_job: String = ""
	if queued and kind == "restore_item" and Rules.identifier(p.get("item_id")) and state.items.has(p.item_id) and state.items[p.item_id].status == "custody_service":
		service_job = Service.work_job(state, p.item_id)
		if service_job.is_empty():
			return "service_work_scope"
	if queued and kind in ["trade", "deliver"] and not VisitQueue.permits(state, p.get("visit_id", command.action_id)):
		return "visit_not_active"
	if kind not in Calendar.COMMON:
		return "calendar_command_unavailable"
	var error: String = ""
	match kind:
		"trade":
			error = VisitPrice.trade_error(state,p)
			if error.is_empty():
				error = BasicSaleQuality.error(state,p)
			if error.is_empty():
				var trade_payload: Dictionary = p.duplicate(true)
				trade_payload.erase("offer_id")
				trade_payload.erase(BasicSaleQuality.FIELD)
				error = _trade(state,trade_payload,command.action_id)
		"deliver": error = _deliver(state, p, command.action_id)
		"move": error = _move(state, p)
		"observe":
			if ComponentAppraisal.recognizes(p.get("key")):
				return "calendar_observation_profile"
			error = _observe(state, p, command.action_id)
		"restore_item": error = _restore_item(state, p, command.action_id)
		"clean_exterior": error = _clean_exterior(state,p,command.action_id)
		"attach", "detach": error = _composition(state, p, command.action_id, kind)
		"replace_component": error = _replace_component(state, p, command.action_id)
		"discard": error = _discard(state, p, command.action_id)
	if error.is_empty() and not service_job.is_empty():
		Service.finish_work(state, service_job, command.action_id)
	if queued and error.is_empty() and kind in ["trade", "deliver"]:
		VisitQueue.finish(state)
	if state.game_minutes >= Calendar.boundary(state.calendar.profile):
		return "calendar_boundary"
	return error

## Public read-only query for any previously player-traded ID, including old
## entries beyond recent-index display. No ownership or hidden state exposed.
func calendar_item_history(item_id: String) -> Dictionary:
	if not _calendar_mode or _state.is_empty():
		return {"records":[],"omitted":0,"work_records":[],"work_omitted":0}
	return ItemLineage.calendar_history(_state,item_id)

## Public read-only overview, including service objects personally worked on.
func calendar_history_index() -> Dictionary:
	if not _calendar_mode or _state.is_empty():
		return {"items":[],"omitted":0}
	return ItemLineage.calendar_index(_state)

func calendar_view(basic_visit:String="") -> Dictionary:
	if not _calendar_mode or _state.is_empty():
		return {}
	var result: Dictionary = Calendar.view(_state)
	result["medicine"] = Medicine.view(_state)
	if VisitClaims.enabled(_state):
		result["trade_history"] = calendar_history_index()
	if _state.calendar.has("queue"):
		result["visits"] = VisitQueue.view(_state)
		if not str(result.visits.active).is_empty():
			var terms:Dictionary=result.visits.terms
			var actor:String=str(terms.get("customer",""))
			if actor.is_empty() and terms.has("seller") and terms.has("buyer"):
				actor=str(terms.seller) if terms.buyer=="player" else str(terms.buyer)
			var remembered:Dictionary=WorldTrace.customer_memory(_state,actor)
			if not remembered.is_empty():
				result["customer_memory"]=remembered
		var quote:Dictionary=CivilianPrice.quote(_state,_definitions,str(result.visits.active))
		if not quote.is_empty():
			# Expose only whether the specific public transaction can be funded,
			# never the customer's balance. No new persisted fields.
			quote["buyer_can_pay"]=quote.can_sell and int(_state.wallets[result.visits.terms.buyer].get(quote.currency,0))>=int(quote.amount)
			result["condition_quote"]=quote
			result.visits.terms.prices[quote.item_id]={"VKC":quote.amount,"USD":0}
		elif CivilianPrice.recognizes(str(result.visits.active)):
			# Fail closed rather than offer the seed maximum when disposition
			# or appraisal permission no longer holds.
			result["condition_quote"]={"item_id":CivilianPrice.ITEM,"can_sell":false,"buyer_can_pay":false,"tier":"unavailable"}
		if _state.calendar.has("appraisal_profile"):
			var active_id:String=str(result.visits.active)
			var active_prices:Dictionary=result.visits.get("terms",{}).get("prices",{})
			result["basic_review_available"]=active_prices.size()==1 and VisitObservation.basic_available(_state,active_id,str(active_prices.keys()[0]))
			if active_prices.size()==1:
				var sale_id:String=str(active_prices.keys()[0])
				if BasicSaleQuality.available(_state,active_id,sale_id):
					result["basic_sale_review_id"]=sale_id
					result["basic_sale_quality"]=BasicSaleQuality.option(_state,active_id,sale_id)
			result["appraisal"] = VisitObservation.active_view(_state,basic_visit)
			if not result.appraisal.is_empty():
				result.appraisal.merge(VisitAssessment.view(_state,result.appraisal.visit_id,result.appraisal.item_id))
				result.appraisal["deck"] = VisitDeck.view(_state,result.appraisal.visit_id,result.appraisal.item_id)
				var price_view: Dictionary = VisitPrice.view(_state,result.appraisal.visit_id,result.appraisal.item_id)
				if not price_view.is_empty():
					result.appraisal["price_offer"] = price_view
					var placement_view: Dictionary = VisitPrice.checkout(_state,_definitions,result.appraisal.visit_id,result.appraisal.item_id)
					if not placement_view.is_empty():
						result.appraisal["checkout"] = placement_view
	if _state.calendar.has("services"):
		result["services"] = Service.view(_state)
	if _state.calendar.has("contracts"):
		result["obligations"] = Contract.view(_state)
	if _state.calendar.profile.has("future_events"):
		result["future_events"]=Future.view(_state)
	if _state.calendar.has("reaction"):
		result["world_news"]=CalendarReaction.view(_state)
	if _state.calendar.has("regional_world"):
		result["world_regions"]=RegionalWorld.view(_state)
	if _state.calendar.profile.has("market_flow"):
		result["regional_market"]=RegionalMarket.view(_state)
	if _state.calendar.has("exchange_market"):
		result["exchange_market"]=Finance.view(_state)
	if _state.calendar.has("merchant_contracts"):
		result["merchant_contracts"]=Merchant.view(_state,_definitions)
	if _state.calendar.has("npc_population"):
		var persona:Dictionary=NpcPopulation.active_view(_state)
		if not persona.is_empty():
			result["npc_visitor"]=persona
	if _state.calendar.profile.has("npc_continuity") and result.get("visits",{}).has("active") and not str(result.visits.active).is_empty():
		var terms:Dictionary=result.visits.terms
		var actor:String=str(terms.get("seller","")) if terms.get("buyer")=="player" else str(terms.get("buyer",terms.get("customer","")))
		var contact:Dictionary=NpcContinuity.visible_history(_state,actor)
		if not contact.is_empty():
			result["npc_encounters"]=contact
	return result

## Seed-bound full replay, with a local cache only for exact validated prefixes.
## No persisted cache or new live save schema. Existing capacity guard still applies.
## Read the most recent journal event only when its authoritative receipt matches.
func alpha_presentation_event(revision: int,kind: String,payload: Dictionary) -> Dictionary:
	if not _alpha_mode or int(_state.get("revision",-1))!=revision: return {}
	var journal: Array = _state.alpha_shop.commands
	if journal.is_empty(): return {}
	var cmd: Dictionary = journal.back()
	if cmd.type!=kind or cmd.payload!=payload or int(cmd.expected_revision)+1!=revision: return {}
	if not Receipt.matches_receipt(_state,cmd.action_id,kind,payload,revision): return {}
	return {"event_id":cmd.action_id,"revision":revision}

func alpha_view() -> Dictionary:
	return AlphaShop.view(_state) if _alpha_mode and not _state.is_empty() else {}

## Alpha-specific player-visible history. Alpha and Calendar modes are
## mutually exclusive; never query a Calendar-only journal for Alpha records.
func alpha_item_history(item_id: String, current_visit: String="") -> Dictionary:
	var result: Dictionary = {"item_id":item_id,"records":[],"omitted":0,"work_records":[],"work_omitted":0,"prior_offers":[]}
	if not _alpha_mode or _state.is_empty() or not Rules.identifier(item_id):
		return result
	var a: Dictionary = _state.alpha_shop
	var journal: Array = a.commands
	var ledger: Array = _state.ledger
	for i: int in range(ledger.size()-1,-1,-1):
		var entry: Dictionary = ledger[i]
		if item_id not in entry.item_ids or "player" not in [entry.from,entry.to]:
			continue
		if result.records.size()>=ItemLineage.DISPLAY_LIMIT:
			result.omitted += 1
			continue
		var single_root: bool = entry.root_ids.size()==1 and entry.root_ids[0]==item_id
		var row: Dictionary = {"event_id":entry.event_id,"minute":int(entry.game_minutes),"direction":"purchase" if entry.from=="player" else "sale","amounts":entry.amounts.duplicate(true) if single_root else null}
		var rev: int = int(entry.revision)
		if single_root and rev>=1 and rev<=journal.size():
			var cmd: Dictionary = journal[rev-1]
			var p: Dictionary = cmd.payload
			if cmd.type=="alpha_trade" and cmd.action_id==entry.event_id and p.get("visit_id")==entry.visit_id and p.get("item_id")==item_id and Receipt.matches_receipt(_state,entry.event_id,cmd.type,p,rev):
				var visit_row: Dictionary = a.get("appraisal",{}).get("visits",{}).get(entry.visit_id,{})
				var accepted: Dictionary = visit_row.get("accepted",{})
				if visit_row.get("item_id")==item_id and accepted.get("currency")==p.currency and accepted.get("amount")==p.amount:
					for offer: Dictionary in visit_row.get("offers",[]):
						if offer.get("action_id")!=accepted.get("action_id") or offer.get("response")!="accepted" or offer.get("currency")!=p.currency or offer.get("amount")!=p.amount:
							continue
						var offer_rev: int = Receipt.receipt_revision(_state,str(offer.action_id))
						if offer_rev<1 or offer_rev>=rev:
							continue
						var offer_cmd: Dictionary = journal[offer_rev-1]
						if offer_cmd.type!="alpha_price_offer" or offer_cmd.action_id!=offer.action_id or offer_cmd.payload.get("amount")!=p.amount or not Receipt.matches_receipt(_state,offer.action_id,offer_cmd.type,offer_cmd.payload,offer_rev):
							continue
						var facts: Array = []
						for fact: Dictionary in offer.get("revealed",[]):
							facts.append({"slot":fact.slot,"value":str(fact.value)})
						row["offer_reference"] = {"offer_id":offer.action_id,"facts":facts,"assessment":offer.get("private_assessment",{}).duplicate(true),"observed_slots":offer.get("observed_slots",[]).duplicate()}
						break
		result.records.append(row)
	var work_types: Dictionary = {"spatial_attach":"attach","spatial_detach":"detach","spatial_restore_item":"restore_item","alpha_service_repair":"restore_item"}
	var events: Array = _state.object_events
	for i: int in range(events.size()-1,-1,-1):
		var event: Dictionary = events[i]
		if item_id not in event.item_ids:
			continue
		var rev: int = int(event.revision)
		if rev<1 or rev>journal.size():
			continue
		var cmd: Dictionary = journal[rev-1]
		if work_types.get(cmd.type,"")!=event.type or cmd.action_id!=event.event_id or not Receipt.matches_receipt(_state,event.event_id,cmd.type,cmd.payload,rev):
			continue
		var p: Dictionary = cmd.payload
		var row: Dictionary = {"event_id":event.event_id,"revision":rev,"kind":event.type}
		if cmd.type in ["spatial_attach","spatial_detach"]:
			if p.get("actor")!="player" or event.item_ids!=[p.get("root_id"),p.get("child_id")]:
				continue
			row["related_item_id"] = p.child_id if p.root_id==item_id else p.root_id
			if a.profile.has("f3_composite_trial"):
				row["role"]="root" if p.root_id==item_id else "child"
		elif event.item_ids!=[p.get("item_id")]:
			continue
		elif a.profile.has("f3_composite_trial") and event.type=="restore_item":
			row["expense"]=event.expenses.duplicate(true)
		if result.work_records.size()>=ItemLineage.DISPLAY_LIMIT:
			result.work_omitted += 1
		else:
			result.work_records.append(row)
	result.prior_offers = AlphaCards.prior_disclosures(_state,item_id,current_visit)
	return result

## Read-only item placement hints; actual player actions must still run
## through _apply_alpha and _move on a validated candidate.
func alpha_shelf_options() -> Dictionary:
	return AlphaShop.shelf_options(_state,_definitions) if _alpha_mode and not _state.is_empty() else {"display":[],"withdraw":[]}

## Full immutable seed replay for B1 commands, independent of the legacy calendar.
func _alpha_valid(state: Dictionary) -> bool:
	if not state.get("alpha_shop") is Dictionary or _alpha_seed.is_empty():
		return false
	var a: Dictionary = state.alpha_shop
	var expected_alpha_keys: Array = ["version", "profile", "binding", "day", "phase", "cursor", "active", "outcomes", "settled_days", "contacts", "commands"]
	if _alpha_seed.alpha_shop.has("week_pawn"):
		expected_alpha_keys.append("week_pawn")
	if _alpha_seed.alpha_shop.has("displayed"):
		expected_alpha_keys.append("displayed")
	if _alpha_seed.alpha_shop.has("contracts"):
		expected_alpha_keys.append("contracts")
	if _alpha_seed.alpha_shop.has("appraisal"):
		expected_alpha_keys.append("appraisal")
	if _alpha_seed.alpha_shop.has("commissions"):
		expected_alpha_keys.append("commissions")
	if _alpha_seed.alpha_shop.has("services"):
		expected_alpha_keys.append("services")
	if _alpha_seed.alpha_shop.has("fx"):
		expected_alpha_keys.append("fx")
	if _alpha_seed.alpha_shop.has("random_visits"):
		expected_alpha_keys.append("random_visits")
	# A signed outbound command may add this key only after dispatch. Older M7
	# saves have no outbound field; preserve their exact seed/save shape.
	# Deterministic command replay below still rejects forged or altered entries.
	if _alpha_seed.alpha_shop.has("outbound") or a.has("outbound"):
		expected_alpha_keys.append("outbound")
	if not Rules.keys(a, expected_alpha_keys):
		return false
	if a.version != 1 or a.profile != _alpha_seed.alpha_shop.profile or a.binding != _alpha_seed.alpha_shop.binding or not a.commands is Array or a.commands.size() != state.revision:
		return false
	var replay: Dictionary = _alpha_seed.duplicate(true)
	for c: Variant in a.commands:
		if not Rules.keys(c, ["action_id", "expected_revision", "type", "payload"]) or not Rules.identifier(c.action_id) or c.expected_revision != replay.revision or not c.type is String or not c.payload is Dictionary or replay.receipts.has(c.action_id) or replay.receipt_archive.has(c.action_id):
			return false
		var fingerprint: String = Rules.canonical(c)
		if fingerprint.to_utf8_buffer().size() > 4096 or not _apply_alpha(replay, c).is_empty():
			return false
		replay.revision += 1
		replay.receipts[c.action_id] = {"fingerprint": fingerprint, "result": {"ok": true, "revision": replay.revision}}
		replay.alpha_shop.commands.append(Rules.normalized(c))
		_compact(replay)
		if not SnapshotFormat.fits(replay):
			return false
	return Rules.canonical(replay) == Rules.canonical(state)

func _calendar_valid(state: Dictionary) -> bool:
	var c: Variant = state.get("calendar")
	var keys: Array = ["version", "profile", "binding", "debt", "commands"]
	if _calendar_seed.calendar.has("dormant"):
		keys.append("dormant")
	if _calendar_seed.calendar.has("tracking"):
		keys.append("tracking")
	if _calendar_seed.calendar.has("reaction"):
		keys.append("reaction")
	if _calendar_seed.calendar.has("regional_world"):
		keys.append("regional_world")
	if _calendar_seed.calendar.has("npc_population"):
		keys.append("npc_population")
	if _calendar_seed.calendar.has("exchange_market"):
		keys.append("exchange_market")
	if _calendar_seed.calendar.has("merchant_contracts"):
		keys.append("merchant_contracts")
	if _calendar_seed.calendar.has("medicine"):
		keys.append("medicine")
	if _calendar_seed.calendar.has("queue"):
		keys.append("queue")
	if _calendar_seed.calendar.has("services"):
		keys.append("services")
	if _calendar_seed.calendar.has("contracts"):
		keys.append("contracts")
	if _calendar_seed.calendar.has("appraisal_profile"):
		keys.append("appraisal_profile")
		keys.append("appraisal_observations")
		if _calendar_seed.calendar.has("appraisal_observation_archive"):
			keys.append("appraisal_observation_archive")
		keys.append("appraisal_assessments")
		# Optional on first explicit deck action; old B2/B3 snapshots remain valid.
		if c is Dictionary and c.has("appraisal_decks"):
			keys.append("appraisal_decks")
		if c is Dictionary and c.has("appraisal_offers"):
			keys.append("appraisal_offers")
	if not Rules.keys(c, keys) or c.version != 1 or c.profile != _calendar_seed.calendar.profile or c.binding != _calendar_seed.calendar.binding or not Rules.integer(c.debt) or not c.commands is Array or c.commands.size() != state.revision or not AppraisalRetention.valid(state):
		return false
	var replay: Dictionary = _calendar_seed.duplicate(true)
	var start: int = 0
	if not _calendar_checkpoint.is_empty():
		var previous: Array = _calendar_checkpoint.calendar.commands
		if previous.size() <= c.commands.size() and previous == c.commands.slice(0, previous.size()):
			replay = _calendar_checkpoint.duplicate(true)
			start = previous.size()
	for index: int in range(start, c.commands.size()):
		var command: Variant = c.commands[index]
		if not Rules.keys(command, ["action_id", "expected_revision", "type", "payload"]) or not Rules.identifier(command.action_id) or command.expected_revision != replay.revision or not command.type is String or not command.payload is Dictionary:
			return false
		if replay.receipts.has(command.action_id) or replay.receipt_archive.has(command.action_id):
			return false
		var fingerprint: String = Rules.canonical(command)
		if fingerprint.to_utf8_buffer().size() > 4096 or not _apply_calendar(replay, command).is_empty():
			return false
		replay.revision += 1
		replay.receipts[command.action_id] = {"fingerprint": fingerprint, "result": {"ok": true, "revision": replay.revision}}
		replay.calendar.commands.append(Rules.normalized(command))
		_compact(replay)
		if not Objects.validate(replay, _definitions) or not SnapshotFormat.fits(replay):
			return false
		if CalendarLife.enabled(replay) and not CalendarLife.valid(replay,_definitions):
			return false
	if Rules.canonical(replay) != Rules.canonical(state):
		return false
	_calendar_checkpoint = replay.duplicate(true)
	return true

## The continuation uses exactly the existing transfer and move primitives.
func _apply_day_one(state: Dictionary, command: Dictionary) -> String:
	var p: Dictionary = command.payload
	if state.day_one.base == null:
		return DayOne.begin(state, p) if command.type == "begin_day_one" else "day_one_begin"
	if _composite_pilot_mode:
		if command.type == Composite.OFFER:
			return Composite.offer(state, ComponentAppraisal.seed()) if p.is_empty() else "composite_payload"
		if command.type in Composite.ACTIONS:
			return Composite.apply(state, command.type, p, command.action_id)
		if Composite.live(state):
			match command.type:
				"observe": return ComponentAppraisal.observe(state, _definitions, p, command.action_id)
				"record_component_hypothesis": return ComponentAppraisal.record_hypothesis(state, p, command.action_id)
				"trade":
					if p.get("visit_id") != CustomerInspection.VISIT or p.get("item_id") != CustomerInspection.ROOT or p.get("inventory") != "player_stock":
						return "composite_trade"
					return _trade(state, p, command.action_id)
			return "composite_visit_active"
		if Composite.enabled(state):
			match command.type:
				"observe": return ComponentAppraisal.observe(state, _definitions, p, command.action_id)
				"record_component_hypothesis": return ComponentAppraisal.record_hypothesis(state, p, command.action_id)
				"move":
					if p.get("item_id") in CustomerInspection.IDS:
						return _move(state, p) if Composite.owned(state, p.item_id, true) and p.get("inventory") == "player_stock" else "composite_move"
				"attach", "detach":
					if p.get("root_id") == CustomerInspection.ROOT and p.get("child_id") in CustomerInspection.IDS and (command.type == "attach" or p.get("inventory") == "player_stock"):
						return _composition(state, p, command.action_id, command.type)
					return "composite_work"
				"restore_item":
					if p.get("item_id") in CustomerInspection.IDS:
						return _restore_item(state, p, command.action_id) if Composite.owned(state, p.item_id, true) else "composite_work"
	match command.type:
		"day_one_next": return DayOne.next(state, p)
		"day_one_decline": return DayOne.decline(state, p)
		"day_one_accept_service": return DayOne.accept_service(state, p)
		"day_one_cancel_service": return DayOne.cancel_service(state, p)
		"day_one_close": return DayOne.close_shop(state, p, command.action_id)
		"day_one_next_morning": return DayOne.next_morning(state, p)
		"day_one_deliver_service": return DayOne.deliver_service(state, p, command.action_id)
		"day_one_pay_overhead": return DayOne.pay_overhead(state, p, command.action_id)
		"restore_item":
			if not DayOne.may_restore(state, p):
				return "service_permission"
			var restore_error: String = _restore_item(state, p, command.action_id)
			if restore_error.is_empty():
				DayOne.mark_restored(state, command.action_id)
			return restore_error
		"accept_rad1_contract":
			return Opening.apply(state, command.type, p, command.action_id) if DayOne.shop(state) else "day_one_phase"
		"move":
			return _move(state, p) if DayOne.may_move(state, p) else "day_one_move"
		"trade":
			if not DayOne.may_sell(state, p):
				return "day_one_sale"
			var error: String = _trade(state, p, command.action_id)
			if error.is_empty():
				DayOne.on_sale(state, p)
			return error
	return "day_one_command"

## Small bounded slice: retain the validated opening checkpoint and exact continuation
## commands. Replay against the same pure candidate handlers, never the live state.
## This is a temporary acceptance oracle, not the future long-campaign save model.
func _day_one_valid(state: Dictionary) -> bool:
	_replay_steps = 0
	var marker: Variant = state.get("day_one")
	var marker_fields: Array = ["base", "commands", "service", "closing", "settlements", "news"]
	if _composite_pilot_mode and marker is Dictionary and marker.has("composite_pilot"):
		marker_fields.append("composite_pilot")
	if not Rules.keys(marker, marker_fields) or not marker.commands is Array or marker.commands.size() > int(state.revision) or not SnapshotFormat.fits(state):
		return false
	if marker.base == null:
		return marker == DayOne.marker() and Opening.valid(state)
	if not marker.base is Dictionary or marker.base.has("day_one") or marker.commands.is_empty() or not validate(marker.base, MAX_RECEIPTS, true) or not DayOne.can_begin(marker.base):
		return false
	var replay: Dictionary = marker.base.duplicate(true)
	replay["day_one"] = DayOne.marker()
	var start: int = 0
	# Reuse only an exactly matching base and command prefix verified in this
	# authority. Different branch or earlier generation falls back to the oracle.
	if not _replay_checkpoint.is_empty() and _replay_checkpoint.day_one.base == marker.base:
		var previous: Array = _replay_checkpoint.day_one.commands
		if previous.size() <= marker.commands.size() and marker.commands.slice(0, previous.size()) == previous:
			replay = _replay_checkpoint.duplicate(true)
			start = previous.size()
	for index: int in range(start, marker.commands.size()):
		var command: Variant = marker.commands[index]
		_replay_steps += 1
		if not Rules.keys(command, ["action_id", "expected_revision", "type", "payload"]) or not Rules.identifier(command.action_id) or not Rules.integer(command.expected_revision) or command.expected_revision != replay.revision or not command.type is String or not command.payload is Dictionary:
			return false
		if replay.receipts.has(command.action_id) or replay.receipt_archive.has(command.action_id):
			return false
		var fingerprint: String = Rules.canonical(command)
		if fingerprint.to_utf8_buffer().size() > 4096 or not _apply_day_one(replay, command).is_empty():
			return false
		replay.revision += 1
		replay.receipts[command.action_id] = {"fingerprint": fingerprint, "result": {"ok": true, "revision": replay.revision}}
		replay.day_one.commands.append(Rules.normalized(command))
		_compact(replay)
		if not Objects.validate(replay, _definitions):
			return false
	if replay != state:
		return false
	_replay_checkpoint = replay.duplicate(true)
	return true

## Diagnostic only; no state mutation or trust decision.
func replay_diagnostics() -> Dictionary:
	return {"steps": _replay_steps, "cached_revision": _replay_checkpoint.get("revision", -1)}

func _apply_component_market(state: Dictionary, command: Dictionary) -> String:
	if command.type == ComponentMarket.ACTION:
		return ComponentMarket.open(state, _definitions, command.payload, command.action_id)
	if command.type != "trade" or not ComponentMarket.allowed(state, command.type) or command.payload != ComponentMarket.payload():
		return "component_market_permission"
	var error: String = _trade(state, command.payload, command.action_id)
	if error.is_empty():
		state.component_market.sale_command = Rules.normalized(command)
	return error

func _component_market_valid(state: Dictionary) -> bool:
	var marker: Variant = state.get("component_market")
	if not Rules.keys(marker, ["base", "open_action", "sale_command"]) or not SnapshotFormat.fits(state):
		return false
	if marker.base == null:
		if marker != ComponentMarket.marker() or state.phase != "workshop" or state.game_minutes != 600 or not state.ledger.is_empty() or not state.visits.is_empty():
			return false
		for table: Dictionary in [state.receipts, state.receipt_archive]:
			for id: String in table:
				if _receipt_type(state, id) not in ["move", "attach", "detach", "restore_item", "observe", "record_component_hypothesis"]:
					return false
		return true
	if not marker.base is Dictionary or marker.base.has("component_market") or not Rules.identifier(marker.open_action) or not validate(marker.base, MAX_RECEIPTS, true) or not ComponentMarket.can_open(marker.base, _definitions):
		return false
	if marker.base.phase != "workshop" or not marker.base.ledger.is_empty() or not marker.base.visits.is_empty():
		return false
	var replay: Dictionary = marker.base.duplicate(true)
	replay["component_market"] = ComponentMarket.marker()
	var commands: Array = [{"action_id": marker.open_action, "expected_revision": replay.revision, "type": ComponentMarket.ACTION, "payload": {}}]
	if marker.sale_command != null:
		commands.append(marker.sale_command)
	for command: Variant in commands:
		if not Rules.keys(command, ["action_id", "expected_revision", "type", "payload"]) or not Rules.identifier(command.action_id) or command.expected_revision != replay.revision or not command.payload is Dictionary or not command.type is String or replay.receipts.has(command.action_id) or replay.receipt_archive.has(command.action_id):
			return false
		if not _apply_component_market(replay, command).is_empty():
			return false
		replay.revision += 1
		replay.receipts[command.action_id] = {"fingerprint": Rules.canonical(command), "result": {"ok": true, "revision": replay.revision}}
		_compact(replay)
		if not Objects.validate(replay, _definitions):
			return false
	return replay == state

func _confirm_purchase(state: Dictionary, p: Dictionary, action_id: String) -> String:
	var error: String = Negotiation.prepare_purchase(state, p)
	if not error.is_empty():
		return error
	error = _transfer(state, "visit_g01", [{"item_id": "R001", "inventory": p.inventory, "x": p.x, "y": p.y, "rotated": p.rotated}], action_id)
	if error.is_empty():
		Negotiation.finish(state, "purchased", action_id)
	return error

func _trade(state: Dictionary, payload: Dictionary, action_id: String) -> String:
	var p: Dictionary = payload.duplicate(true)
	var visit_id: Variant = p.get("visit_id", action_id)
	p.erase("visit_id")
	if not Rules.keys(p, ["item_id", "seller", "buyer", "currency", "amount", "inventory", "x", "y", "rotated"]):
		return "trade_shape"
	if not Rules.identifier(visit_id) or not state.visits.has(visit_id):
		return "visit_missing"
	var visit: Dictionary = state.visits[visit_id]
	if p.seller != visit.seller or p.buyer != visit.buyer or p.currency not in ["VKC", "USD"] or not Rules.integer(p.amount, 1) or not visit.prices.has(p.item_id):
		return "trade_terms"
	var price: Dictionary = visit.prices[p.item_id]
	if CivilianPrice.recognizes(str(visit_id)):
		var quote:Dictionary=CivilianPrice.quote(state,_definitions,visit_id)
		if not _calendar_mode or quote.is_empty() or not quote.can_sell or p.item_id!=quote.item_id or p.currency!=quote.currency or p.amount!=quote.amount:
			return "condition_quote_changed"
		# Commit settled price on candidate only, retaining existing ledger validation.
		price={"VKC":quote.amount,"USD":0}
		visit.prices[p.item_id]=price
	if price[p.currency] != p.amount or price["USD" if p.currency == "VKC" else "VKC"] != 0:
		return "trade_terms"
	return _transfer(state, visit_id, [{"item_id": p.item_id, "inventory": p.inventory, "x": p.x, "y": p.y, "rotated": p.rotated}], action_id)

func _deliver(state: Dictionary, p: Dictionary, action_id: String) -> String:
	if not Rules.keys(p, ["visit_id", "placements"]) or not Rules.identifier(p.visit_id) or not p.placements is Array or not state.visits.has(p.visit_id):
		return "delivery_shape"
	if state.visits[p.visit_id].scope.kind != "special_contract":
		return "delivery_context"
	return _transfer(state, p.visit_id, p.placements, action_id)

func _transfer(state: Dictionary, visit_id: String, placements: Array, action_id: String) -> String:
	var visit: Dictionary = state.visits[visit_id]
	if not Visits.in_window(visit, int(state.game_minutes), state.phase):
		return "visit_time"
	var root_ids: Array = []
	for p: Variant in placements:
		if not Rules.keys(p, ["item_id", "inventory", "x", "y", "rotated"]) or not Rules.identifier(p.item_id):
			return "placement_shape"
		root_ids.append(p.item_id)
	var scope: Dictionary = Visits.validate_scope(visit.scope, visit.scope.purpose, root_ids)
	if not scope.ok:
		return scope.error
	var all_ids: Array = []
	var totals: Dictionary = {"VKC": 0, "USD": 0}
	var old_basis: Dictionary = {"VKC": 0, "USD": 0}
	for p: Dictionary in placements:
		if not visit.prices.has(p.item_id) or not state.items.has(p.item_id):
			return "trade_reference"
		var family: Dictionary = Relations.disposition_family(Objects.nodes(state, _definitions), p.item_id, visit.seller)
		if not family.ok:
			return family.error
		if visit.seller == "player" and not Objects.complete(state, _definitions, p.item_id):
			return "incomplete_sale"
		for id: String in family.item_ids:
			if id in all_ids:
				return "duplicate_family"
			all_ids.append(id)
		var basis: Dictionary = Objects.basis(state, family.item_ids)
		if not basis.ok:
			return basis.error
		for currency: String in totals:
			totals[currency] += visit.prices[p.item_id][currency]
			old_basis[currency] = null if old_basis[currency] == null or basis.basis[currency] == null else old_basis[currency] + basis.basis[currency]
	for currency: String in totals:
		if not Rules.integer(totals[currency]) or state.wallets[visit.buyer][currency] < totals[currency]:
			return "insufficient_funds"
	for p: Dictionary in placements:
		if not Rules.identifier(p.inventory) or not state.inventories.has(p.inventory) or state.inventories[p.inventory].owner_id != visit.buyer:
			return "trade_inventory"
		var ids: Array = Objects.family(state, p.item_id)
		var weights: Dictionary = {}
		for id: String in ids:
			weights[id] = _definitions[state.items[id].def_id].weight
		if visit.buyer == "player":
			for currency: String in totals:
				var allocated: Dictionary = Items.allocate_cost(visit.prices[p.item_id][currency], weights)
				if allocated.is_empty():
					return "basis_allocation"
				for id: String in ids:
					state.items[id].basis[currency] = allocated[id]
		for id: String in ids:
			state.items[id].owner_id = visit.buyer
			state.items[id].custodian_id = visit.buyer
			state.items[id].version += 1
		for grid: Dictionary in state.inventories.values():
			if grid.host_item == p.item_id:
				grid.owner_id = visit.buyer
		if not _place(state, state.items[p.item_id], p):
			return "inventory_placement"
	for currency: String in totals:
		state.wallets[visit.buyer][currency] -= totals[currency]
		state.wallets[visit.seller][currency] += totals[currency]
	visit.scope.completed = true
	all_ids.sort()
	root_ids.sort()
	state.ledger.append({"event_id": action_id, "revision": state.revision + 1, "game_minutes": state.game_minutes, "item_ids": all_ids, "root_ids": root_ids, "from": visit.buyer, "to": visit.seller, "amounts": totals, "basis": old_basis, "visit_id": visit_id})
	return ""

func _move(state: Dictionary, p: Dictionary) -> String:
	if not Rules.keys(p, ["item_id", "actor", "inventory", "x", "y", "rotated"]):
		return "move_shape"
	if p.actor != "player" or not _can_change(state, p.get("item_id"), p.get("actor"), true):
		return "move_ownership"
	if not Rules.identifier(p.inventory) or not state.inventories.has(p.inventory) or state.inventories[p.inventory].owner_id != p.actor:
		return "move_reference"
	if not _place(state, state.items[p.item_id], p):
		return "inventory_placement"
	state.items[p.item_id].version += 1
	return ""

func _place(state: Dictionary, item: Dictionary, p: Dictionary) -> bool:
	if not Objects.destination_accessible(state, p.get("inventory"), item.owner_id, item.custodian_id):
		return false
	if not Rules.integer(p.x, 0, 9) or not Rules.integer(p.y, 0, 9) or not p.rotated is bool:
		return false
	item.inventory = p.inventory
	item.x = int(p.x)
	item.y = int(p.y)
	item.rotated = p.rotated
	return true # Full geometry/relations validated once on the complete candidate.

func _can_change(state: Dictionary, item_id: Variant, actor: Variant, allow_filled: bool = false) -> bool:
	if not Rules.identifier(item_id) or not Rules.identifier(actor) or not state.items.has(item_id):
		return false
	var projected: Dictionary = Objects.nodes(state, _definitions)
	var family: Dictionary = Relations.disposition_family(projected, item_id, actor)
	if family.ok:
		return true
	if not allow_filled or family.error != "relation_filled_container":
		return false
	for id: String in state.items:
		if projected[id].container_id == item_id and not Relations.disposition_family(projected, id, actor).ok:
			return false
	return true

func _composition(state: Dictionary, p: Dictionary, action_id: String, kind: String) -> String:
	var fields: Array = ["actor", "root_id", "child_id"]
	if kind == "detach":
		fields.append_array(["inventory", "x", "y", "rotated"])
	if not Rules.keys(p, fields) or state.phase != "workshop" or p.actor != "player" or not _can_change(state, p.root_id, p.actor):
		return "composition_permission"
	if not Rules.identifier(p.child_id) or not state.items.has(p.child_id) or p.root_id == p.child_id:
		return "composition_reference"
	var root: Dictionary = state.items[p.root_id]
	var child: Dictionary = state.items[p.child_id]
	var root_def: Dictionary = _definitions[root.def_id]
	if root_def.kind != "composite" or not root_def.recombine or _definitions[child.def_id].kind != "atomic" or _definitions[child.def_id].tag not in root_def.required_tags:
		return "composition_compatibility"
	if kind == "detach":
		if child.parent_id != p.root_id or not Rules.identifier(p.inventory) or not state.inventories.has(p.inventory) or state.inventories[p.inventory].owner_id != p.actor:
			return "detach_reference"
		child.parent_id = ""
		if not _place(state, child, p):
			return "inventory_placement"
	else:
		if not _can_change(state, p.child_id, p.actor) or not _definitions[child.def_id].inside.is_empty():
			return "attach_permission"
		for id: String in Objects.family(state, p.root_id):
			if id != p.root_id and _definitions[state.items[id].def_id].tag == _definitions[child.def_id].tag:
				return "duplicate_component"
		child.parent_id = p.root_id
		child.inventory = ""
		child.x = -1
		child.y = -1
		child.rotated = false
	child.version += 1
	root.version += 1
	root.field_versions.composition += 1
	if _civilian_composite(state,p.root_id):
		# Assembly changes invalidate prior aggregate function tests even when the
		# new result happens to be identical. Individual component facts survive.
		root.field_versions.functional += 1
	_event(state, action_id, kind, [p.root_id, p.child_id], {"VKC": 0, "USD": 0}, {"VKC": 0, "USD": 0})
	return ""

## Atomic game-only exchange of abstract civilian electronic inventory components.
## Both existing relation mutations happen on the same detached candidate.
## No intermediate receipt, ledger entry, charge, or save generation.
func _replace_component(state:Dictionary,p:Dictionary,action_id:String)->String:
	if _campaign_mode or _lifecycle_mode or _component_market_mode or not _customer_policy.is_empty() or not Rules.keys(p,["actor","root_id","old_child_id","child_id","inventory","x","y","rotated"]) or p.get("actor")!="player" or state.phase!="workshop":
		return "replacement_permission"
	for key:String in ["root_id","old_child_id","child_id"]:
		if not Rules.identifier(p.get(key)) or not state.items.has(p[key]):
			return "replacement_reference"
	if p.root_id in [p.old_child_id,p.child_id] or p.old_child_id==p.child_id or not Rules.identifier(p.inventory) or not state.inventories.has(p.inventory):
		return "replacement_reference"
	var root:Dictionary=state.items[p.root_id]
	var outgoing:Dictionary=state.items[p.old_child_id]
	var incoming:Dictionary=state.items[p.child_id]
	var rd:Dictionary=_definitions[root.def_id]
	var od:Dictionary=_definitions[outgoing.def_id]
	var nd:Dictionary=_definitions[incoming.def_id]
	var categories:Array=["fixture","electronics","civilian_electronics"]
	if rd.category not in categories or od.category not in categories or nd.category not in categories or rd.kind!="composite" or not rd.recombine or od.kind!="atomic" or nd.kind!="atomic" or od.tag!=nd.tag or outgoing.parent_id!=p.root_id or not incoming.parent_id.is_empty():
		return "replacement_compatibility"
	var grid:Dictionary=state.inventories[p.inventory]
	if root.inventory!=p.inventory or incoming.inventory!=p.inventory or grid.owner_id!="player" or not grid.host_item.is_empty() or not _can_change(state,p.root_id,"player") or not _can_change(state,p.child_id,"player"):
		return "replacement_permission"
	var original_version:int=int(root.version)
	var original_composition:int=int(root.field_versions.composition)
	var original_function:int=int(root.field_versions.functional)
	var removal:Dictionary={"actor":"player","root_id":p.root_id,"child_id":p.old_child_id,"inventory":p.inventory,"x":p.x,"y":p.y,"rotated":p.rotated}
	var added:Dictionary={"actor":"player","root_id":p.root_id,"child_id":p.child_id}
	var failure:String=_composition(state,removal,action_id,"detach")
	if not failure.is_empty():
		return failure
	failure=_composition(state,added,action_id,"attach")
	if not failure.is_empty():
		return failure
	# Only final geometry matters. The displaced part can occupy the freed cell.
	if not Objects.grids_valid(state,_definitions):
		return "replacement_placement"
	state.object_events.pop_back()
	state.object_events.pop_back()
	root.version=original_version+1
	root.field_versions.composition=original_composition+1
	if _civilian_composite(state,p.root_id):
		root.field_versions.functional=original_function+1
	_event(state,action_id,"replace_component",[p.root_id,p.old_child_id,p.child_id],{"VKC":0,"USD":0},{"VKC":0,"USD":0})
	return ""

## Public abstract civilian composition affordances. Never expose private condition,
## internal values, or items outside player custody. Detached candidate only;
## actual mutation always goes through execute and its complete validation.
func composition_options(root_id:String,inventory:String)->Dictionary:
	if not _state.items.has(root_id) or not _state.inventories.has(inventory):
		return {}
	var root:Dictionary=_state.items[root_id]
	var d:Dictionary=_definitions[root.def_id]
	var grid:Dictionary=_state.inventories[inventory]
	if root.owner_id!="player" or root.custodian_id!="player" or not root.parent_id.is_empty() or root.inventory!=inventory or grid.owner_id!="player" or not grid.host_item.is_empty() or d.kind!="composite" or not d.recombine or d.category not in ["fixture","electronics","civilian_electronics"]:
		return {}
	var spatial_evening: bool = _alpha_mode and _state.has("alpha_shop") and _state.alpha_shop.profile.has("spatial_opening") and _state.alpha_shop.phase=="EVENING_WORK"
	var enabled:bool=(_state.phase=="workshop" or spatial_evening) and _can_change(_state,root_id,"player")
	var children:Dictionary={}
	for id:String in Objects.family(_state,root_id):
		if id!=root_id:
			children[_definitions[_state.items[id].def_id].tag]=id
	var slots:Array=[]
	for tag:String in d.required_tags:
		var child_id:String=str(children.get(tag,""))
		var slot:Dictionary={"tag":tag,"item_id":child_id,"detach":{},"detach_positions":[],"attach":[],"replace":[]}
		if not child_id.is_empty():
			slot["label_key"]=_definitions[_state.items[child_id].def_id].localization_key
		if enabled and not child_id.is_empty():
			# Find one valid placement with the real candidate geometry, not UI estimates.
			for y:int in range(int(grid.height)):
				for x:int in range(int(grid.width)):
					var payload:Dictionary={"actor":"player","root_id":root_id,"child_id":child_id,"inventory":inventory,"x":x,"y":y,"rotated":false}
					if _composition_preview("detach",payload):
						slot.detach_positions.append(payload)
						if slot.detach.is_empty():
							slot.detach=payload
			for incoming_id:String in _state.items:
				var incoming:Dictionary=_state.items[incoming_id]
				if incoming_id==root_id or incoming.owner_id!="player" or incoming.custodian_id!="player" or incoming.inventory!=inventory or not incoming.parent_id.is_empty() or _definitions[incoming.def_id].tag!=tag or not _can_change(_state,incoming_id,"player"):
					continue
				var option:Dictionary={"actor":"player","root_id":root_id,"old_child_id":child_id,"child_id":incoming_id,"inventory":inventory,"x":incoming.x,"y":incoming.y,"rotated":incoming.rotated}
				if _composition_preview("replace_component",option):
					slot.replace.append(option)
				# Only advertise a valid final placement; no speculative hidden condition.
				# Alternate destination remains accessible via the existing detach/attach path.
		elif enabled:
			for id:String in _state.items:
				var row:Dictionary=_state.items[id]
				if id==root_id or row.owner_id!="player" or row.custodian_id!="player" or row.inventory!=inventory or not row.parent_id.is_empty() or _definitions[row.def_id].tag!=tag:
					continue
				var payload:Dictionary={"actor":"player","root_id":root_id,"child_id":id}
				if _composition_preview("attach",payload):
					slot.attach.append(payload)
		slots.append(slot)
	var result: Dictionary = {"root_id":root_id,"enabled":enabled,"slots":slots,"revision":_state.revision}
	if d.category=="civilian_electronics":
		var family: Array = Objects.family(_state,root_id)
		var costs: Dictionary = {}
		for slot: Dictionary in slots:
			if not slot.item_id.is_empty():
				costs[slot.item_id] = _state.items[slot.item_id].basis.duplicate(true)
			for option: Dictionary in slot.attach+slot.replace:
				costs[option.child_id] = _state.items[option.child_id].basis.duplicate(true)
		result["family_basis"] = Objects.basis(_state,family).basis
		result["material_basis"] = costs
		result["restore_cost"] = d.restore_cost.duplicate(true)
	return result

func _composition_preview(kind:String,payload:Dictionary)->bool:
	var draft:Dictionary=_state.duplicate(true)
	# Alpha's visible evening phase uses the same legacy workshop primitives;
	# preview that exact temporary phase, without committing a world-clock change.
	if _alpha_mode and draft.has("alpha_shop") and draft.alpha_shop.profile.has("spatial_opening") and draft.alpha_shop.phase=="EVENING_WORK":
		draft.phase="workshop"
	if kind=="replace_component":
		return _replace_component(draft,payload,"preview_only").is_empty() and Objects.grids_valid(draft,_definitions)
	return _composition(draft,payload,"preview_only",kind).is_empty() and Objects.grids_valid(draft,_definitions)

func discard_preview(item_id: String, actor: String = "player") -> Dictionary:
	if actor != "player":
		return _error("discard_permission")
	var family: Dictionary = Relations.disposition_family(Objects.nodes(_state, _definitions), item_id, actor)
	if not family.ok:
		return family
	return {"ok": true, "item_ids": family.item_ids, "basis": Objects.basis(_state, family.item_ids).basis, "revision": _state.revision}

func _discard(state: Dictionary, p: Dictionary, action_id: String) -> String:
	if not Rules.keys(p, ["actor", "item_id", "confirmed_ids"]) or p.actor != "player" or state.phase != "workshop":
		return "discard_permission"
	var family: Dictionary = Relations.disposition_family(Objects.nodes(state, _definitions), p.item_id, p.actor)
	if not family.ok:
		return family.error
	if not p.confirmed_ids is Array or p.confirmed_ids != family.item_ids:
		return "discard_confirmation"
	var loss: Dictionary = Objects.basis(state, family.item_ids)
	if not loss.ok:
		return loss.error
	for id: String in family.item_ids:
		var item: Dictionary = state.items[id]
		state.tombstones[id] = {"def_id": item.def_id, "owner_id": item.owner_id, "custodian_id": item.custodian_id, "basis": item.basis.duplicate(true), "provenance_id": item.provenance_id, "event_id": action_id, "revision": state.revision + 1}
		state.items.erase(id)
	for inv: String in state.inventories.keys():
		if state.inventories[inv].host_item in family.item_ids:
			state.inventories.erase(inv)
	_event(state, action_id, "discard", family.item_ids, loss.basis, {"VKC": 0, "USD": 0})
	return ""

# New civilian electronic composite definitions only. The root functional
# flag represents its own condition; observed whole-unit function additionally
# depends on completeness and each installed component's fictional condition.
func _civilian_composite(state:Dictionary,id:String)->bool:
	if not state.items.has(id):
		return false
	var d:Dictionary=_definitions[state.items[id].def_id]
	return d.category=="civilian_electronics" and d.kind=="composite"

func _civilian_parts_usable(state:Dictionary,id:String)->bool:
	if not Objects.complete(state,_definitions,id):
		return false
	for child_id:String in Objects.family(state,id):
		if child_id!=id and not state.items[child_id].functional:
			return false
	return true

func _observed_function(state:Dictionary,id:String)->bool:
	return bool(state.items[id].functional) and (not _civilian_composite(state,id) or _civilian_parts_usable(state,id))

# Public owner-only, known observations and actual acquired cost. No hidden
# item condition, trade prediction, private NPC prices or invented valuation.
func inventory_appraisal(id:String)->Dictionary:
	if not _state.items.has(id) or not InspectionAccess.stock_access(_state,id,"player"):
		return {}
	var item:Dictionary=_state.items[id]
	var d:Dictionary=_definitions[item.def_id]
	var basic:bool=_calendar_mode and item.def_id in VisitObservation.BASIC_DEFINITIONS_V1 and d.kind=="atomic"
	if d.category!="civilian_electronics" and not basic:
		return {}
	var view:Dictionary=knowledge_view(id)
	var facts:Dictionary={}
	for record:Dictionary in view.get("observations",[]):
		if record.observation_key not in ["functional","complete","restored"] or record.is_claim:
			continue
		# Free owned reviews share a clock minute with evening composition.
		# Saved JSON sorts dictionary keys, so iteration order is not chronology.
		# Prefer a current fact, then the actual command revision (including
		# archived receipts), rather than the clock minute or action ID order.
		var prior_fact:Dictionary=facts.get(record.observation_key,{})
		if prior_fact.is_empty() or (record.current and not prior_fact.current) or (record.current==prior_fact.current and Receipt.receipt_revision(_state,record.evidence_id)>Receipt.receipt_revision(_state,prior_fact.evidence_id)):
			facts[record.observation_key]=record
	# Reuse already obtained purchase evidence if its field version remains current.
	# This is a derived DTO only; the historical receipt and value are untouched.
	if basic:
		for entry:Dictionary in VisitObservation.records(_state).values():
			var record:Dictionary=entry.record
			if record.item_id!=id or record.observation_key!="function_status" or record.observed_value not in ["serviceable","inoperable"]:
				continue
			var fact:Dictionary=Evidence.public_view(record,item.field_versions,id)
			var prior:Dictionary=facts.get("functional",{})
			if not fact.is_empty() and (prior.is_empty() or (fact.current and not prior.current) or (fact.current==prior.current and Receipt.receipt_revision(_state,fact.evidence_id)>Receipt.receipt_revision(_state,prior.evidence_id))):
				fact.observation_key="functional"
				fact.observed_value=record.observed_value=="serviceable"
				facts["functional"]=fact
	var tests:Array=[]
	for key:String in (["functional"] if basic else ["functional","complete","restored"]):
		if key=="complete" and d.kind!="composite":
			continue
		var current:bool=basic and facts.get(key,{}).get("current",false)
		for record:Dictionary in view.get("observations",[]):
			if record.observation_key==key and record.current and not record.is_claim:
				current=true
		var review:bool=_calendar_mode and _state.phase in ["shop","workshop"] and not Calendar.complete(_state)
		var allowed:bool=not current and (review if _calendar_mode else InspectionAccess.generic_end(_state,id,"player",int(d.observation_minutes))>=0)
		tests.append({"key":key,"minutes":0 if _calendar_mode else d.observation_minutes,"allowed":allowed,"fact":facts.get(key,{}),"owned_review":_calendar_mode})
	var family:Dictionary=Objects.basis(_state,Objects.family(_state,id))
	var known:Dictionary={}
	for key:String in facts:
		if facts[key].current:
			known[key]=facts[key].observed_value
	# Completeness is definitional for a single non-composite object, not a hidden condition.
	if d.kind=="atomic":
		known["complete"]=true
	return {"item_id":id,"quality":Items.quality_from_observations(known),"basis":family.get("basis",{}),"tests":tests,"revision":_state.revision}

## Cosmetic care only: an observed work record, no hidden defect changes,
## no value bonus, no new item fields, no time or cash effect. Pilot on known
## civilian stock definitions; no service/property outside player ownership.
func _exterior_care(state: Dictionary,id: String) -> Dictionary:
	if not _calendar_mode or not state.items.has(id) or not _can_change(state,id,"player"):
		return {}
	var item: Dictionary = state.items[id]
	if item.def_id not in ["civil_receiver","portable_radio","fictional_watch_p2","demo_tool","demo_electronics"]:
		return {}
	var cleaned: bool = false
	for event: Dictionary in state.object_events:
		if event.type=="clean_exterior" and event.item_ids==[id]:
			cleaned=true
	return {"cleaned":cleaned,"allowed":not cleaned and state.phase=="workshop" and not Calendar.complete(state)}

func exterior_care_view(id: String) -> Dictionary:
	return _exterior_care(_state,id)

func _clean_exterior(state: Dictionary,p: Dictionary,action_id: String) -> String:
	if not Rules.keys(p,["actor","item_id"]) or p.actor!="player" or not Rules.identifier(p.item_id):
		return "exterior_care_shape"
	var care: Dictionary = _exterior_care(state,p.item_id)
	if care.is_empty() or not care.allowed:
		return "exterior_care_permission"
	_event(state,action_id,"clean_exterior",[p.item_id],{"VKC":0,"USD":0},{"VKC":0,"USD":0})
	return ""

# Shared physical permission boundary. This helper does not inspect hidden
# condition or funds, and does not itself grant a command.
func _restore_access(state:Dictionary,id:String)->String:
	if state.phase!="workshop" or not state.items.has(id):
		return ""
	var item:Dictionary=state.items[id]
	var service:bool=item.status=="custody_service" and item.custodian_id=="player" and item.service_permission and not item.protected and item.reservation_id.is_empty() and item.parent_id.is_empty()
	if not _can_change(state,id,"player") and not service:
		return ""
	if service:
		var box_id:String=state.inventories[item.inventory].host_item
		if not box_id.is_empty():
			var box:Dictionary=state.items[box_id]
			if box.protected or not box.reservation_id.is_empty() or box.status!="stock":
				return ""
		for child_id:String in Objects.family(state,id):
			if state.items[child_id].protected or not state.items[child_id].reservation_id.is_empty():
				return ""
	return "service" if service else "owned"

# Public current function sample, never the item's authoritative condition.
func _known_work_function(id:String)->Variant:
	for test:Dictionary in inventory_appraisal(id).get("tests",[]):
		if test.key=="functional":
			var fact:Dictionary=test.fact
			if fact.get("current",false) and not fact.get("is_claim",true) and fact.get("observed_value") is bool:
				return fact.observed_value
	return null

# Only disclose work eligibility from visible composition, lawful access,
# accepted service terms or current owned evidence. Unexamined usable parts
# remain unknown; a proposed attempt is not a guarantee of execution.
func restoration_preview(id:String)->Dictionary:
	if not _calendar_mode or Calendar.complete(_state):
		return {}
	var mode:String=_restore_access(_state,id)
	if mode.is_empty():
		return {}
	var item:Dictionary=_state.items[id]
	var d:Dictionary=_definitions[item.def_id]
	if not d.restorable:
		return {}
	var result:Dictionary={"id":id,"status":"unavailable"}
	if mode=="service" and Service.work_job(_state,id).is_empty():
		return result
	if not Objects.complete(_state,_definitions,id):
		result.status="incomplete"
		return result
	if mode=="owned":
		var function_fact:Variant=_known_work_function(id)
		if function_fact==null:
			result.status="review_required"
			return result
		if function_fact==true:
			result.status="serviceable"
			return result
		if _civilian_composite(_state,id):
			for child_id:String in Objects.family(_state,id):
				if child_id!=id and _known_work_function(child_id)==false:
					result.status="known_bad_component"
					return result
	result.status="attempt"
	result["cost"]=d.restore_cost.duplicate(true)
	return result

func _restore_item(state: Dictionary, p: Dictionary, action_id: String) -> String:
	if not Rules.keys(p, ["actor", "item_id"]) or p.actor != "player" or state.phase != "workshop" or not state.items.has(p.item_id):
		return "restore_permission"
	var item: Dictionary = state.items[p.item_id]
	var mode:String=_restore_access(state,p.item_id)
	if mode.is_empty():
		return "restore_permission"
	var service:bool=mode=="service"
	var d: Dictionary = _definitions[item.def_id]
	if not d.restorable or item.functional or not Objects.complete(state, _definitions, p.item_id):
		return "restore_state"
	if _civilian_composite(state,p.item_id) and not _civilian_parts_usable(state,p.item_id):
		return "restore_components"
	for currency: String in ["VKC", "USD"]:
		if state.wallets[p.actor][currency] < d.restore_cost[currency]:
			return "insufficient_funds"
		state.wallets[p.actor][currency] -= d.restore_cost[currency]
		if not service and item.basis[currency] != null:
			item.basis[currency] += d.restore_cost[currency]
	item.functional = true
	item.restored = true
	item.version += 1
	item.field_versions.functional += 1
	item.field_versions.restored += 1
	_event(state, action_id, "restore_item", [p.item_id], {"VKC": 0, "USD": 0}, d.restore_cost.duplicate(true))
	return ""

func _event(state: Dictionary, id: String, kind: String, ids: Array, basis: Dictionary, expenses: Dictionary) -> void:
	state.object_events.append({"event_id": id, "revision": state.revision + 1, "type": kind, "item_ids": ids.duplicate(), "basis": basis, "expenses": expenses})

func _accessible(state: Dictionary, id: String, observer: String) -> bool:
	if observer != "player" or not state.items.has(id):
		return false
	if CustomerInspection.enabled(state):
		# Never fall through to the generic visit read permission, including at closing.
		return state.phase == "workshop" and state.items[id].owner_id == "player" and state.items[id].custodian_id == "player"
	return InspectionAccess.generic_read(state, id, observer)

func _observe(state: Dictionary, p: Dictionary, action_id: String) -> String:
	if ComponentAppraisal.recognizes(p.get("key")):
		return ComponentAppraisal.observe(state, _definitions, p, action_id)
	if CustomerInspection.enabled(state):
		return "observation_permission"
	var owned_review:bool=Rules.keys(p,["actor","item_id","key","owned_review"]) and p.get("owned_review")==true
	if (not Rules.keys(p,["actor","item_id","key"]) and not owned_review) or not Rules.identifier(p.item_id) or p.key not in ["functional","restored","complete"] or not p.actor is String or not _accessible(state,p.item_id,p.actor):
		return "observation_permission"
	if owned_review:
		if not state.has("calendar") or state.phase not in ["shop","workshop"] or Calendar.complete(state) or not InspectionAccess.stock_access(state,p.item_id,p.actor):
			return "observation_permission"
	elif state.phase!="shop":
		return "observation_permission"
	var item: Dictionary = state.items[p.item_id]
	var field: String = "composition" if p.key == "complete" else p.key
	for record: Dictionary in state.knowledge.values():
		if record.item_id == p.item_id and record.observation_key == p.key and Evidence.is_current(record.dependent_field_versions, item.field_versions):
			return "evidence_already_known"
	var value: bool = Objects.complete(state, _definitions, p.item_id) if p.key == "complete" else (_observed_function(state,p.item_id) if p.key=="functional" else item[p.key])
	var minute: int = int(state.game_minutes) if owned_review else InspectionAccess.generic_end(state, p.item_id, p.actor, int(_definitions[item.def_id].observation_minutes))
	if minute < 0:
		return "observation_permission_or_time"
	var sampled: Dictionary = Observation.capture(action_id, p.item_id, p.key, "record", minute, value, {field: item.field_versions[field]})
	if sampled.is_empty():
		return "observation_record"
	state.game_minutes = minute
	state.knowledge[action_id] = sampled
	return ""

func save_capacity_view() -> Dictionary:
	return SnapshotFormat.capacity(_state) if not _state.is_empty() else {}

func component_market_view() -> Dictionary:
	return ComponentMarket.view(_state, _definitions) if _component_market_mode and not _state.is_empty() else {}

func component_workshop_view() -> Dictionary:
	return ComponentAppraisal.view(_state, _definitions)

func component_recovery_view(ids: Array) -> Dictionary:
	return ComponentAppraisal.recovery(_state, ids)

func knowledge_view(item_id: String, observer: String = "player") -> Dictionary:
	if not _accessible(_state, item_id, observer):
		return {}
	var known: Dictionary = {}
	var records: Array = []
	for record: Dictionary in _state.knowledge.values():
		if record.item_id != item_id or record.observer_id != observer:
			continue
		var view: Dictionary = Evidence.public_view(record, _state.items[item_id].field_versions, item_id)
		if not view.is_empty():
			if ComponentAppraisal.recognizes(record.observation_key):
				view.current = ComponentAppraisal.fact_current(record, _state.items[item_id])
			records.append(view)
			if view.current and not view.is_claim:
				known[view.observation_key] = view.observed_value
	return {"item_id": item_id, "observations": records, "quality": Items.quality_from_observations(known)}

func _advance(state: Dictionary, payload: Dictionary, action_id: String) -> String:
	if not Rules.keys(payload, ["minutes"]) or not Rules.integer(payload.minutes, 1, 240):
		return "time_range"
	if CustomerInspection.enabled(state) and state.customer_inspection.has("waits"):
		state.customer_inspection.waits[action_id] = int(payload.minutes)
	state.game_minutes += int(payload.minutes)
	return ""

func counter_view() -> Dictionary:
	if not _campaign_mode or _state.is_empty():
		return {}
	var result: Dictionary = Opening.view(_state)
	# First-day pilot: only the known counter radio, never hidden external stock.
	result["item_history"] = ItemLineage.public_history(_state, "R001")
	if _day_one_mode:
		result["day_one"] = DayOne.view(_state, _definitions)
		if _composite_pilot_mode and result.day_one.get("started", false):
			result["composite_pilot"] = {"can_offer": Composite.can_offer(_state), "workshop": ComponentAppraisal.view(_state, _definitions) if Composite.enabled(_state) else {}}
			if Composite.live(_state):
				result.day_one.can_close_shop = false
				result.day_one.can_wholesale = false
	return result

func validate(state: Dictionary, receipt_limit: int = MAX_RECEIPTS, legacy_prefix: bool = false) -> bool:
	_validation_error = ""
	var keys: Array = STATE_KEYS.duplicate()
	if _alpha_mode:
		keys.append("alpha_shop")
	if _calendar_mode:
		keys.append("calendar")
	if _lifecycle_mode:
		keys.append("lifecycle")
		if state.has("component_hypotheses"):
			_validation_error = "guard_1"
			return false
	if _campaign_mode:
		keys.append("campaign")
		if _day_one_mode and not legacy_prefix:
			keys.append("day_one")
			if _composite_pilot_mode and Composite.enabled(state) and state.has("component_hypotheses"):
				keys.append("component_hypotheses")
	elif state.has("component_hypotheses"):
		keys.append("component_hypotheses")
	if not _customer_policy.is_empty():
		keys.append("customer_inspection")
	if _component_market_mode and not legacy_prefix:
		keys.append("component_market")
	if not Rules.keys(state, keys) or not Rules.integer(state.revision) or not Rules.integer(state.game_minutes, 0, 60480):
		_validation_error = "guard_2"
		return false
	for key: String in ["wallets", "inventories", "items", "receipts", "receipt_archive"]:
		if not state[key] is Dictionary:
			_validation_error = "guard_3"
			return false
	if not state.ledger is Array or state.ledger.size() > state.revision or state.receipts.size() > receipt_limit or state.receipts.size() + state.receipt_archive.size() != state.revision:
		_validation_error = "guard_4"
		return false
	var campaign_42:bool=state.get("calendar",{}).get("profile",{}).get("id")=="campaign_42"
	if state.wallets.is_empty() or state.wallets.size() > (64 if campaign_42 else 32) or state.inventories.size() > (64 if campaign_42 else 32) or state.items.size() > 128:
		_validation_error = "guard_5"
		return false
	for owner: Variant in state.wallets:
		if not Rules.identifier(owner) or not Rules.keys(state.wallets[owner], ["VKC", "USD"]):
			_validation_error = "guard_6"
			return false
		for currency: String in ["VKC", "USD"]:
			if not Rules.integer(state.wallets[owner][currency]):
				_validation_error = "guard_7"
				return false
	if not Objects.validate(state, _definitions):
		_validation_error = "guard_8"
		return false
	var history_state: Dictionary = state
	if _calendar_mode and _calendar_seed.get("calendar",{}).has("dormant"):
		if not CalendarLife.valid(state,_definitions):
			_validation_error = "calendar_lifecycle_directory"
			return false
		history_state = CalendarLife.read_history(state)
	if _lifecycle_mode:
		if not state.get("lifecycle") is Dictionary or not state.lifecycle.get("dormant") is Dictionary:
			_validation_error = "guard_9"
			return false
		var directory: Dictionary = Identity.audit(Lifecycle.partition(state), _definitions)
		if not directory.ok:
			_validation_error = "guard_10"
			return false
		history_state = Lifecycle.read_history(state)
	if not _contexts_valid(history_state):
		_validation_error = "guard_11"
		return false
	var event_ids: Dictionary = {}
	var used_visits: Dictionary = {}
	for entry: Variant in state.ledger:
		if not Rules.keys(entry, ["event_id", "revision", "game_minutes", "item_ids", "root_ids", "from", "to", "amounts", "basis", "visit_id"]):
			_validation_error = "guard_12"
			return false
		if not Rules.identifier(entry.event_id) or event_ids.has(entry.event_id) or not state.wallets.has(entry.from) or not state.wallets.has(entry.to) or entry.from == entry.to or not state.visits.has(entry.visit_id):
			_validation_error = "guard_13"
			return false
		if not _ids_valid(history_state, entry.item_ids) or not _ids_valid(history_state, entry.root_ids) or not Objects.money(entry.amounts, false) or not Objects.money(entry.basis) or not Rules.integer(entry.revision, 1, int(state.revision)) or not Rules.integer(entry.game_minutes, 0, int(state.game_minutes)):
			_validation_error = "guard_14"
			return false
		if used_visits.has(entry.visit_id):
			_validation_error = "guard_15"
			return false
		used_visits[entry.visit_id] = true
		var visit: Dictionary = state.visits[entry.visit_id]
		if not visit.scope.completed or visit.buyer != entry.from or visit.seller != entry.to or entry.game_minutes < visit.opens or entry.game_minutes > visit.expires:
			_validation_error = "guard_16"
			return false
		var prices: Dictionary = {"VKC": 0, "USD": 0}
		for id: String in entry.root_ids:
			if id not in entry.item_ids or not visit.prices.has(id):
				_validation_error = "guard_17"
				return false
			for currency: String in prices:
				prices[currency] += visit.prices[id][currency]
		if prices != entry.amounts:
			_validation_error = "guard_18"
			return false
		event_ids[entry.event_id] = true
	for id: String in state.visits:
		if state.visits[id].scope.completed != used_visits.has(id):
			_validation_error = "guard_19"
			return false
	var receipt_revisions: Dictionary = {}
	for action_id: Variant in state.receipt_archive:
		var archived: Variant = state.receipt_archive[action_id]
		if not Rules.identifier(action_id) or state.receipts.has(action_id) or not archived is Array or archived.size() not in [3, 4]:
			_validation_error = "guard_20"
			return false
		if not archived[0] is String or archived[0].length() != 64 or not Rules.integer(archived[1], 1, int(state.revision)) or (archived[2] not in COMMAND_TYPES and archived[2] not in AlphaShop.ACTIONS):
			_validation_error = "guard_21"
			return false
		for character: String in archived[0]:
			if character not in "0123456789abcdef":
				_validation_error = "guard_22"
				return false
		if receipt_revisions.has(int(archived[1])) or (archived[2] in ["trade", "deliver", "confirm_purchase", "alpha_trade", "alpha_commission_deliver"]) != event_ids.has(action_id):
			_validation_error = "guard_23"
			return false
		receipt_revisions[int(archived[1])] = true
	for action_id: Variant in state.receipts:
		var receipt: Variant = state.receipts[action_id]
		if not Rules.identifier(action_id) or not Rules.keys(receipt, ["fingerprint", "result"]):
			_validation_error = "guard_24"
			return false
		if not receipt.fingerprint is String or receipt.fingerprint.length() > 4096 or not Rules.keys(receipt.result, ["ok", "revision"]):
			_validation_error = "guard_25"
			return false
		if not receipt.result.ok is bool or receipt.result.ok != true or not Rules.integer(receipt.result.revision, 1, int(state.revision)):
			_validation_error = "guard_26"
			return false
		if receipt_revisions.has(int(receipt.result.revision)):
			_validation_error = "guard_27"
			return false
		receipt_revisions[int(receipt.result.revision)] = true
		var command: Variant = JSON.parse_string(receipt.fingerprint)
		if not Rules.keys(command, ["action_id", "expected_revision", "type", "payload"]):
			_validation_error = "guard_28"
			return false
		if command.action_id != action_id or not Rules.integer(command.expected_revision) or command.expected_revision + 1 != receipt.result.revision or (command.type not in COMMAND_TYPES and command.type not in AlphaShop.ACTIONS) or not command.payload is Dictionary:
			_validation_error = "guard_29"
			return false
		if Rules.canonical(command) != receipt.fingerprint:
			_validation_error = "guard_30"
			return false
		if (command.type in ["trade", "deliver", "confirm_purchase", "alpha_trade", "alpha_commission_deliver"]) != event_ids.has(action_id):
			_validation_error = "guard_31"
			return false
	for entry: Dictionary in state.ledger:
		if _receipt_revision(state, entry.event_id) != entry.revision or _receipt_type(state, entry.event_id) not in ["trade", "deliver", "confirm_purchase", "alpha_trade", "alpha_commission_deliver"]:
			_validation_error = "guard_32"
			return false
		if state.receipts.has(entry.event_id):
			var command: Dictionary = JSON.parse_string(state.receipts[entry.event_id].fingerprint)
			if command.type in ["trade", "alpha_trade"]:
				var p: Dictionary = command.payload
				if p.get("item_id") not in entry.root_ids or p.get("seller") != entry.to or p.get("buyer") != entry.from or p.get("currency") not in ["VKC", "USD"] or p.get("amount") != entry.amounts[p.currency]:
					_validation_error = "guard_33"
					return false
			if command.type == "alpha_commission_deliver":
				# Unlike generic trade, the public command contains a request
				# identity, never caller-authored price/recipient/item fields.
				var id: String = str(command.payload.get("request_id",""))
				var delivery: Dictionary = state.get("alpha_shop",{}).get("commissions",{}).get("entries",{}).get(id,{})
				if delivery.get("status") != "fulfilled" or delivery.get("deliver_action") != entry.event_id or delivery.get("item_id") not in entry.root_ids:
					_validation_error = "alpha_commission_ledger_binding"
					return false
	if not _customer_policy.is_empty() and not CustomerInspection.valid(state, _customer_policy):
		_validation_error = "guard_34"
		return false
	if not ComponentAppraisal.valid_hypotheses(state) or not _history_valid(history_state):
		_validation_error = "guard_35"
		return false
	if not ComponentAppraisal.valid_customer_fixture(state, _definitions) or not CustomerInspection.economy_valid(state, _definitions):
		_validation_error = "guard_36"
		return false
	if _campaign_mode:
		if _day_one_mode and not legacy_prefix:
			if not _day_one_valid(state):
				_validation_error = "guard_37"
				return false
		elif not Opening.valid(state):
			_validation_error = "guard_38"
			return false
	if _component_market_mode and not legacy_prefix and not _component_market_valid(state):
		_validation_error = "guard_39"
		return false
	if _alpha_mode and not _alpha_valid(state):
		_validation_error = "alpha_replay"
		return false
	if _calendar_mode and not _calendar_valid(state):
		_validation_error = "guard_40"
		return false
	if _lifecycle_mode and not Lifecycle.audit(state, _definitions, _lifecycle_seed):
		_validation_error = "guard_41"
		return false
	for table: Dictionary in [state.receipts, state.receipt_archive]:
		for id: String in table:
			if (not _alpha_mode and _receipt_type(state, id) in AlphaShop.ACTIONS) or (_alpha_mode and _receipt_type(state, id) not in AlphaShop.ACTIONS):
				_validation_error = "alpha_profile_permission"
				return false
			if not _calendar_mode and (_receipt_type(state, id) in Calendar.ACTIONS or _receipt_type(state, id) in Medicine.ACTIONS or _receipt_type(state, id) in VisitQueue.ACTIONS or _receipt_type(state, id) in Service.ACTIONS or _receipt_type(state, id) in Contract.ACTIONS or _receipt_type(state, id) == "inspect_subject" or _receipt_type(state, id) in VisitAssessment.ACTIONS or _receipt_type(state, id) == VisitDeck.ACTION or _receipt_type(state, id) == VisitPrice.ACTION):
				_validation_error = "guard_42"
				return false
			if _receipt_type(state,id) in CalendarTracking.ACTIONS and not (_calendar_mode and CalendarLife.enabled(state) and state.calendar.has("tracking")):
				_validation_error = "calendar_tracking_permission"
				return false
			if not _lifecycle_mode and _receipt_type(state, id) in Lifecycle.ACTIONS and not (_calendar_mode and CalendarLife.enabled(state) and _receipt_type(state,id) in CalendarLife.ACTIONS):
				_validation_error = "guard_43"
				return false
	if not _campaign_mode:
		for table: Dictionary in [state.receipts, state.receipt_archive]:
			for id: String in table:
				if _receipt_type(state, id) in Composite.ACTIONS or _receipt_type(state, id) in Opening.ACTIONS or _receipt_type(state, id) in DayOne.ACTIONS or (_customer_policy.is_empty() and _receipt_type(state, id) in CustomerInspection.ACTIONS) or ((_component_market_mode == false or legacy_prefix) and _receipt_type(state, id) == ComponentMarket.ACTION):
					_validation_error = "guard_44"
					return false
	return true

func _receipt_revision(state: Dictionary, id: String) -> int:
	return Receipt.receipt_revision(state, id)

func _receipt_type(state: Dictionary, id: String) -> String:
	return Receipt.receipt_type(state, id)

func _ids_valid(state: Dictionary, ids: Variant) -> bool:
	if not ids is Array or ids.is_empty() or ids.size() > 128:
		return false
	var seen: Dictionary = {}
	for id: Variant in ids:
		if not Rules.identifier(id) or seen.has(id) or (not state.items.has(id) and not state.tombstones.has(id)):
			return false
		seen[id] = true
	return true

func _contexts_valid(state: Dictionary) -> bool:
	for id: Variant in state.visits:
		var v: Variant = state.visits[id]
		if not Rules.identifier(id) or not Rules.keys(v, ["scope", "seller", "buyer", "prices", "opens", "expires", "allow_inspection"]):
			return false
		if not Rules.identifier(v.seller) or not Rules.identifier(v.buyer) or v.seller == v.buyer or not state.wallets.has(v.seller) or not state.wallets.has(v.buyer) or not v.allow_inspection is bool or not v.prices is Dictionary or v.prices.is_empty():
			return false
		if "player" not in [v.seller, v.buyer]:
			return false
		if not Rules.integer(v.opens, 0, 60480) or not Rules.integer(v.expires, int(v.opens), 60480) or not Rules.keys(v.scope, ["visit_id", "kind", "purpose", "completed", "required_ids"]) or v.scope.visit_id != id or not v.scope.completed is bool:
			return false
		var scope: Dictionary = v.scope.duplicate(true)
		scope.completed = false
		var ids: Array = v.prices.keys()
		if not _ids_valid(state, ids):
			return false
		var checked: Dictionary = Visits.validate_scope(scope, scope.purpose, ids if scope.kind == "special_contract" else [ids[0]])
		if not checked.ok or scope.purpose not in ["purchase", "sale", "delivery"] or (scope.purpose == "purchase" and v.buyer != "player") or (scope.purpose == "sale" and v.seller != "player"):
			return false
		for price: Variant in v.prices.values():
			if not Objects.money(price, false):
				return false
	return true

func _history_valid(state: Dictionary) -> bool:
	var events: Dictionary = {}
	for e: Variant in state.object_events:
		if not Rules.keys(e, ["event_id", "revision", "type", "item_ids", "basis", "expenses"]) or not Rules.identifier(e.event_id) or events.has(e.event_id) or e.type not in ["detach", "attach", "discard", "restore_item", "replace_component","clean_exterior"]:
			return false
		if not _ids_valid(state, e.item_ids) or not Objects.money(e.basis) or not Objects.money(e.expenses, false) or e.revision != _receipt_revision(state, e.event_id) or e.type != ("restore_item" if _receipt_type(state, e.event_id) == "alpha_service_repair" else _receipt_type(state, e.event_id).trim_prefix("spatial_")):
			return false
		events[e.event_id] = e
		if e.type=="clean_exterior":
			if e.item_ids.size()!=1 or e.basis!={"VKC":0,"USD":0} or e.expenses!={"VKC":0,"USD":0}:
				return false
			if state.receipts.has(e.event_id):
				var care_payload: Dictionary = JSON.parse_string(state.receipts[e.event_id].fingerprint).payload
				if care_payload.get("actor")!="player" or e.item_ids!=[care_payload.get("item_id")]:
					return false
		if e.type=="replace_component":
			if e.item_ids.size()!=3 or e.item_ids[0]==e.item_ids[1] or e.item_ids[0]==e.item_ids[2] or e.item_ids[1]==e.item_ids[2] or e.basis!={"VKC":0,"USD":0} or e.expenses!={"VKC":0,"USD":0}:
				return false
			if state.receipts.has(e.event_id):
				var payload:Dictionary=JSON.parse_string(state.receipts[e.event_id].fingerprint).payload
				if e.item_ids!=[payload.get("root_id"),payload.get("old_child_id"),payload.get("child_id")]:
					return false
		if e.type == "discard":
			var basis: Dictionary = {}
			for id: String in e.item_ids:
				if not state.tombstones.has(id) or state.tombstones[id].event_id != e.event_id:
					return false
				basis[id] = state.tombstones[id].basis
			if Items.sum_basis(basis, e.item_ids).get("basis") != e.basis or e.expenses != {"VKC": 0, "USD": 0}:
				return false
	for table: Dictionary in [state.receipts, state.receipt_archive]:
		for id: String in table:
			var kind: String = _receipt_type(state, id)
			if state.receipt_archive.has(id) and state.receipt_archive[id].size() == 4:
				if not ComponentHistory.valid_link(state, id, ComponentAppraisal.observation_keys()):
					return false
				continue
			if kind in ["detach", "attach", "discard", "restore_item", "alpha_service_repair","spatial_attach","spatial_detach","spatial_restore_item", "replace_component","clean_exterior"] and not events.has(id):
				return false
			if kind == "observe" and not state.knowledge.has(id):
				return false
			if kind == "record_component_hypothesis" and not state.get("component_hypotheses", {}).has(id):
				return false
	for id: String in state.tombstones:
		var tomb: Dictionary = state.tombstones[id]
		if not events.has(tomb.event_id) or events[tomb.event_id].type != "discard" or id not in events[tomb.event_id].item_ids or events[tomb.event_id].revision != tomb.revision:
			return false
	for id: Variant in state.knowledge:
		var record: Variant = state.knowledge[id]
		if record is Dictionary and ComponentAppraisal.recognizes(record.get("observation_key")):
			if not Rules.identifier(id) or not ComponentAppraisal.valid_observation(state, _definitions, id, record):
				return false
			continue
		if not Observation.bound(state, id, record, "record") or record.observation_key not in ["functional", "restored", "complete"] or not record.observed_value is bool:
			return false
		if not state.items.has(record.item_id) and not state.tombstones.has(record.item_id):
			return false
		var field: String = "composition" if record.observation_key == "complete" else record.observation_key
		if not Rules.keys(record.dependent_field_versions, [field]) or not Rules.integer(record.dependent_field_versions[field]):
			return false
		if state.items.has(record.item_id):
			var item: Dictionary = state.items[record.item_id]
			if record.dependent_field_versions[field] > item.field_versions[field] or Evidence.public_view(record, item.field_versions, record.item_id).is_empty():
				return false
			if Evidence.is_current(record.dependent_field_versions, item.field_versions):
				var truth: bool = Objects.complete(state, _definitions, record.item_id) if field == "composition" else (_observed_function(state,record.item_id) if field=="functional" else item[field])
				if record.observed_value != truth:
					return false
	return true


## Only trusted fresh setup is upgraded here. Old disk schemas are refused by persistence.
func upgrade_state(state: Dictionary) -> Dictionary:
	return Objects.prepare_initial(state)

func _compact(state: Dictionary) -> void:
	while state.receipts.size() > MAX_RECEIPTS:
		var oldest: String = ""
		var revision: int = Rules.LIMIT + 1
		for action_id: String in state.receipts:
			if state.receipts[action_id].result.revision < revision:
				oldest = action_id
				revision = state.receipts[action_id].result.revision
		var receipt: Dictionary = state.receipts[oldest]
		var command: Dictionary = JSON.parse_string(receipt.fingerprint)
		state.receipt_archive[oldest] = [receipt.fingerprint.sha256_text(), revision, command.type]
		state.receipts.erase(oldest)

func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}

## Public geometry only; one placement routine for purchased and moved objects.
func spatial_fit(id: String, inventory: String) -> Dictionary:
	if not _state.items.has(id) or not _state.inventories.has(inventory):
		return {}
	var grid: Dictionary = _state.inventories[inventory]
	var rows: Array = []
	for other_id: String in _state.items:
		var other: Dictionary = _state.items[other_id]
		if other_id == id or other.inventory != inventory or not other.parent_id.is_empty():
			continue
		var shape: Array = Objects.footprint(_state,_definitions,other_id)
		rows.append({"item_id":other_id,"width":shape[0],"height":shape[1],"x":other.x,"y":other.y,"rotated":other.rotated})
	var shape: Array = Objects.footprint(_state,_definitions,id)
	return preload("res://src/domain/grid_primitives.gd").first_fit(grid.width,grid.height,rows,{"item_id":id,"width":shape[0],"height":shape[1],"rotated":false})

func spatial_dimensions(id: String) -> Array:
	return Objects.footprint(_state,_definitions,id) if _state.items.has(id) else []

func spatial_tag(id: String) -> String:
	return str(_definitions[_state.items[id].def_id].get("tag","")) if _state.items.has(id) else ""
