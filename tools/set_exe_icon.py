#!/usr/bin/env python3
"""Puts the game's icon and name on the Windows program file (love.exe) without changing anything else in it.

love.exe carries its icon as six plain, uncompressed pictures (16, 32, 48, 64, 128 and 256 pixels square).
This script overwrites the pixels of each picture with the game's icon at the same size. It also rewrites the
program's version block (the name Windows shows in Task Manager, on the taskbar and in the file's Properties:
"LÖVE 11.5" becomes "Hearthfire Chronicle") inside the space the old block occupied, padding the rest with zeros.
Every picture and the version block keep their exact length and position, so the rest of the program (its code,
headers and resource tables) stays byte-for-byte identical: the change cannot affect whether or how the program
runs. The worst a mistake here could do is make the icon or the name look wrong.

If the program file is not laid out as expected, nothing is written and the script exits with an error;
build.sh then keeps the engine's own icon.

Usage (on a Mac; it uses `sips` to resize the artwork):
    python3 tools/set_exe_icon.py love.exe icon.png out.exe
"""
import os
import struct
import subprocess
import sys
import tempfile
import zlib

RT_ICON = 3
RT_VERSION = 16
NAME = 'Hearthfire Chronicle'
VERSION = '2.0'


def fail(msg):
    sys.exit('set_exe_icon: ' + msg)


def icon_resources(d):
    """Every icon picture in a Windows program file, as a list of (id, file offset, size)."""
    return [(ident, off, size) for kind, ident, off, size in resources(d) if kind == RT_ICON]


def resources(d):
    """Finds every resource in a Windows program file. Returns a list of (type, id, file offset, size)."""
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    if d[pe:pe + 4] != b'PE\0\0':
        fail('not a Windows program file')
    nsec, optsize = struct.unpack_from('<H', d, pe + 6)[0], struct.unpack_from('<H', d, pe + 20)[0]
    opt = pe + 24
    magic = struct.unpack_from('<H', d, opt)[0]
    ddir = opt + (112 if magic == 0x20b else 96)
    res_rva = struct.unpack_from('<I', d, ddir + 8 * 2)[0]
    if not res_rva:
        fail('the program has no resources')
    secs = [struct.unpack_from('<IIII', d, opt + optsize + 40 * i + 8) for i in range(nsec)]   # vsize, va, rawsize, rawptr

    def offset(rva):
        for vsize, va, rawsize, rawptr in secs:
            if va <= rva < va + max(vsize, rawsize):
                return rva - va + rawptr
        fail('resource address outside the file')

    base = offset(res_rva)
    found = []

    def walk(o, path):
        named, ids = struct.unpack_from('<HH', d, o + 12)
        for i in range(named + ids):
            name, data = struct.unpack_from('<II', d, o + 16 + 8 * i)
            if data & 0x80000000:
                walk(base + (data & 0x7fffffff), path + [name])
            elif len(path) >= 2:
                rva, size = struct.unpack_from('<II', d, base + data)
                found.append((path[0], path[1], offset(rva), size))

    walk(base, [])
    return found


