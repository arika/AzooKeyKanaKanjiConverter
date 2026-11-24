# azooKey の既定辞書の全項目を TSV に書き出す（文の評価セットを作るための逆引き用）。
# 使い方: python3 -I scripts/dump_dictionary.py <anco（CliTool）のパス> <辞書のディレクトリ> <出力.tsv>
#   出力の列: 表記, 読み（カタカナ）, 左 CID, 右 CID, コスト（value）
# 出力はコミットしないこと（手元専用）。
import os, re, subprocess, sys

anco, dict_dir, out_path = sys.argv[1:4]
names = sorted(f[:-len('.louds')] for f in os.listdir(os.path.join(dict_dir, 'louds')) if f.endswith('.louds'))
line_re = re.compile(r'Ruby: (.*) Word: (.*) Value: (\S+) CID: \((\d+), (\d+)\) MID: \d+$')
ansi = re.compile(r'\x1b\[[0-9;]*m')
count = 0
with open(out_path, 'w', encoding='utf-8') as out:
    for name in names:
        # ファイル名は先頭の字のコードポイント（[30A2] など）。anco には字そのものを渡す
        m = re.fullmatch(r'\[([0-9A-F]+)\]', name)
        target = chr(int(m.group(1), 16)) if m else name
        result = subprocess.run([anco, 'dict', 'read', target, '-d', dict_dir, '--word', '.*'],
                                capture_output=True, text=True, encoding='utf-8')
        for line in result.stdout.splitlines():
            g = line_re.search(ansi.sub('', line))
            if g:
                ruby, word, value, lcid, rcid = g.groups()
                out.write(f'{word}\t{ruby}\t{lcid}\t{rcid}\t{value}\n')
                count += 1
print(f'{len(names)} ファイル、{count} 項目を書き出しました: {out_path}', file=sys.stderr)
