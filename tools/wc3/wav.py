"""Extract waves, wave-start rules and creep paths from war3map.j. Run by tools/wc3/fetch_data.sh."""
import sys, re, json
sys.path.insert(0, 'tools')
from slk import lp

J = open(lp('ex/war3map.j'), encoding='latin-1').read()
wts = json.load(open(lp('out/wts.json'), encoding='utf-8'))
R = json.load(open(lp('out/resolved.json'), encoding='utf-8'))
U = R['units']

funcs = {}
for m in re.finditer(r'^function (\w+) takes .*?\n(.*?)^endfunction', J, re.S | re.M):
    funcs[m.group(1)] = m.group(2)

def ts(s):
    m = re.fullmatch(r'"?TRIGSTR_(\d+)"?', s.strip())
    if m:
        return wts.get(str(int(m.group(1))), s)
    return s

def clean(s):
    s = re.sub(r'\|[cC][0-9a-fA-F]{8}', '', str(s))
    return s.replace('|r', '').replace('|R', '').replace('|n', ' ').replace('\r', '').replace('\n', ' ')

# ---- rect centers
rects = {}
for m in re.finditer(r'set (gg_rct_\w+) = Rect\( ([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+) \)', J):
    x1, y1, x2, y2 = map(float, m.group(2, 3, 4, 5))
    rects[m.group(1)[7:]] = {'min': [x1, y1], 'max': [x2, y2], 'center': [(x1 + x2) / 2, (y1 + y2) / 2]}

# ---- path graph: trigger registering enter-rect X with action move to rect Y
graph = {}
for name, body in funcs.items():
    if not name.startswith('InitTrig_Path_') and name != 'InitTrig_END_Go':
        continue
    trig = name[len('InitTrig_'):]
    reg = re.search(r'TriggerRegisterEnterRectSimple\( \w+, gg_rct_(\w+) \)', body)
    act = funcs.get('Trig_%s_Actions' % trig, '')
    mv = re.search(r'"move", GetRectCenter\(gg_rct_(\w+)\)', act)
    if reg:
        graph[reg.group(1)] = mv.group(1) if mv else None
if 'Trig_END_Go_Actions' in funcs:
    pass

# ---- waves
waves = {}
for name, body in funcs.items():
    m = re.fullmatch(r'Trig_Waves(\d+)_Actions', name)
    if not m:
        continue
    n = int(m.group(1))
    spawns, notes, seq = [], [], []
    cond_player = None
    for line in body.splitlines():
        line = line.strip()
        ic = re.match(r'if \( (Trig_\w+)\(\) \) then', line)
        if ic:
            cm = re.search(r'GetPlayerSlotState\(Player\((\d+)\)\)', funcs.get(ic.group(1), ''))
            cond_player = int(cm.group(1)) if cm else None
            continue
        c = re.search(r"CreateNUnitsAtLoc\( (\d+), '(\w{4})', Player\((\d+)\), GetRectCenter\(gg_rct_(\w+)\)", line)
        if c:
            spawns.append((int(c.group(1)), c.group(2), c.group(4), cond_player))
            seq.append(['spawn', int(c.group(1)), c.group(2), c.group(4), cond_player])
            continue
        pw = re.search(r'PolledWait\( ([\d.]+) \)', line)
        if pw:
            seq.append(['wait', float(pw.group(1))])
            continue
        hc = re.search(r'SetPlayerHandicapBJ\( Player\(11\), ([\d.]+) \)', line)
        if hc:
            seq.append(['handicap', float(hc.group(1))])
        if line.startswith('call DisplayTextToForce') or line.startswith('call DisplayTimedTextToForce'):
            t = re.search(r'"(TRIGSTR_\d+)"', line)
            notes.append('text: ' + clean(ts(t.group(1))) if t else line)
        elif 'PlaySoundBJ' in line:
            notes.append('sound: ' + line.split('gg_snd_')[1].split(' ')[0])
        elif any(k in line for k in ('PolledWait', 'LeaderboardSet', 'udg_LVL', 'DestroyTimerDialog', 'endif', 'else', 'DoNothing', 'if (')):
            continue
        elif line:
            notes.append(line)
    units = {}
    for cnt, uid, rect, pl in spawns:
        units.setdefault(uid, []).append((cnt, rect))
    waves[n] = {'spawns': spawns, 'units': units, 'notes': notes, 'seq': seq}

# ---- wave start triggers
starts = {}
for name, body in funcs.items():
    m = re.fullmatch(r'Trig_[Ww]avstart(\d+)_Actions', name)
    if not m:
        continue
    n = int(m.group(1))
    cond = funcs.get('Trig_%s_Conditions' % name[5:-8], '')
    init = funcs.get('InitTrig_%s' % name[5:-8], '')
    gold = re.findall(r'AdjustPlayerStateBJ\( (\d+), GetEnumPlayer\(\), PLAYER_STATE_RESOURCE_GOLD', ''.join(funcs.get(f, '') for f in funcs if f.startswith(name[:-8] + '_Func')))
    starts[n] = {
        'cond': 'all creeps dead' if 'CountUnitsInGroup' in cond else re.sub(r'\s+', ' ', cond.strip())[:200],
        'period': re.findall(r'TriggerRegisterTimerEventPeriodic\( \w+, ([\d.]+) \)', init),
        'gold_all': gold,
        'delay': sum(float(x) for x in re.findall(r'PolledWait\( ([\d.]+) \)', body)),
        'body': [l.strip() for l in body.splitlines() if l.strip() and 'StopSound' not in l],
    }

out = {'rects': rects, 'graph': graph, 'waves': waves, 'starts': starts}
json.dump(out, open(lp('out/waves.json'), 'w', encoding='utf-8'), indent=1, ensure_ascii=False)

# ---- report
lines = []
lines.append('# Path graph')
for k, v in graph.items():
    lines.append('%s -> %s' % (k, v))
lines.append('\n# Waves')
for n in sorted(waves):
    w = waves[n]
    parts = []
    for uid, lst in w['units'].items():
        u = U.get(uid, {})
        tot = sum(c for c, _ in lst)
        parts.append('%s "%s" x%d/spawn (%d spawns) hp=%s arm=%s/%s spd=%s move=%s bounty=%s abil=%s' % (
            uid, clean(u.get('tip', u.get('name', '?')))[:40], lst[0][0], len(lst), u.get('hp'), u.get('armor'), u.get('defType'),
            u.get('moveSpeed'), u.get('moveType'), u.get('bountyBase'), u.get('abilities')))
    s = starts.get(n + 1, {})
    lines.append('W%d: %s | notes: %s | next: %s gold+%s' % (n, ' || '.join(parts), '; '.join(w['notes'])[:400], s.get('cond'), s.get('gold_all')))
open(lp('out/waves.md'), 'w', encoding='utf-8').write('\n'.join(lines))
print(len(waves), 'waves;', len(starts), 'starts;', len(graph), 'path nodes')
