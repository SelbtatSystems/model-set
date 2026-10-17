#!/usr/bin/env python3
"""Tally how issue-loop runs ended, from their stream-json logs. Read-only.

Each merge log should end with one do-pr sentinel (<<<MERGED #N>>>,
<<<MERGE_BLOCKED #N reason>>>, <<<NO_OPEN_PR>>>). A run whose final result
carries none ended early; a log with no result event never finished (killed,
crashed, or still running). Use it to compare skill changes before and after.

Usage: scripts/loop-outcomes.py [--days N] [LOG_DIR ...]
Default LOG_DIRs: ~/Projects/*/issue-loop-logs
"""
import argparse
import collections
import glob
import json
import os
import re
import time

MERGE_SENTINEL = re.compile(r'<<<(MERGED|MERGE_BLOCKED|NO_OPEN_PR)([^>]*)>>>')


def final_result(path):
    result, cost = None, 0.0
    with open(path, errors='ignore') as log:
        for line in log:
            if '"type":"result"' not in line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            result = event.get('result') or ''
            cost = event.get('total_cost_usd') or 0.0
    return result, cost


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--days', type=int, default=30)
    parser.add_argument('log_dirs', nargs='*')
    args = parser.parse_args()
    log_dirs = args.log_dirs or glob.glob(os.path.expanduser('~/Projects/*/issue-loop-logs'))
    since = time.time() - args.days * 86400

    for kind in ('merge', 'build'):
        outcomes, costs = collections.Counter(), collections.Counter()
        blocked_reasons = collections.Counter()
        for log_dir in log_dirs:
            for path in glob.glob(os.path.join(log_dir, f'{kind}-*.log')):
                if os.path.getmtime(path) < since:
                    continue
                result, cost = final_result(path)
                if result is None:
                    outcome = 'no result event'
                elif kind == 'build':
                    outcome = 'no open issues' if '<<<NO_OPEN_ISSUES>>>' in result else 'finished'
                else:
                    sentinels = MERGE_SENTINEL.findall(result)
                    outcome = sentinels[-1][0] if sentinels else 'ended without sentinel'
                    if outcome == 'MERGE_BLOCKED':
                        reason = sentinels[-1][1].strip().split(' ', 1)[-1]
                        blocked_reasons[reason.split(':')[0][:30]] += 1
                outcomes[outcome] += 1
                costs[outcome] += cost
        total = sum(outcomes.values())
        print(f'{kind} runs, last {args.days} days: {total}')
        for outcome, count in outcomes.most_common():
            print(f'  {outcome:24s} {count:5d}  {count / total:6.1%}  ${costs[outcome]:,.0f}')
        for reason, count in blocked_reasons.most_common(8):
            print(f'    blocked: {reason} ({count})')


if __name__ == '__main__':
    main()
