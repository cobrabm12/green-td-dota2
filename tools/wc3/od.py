"""Parse WC3 object data (w3u/w3t/w3b/w3h = no levels; w3a/w3d/w3q = with levels) into JSON.
Usage: python -I objdata.py <extracted_dir> <out.json>"""
import struct, sys, os, json, re

def lp(p):
    p = os.path.abspath(p)
    prefix = '\\\\?\\'
    return prefix + p if os.name == 'nt' and not p.startswith(prefix) else p

def load_wts(path):
    s = open(path, 'rb').read().decode('utf-8', 'replace')
    out = {}
    for m in re.finditer(r'STRING (\d+)\s*(?://[^\n]*\n\s*)?\{\r?\n(.*?)\r?\n\}', s, re.S):
        out[int(m.group(1))] = m.group(2)
    return out

def parse(data, levels, wts):
    pos = 0
    def i32():
        nonlocal pos
        v = struct.unpack_from('<i', data, pos)[0]; pos += 4; return v
    def f32():
        nonlocal pos
        v = struct.unpack_from('<f', data, pos)[0]; pos += 4; return v
    def raw4():
        nonlocal pos
        v = data[pos:pos + 4]; pos += 4
        return v.decode('latin-1') if v != b'\0\0\0\0' else ''
    def cstr():
        nonlocal pos
        e = data.index(b'\0', pos)
        v = data[pos:e].decode('utf-8', 'replace'); pos = e + 1
        m = re.fullmatch(r'TRIGSTR_(\d+)', v)
        if m and int(m.group(1)) in wts:
            v = wts[int(m.group(1))]
        return v
    ver = i32()
    result = {}
    for table in ('original', 'custom'):
        n = i32()
        for _ in range(n):
            orig = raw4(); new = raw4()
            if ver >= 3:
                nsets = i32()
            else:
                nsets = 1
            mods = {}
            for _s in range(nsets):
                if ver >= 3:
                    i32()  # set flag
                nm = i32()
                for _m in range(nm):
                    fid = raw4(); typ = i32()
                    lvl = 0
                    if levels:
                        lvl = i32(); i32()
                    if typ == 0: val = i32()
                    elif typ in (1, 2): val = round(f32(), 4)
                    elif typ == 3: val = cstr()
                    else: raise ValueError('bad type %d at %d' % (typ, pos))
                    raw4()
                    key = fid if not lvl else '%s@%d' % (fid, lvl)
                    mods[key] = val
            oid = new or orig
            result[oid] = {'base': orig, 'table': table, 'mods': mods}
    return result

if __name__ == '__main__':
    d = lp(sys.argv[1])
    wts = load_wts(os.path.join(d, 'war3map.wts'))
    out = {'wts_count': len(wts)}
    for ext, lv in (('w3u', False), ('w3t', False), ('w3b', False), ('w3h', False), ('w3a', True), ('w3d', True), ('w3q', True)):
        p = os.path.join(d, 'war3map.' + ext)
        if os.path.exists(p):
            out[ext] = parse(open(p, 'rb').read(), lv, wts)
            print(ext, len(out[ext]))
    json.dump(out, open(lp(sys.argv[2]), 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
    json.dump({str(k): v for k, v in wts.items()}, open(lp(os.path.join(os.path.dirname(lp(sys.argv[2])), 'wts.json')), 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
