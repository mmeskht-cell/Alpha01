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
