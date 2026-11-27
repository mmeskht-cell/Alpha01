#!/usr/bin/env python3
"""Read-only static dependency inventory for EXIT NOT INCLUDED.

Conservative: recorded res:// references are edges, not proof of dynamic reachability.
Never delete a source solely because this report calls it 'unclassified'.
"""
from __future__ import annotations

import argparse
import json
import re
from collections import deque
from pathlib import Path

RESOURCE = re.compile(r"res://[A-Za-z0-9_./-]+")
RUNNER_TEST = re.compile(r"(?:unit|scenarios)/[A-Za-z0-9_]+")
MANUAL = (
    "scenarios/alpha42_traffic_capacity_test.gd",
    "scenarios/alpha_cross_system_42day_test.gd",
    "scenarios/alpha_42day_real_office_test.gd",
    "scenarios/merchant_office_ui_test.gd",
)
SCAN_SUFFIXES = {".gd", ".tscn", ".tres", ".godot", ".json", ".gdshader"}
WINDOW_WORKFLOW = ".github/workflows/gate1-window.yml"


def discover(project: Path) -> dict:
    root = project.parent
    files = {p.relative_to(project).as_posix(): p for p in project.rglob("*") if p.is_file()}
    edges = {}
    unresolved = {}
    for relative, path in files.items():
        if path.suffix not in SCAN_SUFFIXES:
            continue
        refs = set(RESOURCE.findall(path.read_text(encoding="utf-8", errors="replace")))
        resolved = set()
        missing = set()
        for ref in refs:
            target = ref.removeprefix("res://")
            if target in files:
                resolved.add(target)
            else:
                missing.add(target)
        edges[relative] = sorted(resolved)
        if missing:
            unresolved[relative] = sorted(missing)
    def closure(roots: set[str]) -> set[str]:
        found = set()
        queue = deque(sorted(roots))
        while queue:
            path = queue.popleft()
            if path in found or path not in files:
                continue
            found.add(path)
            queue.extend(target for target in edges.get(path, []) if target not in found)
        return found
    main_config = files.get("project.godot")
    main = "scenes/app/main_menu.tscn"
    if main_config:
        match = re.search(r'run/main_scene\s*=\s*"res://([^"]+)"', main_config.read_text(encoding="utf-8"))
        if match:
            main = match.group(1)
    fixed = set()
    runner = files.get("tools/check_foundation.py")
    if runner:
        script = runner.read_text(encoding="utf-8")
        for match in RUNNER_TEST.findall(script):
            p = "tests/" + match + ".gd"
            if p in files:
                fixed.add(p)
        # Generated primitive tests are formed by the fixed runner.
        for kind in ("item", "grid", "visit", "object_relation", "evidence"):
            p = "tests/unit/" + kind + "_primitives_test.gd"
            if p in files:
                fixed.add(p)
        if "audio_shutdown_test.gd" in script:
            fixed.add("tests/scenarios/audio_shutdown_test.gd")
    window = set()
    workflow_path = root / WINDOW_WORKFLOW
    if workflow_path.is_file():
        source = workflow_path.read_text(encoding="utf-8")
        for target in RESOURCE.findall(source):
            if target.startswith("res://tests/window/"):
                relative = target.removeprefix("res://")
                if relative in files:
                    window.add(relative)
    manual = {"tests/" + entry for entry in MANUAL if "tests/" + entry in files}
    runtime = closure({main})
    fixed_reach = closure(fixed)
    window_reach = closure(window)
    manual_reach = closure(manual)
    classified = {}
    for path in sorted(p for p in files if p.endswith((".gd", ".tscn"))):
        uses = []
        if path in runtime:
            uses.append("player_static")
        if path in fixed_reach:
            uses.append("fixed_ci_static")
        if path in window_reach:
            uses.append("window_ci_static")
        if path in manual_reach:
            uses.append("manual_static")
        classified[path] = uses or ["unclassified_static"]
    return {
        "method": "literal res:// string edges; dynamic loads, external script callbacks and generated data may be missing",
        "entry_scene": main,
        "counts": {
            "game_files": len(files), "player_static": len(runtime),
            "fixed_test_roots": len(fixed), "window_test_roots_from_local_workflow": len(window),
            "manual_test_roots": len(manual),
            "unclassified_code_or_scene": sum(v == ["unclassified_static"] for v in classified.values()),
            "unresolved_literal_references": sum(map(len, unresolved.values())),
        },
        "roots": {
            "player": [main], "fixed_ci": sorted(fixed),
            "window_ci_local_workflow": sorted(window), "manual": sorted(manual),
        },
        "classifications": classified,
        "unresolved_literals": unresolved,
        "warning": "An unclassified source is NOT proven dead; never auto-delete it.",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--game", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = discover(args.game.resolve())
    raw = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(raw, encoding="utf-8")
    print("DEPENDENCY_INVENTORY", json.dumps(result["counts"], sort_keys=True))
    if args.output:
        print("DEPENDENCY_REPORT", args.output)


if __name__ == "__main__":
    main()
