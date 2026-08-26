"""Audit translation placeholder usage: keys whose values contain {…}
placeholders but are called with plain .tr() (no args) render the raw
placeholder literally. Also checks en/zh key parity and arg-count mismatches
for .tr(args: [...]) calls.
"""
import io, json, os, re, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(ROOT, 'assets', 'translations')
LIB = os.path.join(ROOT, 'lib')

def load(name):
    return json.load(io.open(os.path.join(ASSETS, name), encoding='utf-8'))

en = load('en.json')
zh = load('zh.json')

# 1. Key parity
only_en = set(en) - set(zh)
only_zh = set(zh) - set(en)
if only_en:
    print('[parity] keys missing in zh.json:', sorted(only_en))
if only_zh:
    print('[parity] keys missing in en.json:', sorted(only_zh))

# 2. Placeholder shape mismatch between locales for shared keys.
pat = re.compile(r'\{[^{}]*\}')
for k in set(en) & set(zh):
    a, b = pat.findall(en[k] or ''), pat.findall(zh[k] or '')
    if len(a) != len(b):
        print(f'[shape] key "{k}": en has {len(a)} placeholders, zh has {len(b)}')

# 3. Scan dart sources for tr() calls.
tr_plain = re.compile(r"'([A-Za-z0-9_.]+)'\.tr\(\)")
tr_args = re.compile(r"'([A-Za-z0-9_.]+)'\.tr\(args:\s*\[")
usages = {}  # key -> list of (file, line, has_args, arg_count)

for dirpath, _dirs, files in os.walk(LIB):
    for fn in files:
        if not fn.endswith('.dart'):
            continue
        p = os.path.join(dirpath, fn)
        try:
            text = io.open(p, encoding='utf-8').read()
        except Exception:
            continue
        rel = os.path.relpath(p, ROOT)
        for i, line in enumerate(text.splitlines(), 1):
            m = tr_args.search(line)
            if m:
                # count top-level commas crudely
                args_part = line[m.end()-1:line.rfind(']')+1]
                n = args_part.count(',') + 1 if ',' in args_part else (1 if args_part.strip('[]').strip() else 0)
                usages.setdefault(m.group(1), []).append((rel, i, True, n))
                continue
            m = tr_plain.search(line)
            if m:
                usages.setdefault(m.group(1), []).append((rel, i, False, 0))

problems = 0
for key, sites in sorted(usages.items()):
    value_en = en.get(key)
    if value_en is None:
        continue
    need = len(pat.findall(value_en))
    for (rel, line, has_args, argc) in sites:
        if need > 0 and not has_args:
            print(f'[missing-args] {rel}:{line} key "{key}" needs {need} arg(s): "{value_en[:70]}"')
            problems += 1
        elif has_args and argc != need:
            print(f'[arg-mismatch] {rel}:{line} key "{key}" passed {argc} arg(s), needs {need}: "{value_en[:70]}"')
            problems += 1

print(f'done; {problems} problem(s)')
