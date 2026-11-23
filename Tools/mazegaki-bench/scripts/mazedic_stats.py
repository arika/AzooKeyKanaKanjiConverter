# mazegaki-dic（ipadic.maze.txt）から単語内の漢字の読みを抜き出し、読み表＋派生規則での取りこぼしを数える。
# 使い方: python3 -I mazedic_stats.py <ipadic.maze.txt> <kanji_readings.tsv> [--rules legacy|library] [--max N]
#   --rules legacy   Step 0 の規則（既定）: 表の読みの語幹（上限なし）＋促音化・連濁（main.swift の readingVariants を簡略化したもの）
#   --rules library  ライブラリ（MazegakiReadingTable.derive）と同じ規則: 上限つきの語幹・促音化・連濁・連用形・連用形の連濁
#   --max N          --rules library のときの、1 字あたりの表の読みの上限（既定 8。0 以下で上限なし）
# 入力データ・出力はコミットしないこと（手元専用）。
import sys, collections, unicodedata

args = sys.argv[1:]
rules, limit = 'legacy', 8
if '--rules' in args:
    i = args.index('--rules'); rules = args[i + 1]; del args[i:i + 2]
if '--max' in args:
    i = args.index('--max'); limit = int(args[i + 1]); del args[i:i + 2]
if limit <= 0: limit = 10 ** 9
assert rules in ('legacy', 'library'), rules
dic, kd = args[0], args[1]

def kana2kata(s): return ''.join(chr(ord(c)+0x60) if 'ぁ'<=c<='ゖ' else c for c in s)
isk = lambda c: '一'<=c<='鿿' or c in '々〆'

# 読み表: 見出し → 表の書式の読みの並び
# library ではライブラリと同じく、正準等価な見出し（CJK 互換漢字と統合漢字）の行を連結する
table = collections.defaultdict(list)
for l in open(kd, encoding='utf-8'):
    if l.startswith('#') or "\t" not in l: continue
    k, v = l.rstrip('\n').split('\t')
    if rules == 'library':
        table[unicodedata.normalize('NFC', k)] += v.split(',')
    else:
        table[k] = v.split(',')

base = 0; maze = 0; pairs = collections.Counter()
for l in open(dic, encoding='utf-8'):
    f = l.rstrip('\n').split('\t')
    if len(f) < 4: continue
    key, word = f[0], f[1]
    if key == word: base += 1; continue
    maze += 1
    # 漢字 1 字だけをかなにした項目: 前後の一致部分を除いた差分で判定する
    i = 0
    while i < min(len(key),len(word)) and key[i]==word[i]: i+=1
    j = 0
    while j < min(len(key),len(word))-i and key[-1-j]==word[-1-j]: j+=1
    wseg = word[i:len(word)-j]; kseg = key[i:len(key)-j]
    if len(wseg)==1 and isk(wseg) and kseg and all('ぁ'<=c<='ゖ' for c in kseg):
        pairs[(wseg, kana2kata(kseg))] += 1
print('base', base, 'maze', maze, 'distinct (kanji,reading) pairs', len(pairs), 'kanji', len({k for k,_ in pairs}))

# --- Step 0 の規則 ---
def legacy_variants(r):
    s={r}
    if r[-1] in 'キクチツ': s.add(r[:-1]+'ッ')
    d=str.maketrans('カキクケコサシスセソタチツテトハヒフヘホ','ガギグゲゴザジズゼゾダヂヅデドバビブベボ')
    p=str.maketrans('ハヒフヘホ','パピプペポ')
    for x in list(s): s.add(x[0].translate(d)+x[1:]); s.add(x[0].translate(p)+x[1:])
    return s

def legacy_known(notations):
    known = set()
    for x in notations:
        stem = x.split('.')[0]
        if stem: known |= legacy_variants(stem)
    return known

# --- ライブラリと同じ規則（読みと由来） ---
RENDAKU = {'カ':'ガ','キ':'ギ','ク':'グ','ケ':'ゲ','コ':'ゴ','サ':'ザ','シ':'ジ','ス':'ズ','セ':'ゼ','ソ':'ゾ',
           'タ':'ダ','チ':'ヂジ','ツ':'ヅズ','テ':'デ','ト':'ド','ハ':'バパ','ヒ':'ビピ','フ':'ブプ','ヘ':'ベペ','ホ':'ボポ'}
GODAN = dict(zip('ウクグスツヌブムル', 'イキギシチニビミリ'))
IE = set('イキギシジチヂニヒビピミリ' + 'エケゲセゼテデネヘベペメレ')
def is_kata(c): return 'ァ' <= c <= 'ヺ' or c == 'ー'

def library_readings(notations):
    """[(読み, 由来)]。由来は stem / sokuon / rendaku / conjunctive / conjunctiveRendaku"""
    seen, bases = set(), []
    for n in notations:
        if len(bases) >= limit: break
        n = ''.join(kana2kata(c) for c in n if c != '-' and not c.isspace())
        stem, _, oku = n.partition('.')
        if not stem or not all(map(is_kata, stem)) or not all(map(is_kata, oku)): continue
        if (stem, oku) in seen: continue
        seen.add((stem, oku)); bases.append((stem, oku))
    def sokuon(r): return r[:-1] + 'ッ' if len(r) >= 2 and r[-1] in 'キクチツ' else None
    def rendaku(r): return [v + r[1:] for v in RENDAKU.get(r[0], '')]
    def conj(stem, oku):
        if not oku: return None
        body, last = oku[:-1], oku[-1]
        if last == 'ル' and body and body[-1] in IE: return stem + body
        return stem + body + GODAN[last] if last in GODAN else None
    out = []
    add = lambda r, kind: out.append((r, kind)) if r and r not in {x for x, _ in out} else None
    for s, _ in bases: add(s, 'stem')
    for s, _ in bases: add(sokuon(s), 'sokuon')
    for s, _ in bases:
        for r in rendaku(s): add(r, 'rendaku')
    cs = [c for c in (conj(s, o) for s, o in bases) if c]
    for c in cs: add(c, 'conjunctive')
    for c in cs:
        for r in rendaku(c): add(r, 'conjunctiveRendaku')
    return out

miss = collections.Counter(); misscnt = 0; tot = 0; by_kind = collections.Counter()
for (k, r), c in pairs.items():
    tot += c
    if rules == 'legacy':
        hit = r in legacy_known(table.get(k, ()))
    else:
        kinds = dict(library_readings(table.get(unicodedata.normalize('NFC', k), ())))
        hit = r in kinds
        if hit: by_kind[kinds[r]] += c
    if not hit: miss[(k, r)] = c; misscnt += c
print(f'rules {rules}' + (f' max {limit if limit < 10 ** 9 else "none"}' if rules == 'library' else ''))
print('occurrences', tot, 'not covered by table+variants', misscnt, f'({misscnt/tot:.1%})', 'distinct', len(miss))
if by_kind:
    print('covered by kind:', ' '.join(f'{k}:{by_kind[k]}' for k in ('stem', 'sokuon', 'rendaku', 'conjunctive', 'conjunctiveRendaku')))
print('top uncovered:', ' '.join(f'{k}={r}:{c}' for (k,r),c in miss.most_common(40)))
