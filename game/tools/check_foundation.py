#!/usr/bin/env python3
"""Small fixed Gate 0-B checks; no campaign simulation or Android build."""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--scope', choices=['all', 'regression', 'gate0c', 'gate1'], default='all')
parser.add_argument('--report-dir', type=Path, help='New directory for incremental per-command logs; never overwrites previous reports')
args = parser.parse_args()
report = args.report_dir.resolve() if args.report_dir else None
if report:
    report.mkdir(parents=True, exist_ok=False)
    (report / 'manifest.json').write_text(json.dumps({'scope': args.scope, 'started_utc': datetime.now(timezone.utc).isoformat(), 'engine': args.godot, 'status': 'started'}, indent=2), encoding='utf-8')
engine = str(Path(args.godot).resolve())
version = subprocess.check_output([engine, '--version'], text=True, timeout=15).strip()
if report:
    (report / 'engine.txt').write_text(version + '\n', encoding='utf-8')
if not version.startswith('4.7.2.stable.'):
    raise SystemExit(f'Wrong engine: {version}')
commands = [
    [sys.executable, str(root / 'tools/prepare_runtime_assets.py')],
    [sys.executable, str(root / 'tools/localization.py')],
    [engine, '--headless', '--editor', '--path', str(root), '--import'],
]
def check_shutdown():
    # Focused exit-leak diagnostics before heavier checks. Both probes run even if the first leaks.
    # A faster shutdown must not silently pass with ObjectDB or resource leaks.
    shutdown_probes = [
        [engine, '--headless', '--verbose', '--path', str(root), '--quit-after', '3'],
        [engine, '--headless', '--verbose', '--path', str(root), '--quit-after', '120'],
    ]
    shutdown_leaks = []
    for frames, command in zip((3, 120), shutdown_probes):
        print('$ ' + ' '.join(command), flush=True)
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=45, encoding='utf-8', errors='replace')
            output = result.stdout + result.stderr
            leak = any(marker in output for marker in ('ObjectDB instances were leaked', 'Leaked instance:', 'resources still in use at exit', 'Orphan StringName:'))
            failed = bool(result.returncode or leak or 'SCRIPT ERROR:' in output or 'ERROR:' in output or 'FAIL:' in output)
            print(output, end='', flush=True)
            print(f'ZT_SHUTDOWN_PROBE frames={frames} leak={leak} failed={failed}', flush=True)
            if report:
                (report / f'shutdown-{frames}.log').write_text(output, encoding='utf-8')
                (report / f'shutdown-{frames}.json').write_text(json.dumps({'command': command, 'leak': leak, 'failed': failed, 'exit_code': result.returncode}), encoding='utf-8')
            if failed:
                shutdown_leaks.append(frames)
        except subprocess.TimeoutExpired:
            print(f'ZT_SHUTDOWN_PROBE frames={frames} timeout', flush=True)
            shutdown_leaks.append(frames)
    # Active audio is not silently excluded: exercise real playback and drain before exit.
    command = [engine, '--headless', '--verbose', '--path', str(root), '--script', 'res://tests/scenarios/audio_shutdown_test.gd']
    print('$ ' + ' '.join(command), flush=True)
    result = subprocess.run(command, capture_output=True, text=True, timeout=45, encoding='utf-8', errors='replace')
    output = result.stdout + result.stderr
    print(output, end='', flush=True)
    leak = any(marker in output for marker in ('ObjectDB instances were leaked', 'Leaked instance:', 'resources still in use at exit', 'Orphan StringName:'))
    failed = bool(result.returncode or leak or 'SCRIPT ERROR:' in output or 'ERROR:' in output or 'FAIL:' in output or 'ZT_ACTIVE_AUDIO_SHUTDOWN:' not in output)
    print(f'ZT_SHUTDOWN_ACTIVE leak={leak} failed={failed}', flush=True)
    if report:
        (report / 'shutdown-active.log').write_text(output, encoding='utf-8')
        (report / 'shutdown-active.json').write_text(json.dumps({'command': command, 'leak': leak, 'failed': failed, 'exit_code': result.returncode}), encoding='utf-8')
    if failed:
        shutdown_leaks.append('active')
    if shutdown_leaks:
        raise SystemExit(f'Shutdown probes failed: {shutdown_leaks}')

