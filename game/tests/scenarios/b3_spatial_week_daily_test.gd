extends "res://tests/scenarios/alpha_b3_integrated_week_test.gd"
const SpatialSeed = preload("res://src/content/b3_spatial_week_seed.gd")
var observed_days: Array = []

func fresh(src: Dictionary) -> RefCounted:
	return super.fresh(SpatialSeed.content(int(src.alpha_profile.visit_random.seed)))

func go(s: RefCounted,kind: String,p: Dictionary={}) -> bool:
	var before: Dictionary = s.snapshot()
	var preview: Dictionary = {}
	if kind in ["alpha_display","alpha_withdraw_display","alpha_trade","spatial_move","spatial_restore_item","spatial_attach","spatial_detach"]:
		preview = s.spatial_action_preview(kind,p)
		check(s.snapshot()==before,"day %d: preview %s preserves the full save candidate"%[before.alpha_shop.day,kind])
		check(preview.get("ok",false),"preview admits the expected campaign action "+kind)
	if not super.go(s,kind,p):
		return false
	if not preview.is_empty() and preview.get("ok",false):
		var after: Dictionary = s.snapshot()
		check(after.revision==before.revision+1,"only confirmation commits "+kind)
		for currency: String in ["VKC","USD"]:
			check(after.wallets.player[currency]-before.wallets.player[currency]==preview[currency],"quoted cash movement matches settlement "+kind+" "+currency)
	if kind=="alpha_settle":
		var state: Dictionary = s.snapshot()
		var view: Dictionary = s.alpha_view()
		observed_days.append(view.day)
		var record := {"day":view.day,"attendance":view.attendance,"wallet":state.wallets.player,
			"settlements":state.ledger.size(),"pawn":state.alpha_shop.week_pawn,"orders":state.alpha_shop.get("outbound",{}),
			"watch_owner":state.items.WAT02.owner_id,"tool_owner":state.items.TL04.owner_id,
			"revision":state.revision}
		print("SPATIAL_DAY ",JSON.stringify(record))
		check(state.items.size()<=128 and state.inventories.storefront_grid.width==6 and state.inventories.pawn_grid.height==3,"bounded stock and approved spaces")
		check(view.attendance.arrived<=view.attendance.planned,"actual arrivals are bounded by frozen plan")
	return true

func done() -> void:
	check(observed_days==[1,2,3,4,5,6,7],"one observable settlement per day")
	super.done()
