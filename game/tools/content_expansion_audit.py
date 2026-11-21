#!/usr/bin/env python3
"""Read-only, stdlib-only long-campaign content and capacity preflight.

Uses actual engine guard values and the authored baseline. This is NOT a
42-day gameplay simulation or a proof of future content balance.
"""
import argparse
import json
import math
import re
from pathlib import Path

GAME = Path(__file__).resolve().parents[1]
BASELINE = GAME / "data/campaign/gate2/demo7.json"


def int_const(relative_path, name):
    code = (GAME / relative_path).read_text(encoding="utf-8")
    found = re.search(r"(?m)^const\s+" + re.escape(name) +
                      r"\s*:\s*int\s*=\s*(\d+)\b", code)
    if not found:
        raise ValueError(f"missing integer authority constant: {relative_path}:{name}")
    return int(found.group(1))


def authority_limits():
    game = (GAME / "src/domain/game_session.gd").read_text(encoding="utf-8")
    # Both limits must be parsed from the actual authority rather than
    # guessed from a simulation or silently inherited from older 7-day saves.
    found = re.search(
        r"state\.wallets\.size\(\)\s*>\s*\((\d+)\s+if\s+campaign_42\s+else\s+(\d+)\)\s+or\s+"
        r"state\.inventories\.size\(\)\s*>\s*\((\d+)\s+if\s+campaign_42\s+else\s+(\d+)\)\s+or\s+"
        r"state\.items\.size\(\)\s*>\s*(\d+)", game)
    if not found or 'state.get("calendar",{}).get("profile",{}).get("id")=="campaign_42"' not in game:
        raise ValueError("game_session seven/forty-two-day economic guard changed; manual review required")
    wallets_42, wallets, inventories_42, inventories, active_items = map(int, found.groups())
    return {
        "wallets": wallets, "inventories": inventories,
        "wallets_campaign_42": wallets_42, "inventories_campaign_42": inventories_42,
        "active_items": active_items,
        "observations": int_const("src/domain/visit_appraisal_observation.gd", "MAX_OBSERVATIONS"),
        "observations_campaign_42_lossless_total": int_const("src/domain/appraisal_history_retention.gd", "MAX_TOTAL"),
        "reaction_rules": int_const("src/domain/calendar_reaction.gd", "MAX_RULES"),
        "regional_events": int_const("src/domain/regional_world_state.gd", "MAX_EVENTS"),
        "regional_regions": int_const("src/domain/regional_world_state.gd", "MAX_REGIONS"),
        "npc_return_gates": int_const("src/domain/npc_continuity.gd", "MAX_GATES"),
        "reentry_rules": int_const("src/domain/calendar_lifecycle.gd", "MAX_RETURN_RULES"),
        "dormant_roots": int_const("src/domain/dormant_registry.gd", "LIMIT"),
        "tracked_live": int_const("src/domain/selective_tracking.gd", "MAX_TRACKED"),
        "save_bytes": int_const("src/domain/snapshot_format.gd", "MAX_BYTES"),
        "campaign_minutes": int_const("src/domain/business_clock.gd", "CAMPAIGN_END"),
    }


