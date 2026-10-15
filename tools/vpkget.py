"""Extract files from a Valve VPK (v1/v2) by exact path or substring.
Usage: python -I tools/vpkget.py <pak01_dir.vpk> <outdir> <path-or-substring> [...]"""
import os, struct, sys

dirpath, outdir = sys.argv[1], sys.argv[2]
wanted = sys.argv[3:]
f = open(dirpath, 'rb')
sig, ver, tree = struct.unpack('<III', f.read(12))
hdr = 12 + (16 if ver == 2 else 0)
f.seek(hdr)
data = f.read(tree)
pos = 0


def cstr():
    global pos
    e = data.index(b'\0', pos)
    s = data[pos:e].decode('utf-8', 'replace'); pos = e + 1
    return s


entries = []
while True:
    ext = cstr()
    if not ext:
        break
    while True:
        d = cstr()
        if not d:
            break
        while True:
            name = cstr()
            if not name:
                break
            crc, preload, arch, off, ln, term = struct.unpack_from('<IHHIIH', data, pos)
            pos += 18
            pre = data[pos:pos + preload]
            pos += preload
            full = ('%s/%s.%s' % (d, name, ext)) if d != ' ' else '%s.%s' % (name, ext)
            entries.append((full, arch, off, ln, pre))

base = dirpath[:-len('_dir.vpk')]
count = 0
for full, arch, off, ln, pre in entries:
    if not any(w == full or w in full for w in wanted):
        continue
    if arch == 0x7fff:
        f.seek(hdr + tree + off)
        body = f.read(ln)
    else:
        with open('%s_%03d.vpk' % (base, arch), 'rb') as a:
            a.seek(off)
            body = a.read(ln)
    out = os.path.join(outdir, full.replace('/', os.sep))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, 'wb').write(pre + body)
    count += 1
print('extracted', count)
