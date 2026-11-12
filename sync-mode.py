#!/usr/bin/env python3
"""Write MODE.md into the global instruction file of every agent tool, between markers. Idempotent."""
import os, shutil, sys
B = os.path.expanduser('~/Projects/ai-orchestration')
START, END = '<!-- ai-orchestration:mode start -->', '<!-- ai-orchestration:mode end -->'
TARGETS = ['~/.claude/CLAUDE.md', '~/.codex/AGENTS.md', '~/.qwen/QWEN.md', '~/.config/opencode/AGENTS.md']
block = f'{START}\n{open(f"{B}/MODE.md").read().strip()}\n{END}\n'
os.makedirs(f'{B}/backups/config', exist_ok=True)
for t in TARGETS:
    p = os.path.expanduser(t)
    old = open(p).read() if os.path.exists(p) else ''
    bak = f'{B}/backups/config/{t.replace("~/", "").replace("/", "__")}.orig'
    if old and START not in old and not os.path.exists(bak): shutil.copy(p, bak)
    if START in old:
        a, b = old.index(START), old.index(END) + len(END)
        new = old[:a] + block.rstrip('\n') + old[b:]
    else:
        new = (old.rstrip('\n') + '\n\n' if old.strip() else '') + block
    if new != old:
        os.makedirs(os.path.dirname(p), exist_ok=True); open(p, 'w').write(new); print('updated', t)
    else: print('unchanged', t)
