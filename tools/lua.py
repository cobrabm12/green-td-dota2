"""Run a Lua snippet in the running game (server VM) through gtd_luax.
Usage: python -I tools/lua.py "return GTD.Waves.current" [--wait 2]
       python -I tools/lua.py @file.lua [--wait 2]"""
import os, subprocess, sys

code = sys.argv[1]
if code.startswith('@'):
    code = open(code[1:], encoding='utf-8').read()
wait = sys.argv[3] if len(sys.argv) > 3 and sys.argv[2] == '--wait' else '2'
here = os.path.dirname(os.path.abspath(__file__))
hexcode = code.encode('utf-8').hex()
CHUNK = 400
chunks = [hexcode[i:i + CHUNK] for i in range(0, len(hexcode), CHUNK)] or ['']
cmds = ['gtd_luax_add ' + c for c in chunks[:-1]] + ['gtd_luax ' + chunks[-1]]
subprocess.run([sys.executable, '-I', os.path.join(here, 'netcon.py'), '--wait', wait, '--grep', ''] + cmds)
