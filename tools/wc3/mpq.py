"""Minimal MPQ (v1) reader for Warcraft 3 maps. Usage: python -I mpq.py <map.w3x> <outdir>"""
import struct, sys, os, zlib, bz2

M = 0xFFFFFFFF

def _build_table():
    t = [0] * 0x500
    seed = 0x00100001
    for i1 in range(0x100):
        i2 = i1
        for _ in range(5):
            seed = (seed * 125 + 3) % 0x2AAAAB
            a = (seed & 0xFFFF) << 16
            seed = (seed * 125 + 3) % 0x2AAAAB
            b = seed & 0xFFFF
            t[i2] = a | b
            i2 += 0x100
    return t

T = _build_table()

def hstr(s, typ):
    s1, s2 = 0x7FED7FED, 0xEEEEEEEE
    for ch in s.upper().encode('latin-1'):
        s1 = (T[(typ << 8) + ch] ^ ((s1 + s2) & M)) & M
        s2 = (ch + s1 + s2 + (s2 << 5) + 3) & M
    return s1

def decrypt(data, key):
    n = len(data) // 4
    vals = struct.unpack('<%dI' % n, data[:n * 4])
    out = []
    seed = 0xEEEEEEEE
    for v in vals:
        seed = (seed + T[0x400 + (key & 0xFF)]) & M
        ch = v ^ ((key + seed) & M)
        out.append(ch)
        key = ((((~key) << 0x15) + 0x11111111) & M) | (key >> 0x0B)
        seed = (ch + seed + (seed << 5) + 3) & M
    return struct.pack('<%dI' % n, *out) + data[n * 4:]

# ---------- PKWARE DCL explode ----------
_LenBits = [3,2,3,3,4,4,4,5,5,5,5,6,6,6,7,7]
_LenCode = [5,3,1,6,10,2,12,20,4,24,8,48,16,32,64,0]
_ExLenBits = [0,0,0,0,0,0,0,0,1,2,3,4,5,6,7,8]
_LenBase = [0,1,2,3,4,5,6,7,8,10,14,22,38,70,134,262]
_DistBits = [2,4,4,5,5,5,5,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,7,7,7,7,7,7,7,7,7,7,
             7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8]
_DistCode = [0x03,0x0D,0x05,0x19,0x09,0x11,0x01,0x3E,0x1E,0x2E,0x0E,0x36,0x16,0x26,0x06,0x3A,
             0x1A,0x2A,0x0A,0x32,0x12,0x22,0x42,0x02,0x7C,0x3C,0x5C,0x1C,0x6C,0x2C,0x4C,0x0C,
             0x74,0x34,0x54,0x14,0x64,0x24,0x44,0x04,0x78,0x38,0x58,0x18,0x68,0x28,0x48,0x08,
             0xF0,0x70,0xB0,0x30,0xD0,0x50,0x90,0x10,0xE0,0x60,0xA0,0x20,0xC0,0x40,0x80,0x00]

def explode(data):
    ctype, dict_bits = data[0], data[1]
    if ctype != 0:
        raise ValueError('ASCII-mode implode not supported')
    pos = 2
    bitbuf = 0
    nbits = 0
    def need(n):
        nonlocal bitbuf, nbits, pos
        while nbits < n:
            if pos >= len(data):
                raise EOFError
            bitbuf |= data[pos] << nbits
            pos += 1
            nbits += 8
    def bits(n):
        nonlocal bitbuf, nbits
        need(n)
        v = bitbuf & ((1 << n) - 1)
        bitbuf >>= n
        nbits -= n
        return v
    def decode(codes, lens):
        # bit-reversed prefix codes
        for l in range(1, 9):
            need(l) if True else None
            v = bitbuf & ((1 << l) - 1)
            for i, (c, cl) in enumerate(zip(codes, lens)):
                if cl == l and c == v:
                    bits(l)
                    return i
        raise ValueError('bad code')
    out = bytearray()
    try:
        while True:
            if bits(1) == 0:
                out.append(bits(8))
                continue
            li = decode(_LenCode, _LenBits)
            length = _LenBase[li] + (bits(_ExLenBits[li]) if _ExLenBits[li] else 0) + 2
            if length == 519:
                break
            di = decode(_DistCode, _DistBits)
            if length == 2:
                dist = (di << 2) | bits(2)
            else:
                dist = (di << dict_bits) | bits(dict_bits)
            dist += 1
            for _ in range(length):
                out.append(out[-dist])
    except EOFError:
        pass
    return bytes(out)

def decompress(sec):
    mask = sec[0]
    d = sec[1:]
    if mask & 0x10:
        d = bz2.decompress(d)
    if mask & 0x08:
        d = explode(d)
    if mask & 0x02:
        d = zlib.decompress(d)
    if mask & ~(0x02 | 0x08 | 0x10):
        raise ValueError('unsupported compression 0x%02x' % mask)
    return d