def authored_baseline(raw):
    """Validate only the documented demo7.json table contract, not story outcomes."""
    errors = []
    if not isinstance(raw, dict) or set(raw) != {"version", "actors", "trades", "services", "schedule"}:
        return {"errors": ["baseline fields"], "days": 0}
    if raw["version"] != 1 or not all(isinstance(raw[k], list)
                                      for k in ("actors", "trades", "services", "schedule")):
        return {"errors": ["baseline types or version"], "days": 0}
    actors = raw["actors"]
    schedule = raw["schedule"]
    roster = set(actors) | {"player"}
    if any(not isinstance(actor, str) or not actor or actor == "player" for actor in actors):
        errors.append("invalid actor")
    if len(actors) != len(set(actors)):
        errors.append("duplicate actor")
    if not schedule or len(schedule) > 42:
        errors.append("day range")
    trade_by_id, definition_by_item = {}, {}
    for row in raw["trades"]:
        if not isinstance(row, list) or len(row) != 7:
            errors.append("trade row shape")
            continue
        visit, day, item, definition, seller, buyer, price = row
        if not all(isinstance(v, str) and v for v in (visit, item, definition, seller, buyer)):
            errors.append("trade identifiers")
            continue
        if visit in trade_by_id:
            errors.append("duplicate trade visit: " + visit)
        trade_by_id[visit] = day
        if seller not in roster or buyer not in roster or seller == buyer or "player" not in (seller, buyer):
            errors.append("invalid trade parties: " + visit)
        if type(day) is not int or not 1 <= day <= len(schedule):
            errors.append("invalid trade day: " + visit)
        if type(price) is not int or price <= 0:
            errors.append("invalid trade price: " + visit)
        if item in definition_by_item and definition_by_item[item] != definition:
            errors.append("item definition changed: " + item)
        definition_by_item[item] = definition
    job_ids = set()
    for row in raw["services"]:
        if not isinstance(row, list) or len(row) != 6:
            errors.append("service row shape")
            continue
        job_id, item, customer, day, fee, cost = row
        if not all(isinstance(v, str) and v for v in (job_id, item, customer)):
            errors.append("service identifiers")
            continue
        if job_id in job_ids:
            errors.append("duplicate job: " + job_id)
        job_ids.add(job_id)
        if customer not in roster or type(day) is not int or not 1 <= day <= len(schedule):
            errors.append("invalid service customer/day: " + job_id)
        if type(fee) is not int or type(cost) is not int or fee < 0 or cost < 0:
            errors.append("invalid service amounts: " + job_id)
    scheduled, unknown = set(), set()
    for day, visits in enumerate(schedule, 1):
        if not isinstance(visits, list):
            errors.append("invalid visit list")
            continue
        for visit in visits:
            if not isinstance(visit, str) or not visit:
                errors.append("invalid scheduled visit")
                continue
            if visit in scheduled:
                errors.append("duplicate scheduled visit: " + visit)
            scheduled.add(visit)
            if visit in trade_by_id:
                if trade_by_id[visit] != day:
                    errors.append("scheduled trade day mismatch: " + visit)
            elif not re.fullmatch(r"(?:pickup|service)\d+", visit):
                # Author-specific/conditional visits have a separate runtime
                # authority and must be reviewed there, not silently accepted.
                unknown.add(visit)
    for visit in sorted(trade_by_id.keys() - scheduled):
        errors.append("unscheduled trade: " + visit)
    return {
        "errors": sorted(set(errors)),
        "days": len(schedule), "visits": sum(len(x) for x in schedule if isinstance(x, list)),
        "actors_excluding_player": len(actors),
        "trade_rows": len(raw["trades"]), "service_rows": len(raw["services"]),
        "unique_item_definitions": len(set(definition_by_item.values())),
        "special_visits_for_manual_review": sorted(unknown),
    }


def projection(limits, target_days, daily_visits, observation_share, npc_pool, fixed_npcs):
    visits = target_days * daily_visits
    observations = math.ceil(visits * observation_share)
    wallets_if_simultaneous = npc_pool + fixed_npcs + 1
    # The 42-day thresholds require an opt-in, content-bound lossless profile.
    # Other profile horizons retain legacy caps. This remains a hypothesis.
    expanded = target_days == 42
    observation_cap = (limits["observations_campaign_42_lossless_total"]
                       if expanded else limits["observations"])
    wallet_cap = limits["wallets_campaign_42"] if expanded else limits["wallets"]
    alerts = []
    if observations > observation_cap:
        alerts.append("projected observations exceed the selected profile guard")
    if wallets_if_simultaneous > wallet_cap:
        alerts.append("hypothetical simultaneous wallets exceed the selected profile guard")
    if target_days * 1440 > limits["campaign_minutes"]:
        alerts.append("target duration exceeds existing absolute game clock")
    return {
        "target_days": target_days, "daily_visits_assumption": daily_visits,
        "observation_share_assumption": observation_share,
        "capacity_profile_assumption": "campaign_42_lossless_v1" if expanded else "legacy",
        "selected_observation_count_guard": observation_cap,
        "selected_wallet_guard": wallet_cap,
        "estimated_visits": visits, "estimated_observations": observations,
        "simultaneous_wallets_if_all_npcs_active": wallets_if_simultaneous,
        "warnings": alerts,
        "not_tested": ["real trade outcomes", "economic affordability", "save-byte growth",
                       "action latency", "actual 42-day authored content", "actual player behavior"],
    }


