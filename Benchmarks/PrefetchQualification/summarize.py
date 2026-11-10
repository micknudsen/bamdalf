#!/usr/bin/env python3
"""Require complete locked cases and report per-workload outcomes without pooling modes."""
import argparse
import csv
import hashlib
import json
import math
import pathlib
import statistics


def write_csv(path, rows):
    fields = list(dict.fromkeys(key for row in rows for key in row))
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def summarize(case, label, rows):
    values = sorted(row['wall_ms'] for row in rows)
    target = rows[0]['target_ms']
    within = sum(value <= target for value in values)
    return {
        'case': case['id'], 'prefetch_enabled': case['prefetch_enabled'], 'action': label,
        'n': len(rows), 'target_ms': target, 'within_target': within,
        'fraction_within_target': within / len(rows), 'observed_target_met': within / len(rows) >= .95,
        'first_ms': rows[0]['wall_ms'], 'median_ms': statistics.median(values),
        'p95_ms': values[math.ceil(len(values) * .95) - 1], 'maximum_ms': values[-1],
        'required_queries': sum(row.get('required_query_calls', row.get('query_calls', 0)) for row in rows),
        'optional_queries': sum(row.get('optional_query_calls', 0) for row in rows),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('protocol', type=pathlib.Path)
    parser.add_argument('runs', type=pathlib.Path)
    parser.add_argument('output', type=pathlib.Path)
    args = parser.parse_args()
    content = args.protocol.read_bytes()
    digest = hashlib.sha256(content).hexdigest()
    plan = json.loads(content)
    args.output.mkdir(parents=True, exist_ok=False)
    all_rows, summaries, completions, memory, minutes, query_rows = [], [], [], [], [], []
    for case in plan['cases']:
        case_id = case['id']
        directory = args.runs / case_id
        outer = json.loads((directory / 'completion.json').read_text())
        if outer.get('completed') is not True or outer.get('protocol_sha256') != digest or outer.get('cases') != [case_id]:
            raise SystemExit(f'Incomplete or wrong-protocol case: {case_id}')
        native = directory / 'native' / case_id
        complete = json.loads((native / 'completion.json').read_text())
        rows = [json.loads(line) for line in (native / 'samples.jsonl').read_text().splitlines()]
        expected = complete['iterations'] * len(case['steps'])
        if complete.get('completed') is not True or complete['steps'] != expected or sum(row['phase'] == 'steps' for row in rows) != expected:
            raise SystemExit(f'Incomplete native route: {case_id}')
        if case.get('duration_seconds'):
            if complete['navigation_elapsed_seconds'] < case['duration_seconds']:
                raise SystemExit(f'Active memory route was too short: {case_id}')
        elif complete['iterations'] != case['repetitions']:
            raise SystemExit(f'Wrong repetition count: {case_id}')
        all_rows.extend(rows)
        measured = [row for row in rows if row.get('measured') and 'target_ms' in row]
        labels = sorted({(row['action'], row['target_ms']) for row in measured})
        for action, target in labels:
            group = [row for row in measured if row['action'] == action and row['target_ms'] == target]
            summaries.append(summarize(case, f'{action}/limit_{target:g}ms', group))
        complete.update({key: value for key, value in outer.items() if key.startswith('external_')})
        complete['prefetch_enabled'] = case['prefetch_enabled']
        complete['primary_memory_target_met'] = max(complete['external_process_peak_resident_bytes'], complete['process_lifetime_peak_resident_bytes']) < plan['memory_limit_bytes']
        completions.append(complete)
        for query_file in sorted(native.glob('queries-session-*.json')):
            events = json.loads(query_file.read_text())
            if isinstance(events, dict):
                events = events.get('queries', events.get('events', []))
            for event in events:
                query_rows.append({'case': case_id, 'prefetch_enabled': case['prefetch_enabled'], 'session': query_file.stem, **event})
        if case.get('duration_seconds'):
            active_start = complete.get('navigation_start_elapsed_seconds', 0)
            trace = [{'case': case_id, 'prefetch_enabled': case['prefetch_enabled'],
                      **json.loads(line)} for line in (native / 'memory.jsonl').read_text().splitlines()]
            for row in trace:
                row['navigation_elapsed_seconds'] = row['elapsed_seconds'] - active_start
            memory.extend(trace)
            active = [row for row in trace if row['navigation_elapsed_seconds'] >= 0]
            for minute in sorted({int(row['navigation_elapsed_seconds'] // 60) for row in active}):
                values = [row for row in active if int(row['navigation_elapsed_seconds'] // 60) == minute]
                minutes.append({'case': case_id, 'prefetch_enabled': case['prefetch_enabled'], 'minute': minute, 'samples': len(values),
                                'resident_min_bytes': min(row['resident_bytes'] for row in values),
                                'resident_max_bytes': max(row['resident_bytes'] for row in values),
                                'physical_footprint_min_bytes': min(row['physical_footprint_bytes'] for row in values),
                                'physical_footprint_max_bytes': max(row['physical_footprint_bytes'] for row in values)})
    for name, rows in [('samples', all_rows), ('summary', summaries), ('memory-trace', memory),
                       ('memory-by-minute', minutes), ('queries', query_rows)]:
        write_csv(args.output / f'{name}.csv', rows)
    result = {
        'protocol_sha256': digest, 'protocol_product_baseline': plan['baseline_commit'],
        'cases': completions, 'timing_cases_passed': all(row['observed_target_met'] for row in summaries),
        'memory_target_met': all(row['primary_memory_target_met'] for row in completions),
        'all_cases_completed': True, 'timing_summary_groups': len(summaries),
    }
    result['qualified'] = result['timing_cases_passed'] and result['memory_target_met']
    (args.output / 'completion.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'Summarized {len(completions)} cases and {len(all_rows)} observations; qualified={result["qualified"]}')
    for row in summaries:
        if not row['observed_target_met']:
            print(f"MISS {row['case']}/{row['action']}: {row['within_target']}/{row['n']}; p95={row['p95_ms']:.3f}ms")


if __name__ == '__main__':
    main()