tests = []
if args.scope in ('all', 'regression'):
    tests += ['scenarios/alpha_b1_flow_test', 'scenarios/alpha_b1_host_test', 'scenarios/alpha_b1_contract_boundary_test', 'scenarios/alpha_b2_trade_slice_test', 'scenarios/alpha_b2_shelf_options_test', 'scenarios/alpha_b2_stock_custody_integration_test', 'scenarios/alpha_b2_shared_counter_transaction_test', 'scenarios/alpha_b2_unified_launch_test', 'scenarios/alpha_b3_visit_capacity_test', 'scenarios/alpha_b3_market_interest_test', 'scenarios/alpha_b3_market_m2_test', 'scenarios/alpha_b3_fx_m3_test', 'scenarios/alpha_b3_currency_terms_test', 'scenarios/alpha_b3_seeded_visits_test', 'scenarios/alpha_b3_random_runtime_test', 'scenarios/alpha_b3_seed_authority_test', 'scenarios/alpha_b3_conditional_story_test', 'scenarios/alpha_b3_m6_seven_day_real_trade_test', 'scenarios/alpha_b3_m7_finite_interest_test', 'scenarios/b3_f2_battery_market_test', 'scenarios/b3_f2_regional_market_test', 'scenarios/b3_f3_composite_lineage_test', 'scenarios/alpha_b3_week_attendance_test', 'scenarios/alpha_b3_paid_flow_test', 'scenarios/alpha_b3_outbound_funds_test', 'scenarios/alpha_b3_integrated_week_test', 'scenarios/b3_spatial_week_daily_test', 'scenarios/alpha_b2_host_test', 'scenarios/alpha_b2_card_negotiation_test', 'scenarios/alpha_b2_statement_authority_test', 'scenarios/alpha_b2_cards_host_test', 'scenarios/alpha_b2_generic_appraisal_test', 'scenarios/alpha_b2_generic_appraisal_host_test', 'scenarios/alpha_b2_commission_test', 'scenarios/alpha_b2_commission_host_test', 'scenarios/alpha_b2_named_parity_test', 'scenarios/alpha_b2_q08_template_test', 'scenarios/alpha_b2_story_projection_test', 'scenarios/alpha_b2_service_custody_test', 'scenarios/alpha_b2_multi_host_test', 'unit/gate2_contract_plan_test', 'scenarios/gate2_calendar_test', 'scenarios/gate2_medicine_test', 'scenarios/gate2_visit_queue_test', 'scenarios/gate2_service_test', 'scenarios/gate2_contract_test', 'unit/foundation_test', 'unit/save_test', 'unit/checkpoint_pilot_test', 'unit/registry_pilot_test', 'unit/registry_ab_pilot_test', 'unit/replay_checkpoint_test', 'unit/campaign_identity_directory_test', 'scenarios/lifecycle_authority_test', 'scenarios/campaign_capacity_test', 'scenarios/registry_runtime_test', 'unit/localization_test', 'scenarios/foundation_integration', 'unit/retention_test', 'unit/item_lineage_test', 'scenarios/gate2_p3_work_lineage_test', 'scenarios/gate2_p3_l2_compatibility_test', 'scenarios/gate2_p3_calendar_lifecycle_test', 'scenarios/gate2_demo_integration_test', 'scenarios/gate2_demo_host_test', 'scenarios/maintenance_sample_test']
if args.scope in ('all', 'gate0c'):
    tests += [f'unit/{name}_primitives_test' for name in ['item', 'grid', 'visit', 'object_relation', 'evidence']]
    tests += ['scenarios/gate0_c_test']
if args.scope in ('all', 'gate1'):
    tests += ['scenarios/npc_generated_visits_test', 'scenarios/npc_bargaining_policy_test', 'scenarios/calendar_merchant_contracts_test', 'scenarios/alpha42_production_runtime_test', 'scenarios/alpha_hold_market_test', 'scenarios/alpha_content_growth_test', 'scenarios/npc_visit_slots_test', 'scenarios/calendar_exchange_market_test', 'scenarios/regional_market_flow_test', 'scenarios/world_region_npc_continuity_test', 'scenarios/long_history_retention_test', 'unit/world_causal_trace_test', 'unit/appraisal_primitives_test', 'unit/gate2_p2_public_catalog_test', 'unit/gate2_p2_observation_prep_test', 'scenarios/gate2_p2_observation_authority_test', 'scenarios/gate2_p2_assessment_authority_test', 'scenarios/gate2_p2_deck_authority_test', 'scenarios/gate2_p2_generic_panel_test', 'scenarios/gate2_p2_customer_claims_test', 'scenarios/gate2_p2_price_offer_test', 'unit/inspection_profile_test', 'scenarios/gate1_opening_test', 'scenarios/gate1_appraisal_test', 'scenarios/gate1_trade_test', 'unit/inspection_interaction_test', 'scenarios/gate2_p1_card_test', 'scenarios/gate1_material_test', 'scenarios/component_appraisal_test', 'scenarios/component_retention_regions_test', 'scenarios/customer_inspection_test', 'scenarios/appraisal_audit_test', 'scenarios/gate1_2_test', 'scenarios/gate1_3_test', 'scenarios/campaign_composite_pilot_test', 'scenarios/component_market_test', 'unit/day_one_inventory_test', 'scenarios/gate1_scene_smoke_test']