def self_test():
    raw = json.loads(BASELINE.read_text(encoding="utf-8"))
    baseline = authored_baseline(raw)
    assert not baseline["errors"], baseline["errors"]
    assert baseline["days"] == 7 and baseline["trade_rows"] == 19
    assert baseline["special_visits_for_manual_review"] == ["clinic_service"]
    duplicate = json.loads(json.dumps(raw))
    duplicate["schedule"][0].append(duplicate["schedule"][0][0])
    assert any("duplicate scheduled" in e for e in authored_baseline(duplicate)["errors"])
    invalid_actor = json.loads(json.dumps(raw))
    invalid_actor["trades"][0][4] = "unknown_future_actor"
    assert any("invalid trade parties" in e for e in authored_baseline(invalid_actor)["errors"])
    invalid_day = json.loads(json.dumps(raw))
    invalid_day["trades"][0][1] = 3
    assert any("mismatch" in e for e in authored_baseline(invalid_day)["errors"])
    wrong_definition = json.loads(json.dumps(raw))
    wrong_definition["trades"][1][3] = "different_definition"
    assert any("definition changed" in e for e in authored_baseline(wrong_definition)["errors"])
    limits = authority_limits()
    assert limits["save_bytes"] == 1048576 and limits["wallets"] == 32
    assert limits["wallets_campaign_42"] == 64 and limits["inventories_campaign_42"] == 64
    assert limits["observations"] == 128 and limits["observations_campaign_42_lossless_total"] >= 177
    sample = projection(limits, 42, 6, 0.7, 40, 10)
    assert sample["selected_wallet_guard"] == 64 and sample["selected_observation_count_guard"] >= 177
    assert not sample["warnings"], sample["warnings"]
    stress = projection(limits, 42, 20, 10.0, 100, 10)
    assert any("observations" in w for w in stress["warnings"])
    assert any("wallets" in w for w in stress["warnings"])
    assert projection(limits, 7, 6, 0.7, 40, 10)["warnings"]
    print("ZT_CONTENT_EXPANSION_SELF_TEST_PASS")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-days", type=int, default=42)
    parser.add_argument("--daily-visits", type=int, default=6)
    parser.add_argument("--observation-share", type=float, default=0.7)
    parser.add_argument("--npc-pool", type=int, default=40)
    parser.add_argument("--fixed-npcs", type=int, default=10)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not 1 <= args.target_days <= 365 or not 1 <= args.daily_visits <= 20 or not 0.0 <= args.observation_share <= 10.0 or not 0 <= args.npc_pool <= 1000 or not 0 <= args.fixed_npcs <= 1000:
        parser.error("target assumptions out of scope")
    raw = json.loads(BASELINE.read_text(encoding="utf-8"))
    checked = authored_baseline(raw)
    limits = authority_limits()
    projected = projection(limits, args.target_days, args.daily_visits,
                           args.observation_share, args.npc_pool, args.fixed_npcs)
    result = {"source": "demo7.json plus authority source constants",
              "baseline": checked, "limits": limits, "hypothetical": projected,
              "certifies_long_campaign": False}
    if args.json:
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    else:
        print("ZT_CONTENT_EXPANSION_AUDIT baseline_days=%d baseline_visits=%d trade_rows=%d unique_definitions=%d errors=%d manual_special=%s" %
              (checked["days"], checked["visits"], checked["trade_rows"],
               checked["unique_item_definitions"], len(checked["errors"]),
               ",".join(checked["special_visits_for_manual_review"])))
        print("ZT_EXPANSION_LIMITS " + json.dumps(limits, sort_keys=True))
        print("ZT_EXPANSION_HYPOTHESIS " + json.dumps(projected, sort_keys=True))
    if checked["errors"]:
        raise SystemExit("ZT_CONTENT_EXPANSION_INVALID: " + repr(checked["errors"]))


if __name__ == "__main__":
    main()
