# mazegaki-dic（ipadic.maze.txt）から単語内の漢字の読みを抜き出し、読み表＋派生規則での取りこぼしを数える。
# 使い方: python3 -I mazedic_stats.py <ipadic.maze.txt> <kanji_readings.tsv>
# 入力データ・出力はコミットしないこと（手元専用）。派生規則は main.swift の readingVariants を簡略化したもの。
import sys, collections, re
dic, kd = sys.argv[1], sys.argv[2]
def kana2kata(s): return ''.join(chr(ord(c)+0x60) if 'ぁ'<=c<='ゖ' else c for c in s)
isk = lambda c: '一'<=c<='鿿' or c in '々〆'
kdr = {}
for l in open(kd, encoding='utf-8'):
    if "\t" not in l: continue
    k, v = l.rstrip('\n').split('\t'); kdr[k] = set(v.split(','))
base = 0; maze = 0; pairs = collections.Counter(); words=set(); jukuji=0
cur=None
for l in open(dic, encoding='utf-8'):
    f = l.rstrip('\n').split('\t')
    if len(f) < 4: continue
    key, word = f[0], f[1]
    if key == word: base += 1; words.add(word); continue
    maze += 1
    # single-kanji replacement: same length prefix/suffix alignment
    # find positions where key differs from word
    i = 0
    while i < min(len(key),len(word)) and key[i]==word[i]: i+=1
    j = 0
    while j < min(len(key),len(word))-i and key[-1-j]==word[-1-j]: j+=1
    wseg = word[i:len(word)-j]; kseg = key[i:len(key)-j]
    if len(wseg)==1 and isk(wseg) and kseg and all('ぁ'<=c<='ゖ' for c in kseg):
        pairs[(wseg, kana2kata(kseg))] += 1
# words with kanji but no mazegaki expansion (jukujikun etc.)
print('base', base, 'maze', maze, 'distinct (kanji,reading) pairs', len(pairs), 'kanji', len({k for k,_ in pairs}))
def variants(r):
    s={r}
    if r[-1] in 'キクチツ': s.add(r[:-1]+'ッ')
    d=str.maketrans('カキクケコサシスセソタチツテトハヒフヘホ','ガギグゲゴザジズゼゾダヂヅデドバビブベボ')
    p=str.maketrans('ハヒフヘホ','パピプペポ')
    for x in list(s): s.add(x[0].translate(d)+x[1:]); s.add(x[0].translate(p)+x[1:])
    return s
miss = collections.Counter(); misscnt=0; tot=0
for (k,r),c in pairs.items():
    tot+=c
    known=set()
    for x in kdr.get(k,()): known|=variants(x)
    if r not in known: miss[(k,r)]=c; misscnt+=c
print('occurrences', tot, 'not covered by KANJIDIC+variants', misscnt, f'({misscnt/tot:.1%})', 'distinct', len(miss))
print('top uncovered:', ' '.join(f'{k}={r}:{c}' for (k,r),c in miss.most_common(40)))