class MPQ:
    def __init__(self, path):
        self.raw = open(path, 'rb').read()
        base = 0
        while self.raw[base:base + 4] != b'MPQ\x1a':
            base += 0x200
        self.base = base
        (_, hsize, asize, ver, shift, htoff, btoff, hcount, bcount) = struct.unpack_from('<4sIIHHIIII', self.raw, base)
        self.sector = 512 << shift
        ht = decrypt(self.raw[base + htoff: base + htoff + hcount * 16], hstr('(hash table)', 3))
        bt = decrypt(self.raw[base + btoff: base + btoff + bcount * 16], hstr('(block table)', 3))
        self.hashes = [struct.unpack_from('<IIHHI', ht, i * 16) for i in range(hcount)]
        self.blocks = [struct.unpack_from('<IIII', bt, i * 16) for i in range(bcount)]

    def find(self, name):
        n = len(self.hashes)
        start = hstr(name, 0) % n
        a, b = hstr(name, 1), hstr(name, 2)
        for k in range(n):
            h = self.hashes[(start + k) % n]
            if h[4] == 0xFFFFFFFF:
                return None
            if h[0] == a and h[1] == b and h[4] < len(self.blocks):
                return h[4]
        return None

    def read(self, name):
        bi = self.find(name)
        if bi is None:
            return None
        off, csize, fsize, flags = self.blocks[bi]
        off += self.base
        key = hstr(name.replace('/', '\\').split('\\')[-1], 3)
        if flags & 0x20000:
            key = ((key + (off - self.base)) ^ fsize) & M
        if flags & 0x01000000:
            d = self.raw[off: off + csize]
            if flags & 0x10000:
                d = decrypt(d, key)
            if flags & 0x200 and csize < fsize:
                d = decompress(d)
            elif flags & 0x100 and csize < fsize:
                d = explode(d)
            return d
        nsec = (fsize + self.sector - 1) // self.sector
        if not (flags & 0x300):
            d = self.raw[off: off + csize]
            if flags & 0x10000:
                out = bytearray()
                for i in range(nsec):
                    out += decrypt(d[i * self.sector:(i + 1) * self.sector], (key + i) & M)
                d = bytes(out)
            return d[:fsize]
        tcount = nsec + 1 + (1 if flags & 0x04000000 else 0)
        st = self.raw[off: off + tcount * 4]
        if flags & 0x10000:
            st = decrypt(st, (key - 1) & M)
        offs = struct.unpack('<%dI' % tcount, st)
        out = bytearray()
        for i in range(nsec):
            sec = self.raw[off + offs[i]: off + offs[i + 1]]
            if flags & 0x10000:
                sec = decrypt(sec, (key + i) & M)
            expect = min(self.sector, fsize - i * self.sector)
            if len(sec) < expect:
                sec = decompress(sec) if flags & 0x200 else explode(sec)
            out += sec
        return bytes(out[:fsize])

NAMES = ['(listfile)', '(attributes)', 'war3map.j', 'scripts\\war3map.j', 'war3map.lua', 'war3map.w3i', 'war3map.wts',
         'war3map.w3u', 'war3map.w3t', 'war3map.w3a', 'war3map.w3b', 'war3map.w3d', 'war3map.w3q', 'war3map.w3h',
         'war3map.doo', 'war3mapUnits.doo', 'war3map.w3r', 'war3map.w3e', 'war3map.wpm', 'war3map.shd', 'war3map.mmp',
         'war3map.wtg', 'war3map.wct', 'war3map.w3c', 'war3map.w3s', 'war3mapMisc.txt', 'war3mapSkin.txt',
         'war3mapExtra.txt', 'war3map.imp', 'war3mapMap.blp', 'war3mapPreview.tga']

def lp(p):
    p = os.path.abspath(p)
    prefix = '\\\\?\\'
    return prefix + p if os.name == 'nt' and not p.startswith(prefix) else p

if __name__ == '__main__':
    m = MPQ(lp(sys.argv[1]))
    outdir = lp(sys.argv[2])
    os.makedirs(outdir, exist_ok=True)
    names = list(NAMES)
    lf = m.read('(listfile)')
    if lf:
        names += [l.strip() for l in lf.decode('latin-1').splitlines() if l.strip()]
    seen = set()
    found_blocks = set()
    for n in names:
        if n.lower() in seen:
            continue
        seen.add(n.lower())
        bi = m.find(n)
        if bi is None:
            continue
        try:
            d = m.read(n)
        except Exception as e:
            print('FAIL', n, e)
            continue
        found_blocks.add(bi)
        p = os.path.join(outdir, n.replace('\\', '__'))
        open(p, 'wb').write(d)
        print('%-40s %8d' % (n, len(d)))
    live = [i for i, b in enumerate(m.blocks) if b[3] & 0x80000000]
    print('blocks: %d live, %d named' % (len(live), len(found_blocks)))
