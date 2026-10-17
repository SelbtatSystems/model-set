#!/usr/bin/env python3
"""How often each skill was used on this machine, per agent. Read-only.

Claude (every profile under ~/.claude*/projects):
  calls    the model loaded it with the Skill tool
  slash    a /name command, typed by a person or started by a loop runner
  refused  a Skill-tool call the harness refused (hidden, unknown, not model-callable)
Codex (~/.codex/sessions):
  $name    a user message started with $name (a person or a runner)
  reads    sessions where the model read skills/<name>/SKILL.md through a command

Run it before retiring, hiding or renaming a skill: a skill one agent never uses
may be load-bearing for the other. Skills installed for an agent but used by
neither are listed at the end.

Usage: scripts/skill-usage.py [--days N] [skill ...]
"""
import argparse
import collections
import glob
import json
import os
import re
import time

REFUSAL_MARKERS = ('cannot be used with Skill tool', 'Unknown skill', 'disabled via skillOverrides')
SLASH = re.compile(r'<command-name>/([a-z0-9:-]+)</command-name>')
CODEX_READ = re.compile(r'skills/([a-z0-9:-]+)/SKILL\.md')
CODEX_INVOKE = re.compile(r'"type":"input_text","text":"\$([a-z0-9:-]+)')
CODEX_TOOL_LINE = ('"custom_tool_call"', '"function_call"', 'CommandExecution')


def recent(paths, since):
    return [p for p in paths if os.path.getmtime(p) >= since]


def scan_claude(since, use, refusals):
    files = recent(glob.glob(os.path.expanduser('~/.claude*/projects/**/*.jsonl'), recursive=True), since)
    for path in files:
        skill_by_call = {}
        seen_messages = set()
        with open(path, errors='ignore') as transcript:
            for line in transcript:
                has_call = '"name":"Skill"' in line
                has_slash = '<command-name>/' in line
                has_refusal = any(marker in line for marker in REFUSAL_MARKERS)
                if not (has_call or has_slash or has_refusal):
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                content = (event.get('message') or {}).get('content')
                if has_slash and event.get('uuid') not in seen_messages:
                    seen_messages.add(event.get('uuid'))
                    text = content if isinstance(content, str) else json.dumps(content)
                    for name in set(SLASH.findall(text)):
                        use[name]['claude slash'] += 1
                if not isinstance(content, list):
                    continue
                for block in content:
                    if block.get('type') == 'tool_use' and block.get('name') == 'Skill':
                        name = (block.get('input') or {}).get('skill')
                        if name:
                            skill_by_call[block.get('id')] = name
                            use[name]['claude calls'] += 1
                    elif block.get('type') == 'tool_result' and block.get('tool_use_id') in skill_by_call:
                        result = block.get('content')
                        result = result if isinstance(result, str) else json.dumps(result)
                        if any(marker in result for marker in REFUSAL_MARKERS):
                            name = skill_by_call[block['tool_use_id']]
                            use[name]['claude refused'] += 1
                            refusals[name][result.strip()[:110]] += 1
    return len(files)


def codex_command_text(event):
    """The command the model ran, never its output: outputs list every SKILL.md a search finds."""
    payload = event.get('payload') or {}
    if payload.get('type') == 'custom_tool_call':
        return str(payload.get('input') or '')
    if payload.get('type') == 'function_call':
        return str(payload.get('arguments') or '')
    item = payload.get('item') or {}
    if item.get('type') == 'CommandExecution':
        return ' '.join(item.get('command') or [])
    return ''


def scan_codex(since, use):
    files = recent(glob.glob(os.path.expanduser('~/.codex/sessions/**/*.jsonl'), recursive=True), since)
    for path in files:
        read_here = set()
        with open(path, errors='ignore') as session:
            for line in session:
                for name in CODEX_INVOKE.findall(line):
                    use[name]['codex $name'] += 1
                if 'SKILL.md' in line and any(marker in line for marker in CODEX_TOOL_LINE):
                    try:
                        read_here.update(CODEX_READ.findall(codex_command_text(json.loads(line))))
                    except json.JSONDecodeError:
                        continue
        for name in read_here:
            use[name]['codex reads'] += 1
    return len(files)


def installed(skill_dir):
    path = os.path.expanduser(skill_dir)
    if not os.path.isdir(path):
        return set()
    return {n for n in os.listdir(path) if os.path.isfile(os.path.join(path, n, 'SKILL.md'))}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--days', type=int, default=60)
    parser.add_argument('skills', nargs='*', help='only these skills')
    args = parser.parse_args()
    since = time.time() - args.days * 86400

    use = collections.defaultdict(collections.Counter)
    refusals = collections.defaultdict(collections.Counter)
    claude_files = scan_claude(since, use, refusals)
    codex_files = scan_codex(since, use)

    claude_installed, codex_installed = installed('~/.claude/skills'), installed('~/.codex/skills')
    # A /name that only ever arrived as a slash command and is not installed is a CLI
    # command (/clear, /model), not a skill.
    skill_like = {n for n, c in use.items()
                  if n in claude_installed | codex_installed or sum(c.values()) > c['claude slash']}
    names = set(args.skills) or skill_like
    columns = ['claude calls', 'claude slash', 'claude refused', 'codex $name', 'codex reads']
    print(f'Skill use, last {args.days} days: {claude_files} Claude transcripts, {codex_files} Codex sessions\n')
    print(f'{"skill":34s}' + ''.join(f'{c:>16s}' for c in columns))
    for name in sorted(names, key=lambda n: (-sum(use[n].values()), n)):
        print(f'{name:34s}' + ''.join(f'{use[name][c]:16d}' for c in columns))

    if any(not args.skills or n in args.skills for n in refusals):
        print('\nRefused Skill-tool calls:')
        for name, messages in sorted(refusals.items()):
            if args.skills and name not in args.skills:
                continue
            for message, count in messages.most_common(3):
                print(f'  {name}: {count}x  {message}')

    if not args.skills:
        unused = sorted((claude_installed | codex_installed) - skill_like)
        print(f'\nInstalled but used by neither agent ({len(unused)}):')
        for name in unused:
            hosts = '+'.join(h for h, s in (('claude', claude_installed), ('codex', codex_installed)) if name in s)
            print(f'  {name}  [{hosts}]')


if __name__ == '__main__':
    main()
