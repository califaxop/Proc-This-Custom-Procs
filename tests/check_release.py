#!/usr/bin/env python3
"""Proc This! release check: python3 tests/check_release.py

Before a release: the version is the same in the toc, the CHANGELOG and the README's "Recent
changes"; every file the toc loads exists and every Lua file is loaded; the release workflow leaves
the developer files out of the zip; and the offline tests pass. Prints each check; exits 1 if any
fails.
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
fails = []


def check(ok, what):
    print(('ok    ' if ok else 'FAIL  ') + what)
    if not ok:
        fails.append(what)


def read(name):
    with open(os.path.join(ROOT, name), encoding='utf-8') as f:
        return f.read()


toc = read('ProcThis.toc')
version = re.search(r'^## Version:\s*(\S+)', toc, re.M).group(1)
changelog = re.search(r'^## (\d+\.\d+\.\d+)', read('CHANGELOG.md'), re.M)
readme = re.search(r'^- \*\*(\d+\.\d+\.\d+):\*\*', read('README.md'), re.M)
check(changelog and changelog.group(1) == version, f'CHANGELOG starts with {version}')
check(readme and readme.group(1) == version, f"README's Recent changes start with {version}")

loaded = [l.strip() for l in toc.splitlines() if l.strip().endswith('.lua') and not l.startswith('#')]
check(all(os.path.isfile(os.path.join(ROOT, f)) for f in loaded), 'every file the toc loads exists')
on_disk = sorted(f for f in os.listdir(ROOT) if f.endswith('.lua'))
check(sorted(loaded) == on_disk, 'every Lua file is in the toc: ' + ', '.join(set(on_disk) ^ set(loaded)) if sorted(loaded) != on_disk else 'every Lua file is in the toc')

wf = read('.github/workflows/release.yml')
for name in ("README.md", "CHANGELOG.md", "DEVELOPMENT.md", "API_COMPATIBILITY.md", "/tests"):
    check(f"--exclude='{name}'" in wf, f'the release zip leaves out {name}')

r = subprocess.run([sys.executable, os.path.join(HERE, 'run_tests.py')], capture_output=True, text=True)
last = (r.stdout.strip().splitlines() or ['?'])[-1]
check(r.returncode == 0, 'offline tests: ' + last)

print('\n' + ('release check passed' if not fails else f'{len(fails)} check(s) failed'))
sys.exit(1 if fails else 0)
