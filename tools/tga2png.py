"""Convert an (uncompressed or RLE) 24/32-bit TGA screenshot to PNG, optionally downscaled.
Usage: python -I tools/tga2png.py in.tga out.png [scale]"""
import struct, sys, zlib


def read_tga(path):
    d = open(path, 'rb').read()
    idlen, cmtype, itype = d[0], d[1], d[2]
    w, h = struct.unpack_from('<HH', d, 12)
    bpp, desc = d[16], d[17]
    pos = 18 + idlen + (struct.unpack_from('<H', d, 5)[0] * ((d[7] + 7) // 8) if cmtype else 0)
    px = bpp // 8
    n = w * h
    if itype == 2:
        raw = d[pos:pos + n * px]
    elif itype == 10:
        out = bytearray()
        while len(out) < n * px:
            hdr = d[pos]; pos += 1
            cnt = (hdr & 0x7f) + 1
            if hdr & 0x80:
                out += d[pos:pos + px] * cnt; pos += px
            else:
                out += d[pos:pos + px * cnt]; pos += px * cnt
        raw = bytes(out)
    else:
        raise ValueError('unsupported TGA type %d' % itype)
    rows = [raw[y * w * px:(y + 1) * w * px] for y in range(h)]
    if not (desc & 0x20):   # bottom-up
        rows.reverse()
    return w, h, px, rows


def main():
    src, dst = sys.argv[1], sys.argv[2]
    scale = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    w, h, px, rows = read_tga(src)
    ow, oh = w // scale, h // scale
    out = bytearray()
    for y in range(oh):
        row = rows[y * scale]
        out.append(0)
        for x in range(ow):
            i = x * scale * px
            b, g, r = row[i], row[i + 1], row[i + 2]
            out += bytes((r, g, b))

    def chunk(t, data):
        c = struct.pack('>I', len(data)) + t + data
        return c + struct.pack('>I', zlib.crc32(t + data) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', ow, oh, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(bytes(out), 6)) + chunk(b'IEND', b'')
    open(dst, 'wb').write(png)
    print('%dx%d -> %s' % (ow, oh, dst))


if __name__ == '__main__':
    main()
