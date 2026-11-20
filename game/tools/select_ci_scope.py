#!/usr/bin/env python3
"""Fail closed: only explicitly reviewed UI paths qualify for focused CI."""
import argparse
import re
import subprocess

UI_FILES = {
    "game/src/presentation/spatial_management.gd",
    "game/src/presentation/generic_trade_history.gd",
    "game/src/presentation/native_history_browser.gd",
    "game/src/presentation/native_office.gd",
    "game/tests/window/civilian_candidate_window.gd",
    "game/tests/window/native_v23_window.gd",
    "game/tests/window/composition_inventory_window.gd",
    "game/locales/keys.json",
    "game/locales/core.pot",
    "game/locales/ko/core.po",
    "game/locales/en/core.po",
}
RECORD_FILES = {
    "PROJECT_STATE.json",
    "development/NEXT_CHAT_HANDOFF.md",
    "development/RESPONSIVE_UI_REVIEW_20261120.md",
}

def classify(paths):
    changed = set(paths)
    if changed & UI_FILES and changed <= UI_FILES | RECORD_FILES:
        return "focused"
    return "full"

def self_test():
    ui = "game/src/presentation/spatial_management.gd"
    assert classify([ui, "PROJECT_STATE.json"]) == "focused"
    assert classify(["game/locales/en/core.po"]) == "focused"
    assert classify([ui, "game/src/domain/wallet.gd"]) == "full"
    assert classify([ui, "game/src/persistence/save.gd"]) == "full"
    assert classify([ui, "game/data/campaign/example.json"]) == "full"
    assert classify([ui, "game/src/presentation/spatial_demo7_host.gd"]) == "full"
    assert classify([ui, ".github/workflows/game-ci.yml"]) == "full"
    assert classify([ui, "game/tools/select_ci_scope.py"]) == "full"
    assert classify([ui, "development/FULL_CI_CHECKPOINT.md"]) == "full"
    assert classify(["PROJECT_STATE.json"]) == "full"
    assert classify([]) == "full"

def git(*args):
    return subprocess.run(["git", *args], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60).stdout

def main():
    self_test()
    parser = argparse.ArgumentParser()
    parser.add_argument("--before", default="")
    parser.add_argument("--head", default="")
    parser.add_argument("--event", default="")
    parser.add_argument("--forced", default="")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        print("CI_SCOPE_SELF_TEST_PASS")
        return
    if args.event != "push" or args.forced != "false":
        print("full")
        return
    if not all(re.fullmatch(r"[0-9a-f]{40}", x) and x != "0"*40 for x in (args.before, args.head)):
        print("full")
        return
    try:
        if git("rev-parse", "HEAD").decode().strip() != args.head:
            print("full")
            return
        # A single atomic push has both trees in the two-commit checkout.
        # Missing base (e.g. a multi-commit push) deliberately falls back to full.
        git("cat-file", "-e", args.before + "^{commit}")
        # Disable rename detection so moving a core file into an allowed path
        # includes both its removed and added paths in the security boundary.
        raw = git("diff", "--no-renames", "--name-only", "-z", args.before, args.head)
        paths = [p.decode("utf-8", errors="strict") for p in raw.split(b"\0") if p]
        print(classify(paths))
    except (OSError, subprocess.SubprocessError, UnicodeError):
        print("full")

if __name__ == "__main__":
    main()
