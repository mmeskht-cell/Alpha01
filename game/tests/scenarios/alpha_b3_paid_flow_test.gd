extends "res://tests/scenarios/alpha_b3_m7_finite_interest_test.gd"
## Replay the inherited real D2 purchase and D6 resale in general chat.
## Expected figures are the existing signed WAT02 terms, not new profile data.
func go(s: RefCounted, kind: String, p: Dictionary = {}) -> bool:
	if not super.go(s, kind, p):
		return false
	if kind == "alpha_close":
		var view: Dictionary = s.alpha_view()
		var flow: Dictionary = view.local_trade_flow
		var settled_watch: bool = false
		for entry: Dictionary in s.snapshot().ledger:
			if "WAT02" in entry.root_ids and int(entry.game_minutes / 1440) + 1 == int(view.day):
				settled_watch = true
		if settled_watch and view.day == 2:
			check(flow == {"bought":1,"sold":0,"VKC":-80,"USD":0}, "D2 sourced watch purchase")
		elif settled_watch and view.day == 6:
			check(flow == {"bought":0,"sold":1,"VKC":140,"USD":0}, "D6 same-ID resale")
		else:
			check(flow == {"bought":0,"sold":0,"VKC":0,"USD":0}, "no phantom trade")
	return true
