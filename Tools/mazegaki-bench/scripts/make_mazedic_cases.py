# mazegaki-dic（ipadic.maze.txt）から、手元専用の評価セット（交ぜ書きのキーと正解の組）を作る。
# 使い方:
#   python3 -I scripts/make_mazedic_cases.py <ipadic.maze.txt> <kanjidic2.xml.gz> <kanji_readings.tsv> <出力.tsv> [件数] [乱数の種]
# 入力データ・出力はコミットしないこと（CLAUDE.md の原則 3）。出力先は data/（.gitignore 済み）にする。
#
# 抽出の規則:
# - 交ぜ書きの項目（キー != 単語）のうち、漢字 1 字だけをかなにしたもの（mazedic_stats.py と同じ定義）。
# - 一般語彙に限る。固有名詞（地名・姓・名・人名・組織・固有名詞）と接辞（接尾・接頭・助数詞）は除く。
# - 熟字訓などの不規則な読みの語を除く。単語の 1 字かな化の項目すべてについて、割り当てられた読みが
#   KANJIDIC の読み（音・訓の語幹・送り仮名つきの訓・連用形・名乗り）と促音化・連濁で説明できない語は、
#   熟字訓などで機械的に分割されたものとみなして除外する（例: 今う→今日、大とな→大人）。
# - 1 つのキーに正解が複数ある場合は、すべて正解の列に入れる（ベンチはどれか 1 つの順位を採る）。
# - カテゴリは「品詞/表内」または「品詞/表外」。表内 = かなにした字の読みが、読み表（kanji_readings.tsv）
#   と促音化・連濁で取れる（mazedic_stats.py で取りこぼしにならない）。表外 = Step 1 の改善対象。
#
# 出力（TSV、ヘッダ行は # で始まる）: カテゴリ<TAB>入力<TAB>正解1,正解2,…<TAB>読み（ひらがな）
# 同時に <出力>.kana.tsv に、入力を全部かなにした対照用のセットを書く（読みで変換したときの上限の目安）。
import gzip, random, sys, collections
import xml.etree.ElementTree as ET

dic_path, kd_xml, kd_tsv, out_path = sys.argv[1:5]
N = int(sys.argv[5]) if len(sys.argv) > 5 else 3000
SEED = int(sys.argv[6]) if len(sys.argv) > 6 else 20261123

def kata(s): return ''.join(chr(ord(c) + 0x60) if 'ぁ' <= c <= 'ゖ' else c for c in s)
def is_kanji(c): return '一' <= c <= '鿿' or '㐀' <= c <= '䶿' or c in '々〆'
def is_hira(c): return 'ぁ' <= c <= 'ゖ' or c == 'ー'

DAKU = str.maketrans('カキクケコサシスセソタチツテトハヒフヘホ', 'ガギグゲゴザジズゼゾダヂヅデドバビブベボ')
HANDAKU = str.maketrans('ハヒフヘホ', 'パピプペポ')
def variants(r):
    s = {r}
    if len(r) >= 2 and r[-1] in 'キクチツ': s.add(r[:-1] + 'ッ')
    for x in list(s):
        s.add(x[0].translate(DAKU) + x[1:]); s.add(x[0].translate(HANDAKU) + x[1:])
    # ヂ/ヅ はジ/ズとも書かれる
    for x in list(s):
        s.add(x.replace('ヂ', 'ジ').replace('ヅ', 'ズ'))
    return s

# ウ段 → イ段（連用形）
U2I = dict(zip('ウクグスツヌフブムルュ', 'イキギシチニヒビミリィ'))