if args.scope in ('all', 'gate1', 'regression'):
    tests += ['b3_known_estimate_read_model', 'b3_surface_visual_projection', 'b3_ratio_offer_projection', 'b3_public_dialogue_projection']
demo_parts = ('canonical', 'civilian', 'condition_v1', 'condition_v2', 'alpha')
for test in tests:
    command = [engine, '--headless', '--path', str(root), '--script', f'res://tests/{test}.gd']
    if test == 'scenarios/alpha_b2_commission_test':
        commands.extend(command + ['--', part] for part in ('happy', 'declined', 'expired', 'bypass'))
    elif test == 'scenarios/alpha_b2_service_custody_test':
        commands.extend(command + ['--', part] for part in ('happy', 'declined', 'unpaid', 'overdue', 'recovery', 'multi'))
    elif test == 'scenarios/alpha_b1_contract_boundary_test':
        # Four bounded source-authored obligation paths; isolate each failure.
        commands.extend(command + ['--', part] for part in ('missed', 'unpaid', 'extension', 'paid'))
    elif test == 'scenarios/gate2_demo_integration_test':
        # Identical four independent scenarios, one process and timeout per part.
        commands.extend(command + ['--', part] for part in demo_parts)
    elif test == 'scenarios/b3_f2_battery_market_test':
        commands.extend(command + ['--', part] for part in ('supply', 'regular', 'late', 'resale'))
    elif test == 'scenarios/b3_f2_regional_market_test':
        commands.extend(command + ['--', part] for part in ('quotes', 'memory', 'finite', 'recovery', 'scope', 'week', 'supplier', 'authority', 'service_memory', 'commission_memory'))
    elif test == 'scenarios/b3_f3_composite_lineage_test':
        commands.extend(command + ['--', part] for part in ('scope', 'route', 'choices'))
    elif test == 'scenarios/b3_spatial_week_daily_test':
        commands.extend(command + ['--', part] for part in (
            'return', 'empty', 'cancel', 'redeem', 'extend',
            'forfeit', 'market', 'combined', 'shortage'))
    elif test == 'scenarios/alpha_b3_integrated_week_test':
        # Nine unchanged seven-day paths, one bounded Godot process per route.
        commands.extend(command + ['--', part] for part in (
            'return', 'empty', 'cancel', 'redeem', 'extend',
            'forfeit', 'market', 'combined', 'shortage'))
    else:
        commands.append(command)
commands.append([engine, '--headless', '--path', str(root), 'res://scenes/app/demo7.tscn', '--quit-after', '3'])
commands.append([engine, '--headless', '--path', str(root), 'res://scenes/app/boot.tscn', '--quit-after', '3'])
commands.append([engine, '--headless', '--path', str(root), 'res://scenes/app/alpha_playtest_menu.tscn', '--quit-after', '3'])
commands.append([engine, '--headless', '--path', str(root), '--quit-after', '3'])
# Cheap, deterministic expansion-budget diagnostics (never rewrites a save or
# extrapolates the 42-day synthetic load into an acceptance certificate).
commands.append([sys.executable, str(root / 'tools/content_expansion_audit.py'), '--self-test'])
commands.append([sys.executable, str(root / 'tools/content_expansion_audit.py'), '--target-days', '42', '--daily-visits', '6', '--observation-share', '0.7', '--npc-pool', '40'])
def record_step(index, command, output, code, status):
    if report:
        # Individual files survive interruption; no summary is needed to recover prior steps.
        (report / f'{index:02d}.log').write_text('$ ' + ' '.join(command) + '\n' + output, encoding='utf-8')
        (report / f'{index:02d}.json').write_text(json.dumps({'command': command, 'exit_code': code, 'status': status, 'finished_utc': datetime.now(timezone.utc).isoformat()}, indent=2), encoding='utf-8')

