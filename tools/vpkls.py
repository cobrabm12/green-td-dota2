"""List files in a Valve VPK v1/v2 directory file. Usage: python -I vpkls.py <pak01_dir.vpk> <out.txt> [ext,ext]"""
import struct, sys
path, out = sys.argv[1], sys.argv[2]
exts = set(sys.argv[3].split(',')) if len(sys.argv) > 3 else None
f = open(path, 'rb')
sig, ver, tree = struct.unpack('<III', f.read(12))
assert sig == 0x55aa1234, hex(sig)
if ver == 2:
    f.read(16)
data = f.read(tree)
pos = 0
def cstr():
    global pos
    e = data.index(b'\0', pos)
    s = data[pos:e].decode('utf-8', 'replace'); pos = e + 1
    return s
res = []
while True:
    ext = cstr()
    if not ext: break
    while True:
        d = cstr()
        if not d: break
        while True:
            name = cstr()
            if not name: break
            crc, preload, arch, off, ln, term = struct.unpack_from('<IHHIIH', data, pos)
            pos += 18 + preload
            if exts is None or ext in exts:
                res.append(('%s/%s.%s' % (d, name, ext)) if d != ' ' else '%s.%s' % (name, ext))
open(out, 'w', encoding='utf-8').write('\n'.join(sorted(res)))
print(len(res))
