# 文書（Markdown）の文から、手元専用の文の評価セット（交ぜ書きの入力と正解の組）を作る。
# 使い方:
#   python3 -I scripts/make_sentence_cases.py <azooKey_dict.tsv> <ipadic.maze.txt> <kanjidic2.xml.gz> <kanji_readings.tsv> <出力.tsv> <文書.md>...
#   - azooKey_dict.tsv: scripts/dump_dictionary.py の出力（表記と読みの逆引きに使う）
#   - ipadic.maze.txt: 語の中の漢字ごとの読みを求めるのに使う（mazegaki-dic）
#   - kanjidic2.xml.gz: 教育漢字（学年 1〜6）の一覧を取るのに使う
#   - kanji_readings.tsv: ipadic.maze.txt で読みが分からない字の、読みの候補
# 作り方:
#   1. 文書から、コード・表・英字を含まない日本語の文を取り出す。交ぜ書き変換そのものを説明する節と文は除く。
#   2. 辞書を逆向きに使って文を語に区切り、語の読みを得る（コストの和が最小の区切り方。連接コストは使わない）。
#   3. 教育漢字はそのまま残し、それ以外の漢字をかなに開いて、交ぜ書きの入力にする。
#      字ごとの読みは、(a) 漢字が 1 字だけの続きならその部分の読み、(b) ipadic.maze.txt でその語のその字を開いた形、
#      (c) 読み表（語幹・促音化・連濁）で分けられる読み、の順に求める。どれでも分けられなければ、その漢字の続きをまとめて開く。
# 出力の列: カテゴリ, 交ぜ書きの入力, 正解（元の文）, かなの入力（読み全体）, 正解の語の区切り（| で区切る）
#   カテゴリ: 文/開いた（開いた字がある）、文/そのまま（教育漢字だけで、入力が正解と同じ）
# 出力も、別名で書き出すかなの入力のセット（<出力>.kana.tsv）も、コミットしないこと（手元専用）。
import collections, gzip, re, sys

dict_path, maze_path, kd_xml, kd_tsv, out_path = sys.argv[1:6]
docs = sys.argv[6:]

def hira2kata(s): return ''.join(chr(ord(c) + 0x60) if 'ぁ' <= c <= 'ゖ' else c for c in s)
def kata2hira(s): return ''.join(chr(ord(c) - 0x60) if 'ァ' <= c <= 'ヶ' else c for c in s)
def is_kanji(c): return '一' <= c <= '鿿' or '豈' <= c <= '﫿' or c == '々'
def is_kana(c): return 'ぁ' <= c <= 'ゖ' or 'ァ' <= c <= 'ヺ' or c == 'ー'
PUNCT = set('、。「」『』（）・！？…〜：')

# --- 教育漢字 ---
kyoiku = set()
with gzip.open(kd_xml, 'rt', encoding='utf-8') as f:
    literal = None
    for line in f:
        m = re.search(r'<literal>(.)</literal>', line)
        if m: literal = m.group(1)
        m = re.search(r'<grade>(\d+)</grade>', line)
        if m and literal and 1 <= int(m.group(1)) <= 6: kyoiku.add(literal)

# --- 逆引きの辞書: 表記 → [(読み, コスト)] ---
lexicon = collections.defaultdict(list)
for line in open(dict_path, encoding='utf-8'):
    word, ruby, _, _, value = line.rstrip('\n').split('\t')
    if not word or not all(is_kanji(c) or is_kana(c) for c in word): continue
    lexicon[word].append((ruby, -float(value)))
for word in lexicon:
    lexicon[word] = sorted(set(lexicon[word]), key=lambda x: x[1])
MAX_WORD = max(map(len, lexicon))

# --- ipadic.maze.txt: (語, 字の位置) → 読み（カタカナ） ---
maze = collections.defaultdict(dict)
for line in open(maze_path, encoding='utf-8'):
    f = line.rstrip('\n').split('\t')
    if len(f) < 4: continue
    key, word = f[0], f[1]
    if key == word: continue
    i = 0
    while i < min(len(key), len(word)) and key[i] == word[i]: i += 1
    j = 0
    while j < min(len(key), len(word)) - i and key[-1 - j] == word[-1 - j]: j += 1
    wseg, kseg = word[i:len(word) - j], key[i:len(key) - j]
    if len(wseg) == 1 and is_kanji(wseg) and kseg and all('ぁ' <= c <= 'ゖ' for c in kseg):
        maze[word][i] = hira2kata(kseg)

# --- 読み表（語幹・促音化・連濁） ---
table = collections.defaultdict(set)
DAKU = str.maketrans('カキクケコサシスセソタチツテトハヒフヘホ', 'ガギグゲゴザジズゼゾダヂヅデドバビブベボ')
HANDAKU = str.maketrans('ハヒフヘホ', 'パピプペポ')
for line in open(kd_tsv, encoding='utf-8'):
    if line.startswith('#') or '\t' not in line: continue
    k, v = line.rstrip('\n').split('\t')
    for n in v.split(','):
        stem = hira2kata(n.split('.')[0].replace('-', ''))
        if not stem: continue
        forms = {stem}
        if stem[-1] in 'キクチツ': forms.add(stem[:-1] + 'ッ')
        for x in list(forms):
            forms.add(x[0].translate(DAKU) + x[1:]); forms.add(x[0].translate(HANDAKU) + x[1:])
        table[k] |= forms

