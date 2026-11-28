#!/usr/bin/env python3
"""Replay real seven-day campaign commands across deterministic seeds."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--godot", required=True, type=Path)
parser.add_argument("--out", required=True, type=Path)
parser.add_argument("--first-seed", type=int, default=101)
parser.add_argument("--max-seeds", type=int, default=64, choices=range(12, 129), metavar="12..128")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
engine = str(args.godot.resolve(strict=True))
args.out.mkdir(parents=True, exist_ok=False)
required = {f"CS{i:02d}" for i in range(1, 25)}
covered = {phase: set() for phase in ("visible", "offers", "bought", "sold")}
reports = []
fatal = re.compile(r"SCRIPT ERROR:|^ERROR:|^FAIL:|ObjectDB instances were leaked|resources still in use at exit", re.M)
env = dict(os.environ, XDG_DATA_HOME=str((args.out / "data").resolve()), XDG_CONFIG_HOME=str((args.out / "config").resolve()))
for seed in range(args.first_seed, args.first_seed + args.max_seeds):
    command = [engine, "--headless", "--path", str(root), "--script",
               "res://tests/b3_campaign_catalog_test.gd", "--", "week", str(seed)]
    log = args.out / f"seed-{seed}.log"
    with log.open("w", encoding="utf-8") as output:
        completed = subprocess.run(command, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=180)
    contents = log.read_text(encoding="utf-8", errors="replace")
    witness = re.search(r"^B3_CATALOG_WEEK_JSON (.+)$", contents, re.M)
    passed = re.search(r"^B3_CAMPAIGN_CATALOG: [1-9][0-9]* checks, 0 failures", contents, re.M)
    if completed.returncode != 0 or not witness or not passed or fatal.search(contents):
        sys.exit(f"Invalid or failed witness for seed {seed}: {log}")
    row = json.loads(witness[1])
    if row["seed"] != seed or len(row["daily"]) != 7:
        sys.exit(f"Incomplete week report for seed {seed}: {log}")
    reports.append(row)
    for phase, items in covered.items():
        items.update(row[phase])
    if len(reports) >= 12 and all(required <= items for items in covered.values()):
        break

missing = {phase: sorted(required - items) for phase, items in covered.items()}
summary = {"weeks": reports, "coverage": {phase: sorted(items) for phase, items in covered.items()}, "missing": missing}
(args.out / "coverage.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
if any(missing.values()):
    sys.exit(f"Actual visit/trade coverage incomplete: {missing}")
print(f"Full integrated catalog turnover across {len(reports)} real first weeks.")
# Three bounded comparison weeks, never weaken original coverage or acceptance.
mixed = []
for seed in range(args.first_seed, args.first_seed + 3):
    command = [engine, "--headless", "--path", str(root), "--script",
               "res://tests/b3_campaign_catalog_test.gd", "--", "mixed", str(seed)]
    log = args.out / f"mixed-{seed}.log"
    with log.open("w", encoding="utf-8") as output:
        completed = subprocess.run(command, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=180)
    contents = log.read_text(encoding="utf-8", errors="replace")
    witness = re.search(r"^B3_MIXED_WEEK_JSON (.+)$", contents, re.M)
    passed = re.search(r"^B3_CAMPAIGN_CATALOG: [1-9][0-9]* checks, 0 failures", contents, re.M)
    if completed.returncode or not witness or not passed or fatal.search(contents):
        sys.exit(f"Invalid or failed mixed witness for seed {seed}: {log}")
    row = json.loads(witness[1])
    if row["seed"] != seed or len(row["daily"]) != 7:
        sys.exit(f"Incomplete mixed week: {log}")
    mixed.append(row)
legacy = {"HY05", "F3R01", "BAT02", "TL04", "EL06", "F3S01", "R001", "R003", "WAT02", "GE03"}
mixed_coverage = {side: sorted({entry["item"] for row in mixed for entry in row[side]} & legacy)
                  for side in ("bought", "sold")}
(args.out / "mixed-coverage.json").write_text(
    json.dumps({"weeks": mixed, "legacy_witnessed": mixed_coverage,
                "legacy_not_witnessed": {side: sorted(legacy - set(ids)) for side, ids in mixed_coverage.items()}},
               indent=2) + "\n", encoding="utf-8")
print(f"Mixed ordinary-trade diagnostic: {len(mixed)} actual weeks; legacy witnessed {mixed_coverage}")

# The legacy isolated F3 regression is retained; additionally run its actual
# full lifecycle against the default integrated campaign, not cloned stock.
log = args.out / "integrated-composite.log"
command = [engine, "--headless", "--path", str(root), "--script",
           "res://tests/scenarios/b3_f3_composite_lineage_test.gd", "--", "integrated_route"]
with log.open("w", encoding="utf-8") as output:
    completed = subprocess.run(command, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=300)
contents = log.read_text(encoding="utf-8", errors="replace")
witness = re.search(r"^B3_INTEGRATED_COMPOSITE_WITNESS (.+)$", contents, re.M)
passed = re.search(r"^B3_F3_COMPOSITE_PART integrated_route: [1-9][0-9]* checks, 0 failures", contents, re.M)
if completed.returncode or not witness or not passed or fatal.search(contents):
    sys.exit(f"Invalid or failed integrated composite witness: {log}")
(args.out / "integrated-composite.json").write_text(
    json.dumps(json.loads(witness[1]), indent=2) + "\n", encoding="utf-8")
print("Integrated campaign composite purchase, replacement, repair, resale and return witnessed.")

# Compare actual candidate v2 attendance against the unchanged v1 weeks.
planner_trial = []
for seed in range(args.first_seed, args.first_seed + 3):
    log = args.out / f"planner-v2-{seed}.log"
    command = [engine, "--headless", "--path", str(root), "--script",
               "res://tests/b3_campaign_catalog_test.gd", "--", "week_v2", str(seed)]
    with log.open("w", encoding="utf-8") as output:
        completed = subprocess.run(command, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=180)
    contents = log.read_text(encoding="utf-8", errors="replace")
    witness = re.search(r"^B3_CATALOG_WEEK_JSON (.+)$", contents, re.M)
    passed = re.search(r"^B3_CAMPAIGN_CATALOG: [1-9][0-9]* checks, 0 failures", contents, re.M)
    if completed.returncode or not witness or not passed or fatal.search(contents):
        sys.exit(f"Invalid or failed planner trial: {log}")
    row = json.loads(witness[1])
    if row["seed"] != seed or row.get("planner_version") != 2 or len(row["daily"]) != 7:
        sys.exit(f"Incomplete planner trial: {log}")
    planner_trial.append(row)
(args.out / "planner-v2-comparison.json").write_text(
    json.dumps({"v1": reports[:3], "v2": planner_trial}, indent=2) + "\n", encoding="utf-8")
print("Three opt-in planner v2 weeks compared with unchanged v1; no improvement presumed.")

# Compare the same mixed ordinary-trade strategy, rather than crediting a
# planning policy for a deliberately catalog-only purchasing strategy.
mixed_v2 = []
for seed in range(args.first_seed, args.first_seed + 3):
    log = args.out / f"mixed-v2-{seed}.log"
    command = [engine, "--headless", "--path", str(root), "--script",
               "res://tests/b3_campaign_catalog_test.gd", "--", "mixed_v2", str(seed)]
    with log.open("w", encoding="utf-8") as output:
        completed = subprocess.run(command, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=180)
    contents = log.read_text(encoding="utf-8", errors="replace")
    witness = re.search(r"^B3_MIXED_WEEK_JSON (.+)$", contents, re.M)
    passed = re.search(r"^B3_CAMPAIGN_CATALOG: [1-9][0-9]* checks, 0 failures", contents, re.M)
    if completed.returncode or not witness or not passed or fatal.search(contents):
        sys.exit(f"Invalid or failed mixed v2 comparison: {log}")
    row = json.loads(witness[1])
    if row["seed"] != seed or row.get("planner_version") != 2 or len(row["daily"]) != 7:
        sys.exit(f"Incomplete mixed v2 comparison: {log}")
    mixed_v2.append(row)
(args.out / "planner-mixed-comparison.json").write_text(
    json.dumps({"v1": mixed, "v2": mixed_v2}, indent=2) + "\n", encoding="utf-8")
print("Three same-seed mixed ordinary-trade v2 weeks compared with v1.")

# The v3 candidate does not replace either comparison. Its extra demand
# must arise from an actual existing buyer and stock, not synthetic turnover.
mixed_v3 = []
for seed in range(args.first_seed, args.first_seed + 3):
    log = args.out / f"mixed-v3-{seed}.log"
    command = [engine, "--headless", "--path", str(root), "--script",
               "res://tests/b3_campaign_catalog_test.gd", "--", "mixed_v3", str(seed)]
    with log.open("w", encoding="utf-8") as output:
        completed = subprocess.run(command, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=180)
    contents = log.read_text(encoding="utf-8", errors="replace")
    witness = re.search(r"^B3_MIXED_WEEK_JSON (.+)$", contents, re.M)
    passed = re.search(r"^B3_CAMPAIGN_CATALOG: [1-9][0-9]* checks, 0 failures", contents, re.M)
    if completed.returncode or not witness or not passed or fatal.search(contents):
        sys.exit(f"Invalid or failed mixed v3 comparison: {log}")
    row = json.loads(witness[1])
    if row["seed"] != seed or row.get("planner_version") != 3 or len(row["daily"]) != 7:
        sys.exit(f"Incomplete mixed v3 comparison: {log}")
    mixed_v3.append(row)
(args.out / "planner-retry-comparison.json").write_text(
    json.dumps({"v1": mixed, "v2": mixed_v2, "v3": mixed_v3}, indent=2) + "\n", encoding="utf-8")
log = args.out / "retry-witness.log"
command = [engine, "--headless", "--path", str(root), "--script",
           "res://tests/b3_campaign_catalog_test.gd", "--", "retry"]
with log.open("w", encoding="utf-8") as output:
    completed = subprocess.run(command, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=300)
contents = log.read_text(encoding="utf-8", errors="replace")
witness = re.search(r"^B3_CATALOG_RETRY_JSON (.+)$", contents, re.M)
passed = re.search(r"^B3_CAMPAIGN_CATALOG: [1-9][0-9]* checks, 0 failures", contents, re.M)
if completed.returncode or not witness or not passed or fatal.search(contents):
    sys.exit(f"Invalid or failed actual retry witness: {log}")
(args.out / "retry-witness.json").write_text(
    json.dumps(json.loads(witness[1]), indent=2) + "\n", encoding="utf-8")
print("v3 same-seed mixed comparison and actual retry settlement witnessed.")
