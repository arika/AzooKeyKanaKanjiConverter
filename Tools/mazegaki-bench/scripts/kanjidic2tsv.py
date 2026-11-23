# KANJIDIC2 から交ぜ書き変換用の読み表（Docs/converter_api.md の形式）を作る。
# 使い方: python3 -I scripts/kanjidic2tsv.py [--nanori] <kanjidic2.xml.gz> <出力.tsv>
#   --nanori  名前の読み（nanori）を末尾に加える（既定では加えない）
# 出力はコミットしないこと（KANJIDIC2 は CC BY-SA 4.0）。
#
# 読みの並び: 音読み → 訓読み（→ 名前の読み）。KANJIDIC の順のまま。
# 訓読みは送り仮名を `.` の後ろに残す（例: トオ.ル）。`-`（接頭・接尾の印）は除く。
# 語幹だけを取り出すと、送り仮名を残す前の形式（Step 0）と同じ読みの並びになる。
import gzip, sys, xml.etree.ElementTree as ET

args = sys.argv[1:]
nanori = '--nanori' in args
args = [a for a in args if a != '--nanori']
src, dst = args[0], args[1]

def kata(s):
    return ''.join(chr(ord(c)+0x60) if 0x3041 <= ord(c) <= 0x3096 else c for c in s)

n = 0
with gzip.open(src) as f, open(dst, 'w', encoding='utf-8') as out:
    out.write("# generated from KANJIDIC2 (EDRDG, CC BY-SA 4.0) : kanji<TAB>readings(katakana, on then kun with okurigana after '.'"
              + (", then nanori" if nanori else "") + ")\n")
    for ev, el in ET.iterparse(f):
        if el.tag != 'character':
            continue
        lit = el.findtext('literal')
        rs = []
        def add(v):
            if v and v not in rs:
                rs.append(v)
        for r in el.iter('reading'):
            t = r.get('r_type')
            if t not in ('ja_on', 'ja_kun'):
                continue
            v = kata(r.text.replace('-', ''))
            if v.endswith('.'):
                v = v[:-1]
            add(v)
        if nanori:
            for r in el.iter('nanori'):
                add(kata(r.text.replace('-', '')))
        if rs:
            out.write(f"{lit}\t{','.join(rs)}\n"); n += 1
        el.clear()
print(n, "entries")
