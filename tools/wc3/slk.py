import os, re
B = chr(92)
def lp(p):
    p = os.path.abspath(p)
    return p if p.startswith(B + B) else B + B + '?' + B + p

def read_slk(path):
    """Return (headers, rows) where rows is dict keyed by first-column value -> dict(header->value)."""
    cells = {}
    x = y = 0
    for line in open(lp(path), encoding='latin-1'):
        line = line.rstrip('\r\n')
        if not line.startswith('C;'):
            continue
        parts = line.split(';')
        val = None
        for p in parts[1:]:
            if not p: continue
            t = p[0]
            if t == 'X': x = int(p[1:])
            elif t == 'Y': y = int(p[1:])
            elif t == 'K':
                val = ';'.join(parts[parts.index(p):])[1:]
                break
        if val is None: continue
        if val.startswith('"') and val.endswith('"'): val = val[1:-1]
        else:
            try: val = int(val)
            except ValueError:
                try: val = float(val)
                except ValueError: pass
        cells[(y, x)] = val
    maxx = max(k[1] for k in cells)
    maxy = max(k[0] for k in cells)
    headers = [cells.get((1, i)) for i in range(1, maxx + 1)]
    rows = {}
    for r in range(2, maxy + 1):
        key = cells.get((r, 1))
        if key is None: continue
        rows[str(key)] = {headers[i - 1]: cells[(r, i)] for i in range(1, maxx + 1) if (r, i) in cells and headers[i - 1]}
    return headers, rows

def read_profile(path):
    """Read WC3 .txt profile ([section] key=value)."""
    out = {}; cur = None
    for line in open(lp(path), encoding='utf-8', errors='replace'):
        line = line.strip()
        if line.startswith('//') or not line: continue
        if line.startswith('[') and line.endswith(']'):
            cur = out.setdefault(line[1:-1], {}); continue
        if cur is not None and '=' in line:
            k, v = line.split('=', 1); cur[k] = v
    return out
