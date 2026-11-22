extends SceneTree
## Q08 technical expansion proof, NOT authored 42-day story or human acceptance.
## One additional data-only commission profile reuses existing G03/Ian visits,
## actual TL04/HY05 and finite original funds. Nothing is minted or dispatched.
const Named = preload("res://src/content/alpha_b2_named_commission_seed.gd")
const Legacy = preload("res://src/content/alpha_b2_commission_seed.gd")
const Commission = preload("res://src/domain/alpha_commission.gd")
const Alpha = preload("res://src/domain/alpha_shop_cycle.gd")
const Session = preload("res://src/domain/game_session.gd")
const Repo = preload("res://src/persistence/save_repository.gd")
const Rules = preload("res://src/domain/value_rules.gd")
const Q08_ID: String = "b2_commission_q08_capacity_1"
var checks: int = 0
var failures: int = 0

func check(ok: bool, description: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", description)
	return ok

func _initialize() -> void:
	var registered: Dictionary = Commission.profiles()
	check(registered.size() == 3 and registered.has(Q08_ID), "bounded data-only profile manifest accepts third authored template")
	check(not Commission.config().is_empty() and not Commission.config(Commission.NAMED_PROFILE).is_empty(), "original G03 and Ian legacy profile files still resolve")
	check(Commission.config("not_registered_profile").is_empty() and Commission.config("../escape").is_empty(), "unregistered/path traversal profile denied")
	var template: Dictionary = Commission.config(Q08_ID)
	if not check(template.get("requests", []).size() == 2 and template.profile_id == Q08_ID, "new template loads without editing Commission source allowlist"):
		quit(1)
		return
	var original: Dictionary = Legacy.content()
	var named: Dictionary = Named.content()
	if not check(not original.is_empty() and not named.is_empty(), "real existing G03 and Ian market source is available"):
		quit(1)
		return
	check(original.alpha_profile.commission_profile_id == Commission.DEFAULT_PROFILE and named.alpha_profile.commission_profile_id == Commission.NAMED_PROFILE, "original source profiles are unmodified")
	var profile: Dictionary = named.alpha_profile.duplicate(true)
	profile.commission_profile_id = Q08_ID
	# Capacity-only extension. Days 8-42 have zero scheduled visitors:
	# NEVER call them 42 days of released economy/story content.
	while profile.days.size() < 42:
		profile.days.append([])
	check(profile.days.size() == 42 and profile.days[41].is_empty(), "data-derived 42-day finite schedule permits empty future days")
	check(Commission.profile_valid(profile, named.state), "third request template is source-bound to original items/actors and 42-day capacity")
	check(Alpha.profile_valid(profile, named.state), "new manifest entry passes original single-counter validation with no new runtime core")
	check(named.state.wallets == original.state.wallets and named.state.items == original.state.items and named.state.visits == original.state.visits, "new template never mints extra wallet, stock or virtual trade")
	var forbidden: Dictionary = template.duplicate(true)
	forbidden.requests.append(template.requests[0].duplicate(true))
	forbidden.requests[2].request_id = "duplicate_offer_new_id"
	check(not Commission.profile_valid_with_config(profile, named.state, forbidden), "duplicate offer and return encounter cannot assign two contracts to same real visitor")
	forbidden = template.duplicate(true)
	forbidden.requests.append(template.requests[1].duplicate(true))
	forbidden.requests[2].request_id = "duplicate_item_new_id"
	check(not Commission.profile_valid_with_config(profile, named.state, forbidden), "same real source item cannot be reserved by two request records")
	forbidden = template.duplicate(true)
	forbidden.requests[1].return_item_id = "TL04"
	check(not Commission.profile_valid_with_config(profile, named.state, forbidden), "Ian cannot be assigned G03-owned source specimen")
	forbidden = template.duplicate(true)
	forbidden.requests[1].due_day = 43
	check(not Commission.profile_valid_with_config(profile, named.state, forbidden), "day beyond finite 42-day boundary is refused")
	var s := Session.new()
	if not check(s.initialize(named.defs, named.state, false, false, {}, profile), "data-only Q08 profile initializes original GameSession with 42-day capacity"):
		printerr("Q08_INITIALIZATION ", s.initialization_error())
		quit(1)
		return
	check(s.snapshot().wallets == named.state.wallets and s.snapshot().items == named.state.items and s.snapshot().ledger == named.state.ledger, "no economy/stock/ledger modifications at initial load")
	check(s.snapshot().alpha_shop.commissions.entries.size() == 2 and s.snapshot().alpha_shop.commissions.settlements.is_empty(), "new profile creates two unoffered source-bound contracts with zero settlement")
	var directory: String = "user://zt_rebuild/q08_data_only_" + str(Time.get_ticks_usec())
	var storage := Repo.new(directory)
	check(storage.save_session(s, "q08").ok, "A/B save new template with original source wallet and stock")
	var resumed := Session.new()
	check(resumed.initialize(named.defs, named.state, false, false, {}, profile) and storage.load_session(resumed, "q08").ok and resumed.snapshot() == s.snapshot(), "new data profile cold restores with exact 42-day binding and zero invented events")
	print("B2_Q08_DATA_TEMPLATE_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