# --- 文の取り出し ---
def sentences(path):
    in_code = False
    in_mazegaki = False
    for line in open(path, encoding='utf-8'):
        if line.startswith('```'):
            in_code = not in_code; continue
        if not in_code and line.startswith('#'):
            # 交ぜ書き変換を説明する節は、交ぜ書きの例（破たん）を正解に含むので除く
            in_mazegaki = '交ぜ書き' in line or 'azegaki' in line
        if in_code or in_mazegaki or line.lstrip().startswith('|'): continue
        line = re.sub(r'^\s*(#+|[-*+]|\d+\.)\s+', '', line.rstrip('\n'))
        line = re.sub(r'\*\*|__', '', line)
        for s in re.split(r'(?<=。)', line):
            s = s.strip()
            if not (8 <= len(s) <= 60): continue
            if not all(is_kanji(c) or is_kana(c) or c in PUNCT for c in s): continue
            if not any(is_kanji(c) for c in s): continue
            # 交ぜ書き変換そのものを説明する文は、交ぜ書きの例（破たん）を正解に含むので除く
            if '交ぜ書き' in s or '入力漢字' in s: continue
            yield s

# --- 区切り: コストの和が最小（1 語ごとに 1.0 を足して、長い語を好む） ---
WORD_PENALTY = 1.0
def segment(s):
    n = len(s)
    best = [(0.0, None)] + [(float('inf'), None)] * n
    for i in range(n):
        if best[i][0] == float('inf'): continue
        for j in range(i + 1, min(n, i + MAX_WORD) + 1):
            w = s[i:j]
            options = []
            if w in lexicon:
                ruby, cost = lexicon[w][0]
                options.append((ruby, cost))
            elif j == i + 1 and (is_kana(w) or w in PUNCT):
                options.append((hira2kata(w), 20.0))
            for ruby, cost in options:
                c = best[i][0] + cost + WORD_PENALTY
                if c < best[j][0]: best[j] = (c, (i, w, ruby))
    if best[n][0] == float('inf'): return None
    words, j = [], n
    while j > 0:
        i, w, ruby = best[j][1]
        words.append((w, ruby)); j = i
    return words[::-1]

# --- 字ごとの読み ---
def split_run(run, ruby, word, offset):
    """漢字の続き run（語 word の offset 文字目から）の読み ruby を、字ごとに分ける。分けられなければ None"""
    if len(run) == 1: return [ruby]
    known = maze.get(word, {})
    def rec(k, p):
        if k == len(run): return [] if p == len(ruby) else None
        c = run[k]
        choices = [known[offset + k]] if offset + k in known else sorted(table.get(c, ()), key=len, reverse=True)
        for r in choices:
            if ruby.startswith(r, p):
                rest = rec(k + 1, p + len(r))
                if rest is not None: return [r] + rest
        return None
    return rec(0, 0)

def mazegaki(word, ruby):
    """語を交ぜ書きの入力にする。(入力, 開いた字があるか, 読みの対応に失敗したか)"""
    if all(c in kyoiku or not is_kanji(c) for c in word): return word, False, False
    # 表記と読みを、かなの部分で揃えて漢字の続きごとに対応づける
    pattern = ''.join('(.+?)' if is_kanji(c) else re.escape(hira2kata(c)) for c in re.findall(r'[^\W\d_a-zA-Z]', word) or word)
    parts = re.findall(r'[一-鿿豈-﫿々]+|[^一-鿿豈-﫿々]+', word)
    regex = ''.join('(.+?)' if is_kanji(p[0]) else re.escape(hira2kata(p)) for p in parts)
    m = re.fullmatch(regex, ruby)
    if not m: return kata2hira(ruby), True, True
    out, failed, g, offset = [], False, 0, 0
    for p in parts:
        if is_kanji(p[0]):
            r = m.group(g + 1); g += 1
            if all(c in kyoiku for c in p):
                out.append(p)
            else:
                rs = split_run(p, r, word, offset)
                if rs is None:
                    out.append(kata2hira(r)); failed = True
                else:
                    # 々 は直前の字に合わせる
                    keep = []
                    for k, c in enumerate(p):
                        keep.append(keep[-1] if c == '々' and keep else c in kyoiku)
                    out.append(''.join(c if keep[k] else kata2hira(rs[k]) for k, c in enumerate(p)))
        else:
            out.append(p)
        offset += len(p)
    return ''.join(out), True, failed

seen, rows = set(), []
stats = collections.Counter()
for doc in docs:
    for s in sentences(doc):
        if s in seen: continue
        seen.add(s)
        words = segment(s)
        if words is None: stats['区切れない'] += 1; continue
        inputs, opened, failed = [], False, False
        for w, r in words:
            i, o, f = mazegaki(w, r)
            inputs.append(i); opened |= o; failed |= f
        stats['語ごとかなに開いた文' if failed else '文'] += 1
        reading = kata2hira(''.join(r for _, r in words))
        rows.append(('文/開いた' if opened else '文/そのまま', ''.join(inputs), s, reading, '|'.join(w for w, _ in words)))

rows.sort(key=lambda r: r[0])
with open(out_path, 'w', encoding='utf-8') as out, open(out_path.removesuffix('.tsv') + '.kana.tsv', 'w', encoding='utf-8') as kana:
    head = '# 文書由来の文の評価セット（手元専用・コミット禁止）\n'
    out.write(head); kana.write(head)
    for cat, inp, exp, reading, segs in rows:
        out.write(f'{cat}\t{inp}\t{exp}\t{reading}\t{segs}\n')
        kana.write(f'{cat}\t{reading}\t{exp}\t{reading}\t{segs}\n')
print(f'{len(rows)} 文（{dict(stats)}）、うち開いた字がある文 {sum(r[0] == "文/開いた" for r in rows)}: {out_path}', file=sys.stderr)
