#!/usr/bin/env python3
"""Run Fancraft's headless regression suites; fail on script errors even if Godot exits 0."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
suites = ['inventory', 'terrain_shape', 'texture_library']
for suite in suites:
    result = subprocess.run([str(root / 'tools/godot.sh'), '--headless', '--script', f'res://tests/{suite}.gd'],
                            cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
    print(result.stdout, end='', flush=True)
    marker = f'{suite.upper()}_RESULT failures=0'
    if result.returncode or marker not in result.stdout or 'SCRIPT ERROR' in result.stdout:
        print(f'SUITE FAILED: {suite}')
        sys.exit(result.returncode or 1)
# Game-level checks run the real main scene headless with a dev hook.
for hook, marker in [('--inputtest', 'INPUT_TEST_RESULT failures=0')]:
    result = subprocess.run([str(root / 'tools/godot.sh'), '--headless', '--', hook], cwd=root, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
    print('\n'.join(l for l in result.stdout.splitlines() if 'RESULT' in l or 'FAIL' in l or 'SCRIPT ERROR' in l))
    if result.returncode or marker not in result.stdout or 'SCRIPT ERROR' in result.stdout:
        print(f'SUITE FAILED: {hook}')
        sys.exit(result.returncode or 1)
print(f'CHECKS_PASSED suites={len(suites) + 1}')
