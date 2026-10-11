#!/usr/bin/env python3
"""Explicitly authorized local text -> missing vocabulary. See README.md."""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import sys
import tempfile

sys.dont_write_bytecode = True
from personal_common import Refusal, require, plain, run, locked, publish, restore_files

HEADER = '# 个人词表，由 RockType 生成\n'
CUSTOM_HEADER = '# RockType personal dictionary; preserve with personal scripts.\n'
BEGIN = '  # BEGIN RockType personal dictionary\n'
END = '  # END RockType personal dictionary\n'
NAMES = ['roarkt_personal.dict.yaml', 'roarkt_personal_en.dict.yaml',
         'roarkt.custom.yaml', 'roarkt_flypy.custom.yaml', 'roarkt_personal_en.schema.yaml']
EXCLUDED = {'.git', '.build', 'node_modules', 'roarkt-backups'}


def yaml_module():
    try:
        import yaml
        return yaml
    except ImportError:
        raise Refusal('PyYAML 6 required (see README)') from None


def parse_yaml(text):
    yaml = yaml_module()
    # Reject ambiguous constructs instead of silently dropping handwritten YAML.
    tokens = list(yaml.scan(text))
    require(not any(isinstance(t, (yaml.tokens.AnchorToken, yaml.tokens.AliasToken,
                                  yaml.tokens.TagToken)) for t in tokens), 'YAML anchors/tags unsupported')
    node = yaml.compose(text)
    def check(n):
        if isinstance(n, yaml.MappingNode):
            keys = [k.value for k, _ in n.value]
            require(len(keys) == len(set(keys)), 'duplicate YAML keys')
            for _, value in n.value:
                check(value)
        elif isinstance(n, yaml.SequenceNode):
            for value in n.value:
                check(value)
    if node:
        check(node)
    return yaml.safe_load(text), node


def patch(text):
    if text.startswith(CUSTOM_HEADER):
        text = text[len(CUSTOM_HEADER):]
    if BEGIN in text or END in text:
        require(text.count(BEGIN) == text.count(END) == 1, 'invalid managed patch')
        start, end = text.index(BEGIN), text.index(END) + len(END)
        require(start < end, 'invalid managed patch')
        require(text[start:end] == managed_block(), 'managed patch was edited')
        text = text[:start] + text[end:]
    data, node = parse_yaml(text)
    yaml = yaml_module()
    if data is None:
        text += ('\n' if text and not text.endswith('\n') else '') + 'patch:\n'
        index = len(text)
    else:
        require(isinstance(data, dict) and (isinstance(data.get('patch'), dict) or data.get('patch') is None), 'block patch mapping required')
        mapping = next(v for k, v in node.value if k.value == 'patch')
        require((isinstance(mapping, yaml.MappingNode) and not mapping.flow_style) or (isinstance(mapping, yaml.ScalarNode) and mapping.tag.endswith(':null')), 'block patch mapping required')
        for key in (data['patch'] or {}):
            require(isinstance(key, str), 'non-string patch key')
            require(not any(key == prefix or key.startswith(prefix + '/') or key.startswith(prefix + '+')
                            for prefix in ('translator/dictionary', 'translator/user_dict', 'english/dictionary', 'english/user_dict', 'schema/dependencies')) and key not in ('translator', 'english', 'schema', 'translator/+', 'english/+', 'schema/+', '__include', '__patch'), 'translator/english patch conflict')
        index = mapping.end_mark.index
        if isinstance(mapping, yaml.ScalarNode) and text[index:index + 1] == '\n':
            index += 1
        # end_mark can be at a following root key; preserve all original bytes.
    prefix = text[:index]
    text = prefix + ('\n' if prefix and not prefix.endswith('\n') else '') + managed_block() + text[index:]
    result = CUSTOM_HEADER + text
    parse_yaml(result)
    return result


def managed_block():
    return (BEGIN + '  "translator/dictionary": roarkt_personal\n'
            '  "translator/user_dict": roarkt_zh\n'
            '  "english/dictionary": roarkt_personal_en\n'
            '  "english/user_dict": roarkt_en\n'
            '  "schema/dependencies/@next": roarkt_personal_en\n' + END)