# 寛容な読み集合（熟字訓の判定用）
generous = collections.defaultdict(set)
with gzip.open(kd_xml) as f:
    for ev, el in ET.iterparse(f):
        if el.tag != 'character': continue
        lit = el.findtext('literal')
        rs = set()
        for r in el.iter('reading'):
            t = r.get('r_type')
            if t not in ('ja_on', 'ja_kun'): continue
            v = kata(r.text.replace('-', ''))
            if '.' in v:
                stem, oku = v.split('.', 1)
                rs.add(stem); rs.add(stem + oku)
                for i in range(1, len(oku)): rs.add(stem + oku[:i])
                if oku[-1] in U2I: rs.add(stem + oku[:-1] + U2I[oku[-1]])
            else:
                rs.add(v)
        for n in el.iter('nanori'):
            rs.add(kata(n.text))
        for x in rs:
            if x: generous[lit] |= variants(x)
        el.clear()

strict = collections.defaultdict(set)
for l in open(kd_tsv, encoding='utf-8'):
    if l.startswith('#') or '\t' not in l: continue
    k, v = l.rstrip('\n').split('\t')
    for x in v.split(','): strict[k] |= variants(x)

EXCLUDE_POS = {'地名', '固有名詞', '名', '姓', '組織', '人名', '接尾一般', '接頭語', '助数詞'}
def pos_group(p):
    if p.startswith('動詞'): return '動詞'
    if p == '名詞サ変': return 'サ変名詞'
    if p == '名詞形動': return '形動名詞'
    if p in ('名詞', '形容詞', '副詞'): return p
    return 'その他'

def single_kanji_diff(key, word):
    i = 0
    while i < min(len(key), len(word)) and key[i] == word[i]: i += 1
    j = 0
    while j < min(len(key), len(word)) - i and key[-1 - j] == word[-1 - j]: j += 1
    wseg = word[i:len(word) - j]; kseg = key[i:len(key) - j]
    if len(wseg) == 1 and is_kanji(wseg) and kseg and all('ぁ' <= c <= 'ゖ' for c in kseg):
        return wseg, kata(kseg)
    return None

entries = []                                 # (key, word, pos, reading, kanji, kana-reading)
irregular = set()                            # 熟字訓など、読みを説明できない語
for l in open(dic_path, encoding='utf-8'):
    f = l.rstrip('\n').split('\t')
    if len(f) < 4: continue
    key, word, pos, reading = f[0], f[1], f[2], f[3].split(' ')[0]
    if key == word or pos in EXCLUDE_POS: continue
    d = single_kanji_diff(key, word)
    if d is None: continue
    k, r = d
    if r not in generous.get(k, ()): irregular.add(word)
    entries.append((key, word, pos, reading, k, r))

by_key = collections.OrderedDict()
for key, word, pos, reading, k, r in entries:
    if word in irregular: continue
    e = by_key.setdefault(key, {'words': [], 'pos': pos, 'reading': reading, 'covered': True})
    if word not in e['words']: e['words'].append(word)
    if r not in strict.get(k, ()): e['covered'] = False

keys = sorted(by_key)
random.Random(SEED).shuffle(keys)
sample = sorted(keys[:N], key=lambda k: (pos_group(by_key[k]['pos']), not by_key[k]['covered'], k))

def write(path, use_reading):
    with open(path, 'w', encoding='utf-8') as out:
        out.write(f'# mazegaki-dic 由来の評価セット（手元専用・コミット禁止） seed={SEED} n={len(sample)}\n')
        for k in sample:
            e = by_key[k]
            cat = pos_group(e['pos']) + ('/表内' if e['covered'] else '/表外')
            inp = e['reading'] if use_reading else k
            out.write(f"{cat}\t{inp}\t{','.join(e['words'])}\t{e['reading']}\n")
write(out_path, False)
write(out_path.removesuffix('.tsv') + '.kana.tsv', True)

print(f'entries(1字かな・一般語彙) {len(entries)}  irregular words {len(irregular)}  keys {len(by_key)}  sampled {len(sample)}')
c = collections.Counter(pos_group(by_key[k]['pos']) + ('/表内' if by_key[k]['covered'] else '/表外') for k in sample)
print(' '.join(f'{k}:{v}' for k, v in sorted(c.items())))
print('multi-answer keys', sum(1 for k in sample if len(by_key[k]['words']) > 1))
