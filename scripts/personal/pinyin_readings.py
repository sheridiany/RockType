"""Resolve explicit pinyin from dictionary source data, never guess readings."""
from pathlib import Path
import re
import yaml
from personal_common import plain, require


def encode_words(root, words, to_traditional):
    root = plain(root)
    tables = []
    seen = set()

    def resource(name, suffix):
        require(isinstance(name, str) and re.fullmatch(r'[A-Za-z0-9_/.-]+', name)
                and '..' not in name and not name.startswith('/'), 'invalid reading resource')
        path = plain(root / (name + suffix))
        require(path.is_relative_to(root) and path.is_file(), 'reading resource missing')
        return path

    def visit(name):
        if name in seen:
            return
        seen.add(name)
        parts = re.split(r'^\.\.\.\s*$', resource(name, '.dict.yaml').read_text(), maxsplit=1, flags=re.M)
        require(len(parts) == 2, 'reading dictionary header missing')
        meta = yaml.safe_load(parts[0])
        require(isinstance(meta, dict), 'invalid reading header')
        tables.append((meta, parts[1]))
        for imported in meta.get('import_tables', []):
            visit(imported)

    visit('roarkt_zh')
    preset = {}
    top = tables[0][0]
    if top.get('use_preset_vocabulary') or top.get('vocabulary'):
        for line in resource(top.get('vocabulary') or 'essay', '.txt').read_text().splitlines():
            if not line or line.startswith('#'):
                continue
            fields = line.split('\t')
            preset[fields[0]] = float(fields[1]) if len(fields) > 1 else 0
    readings = {}
    for meta, body in tables:
        columns = meta.get('columns', ['text', 'code', 'weight'])
        require(isinstance(columns, list) and 'text' in columns and 'code' in columns, 'reading columns unsupported')
        def field(fields, name):
            index = columns.index(name) if name in columns else len(fields)
            return fields[index].strip() if index < len(fields) else ''
        for line in body.splitlines():
            if not line or line.startswith('#'):
                continue
            fields = line.split('\t')
            word, code, weight = (field(fields, name) for name in ['text', 'code', 'weight'])
            code = ' '.join(code.split())
            if not re.fullmatch(r'[\u3400-\u9fff]+', word) or not re.fullmatch(r'[a-z]+(?: [a-z]+)*', code):
                continue
            if len(code.split()) != len(word):
                continue
            if not weight or weight.endswith('%'):
                frequency = preset.get(word, 0) * (float(weight[:-1]) / 100 if weight else 1)
            else:
                frequency = float(weight)
            previous = readings.get(word)
            if previous is None or frequency > previous[0] or (frequency == previous[0] and code < previous[1]):
                readings[word] = (frequency, code)
    words = list(words)
    chars = sorted({char for word in words for char in word})
    originals = words + chars
    converted = to_traditional(originals)
    require(len(converted) == len(originals), 'reading conversion mismatch')
    traditional = dict(zip(originals, converted))

    def reading(word):
        return readings.get(word) or readings.get(traditional[word])

    result = {}
    for word in words:
        phrase = reading(word)
        if phrase:
            result[word] = phrase[1]
            continue
        syllables = [reading(char) for char in word]
        if all(item is not None and len(item[1].split()) == 1 for item in syllables):
            result[word] = ' '.join(item[1] for item in syllables)
    return result