def swift_text(text):
    """Extract comments/literals; discard complete interpolated strings."""
    def comment(i):
        if text.startswith('//', i):
            end = text.find('\n', i)
            return len(text) if end < 0 else end
        depth, i = 1, i + 2
        while i < len(text) and depth:
            if text.startswith('/*', i):
                depth += 1; i += 2
            elif text.startswith('*/', i):
                depth -= 1; i += 2
            else:
                i += 1
        require(depth == 0, 'unterminated Swift comment')
        return i

    def interpolation(i):
        depth = 1
        while i < len(text):
            if text.startswith(('//', '/*'), i):
                i = comment(i); continue
            match = re.match(r'(#+)?("""|")', text[i:])
            if match:
                i, _ = literal(i, match); continue
            if text[i] == '(':
                depth += 1
            elif text[i] == ')':
                depth -= 1
                if depth == 0:
                    return i + 1
            i += 1
        raise Refusal('unterminated Swift interpolation')

    def literal(i, match):
        hashes, quote = match.group(1) or '', match.group(2)
        i += len(match.group()); start = i
        closing, escape, interpolated = quote + hashes, '\\' + hashes, False
        while i < len(text):
            if text.startswith(escape + '(', i):
                interpolated = True
                i = interpolation(i + len(escape) + 1)
            elif text.startswith(escape, i):
                i += len(escape) + 1
            elif text.startswith(closing, i):
                return i + len(closing), None if interpolated else text[start:i]
            else:
                i += 1
        raise Refusal('unterminated Swift string')

    result, i = [], 0
    while i < len(text):
        if text.startswith(('//', '/*'), i):
            end = comment(i)
            result.append(text[i + 2:end - 2] if text.startswith('/*', i) else text[i + 2:end])
            i = end
        else:
            match = re.match(r'(#+)?("""|")', text[i:])
            if match:
                i, value = literal(i, match)
                if value is not None:
                    result.append(value)
            else:
                i += 1
    return '\n'.join(result)


def sources(roots):
    seen = set()
    for source in roots:
        root = plain(source)
        require(root.is_dir(), 'source must be a directory')
        for base, dirs, files in os.walk(root, followlinks=False):
            dirs[:] = sorted(d for d in dirs if d not in EXCLUDED and not d.startswith('.')
                             and not (Path(base) / d).is_symlink())
            for name in sorted(files):
                p = Path(base) / name
                if p.suffix not in ('.md', '.swift') or p.is_symlink() or p in seen:
                    continue
                require(p.is_file() and p.stat().st_size <= 4 * 1024 * 1024, 'source file unsupported or too large')
                seen.add(p)
                text = p.read_text(encoding='utf-8')
                yield swift_text(text) if p.suffix == '.swift' else text