for index, command in enumerate(commands, start=1):
    print('$ ' + ' '.join(command), flush=True)
    if report:
        (report / f'{index:02d}.started.json').write_text(json.dumps({'command': command, 'started_utc': datetime.now(timezone.utc).isoformat()}, indent=2), encoding='utf-8')
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=180 if any('gate2_demo_integration_test.gd' in str(part) for part in command) else (90 if any('campaign_capacity_test.gd' in str(part) or 'gate2_demo_host_test.gd' in str(part) or 'alpha_b1_contract_boundary_test.gd' in str(part) or 'alpha_b2_commission_test.gd' in str(part) or 'alpha_b2_named_parity_test.gd' in str(part) or 'alpha_b2_service_custody_test.gd' in str(part) for part in command) else 45), encoding='utf-8', errors='replace')
    except subprocess.TimeoutExpired as exc:
        def decoded(value):
            return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else (value or '')
        output = decoded(exc.stdout) + decoded(exc.stderr)
        record_step(index, command, output, 124, 'timeout')
        print(output, end='', flush=True)
        raise SystemExit(124)
    output = result.stdout + result.stderr
    print(output, end='', flush=True)
    failed = bool(result.returncode or 'SCRIPT ERROR:' in output or 'ERROR:' in output or 'FAIL:' in output or 'ObjectDB instances were leaked' in output or 'resources still in use at exit' in output)
    if any('gate2_demo_integration_test.gd' in str(part) for part in command):
        expected = f'GATE2_DEMO_INTEGRATION_PART {command[-1]}: '
        if not any(line.startswith(expected) and line.endswith(' checks, 0 failures') and line[len(expected):].split(' ', 1)[0].isdigit() and int(line[len(expected):].split(' ', 1)[0]) > 0 for line in output.splitlines()):
            print('FAIL: missing successful demo part marker', command[-1], flush=True)
            failed = True
    if any('alpha_b3_integrated_week_test.gd' in str(part) for part in command):
        # The exit code alone does not prove the specified route ran.
        expected = f'ALPHA_B3_INTEGRATED_WEEK_PART {command[-1]}: '
        valid = any(
            line.startswith(expected)
            and line.endswith(' checks, 0 failures')
            and line[len(expected):].split(' ', 1)[0].isdigit()
            and int(line[len(expected):].split(' ', 1)[0]) > 0
            for line in output.splitlines()
        )
        if not valid:
            print('FAIL: missing successful B3 first-week route marker', command[-1], flush=True)
            failed = True
    if any('b3_f2_battery_market_test.gd' in str(part) for part in command):
        expected = f'B3_F2_MARKET_PART {command[-1]}: '
        if not any(line.startswith(expected) and line.endswith(' checks, 0 failures') and line[len(expected):].split(' ', 1)[0].isdigit() and int(line[len(expected):].split(' ', 1)[0]) > 0 for line in output.splitlines()):
            print('FAIL: missing successful B3-F2 market part marker', command[-1], flush=True)
            failed = True
    if any('b3_f2_regional_market_test.gd' in str(part) for part in command):
        expected = f'B3_F2_REGIONAL_PART {command[-1]}: '
        if not any(line.startswith(expected) and line.endswith(' checks, 0 failures') and line[len(expected):].split(' ', 1)[0].isdigit() and int(line[len(expected):].split(' ', 1)[0]) > 0 for line in output.splitlines()):
            print('FAIL: missing successful B3-F2 regional part marker', command[-1], flush=True)
            failed = True
    if any('b3_f3_composite_lineage_test.gd' in str(part) for part in command):
        expected = f'B3_F3_COMPOSITE_PART {command[-1]}: '
        if not any(line.startswith(expected) and line.endswith(' checks, 0 failures') and line[len(expected):].split(' ', 1)[0].isdigit() and int(line[len(expected):].split(' ', 1)[0]) > 0 for line in output.splitlines()):
            print('FAIL: missing successful B3-F3 composite part marker', command[-1], flush=True)
            failed = True
    if any('b3_spatial_week_daily_test.gd' in str(part) for part in command):
        # Explicit seven day receipts and final per-route gate from the B3 spatial profile.
        route = command[-1]
        expected = f'ALPHA_B3_INTEGRATED_WEEK_PART {route}: '
        receipts = [line for line in output.splitlines() if line.startswith('SPATIAL_DAY ')]
        valid = (
            len(receipts) == 7 and
            any(
                line.startswith(expected) and line.endswith(' failures') and
                ', 0 failures' in line and
                int(line[len(expected):].split(' ', 1)[0]) >= 15
                for line in output.splitlines()
                if line.startswith(expected) and line[len(expected):].split(' ', 1)[0].isdigit()
            )
        )
        if valid:
            try:
                parsed = [json.loads(line[len('SPATIAL_DAY '):]) for line in receipts]
                valid = [day.get('day') for day in parsed] == list(range(1, 8))
            except (ValueError, TypeError):
                valid = False
        if not valid:
            print('FAIL: B3 spatial week route missing ordered daily receipts / pass', route, flush=True)
            failed = True
    record_step(index, command, output, result.returncode or (1 if failed else 0), 'failed' if failed else 'passed')
    if failed:
        raise SystemExit(result.returncode or 1)
    if index == 3:
        check_shutdown()
if report:
    (report / 'complete.json').write_text(json.dumps({'scope': args.scope, 'steps': len(commands), 'status': 'passed', 'finished_utc': datetime.now(timezone.utc).isoformat()}, indent=2), encoding='utf-8')
print('FIXED_CHECKS_PASS scope=' + args.scope)
