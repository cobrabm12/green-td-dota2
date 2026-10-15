"""Measure server speed (game seconds per real second) and client FPS in the running game.
Usage: python -I tools/perf.py [seconds]"""
import os, subprocess, sys, time, re

here = os.path.dirname(os.path.abspath(__file__))
secs = float(sys.argv[1]) if len(sys.argv) > 1 else 10


def lua(code):
    r = subprocess.run([sys.executable, '-I', os.path.join(here, 'lua.py'), code, '--wait', '1'],
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    m = re.search(r'\[GTD-TEST\] lua ok (.*)', r.stdout)
    return m.group(1).strip() if m else None


def netcon(*cmds, wait='1'):
    r = subprocess.run([sys.executable, '-I', os.path.join(here, 'netcon.py'), '--wait', wait] + list(cmds),
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    return r.stdout


state = "return string.format('%.3f|%d|%d|%d', GameRules:GetGameTime(), GTD.Waves.current, GTD.Creeps.count, GTD.Waves.chances)"
r0 = time.time(); s0 = lua(state)
netcon('gtd_fps %d' % int(secs))
time.sleep(secs)
r1 = time.time(); s1 = lua(state)
time.sleep(2)
log = r'C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta\game\dota\console.log'
with open(log, 'rb') as f:
    f.seek(max(0, os.path.getsize(log) - 400000))
    tail = f.read().decode('utf-8', 'replace')
fps = re.findall(r'\[GTD-TEST\] fps .*', tail)[-1:]
g0, w0, c0, ch0 = s0.split('|')
g1, w1, c1, ch1 = s1.split('|')
ratio = (float(g1) - float(g0)) / (r1 - r0)
print('server: %.1f game s in %.1f real s -> %.2fx real time (timescale-adjusted)' % (float(g1) - float(g0), r1 - r0, ratio))
print('wave %s -> %s, creeps %s -> %s, chances %s -> %s' % (w0, w1, c0, c1, ch0, ch1))
print('\n'.join(fps) if fps else 'no fps report received')