def vocabulary(root, name, seen=None):
    seen = set() if seen is None else seen
    require(re.fullmatch(r'[A-Za-z0-9_/.-]+', name) and '..' not in name and not name.startswith('/'), 'invalid dictionary import')
    if name in seen:
        return set()
    seen.add(name)
    p = plain(root / (name + '.dict.yaml'))
    require(p.is_relative_to(root) and p.is_file(), 'dictionary import missing')
    text = p.read_text()
    parts = re.split(r'^\.\.\.\s*$', text, maxsplit=1, flags=re.M)
    require(len(parts) == 2, 'dictionary header missing')
    meta, _ = parse_yaml(parts[0])
    words = {line.split('\t')[0] for line in parts[1].splitlines() if line and not line.startswith('#')}
    for imported in meta.get('import_tables', []):
        words |= vocabulary(root, imported, seen)
    return words


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rime-dir', required=True, help='existing target; never inferred')
    parser.add_argument('--source', action='append', help='explicitly authorized directory; repeatable')
    parser.add_argument('--allow-default-source', action='store_true', help='authorize ~/Repos .md and Swift comments/strings')
    parser.add_argument('--dictionary-dir', help='directory containing the complete deployed source dictionaries')
    parser.add_argument('--min-count', type=int, default=3)
    parser.add_argument('--limit', type=int, default=1500)
    parser.add_argument('--apply', action='store_true', help='default is read-only statistics')
    parser.add_argument('--offline', action='store_true', help='confirm input method and settings writer are stopped')
    parser.add_argument('--rollback', help='backup ID printed by a successful apply')
    args = parser.parse_args()
    os.umask(0o077)
    target = plain(args.rime_dir)
    require(args.min_count >= 2 and 1 <= args.limit <= 10000, 'invalid frequency/limit')
    if args.rollback:
        require(args.offline and args.apply, 'rollback requires --apply --offline')
        with locked(target):
            restore_files(target, args.rollback, NAMES)
        print('rollback complete'); return
    require(args.source or args.allow_default_source, 'explicit source authorization required')
    require(args.dictionary_dir, '--dictionary-dir required')
    require(not args.apply or args.offline, 'apply requires --offline')
    roots = args.source or [str(Path.home() / 'Repos')]
    dictionary = plain(args.dictionary_dir)
    known = vocabulary(dictionary, 'roarkt_zh') | vocabulary(dictionary, 'roarkt_en')
    counts, files = Counter(), 0
    with tempfile.TemporaryDirectory(prefix='roarkt-tokenizer-') as temporary:
        binary = Path(temporary) / 'tokenize'
        run(['xcrun', 'swiftc', Path(__file__).with_name('tokenize.swift'), '-o', binary])
        for text in sources(roots):
            files += 1
            counts.update(json.loads(run([binary], data=text.encode())))
            counts.update(re.findall(r'(?<![\w@/])[A-Za-z][A-Za-z0-9]*(?:[-+][A-Za-z0-9]+)*(?![\w@/])', text))
    selected = [(word, count) for word, count in counts.items()
                if count >= args.min_count and word not in known and 2 <= len(word) <= 48]
    selected.sort(key=lambda pair: (-pair[1], pair[0]))
    selected = selected[:args.limit]
    zh = [(w, c) for w, c in selected if re.fullmatch('[\u3400-\u9fff]+', w)]
    en = [(w, c) for w, c in selected if w.isascii()]
    print(f'files={files} distinct={len(counts)} missing_chinese={len(zh)} missing_english={len(en)}')
    if not args.apply:
        return
    changes = {}
    for name, imported, rows, english in [('roarkt_personal', 'roarkt_zh', zh, False),
                                          ('roarkt_personal_en', 'roarkt_en', en, True)]:
        body = HEADER + f'---\nname: {name}\nversion: "1"\nsort: by_weight\nuse_preset_vocabulary: false\nimport_tables:\n  - {imported}\n...\n'
        for word, count in rows:
            body += f'{word}\t{word.lower() if english else ""}\t{min(count, 100)}\n'
        changes[name + '.dict.yaml'] = body.encode()
    changes['roarkt_personal_en.schema.yaml'] = (HEADER + '''schema:
  schema_id: roarkt_personal_en
  name: Personal English Dictionary
  version: "1"
engine:
  translators:
    - table_translator
speller:
  alphabet: zyxwvutsrqponmlkjihgfedcba
  delimiter: " '"
translator:
  dictionary: roarkt_personal_en
''').encode()
    with locked(target):
        for name in NAMES[:2] + NAMES[4:]:
            p = plain(target / name)
            require(not p.exists() or p.read_text().startswith(HEADER), 'personal dictionary is user-owned')
        for name in NAMES[2:4]:
            p = plain(target / name)
            changes[name] = patch(p.read_text() if p.exists() else '').encode()
        token = publish(target, changes, 'personal')
    print('unchanged' if token is None else f'applied backup_id={token}; redeploy manually')

if __name__ == '__main__':
    try:
        main()
    except Refusal as error:
        print('refused: ' + str(error), file=sys.stderr); sys.exit(2)
    except Exception:
        print('failed: dependency, input format or filesystem error; no content logged', file=sys.stderr); sys.exit(1)
