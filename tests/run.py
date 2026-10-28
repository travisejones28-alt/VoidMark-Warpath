#!/usr/bin/env python3
"""Run Lua 5.1 runtime tests via native Lua or lupa.lua51, then static packaging checks."""
import pathlib, shutil, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[1]
import os
os.chdir(root)
lua = shutil.which('lua5.1') or shutil.which('lua')
if lua:
    subprocess.run([lua, 'tests/runtime.lua'], check=True)
else:
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError:
        sys.exit('Install Lua 5.1, or pip install lupa, then run python tests/run.py')
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(pathlib.Path('tests/runtime.lua').read_text())
files = []
for toc in ['VoidMarkWarpath.toc', 'VoidMarkWarpath_Camelot.toc']:
    lines = pathlib.Path(toc).read_text().splitlines()
    assert '## Title: Warpath' in lines
    assert '## SavedVariablesPerCharacter: WarpathCharDB' in lines
    assert ('## Interface: 16001' if 'Camelot' in toc else '## Interface: 11509') in lines
    entries = [x for x in lines if x and not x.startswith('#')]
    assert entries == ['Core.lua', 'Compat.lua', 'Database.lua', 'Targeting.lua', 'Macros.lua', 'Alerts.lua', 'Detection.lua', 'UI.lua', 'Minimap.lua', 'Config.lua']
    for file in entries: assert pathlib.Path(file).is_file(), file
    files = entries
for file in files:
    text = pathlib.Path(file).read_text()
    for forbidden in ['TargetUnit(', 'RunMacro(', 'RunMacroText(', 'SetAttribute(', 'SetBinding(', 'UIParent:UnregisterEvent', 'ADDON_ACTION_FORBIDDEN']:
        assert forbidden not in text, (file, forbidden)
assert not pathlib.Path('Data').exists()
print('PASS: TOCs, module order, standalone structure, no insecure targeting/casting or legacy error scanning')
