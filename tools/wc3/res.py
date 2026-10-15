"""Resolve map object data against base SLK tables. Run by tools/wc3/fetch_data.sh."""
import sys, json, os
sys.path.insert(0, 'tools')
from slk import read_slk, lp

obj = json.load(open(lp('out/obj.json'), encoding='utf-8'))

# ---------------- units ----------------
_, umeta = read_slk('slk/unitmetadata.slk')
tables = {}
for name, f in (('UnitBalance', 'unitbalance'), ('UnitWeapons', 'unitweapons'), ('UnitData', 'unitdata'), ('UnitAbilities', 'unitabilities')):
    tables[name] = read_slk('slk/%s.slk' % f)[1]

KEEP = {
 'unam': 'name', 'utip': 'tip', 'utub': 'ubertip', 'uhot': 'hotkey', 'umdl': 'model', 'usca': 'scale', 'uico': 'icon',
 'ugol': 'gold', 'ulum': 'lumber', 'upoi': 'points', 'ubld': 'buildtime', 'uupt': 'upgradesTo', 'ubui': 'builds', 'utra': 'trains',
 'uabi': 'abilities', 'udaa': 'defaultAbility', 'uhpm': 'hp', 'uhpr': 'hpRegen', 'umpm': 'mana', 'umpi': 'manaInit', 'umpr': 'manaRegen',
 'udef': 'armor', 'udty': 'defType', 'umvs': 'moveSpeed', 'umvt': 'moveType', 'ucol': 'collision', 'ulev': 'level',
 'uaen': 'attacksEnabled', 'ua1b': 'dmgBase1', 'ua1d': 'dmgDice1', 'ua1s': 'dmgSides1', 'ua1c': 'cool1', 'ua1r': 'range1',
 'ua1t': 'atkType1', 'ua1w': 'weapType1', 'ua1g': 'targets1', 'uamn': 'minRange', 'ua1f': 'areaFull1', 'ua1h': 'areaMed1',
 'ua1q': 'areaSmall1', 'uhd1': 'factorMed1', 'uqd1': 'factorSmall1', 'usd1': 'spillDist1', 'utc1': 'maxTargets1',
 'udl1': 'dmgLoss1', 'ua1z': 'missileSpeed1', 'ua1m': 'missile1', 'ubs1': 'backswing1', 'udp1': 'dmgPoint1',
 'ua2b': 'dmgBase2', 'ua2d': 'dmgDice2', 'ua2s': 'dmgSides2', 'ua2c': 'cool2', 'ua2r': 'range2', 'ua2t': 'atkType2',
 'ua2w': 'weapType2', 'ua2g': 'targets2', 'ua2f': 'areaFull2', 'ua2h': 'areaMed2', 'ua2q': 'areaSmall2',
 'ubba': 'bountyBase', 'ubdi': 'bountyDice', 'ubsi': 'bountySides', 'ulba': 'lumberBountyBase', 'ulbd': 'lumberBountyDice', 'ulbs': 'lumberBountySides',
 'urtm': 'repairTime', 'ureq': 'requires', 'upgr': 'upgradesUsed', 'ures': 'researches', 'usid': 'sight', 'utyp': 'classification',
 'urac': 'race', 'umh1': 'showUI1', 'uimz': 'impactZ', 'umvh': 'flyHeight', 'uacq': 'acquire', 'ucs1': 'cs1',
 'utar': 'targetedAs', 'ufoo': 'food', 'unbm': 'nbmmIcon', 'isbldg': 'isbldg', 'ubdg': 'isBuilding', 'uhos': 'hostile',
 'ua1p': 'splashTargets1', 'udup': 'dmgUpg', 'uarm': 'armorSound',
}
id2field = {k: (v['slk'], v['field']) for k, v in umeta.items()}

def base_unit(uid):
    out = {}
    for t, rows in tables.items():
        r = rows.get(uid)
        if not r: continue
        for mid, (slk, field) in id2field.items():
            if slk == t and field in r and mid in KEEP:
                out[KEEP[mid]] = r[field]
    return out

units = {}
for uid, o in obj['w3u'].items():
    rec = base_unit(o['base'])
    rec['_base'] = o['base']
    for mid, val in o['mods'].items():
        rec[KEEP.get(mid, mid)] = val
    units[uid] = rec

# ---------------- abilities ----------------
_, ameta = read_slk('slk/abilitymetadata.slk')
_, adata = read_slk('slk/abilitydata.slk')
a_id2 = {k: (v['field'], v.get('data', 0), v.get('repeat', 0)) for k, v in ameta.items()}
abil = {}
for aid, o in obj['w3a'].items():
    base = adata.get(o['base'], {})
    lv = o['mods'].get('alev', base.get('levels', 1))
    rec = {'_base': o['base'], 'code': base.get('code', o['base']), 'levels': lv, 'lv': {}}
    for L in range(1, int(lv) + 1 if isinstance(lv, int) else 2):
        d = {}
        for col in ('targs', 'Cast', 'Dur', 'HeroDur', 'Cool', 'Cost', 'Area', 'Rng', 'UnitID', 'BuffID'):
            c = '%s%d' % (col, min(L, 4))
            if c in base and base[c] not in ('-', '_', ''):
                d[col] = base[c]
        for X in 'ABCDEFGHI':
            c = 'Data%s%d' % (X, min(L, 4))
            if c in base and base[c] not in ('-', '_', ''):
                d['Data' + X] = base[c]
        rec['lv'][L] = d
    other = {}
    for key, val in o['mods'].items():
        if '@' in key:
            mid, L = key.split('@'); L = int(L)
            field, data, rep = a_id2.get(mid, (mid, 0, 0))
            name = field + ('ABCDEFGHI'[data - 1] if data else '')
            rec['lv'].setdefault(L, {})[name] = val
        else:
            field, data, rep = a_id2.get(key, (key, 0, 0))
            other[field] = val
    rec.update(other)
    abil[aid] = rec

# ---------------- upgrades ----------------
_, umet2 = read_slk('slk/upgrademetadata.slk')
_, udat = read_slk('slk/upgradedata.slk')
upg = {}
for rid, o in obj['w3q'].items():
    rec = {'_base': o['base']}
    rec.update({k: v for k, v in udat.get(o['base'], {}).items() if v not in ('-', '_')})
    for key, val in o['mods'].items():
        mid = key.split('@')[0]
        f = umet2.get(mid, {}).get('field', mid)
        if '@' in key: f += '@' + key.split('@')[1]
        rec[f] = val
    upg[rid] = rec

json.dump({'units': units, 'abilities': abil, 'upgrades': upg, 'buffs': obj.get('w3h', {}), 'items': obj.get('w3t', {})},
          open(lp('out/resolved.json'), 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
print('units', len(units), 'abilities', len(abil), 'upgrades', len(upg))
