#!/usr/bin/env python3
"""Audit completed native routes against the frozen input coordinates.

This postprocessor does not load production code or rerun native measurements.
The pointer expectation is the protocol's original down position plus its stated
fractional displacement. Effective positions are checked to one millionth of a
base. At exact half-base release ties, either adjacent integer is accepted: both
are equally near the validated preview, and floating event coordinates can lie
on either side of the tie. Subsequent actions use that validated committed base.
"""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path

TOLERANCE_BASES = 1e-6


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def interval(text):
    reference, bounds = text.replace(',', '').split(':')
    start, end = map(int, bounds.split('-'))
    if start < 1 or end < start:
        raise ValueError(f'Invalid recorded interval: {text}')
    return reference, start, end


def route_events(case, iterations):
    for iteration in range(iterations):
        reset = iteration == 0 or case['fresh_session']
        phases = []
        if reset:
            phases.append(('setup', case['setup']))
        phases.append(('steps', case['steps']))
        if case['fresh_session']:
            phases.append(('finish', case.get('finish', [])))
        for phase, steps in phases:
            for step in steps:
                yield step, phase, iteration, reset
                reset = False
    if not case['fresh_session']:
        for step in case.get('finish', []):
            yield step, 'finish', iterations - 1, False


def audit_case(case, directory, protocol_hash):
    outer = json.loads((directory / 'completion.json').read_text())
    if outer.get('completed') is not True or outer.get('cases') != [case['id']] or outer.get('protocol_sha256') != protocol_hash:
        raise ValueError(f"Wrong or incomplete run: {case['id']}")
    native = directory / 'native' / case['id']
    complete = json.loads((native / 'completion.json').read_text())
    if complete.get('completed') is not True:
        raise ValueError(f"Native route incomplete: {case['id']}")
    path = native / 'samples.jsonl'
    rows = [json.loads(line) for line in path.read_text().splitlines()]
    expected = list(route_events(case, complete['iterations']))
    if len(rows) != len(expected):
        raise ValueError(f"Missing or extra route events: {case['id']}")
    target = drag = None
    maximum_error = 0.0
    action_counts = Counter()
    release_ties = 0
    previous_scroll = None
    for row, (step, phase, iteration, reset) in zip(rows, expected):
        label = f"{case['id']}/{phase}/{iteration}/{step['id']}"
        if any(row.get(key) != value for key, value in {
            'case': case['id'], 'phase': phase, 'iteration': iteration,
            'step': step['id'], 'action': step['action'],
        }.items()):
            raise ValueError(f'Out-of-order or incorrect recorded event: {label}')
        if reset:
            target = drag = None
            previous_scroll = None
        action = step['action']
        observed_reference, observed_start, observed_end = interval(row['interval'])
        observed_offset = row['preview_offset_bases']
        if not math.isfinite(observed_offset):
            raise ValueError(f'Nonfinite preview position: {label}')
        if action in ('type', 'required_failure'):
            target = interval(step['expected_interval'] if action == 'required_failure' else step['interval'])
            drag = None
        elif target is None:
            raise ValueError(f'Action before a known target: {label}')
        elif action in ('pan_left', 'pan_right'):
            reference, start, end = target
            width = end - start + 1
            displacement = math.ceil(width / 2) * (-1 if action == 'pan_left' else 1)
            start = min(max(1, start + displacement), case['reference_lengths'][reference] - width + 1)
            target = reference, start, start + width - 1
            drag = None
        elif action in ('zoom_in', 'zoom_out', 'double_click', 'option_click'):
            reference, start, end = target
            width, length = end - start + 1, case['reference_lengths'][reference]
            new_width = math.ceil(width / 2) if action in ('zoom_in', 'double_click') else min(length, width * 2)
            if action in ('double_click', 'option_click'):
                hit = start + min(width - 1, math.floor(min(1, max(0, step['fraction'])) * width))
                start = hit - math.floor(new_width / 2)
            else:
                start += math.floor((width - new_width) / 2)
            start = min(max(1, start), length - new_width + 1)
            target = reference, start, start + new_width - 1
            drag = None
        elif action == 'mouse_down':
            drag = target, step['fraction']
        elif action == 'mouse_drag':
            if drag is None:
                raise ValueError(f'Drag lacks a pointer-down anchor: {label}')
            (reference, start, end), down_fraction = drag
            width = end - start + 1
            exact_start = start - (step['fraction'] - down_fraction) * width
            exact_start = min(max(1, exact_start), case['reference_lengths'][reference] - width + 1)
            target = reference, exact_start, exact_start + width - 1
        elif action == 'mouse_up':
            if drag is None:
                raise ValueError(f'Release lacks an active gesture: {label}')
            reference, exact_start, exact_end = target
            error = abs(observed_start - exact_start)
            if error > .5 + TOLERANCE_BASES or observed_end - observed_start != exact_end - exact_start:
                raise ValueError(f'Release did not commit the nearest preview base: {label}')
            if abs(error - .5) <= TOLERANCE_BASES:
                release_ties += 1
            target = reference, observed_start, observed_end
            drag = None
        elif action not in ('scroll', 'settle_optional', 'draft', 'dismiss_error'):
            raise ValueError(f'Unsupported protocol action: {label}')
        reference, expected_start, expected_end = target
        if observed_reference != reference or observed_end - observed_start != expected_end - expected_start:
            raise ValueError(f'Wrong reference or viewport width: {label}')
        error = max(abs(observed_start + observed_offset - expected_start),
                    abs(observed_end + observed_offset - expected_end))
        maximum_error = max(maximum_error, error)
        if error > TOLERANCE_BASES:
            raise ValueError(f'Wrong effective position: {label}; error={error:.9g} bases')
        if abs(observed_offset) > .5 + TOLERANCE_BASES or (drag is None and abs(observed_offset) > TOLERANCE_BASES):
            raise ValueError(f'Wrong fractional/committed state: {label}')
        if 'expected_interval' in step and interval(step['expected_interval']) != (observed_reference, observed_start, observed_end):
            raise ValueError(f'Explicit interval expectation differs: {label}')
        if step.get('expected_scroll_change') and row['vertical_offset_points'] == previous_scroll:
            raise ValueError(f'Expected actual scroll movement: {label}')
        previous_scroll = row['vertical_offset_points']
        action_counts[action] += 1
    return {'case': case['id'], 'events_checked': len(rows),
            'action_counts': dict(action_counts), 'maximum_effective_position_error_bases': maximum_error,
            'half_base_release_ties': release_ties, 'samples_sha256': sha256(path)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('protocol', type=Path)
    parser.add_argument('runs', type=Path)
    parser.add_argument('--case', action='append', help='Audit only this case; repeat as needed')
    parser.add_argument('--completed-only', action='store_true', help='Explicit partial audit, skipping cases without completion records')
    args = parser.parse_args()
    plan = json.loads(args.protocol.read_text())
    selected = [case for case in plan['cases'] if args.case is None or case['id'] in args.case]
    if not selected or (args.case and set(args.case) != {case['id'] for case in selected}):
        raise SystemExit('Unknown or empty case selection')
    protocol_hash = sha256(args.protocol)
    results, skipped = [], []
    for case in selected:
        directory = args.runs / case['id']
        if args.completed_only and not (directory / 'completion.json').is_file():
            skipped.append(case['id'])
            continue
        results.append(audit_case(case, directory, protocol_hash))
    print(json.dumps({
        'protocol_sha256': protocol_hash, 'auditor_sha256': sha256(Path(__file__)),
        'tolerance_bases': TOLERANCE_BASES, 'all_protocol_cases_checked': len(results) == len(plan['cases']),
        'skipped_cases': skipped, 'cases': results,
        'events_checked': sum(case['events_checked'] for case in results),
        'scope': 'Postprocessing of recorded coordinates against the frozen native input route; no production-private access or new timing observations.',
    }, indent=2))


if __name__ == '__main__':
    main()
