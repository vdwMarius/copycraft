#!/usr/bin/env python3
"""Run current game checks; reject script errors even when Godot exits zero."""
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
suites = ['material_pack', 'surface_relief', 'material_integration', 'material_ui', 'micro_details', 'touch', 'autojump', 'smoke']
for suite in suites:
    result = subprocess.run([str(root/'tools/godot.sh'), '--headless', '--script', f'res://tests/{suite}.gd'], cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout, end='', flush=True)
    marker = f'{suite.upper()}_RESULT failures=0'
    if result.returncode or marker not in result.stdout or 'SCRIPT ERROR' in result.stdout or 'ERROR:' in result.stdout:
        sys.exit(result.returncode or 1)
print(f'CHECKS_PASSED suites={len(suites)}')
