import gzip, sys, xml.etree.ElementTree as ET
def kata(s):
    return ''.join(chr(ord(c)+0x60) if 0x3041 <= ord(c) <= 0x3096 else c for c in s)
src, dst = sys.argv[1], sys.argv[2]
n = 0
with gzip.open(src) as f, open(dst, 'w', encoding='utf-8') as out:
    out.write("# generated from KANJIDIC2 (EDRDG, CC BY-SA 4.0) : kanji<TAB>readings(katakana, on first then kun stem)\n")
    for ev, el in ET.iterparse(f):
        if el.tag != 'character':
            continue
        lit = el.findtext('literal')
        rs = []
        for r in el.iter('reading'):
            t = r.get('r_type')
            if t not in ('ja_on', 'ja_kun'):
                continue
            v = r.text.replace('-', '')
            if t == 'ja_kun':
                v = v.split('.')[0]
            v = kata(v)
            if v and v not in rs:
                rs.append(v)
        if rs:
            out.write(f"{lit}\t{','.join(rs)}\n"); n += 1
        el.clear()
print(n, "entries")