def read_png(path):
    """Reads an 8-bit RGB or RGBA PNG. Returns (width, height, RGBA bytes, top row first)."""
    d = open(path, 'rb').read()
    if d[:8] != b'\x89PNG\r\n\x1a\n':
        fail(path + ' is not a PNG')
    pos, idat, head = 8, [], None
    while pos < len(d):
        length, kind = struct.unpack_from('>I4s', d, pos)
        body = d[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b'IHDR':
            head = struct.unpack('>IIBBBBB', body)
        elif kind == b'IDAT':
            idat.append(body)
        elif kind == b'IEND':
            break
    w, h, depth, ctype, _, _, interlace = head
    if depth != 8 or ctype not in (2, 6) or interlace:
        fail('unsupported PNG format in ' + path)
    n = 4 if ctype == 6 else 3
    raw = zlib.decompress(b''.join(idat))
    stride = w * n
    prev = bytearray(stride)
    rows = []
    i = 0
    for _ in range(h):
        f = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        if f == 1:
            for x in range(n, stride):
                line[x] = (line[x] + line[x - n]) & 255
        elif f == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                left = line[x - n] if x >= n else 0
                line[x] = (line[x] + ((left + prev[x]) >> 1)) & 255
        elif f == 4:
            for x in range(stride):
                a = line[x - n] if x >= n else 0
                b = prev[x]
                c = prev[x - n] if x >= n else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        elif f != 0:
            fail('bad PNG data in ' + path)
        rows.append(line)
        prev = line
    out = bytearray()
    for line in rows:
        if n == 4:
            out += line
        else:
            for x in range(0, stride, 3):
                out += line[x:x + 3] + b'\xff'
    return w, h, bytes(out)


def sips(*args):
    subprocess.run(['sips'] + list(args), check=True, capture_output=True)


def trimmed(png, tmp):
    """Mac icons leave a transparent margin around the artwork; Windows icons fill their square.
    Returns a copy of the artwork cropped (around its centre) to just outside the visible part."""
    probe = os.path.join(tmp, 'probe.png')
    sips('-z', '256', '256', png, '--out', probe)
    w, h, rgba = read_png(probe)
    xs = [x for y in range(h) for x in range(w) if rgba[(y * w + x) * 4 + 3] >= 48]
    ys = [y for y in range(h) for x in range(w) if rgba[(y * w + x) * 4 + 3] >= 48]
    if not xs:
        return png
    c = (w - 1) / 2
    half = max(c - min(xs), max(xs) - c, c - min(ys), max(ys) - c) + 1
    frac = (2 * half + 0.03 * w) / w              # visible part plus a 1.5% margin on each side
    if frac >= 0.97:
        return png
    full = struct.unpack('>I', open(png, 'rb').read()[16:20])[0]
    side = int(round(full * frac))
    out = os.path.join(tmp, 'trimmed.png')
    sips('-c', str(side), str(side), png, '--out', out)
    tw, th, _ = struct.unpack('>IIB', open(out, 'rb').read()[16:25])
    if (tw, th) != (side, side):
        return png
    return out


def dib_body(w, rgba):
    """Pixels of a 32-bit icon picture as Windows stores them: rows bottom-up, blue-green-red-alpha,
    followed by a 1-bit mask (1 = see-through) with rows padded to 4 bytes."""
    colour = bytearray()
    mask = bytearray()
    mask_row = ((w + 31) // 32) * 4
    for y in range(w - 1, -1, -1):
        bits = bytearray(mask_row)
        for x in range(w):
            r, g, b, a = rgba[(y * w + x) * 4:(y * w + x) * 4 + 4]
            colour += bytes((b, g, r, a))
            if a < 128:
                bits[x >> 3] |= 0x80 >> (x & 7)
        mask += bits
    return bytes(colour + mask)


def parse_version_node(b, pos):
    """One node of the version block: (key, type, value bytes, children). See VS_VERSIONINFO in the Windows docs."""
    length, vlen, vtype = struct.unpack_from('<HHH', b, pos)
    end = pos + length
    k = pos + 6
    kend = k
    while b[kend:kend + 2] != b'\0\0':
        kend += 2
    key = b[k:kend].decode('utf-16-le')
    p = (kend + 2 + 3) & ~3
    vbytes = vlen * 2 if vtype == 1 else vlen
    value = bytes(b[p:p + vbytes])
    p = (p + vbytes + 3) & ~3
    children = []
    while p < end:
        child, p = parse_version_node(b, p)
        children.append(child)
        p = (p + 3) & ~3
    return [key, vtype, value, children], end


def build_version_node(node):
    key, vtype, value, children = node
    out = bytearray(b'\0' * 6) + (key + '\0').encode('utf-16-le')
    out += b'\0' * (-len(out) % 4)
    out += value
    for child in children:
        out += b'\0' * (-len(out) % 4)
        out += build_version_node(child)
    vlen = len(value) // 2 if vtype == 1 else len(value)
    struct.pack_into('<HHH', out, 0, len(out), vlen, vtype)
    return bytes(out)


def text(s):
    return (s + '\0').encode('utf-16-le')


def set_name(d, name, version):
    """Rewrites the program's version block (the name Windows shows in Task Manager, the taskbar and the file's
    Properties) in the space it already occupies. Returns the (start, end) of the bytes that may change."""
    found = [(off, size) for kind, ident, off, size in resources(d) if kind == RT_VERSION]
    if len(found) != 1:
        fail('expected one version block in the program')
    off, size = found[0]
    root, end = parse_version_node(d, off)
    if root[0] != 'VS_VERSION_INFO' or len(root[2]) != 52 or end - off > size:
        fail('the version block is not laid out as expected')
    major, minor = (int(x) for x in version.split('.'))
    fixed = bytearray(root[2])
    struct.pack_into('<IIII', fixed, 8, major << 16 | minor, 0, major << 16 | minor, 0)   # file and product version
    root[2] = bytes(fixed)
    new = {'FileDescription': name, 'ProductName': name, 'FileVersion': version, 'ProductVersion': version,
           'InternalName': '', 'OriginalFilename': name + '.exe',            # InternalName was empty already
           'LegalCopyright': 'Engine © 2006-2024 LÖVE Development Team'}
    tables = [t for sfi in root[3] if sfi[0] == 'StringFileInfo' for t in sfi[3]]
    if not tables:
        fail('the version block has no names in it')
    for table in tables:
        table[3] = [[k, 1, text(v), []] for k, v in new.items()]       # CompanyName (the engine's joke) is dropped
    block = build_version_node(root)
    if len(block) > size:
        fail('the new names do not fit in the space of the old ones')
    d[off:off + size] = block + b'\0' * (size - len(block))
    return off, off + size


def main():
    if len(sys.argv) != 4:
        fail('usage: set_exe_icon.py love.exe icon.png out.exe')
    exe, png, out = sys.argv[1:4]
    original = open(exe, 'rb').read()
    d = bytearray(original)
    icons = icon_resources(d)
    if not icons:
        fail('the program has no icon pictures')
    changed = []
    a, b = set_name(d, NAME, VERSION)
    changed.append((a, b, 0))
    with tempfile.TemporaryDirectory() as tmp:
        art = trimmed(png, tmp)
        for ident, off, size in icons:
            header, w, h2, planes, bpp, compression = struct.unpack_from('<IiiHHI', d, off)
            expected = 40 + w * w * 4 + ((w + 31) // 32) * 4 * w
            if not (header == 40 and h2 == 2 * w and planes == 1 and bpp == 32 and compression == 0 and size == expected):
                fail('icon picture %s is not a plain 32-bit picture; leaving the program untouched' % ident)
            small = os.path.join(tmp, '%d.png' % w)
            sips('-z', str(w), str(w), art, '--out', small)
            pw, ph, rgba = read_png(small)
            if (pw, ph) != (w, w):
                fail('could not resize the artwork to %dx%d' % (w, w))
            body = dib_body(w, rgba)
            if len(body) != size - 40:
                fail('internal size mismatch for %dx%d' % (w, w))
            d[off + 40:off + size] = body
            changed.append((off + 40, off + size, w))
    # Safety net: the file must be the same length, and identical everywhere outside the icon pixels.
    if len(d) != len(original):
        fail('length changed; nothing written')
    pos = 0
    for a, b, _ in sorted(changed):
        if d[pos:a] != original[pos:a]:
            fail('bytes outside the icon changed; nothing written')
        pos = b
    if d[pos:] != original[pos:]:
        fail('bytes outside the icon changed; nothing written')
    tmp_out = out + '.part'
    with open(tmp_out, 'wb') as f:
        f.write(d)
    os.replace(tmp_out, out)
    sizes = ', '.join(str(w) for _, _, w in sorted(changed, key=lambda c: c[2]) if w)
    print('Windows icon set (%s px) and program named "%s"; %d of %d bytes changed, all inside the icon pictures '
          'and the version block' % (sizes, NAME, sum(1 for i in range(len(d)) if d[i] != original[i]), len(d)))


if __name__ == '__main__':
    main()
