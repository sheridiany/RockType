"""Synthetic fixtures only. Invoked by the SPM test target and scripts/test.sh."""
import fcntl
from collections import Counter
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / 'scripts/personal'
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('personal', SCRIPTS / 'build-personal-dict.py')
personal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(personal)
from personal_common import Refusal, digest
from candidate_quality import NUMBER, chinese_candidates
from english_prose import EnglishCounts, english_occurrences


def invoke(script, args, env=None):
    return subprocess.run([sys.executable, '-B', str(SCRIPTS / script), *map(str, args)],
                          capture_output=True, text=True, env=env)


def command(args, cwd):
    result = subprocess.run(list(map(str, args)), cwd=cwd, capture_output=True, text=True)
    if result.returncode:
        raise AssertionError('synthetic tool failed: ' + result.stderr[-1500:])
    return result.stdout


class PersonalTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='roarkt-personal-test-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.target = self.base / 'rime'; self.target.mkdir()
        self.source = self.base / 'source'; self.source.mkdir()
        self.dicts = self.base / 'dicts'; self.dicts.mkdir()
        (self.dicts / 'roarkt_zh.dict.yaml').write_text('---\nname: roarkt_zh\nversion: "1"\n...\n火\thuo\t100\n星\txing\t100\n')
        (self.dicts / 'roarkt_en.dict.yaml').write_text('---\nname: roarkt_en\nversion: "1"\n...\nKnownword\tknownword\t100\n')
        (self.source / 'note.md').write_text(('火星 Herdr Knownword\n') * 4)
        (self.source / 'code.swift').write_text('let Codeonlyword = 1\n// Magpie Magpie Magpie\nlet x = "Oriole Oriole Oriole"\n')
        for folder in ['.git', '.build', 'node_modules']:
            (self.source / folder).mkdir()
            (self.source / folder / 'private.md').write_text('Hiddenbird ' * 5)
        (self.base / 'outside.md').write_text('Linkbird ' * 5)
        (self.source / 'link.md').symlink_to(self.base / 'outside.md')
        self.args = ['--rime-dir', self.target, '--source', self.source, '--dictionary-dir', self.dicts]

    def test_directory_selection(self):
        home = self.base / 'home'; home.mkdir()
        default = home / 'Library/Application Support/RoarkT/Rime'
        default.mkdir(parents=True)
        legacy = home / 'Library/Rime'; legacy.mkdir()
        (legacy / 'sentinel').write_text('untouched')
        legacy_before = digest(legacy)
        override = self.base / 'environment profile'; override.mkdir()
        env = {**os.environ, 'HOME': str(home), 'ROARKT_RIME_USER_DIR': ''}
        for mode, target in [('default', default), ('environment', override), ('argument', self.target)]:
            with self.subTest(mode=mode):
                if mode == 'default':
                    env.pop('ROARKT_RIME_USER_DIR', None)
                else:
                    env['ROARKT_RIME_USER_DIR'] = str(override)
                args = self.args[2:] + ['--apply', '--offline']
                if mode == 'argument':
                    args += ['--rime-dir', target]
                before = {p: digest(p) for p in [default, override, self.target] if p != target}
                result = invoke('build-personal-dict.py', args, env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue((target / 'roarkt_personal.patch.yaml').is_file())
                self.assertEqual(before, {p: digest(p) for p in before})
                token = result.stdout.split('backup_id=')[1].split(';')[0]
                rollback = ['--rollback', token, '--apply', '--offline']
                if mode == 'argument':
                    rollback += ['--rime-dir', target]
                if mode == 'default':
                    env['ROARKT_RIME_USER_DIR'] = ''
                result = invoke('build-personal-dict.py', rollback, env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse((target / 'roarkt_personal.patch.yaml').exists())
        self.assertEqual(digest(legacy), legacy_before)

    def test_recursive_and_preset_vocabulary_normalized(self):
        (self.dicts / 'roarkt_zh.dict.yaml').write_text(
            '---\nname: roarkt_zh\nuse_preset_vocabulary: true\n'
            'import_tables: [luna_pinyin, roarkt_ai]\n...\n')
        (self.dicts / 'luna_pinyin.dict.yaml').write_text(
            '---\nname: luna_pinyin\nimport_tables: [nested]\n...\n數據\tshu ju\n')
        (self.dicts / 'nested.dict.yaml').write_text(
            '---\nname: nested\nimport_tables: [luna_pinyin]\n...\n應當\tying dang\n')
        (self.dicts / 'roarkt_ai.dict.yaml').write_text(
            '---\nname: roarkt_ai\nimport_tables: [nested]\n...\n軟件\truan jian\n')
        (self.dicts / 'essay.txt').write_text('公司\t100\n管理\t90\n')
        self.source.joinpath('code.swift').unlink()
        self.source.joinpath('note.md').write_text(('数据 數據 应当 公司 管理 软件 火星 Herdr\n') * 4)
        result = invoke('build-personal-dict.py', self.args + ['--apply', '--offline'])
        self.assertEqual(result.returncode, 0, result.stderr)
        generated = (self.target / 'roarkt_personal.dict.yaml').read_text()
        for word in ['数据', '數據', '应当', '公司', '管理', '软件']:
            self.assertNotIn(word, generated)
        self.assertIn('火星', generated)
        # A missing dependency must fail closed, never claim its words are missing.
        for name in ['nested.dict.yaml', 'essay.txt']:
            path = self.dicts / name
            contents = path.read_bytes()
            path.unlink()
            result = invoke('build-personal-dict.py', self.args)
            self.assertEqual(result.returncode, 2)
            self.assertEqual((self.target / 'roarkt_personal.dict.yaml').read_text(), generated)
            path.write_bytes(contents)

    def test_english_prose_only(self):
        markdown = """Herdr Magpie RockType MLX LLM Knownword KNOWNWORD knownword.
camelCase PascalCase URLSession snake_case name123 sha256 dotted.member file.swift
let var func return async await nil true false print append map flatmap sizeof malloc require
[Herdr](https://Urlbird.invalid/Pathbird) ![Imagebird](image.png)
https://Webbird.invalid/Routebird /Users/Pathbird ./Relativebird ~/Homebird foo/Barbird
`Inlinebird` ``Nestedbird ` Quotedbird``
```swift
Fencebird
```
~~~text
Tildebird
~~~
    Indentedbird
> ```swift
> Quotebird
> ```
[ref]: https://Refbird.invalid "Titlebird"
<!-- Hiddenbird -->
<code>Htmlbird</code>
"""
        self.source.joinpath('note.md').write_text('---\nauthor: Metabird Metabird Metabird\n---\n' + markdown * 4)
        self.source.joinpath('code.swift').write_text(
            '// Magpie MLX LLM RockType\n' * 4 +
            '/* Herdr /* Magpie */ LLM */\n' * 4 +
            '// `Commentcode` https://Commenturl.invalid CommentType key_value\n' * 4 +
            'let Oriole = "Stringbird Stringbird Stringbird // Fakecomment"\n' +
            'let raw = #"Rawbird Rawbird Rawbird"#\n')
        result = invoke('build-personal-dict.py', self.args + ['--apply', '--offline'])
        self.assertEqual(result.returncode, 0, result.stderr)
        generated = (self.target / 'roarkt_personal_en.dict.yaml').read_text().split('...\n', 1)[1]
        words = {line.split('\t')[0] for line in generated.splitlines()}
        self.assertEqual(words, {'Herdr', 'Magpie', 'RockType', 'MLX', 'LLM'})
        self.assertNotIn('Herdr', result.stdout + result.stderr)

    def test_english_case_merging_and_sentence_initials(self):
        english = EnglishCounts()
        prose = ('Matchers work. ' * 12 + 'the matchers work. ' * 3 +
                 'the Assertions work. ' * 4 + 'the assertions work. ' * 2 +
                 'Workflow works. ' * 8 + 'the workflow works. ' * 3 +
                 'the ehr works. ' * 2 + 'the EHR works. ' * 5 +
                 '# Novelties\n' * 4 + 'the Herdr works. ' * 3)
        for word, initial in english_occurrences(prose):
            english.add(word, initial)
        merged = english.merged()
        for word, count in [('matchers', 15), ('Assertions', 6), ('workflow', 11),
                            ('EHR', 7), ('novelties', 4), ('Herdr', 3)]:
            self.assertEqual(merged[word], count)
        self.assertEqual(len({word.casefold() for word in merged}), len(merged))
        self.assertNotIn('Matchers', merged)
        self.assertNotIn('Workflow', merged)

    def test_chinese_numbers_composition_and_context_threshold(self):
        numerals = ['第五十七', '百五十一', '一十四', '第一百零四', '第十二章',
                    '三百万人', '二十分钟', '两千多项', '上十']
        for word in numerals:
            self.assertIsNotNone(NUMBER.fullmatch(word))
        known = {'平台', '发行', '类型', '测试', '星', '澜', '英伟达', '超伟达'}
        counts = Counter(dict.fromkeys(numerals + ['和平台', '开发行', '类型化',
                         '平台类型测试', '星澜', '伟达'], 10))
        contexts = Counter({('伟达', '英', ''): 8, ('伟达', '', ''): 2})
        self.assertEqual(chinese_candidates(counts, contexts, known, 3), {'星澜': 10})
        # 70% containment leaves real standalone usage; exactly 80% removes it.
        contexts = Counter({('伟达', '英', ''): 7, ('伟达', '', ''): 3})
        self.assertIn('伟达', chinese_candidates(counts, contexts, known, 3))
        # Unrelated parents must not be summed into a fictitious 80% parent.
        contexts = Counter({('伟达', '英', ''): 4, ('伟达', '超', ''): 4, ('伟达', '', ''): 2})
        self.assertIn('伟达', chinese_candidates(counts, contexts, known, 3))
        # A longer new candidate, not only a known dictionary word, also counts.
        counts['星澜计划'] = 8
        contexts = Counter({('星澜', '', '计划'): 8, ('星澜', '', ''): 2})
        result = chinese_candidates(counts, contexts, known, 3)
        self.assertNotIn('星澜', result)
        self.assertIn('星澜计划', result)

    def test_quality_filters_in_generated_dictionaries(self):
        self.source.joinpath('note.md').write_text(
            ('第五十七 第十二章 第一百零四 和平台 类型化\n') * 4 +
            'Matchers work. ' * 8 + 'the matchers work. ' * 3 +
            'the EHR works. ' * 5 + 'the ehr works. ' * 3)
        self.source.joinpath('code.swift').unlink()
        with (self.dicts / 'roarkt_zh.dict.yaml').open('a') as stream:
            stream.write('平台\tping tai\n类型\tlei xing\n')
        result = invoke('build-personal-dict.py', self.args + ['--apply', '--offline'])
        self.assertEqual(result.returncode, 0, result.stderr)
        english = (self.target / 'roarkt_personal_en.dict.yaml').read_text().split('...\n')[1]
        rows = {fields[0]: int(fields[2]) for line in english.splitlines() if (fields := line.split('\t'))}
        self.assertEqual(rows['matchers'], 11)
        self.assertEqual(rows['EHR'], 8)
        self.assertNotIn('Matchers', rows)
        self.assertNotIn('ehr', rows)
        chinese = (self.target / 'roarkt_personal.dict.yaml').read_text().split('...\n')[1]
        for word in ['第五十七', '第十二章', '第一百零四', '和平台', '类型化']:
            self.assertNotIn(word, chinese)

    def test_source_lexer(self):
        text = personal.swift_text('let CodeToken = 0\n/* outer /* inner */ tail */\nlet a = #"raw word"#\nlet b = """multi\nline"""\nlet c = "skip \\(SecretCode)"')
        self.assertIn('inner', text)
        self.assertIn('raw word', text)
        self.assertIn('multi\nline', text)
        self.assertNotIn('CodeToken', text)
        self.assertNotIn('SecretCode', text)

    def test_authorization_and_symlink_rejected(self):
        result = invoke('build-personal-dict.py', ['--rime-dir', self.target])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(list(self.target.iterdir()), [])
        (self.base / 'target-link').symlink_to(self.target)
        result = invoke('build-personal-dict.py', ['--rime-dir', self.base / 'target-link'])
        self.assertEqual(result.returncode, 2)

    def test_build_idempotence_privacy_rollback_and_deploy(self):
        fixture = Path(os.environ['ROARKT_SETTINGS_FIXTURE'])
        customs = ['roarkt.custom.yaml', 'roarkt_flypy.custom.yaml']
        for name in customs:
            shutil.copy2(fixture / 'initial' / name, self.target / name)
        initial = {name: (self.target / name).read_bytes() for name in customs}
        result = invoke('build-personal-dict.py', self.args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(list(self.target.iterdir())), 2)
        result = invoke('build-personal-dict.py', self.args + ['--apply', '--offline'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('Herdr', result.stdout + result.stderr)
        token = result.stdout.split('backup_id=')[1].split(';')[0]
        english = (self.target / 'roarkt_personal_en.dict.yaml').read_text()
        for included in ['Herdr', 'Magpie']:
            self.assertIn(included, english)
        for excluded in ['Knownword\t', 'Codeonlyword', 'Hiddenbird', 'Linkbird', 'Oriole']:
            self.assertNotIn(excluded, english)
        self.assertIn('火星', (self.target / 'roarkt_personal.dict.yaml').read_text())
        before = {n: (self.target / n).read_bytes() for n in personal.NAMES}
        result = invoke('build-personal-dict.py', self.args + ['--apply', '--offline'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('unchanged', result.stdout)
        self.assertEqual(initial, {name: (self.target / name).read_bytes() for name in customs})
        self.assertEqual(before, {n: (self.target / n).read_bytes() for n in personal.NAMES})
        # Real deployment with minimal synthetic source tables and both factory schemas.
        bin_dir = self.base / 'bin'; bin_dir.mkdir()
        shutil.copy2(ROOT / 'InputMethod/bin/rime_deployer', bin_dir / 'rime_deployer')
        (self.base / 'Frameworks').symlink_to(ROOT / 'InputMethod/lib')
        shared = self.base / 'shared'; shared.mkdir()
        for name in ['default.yaml', 'key_bindings.yaml', 'punctuation.yaml', 'symbols.yaml', 'pinyin.yaml', 'essay.txt']:
            shutil.copy2(ROOT / 'InputMethod/data/plum' / name, shared / name)
        for path in (ROOT / 'Rime').glob('*.yaml'):
            shutil.copy2(path, shared / path.name)
        shutil.copytree(ROOT / 'Rime/lua', shared / 'lua')
        shutil.copytree(ROOT / 'InputMethod/data/opencc', shared / 'opencc')
        for path in self.dicts.iterdir():
            shutil.copy2(path, shared / path.name)
        build = self.base / 'build'; build.mkdir()
        command([bin_dir / 'rime_deployer', '--build', self.target, shared, build], self.base)
        for scheme in ['roarkt', 'roarkt_flypy']:
            import yaml
            deployed = yaml.safe_load((build / (scheme + '.schema.yaml')).read_text())
            self.assertEqual(deployed['translator']['dictionary'], 'roarkt_personal')
            self.assertEqual(deployed['translator']['user_dict'], 'roarkt_zh')
            self.assertEqual(deployed['english']['dictionary'], 'roarkt_personal_en')
            self.assertEqual(deployed['english']['user_dict'], 'roarkt_en')
        self.assertTrue((build / 'roarkt_personal.table.bin').is_file())
        self.assertTrue((build / 'roarkt_personal_en.table.bin').is_file())
        probe = self.base / 'probe'
        runtime = ROOT / 'InputMethod'
        command(['xcrun', 'swiftc', '-import-objc-header', ROOT / 'Tests/InputMethodTests/RimeBridge.h',
                 '-I', runtime / 'librime/src', ROOT / 'Tests/PersonalScriptsTests/CandidateProbe.swift',
                 runtime / 'lib/librime.1.dylib', runtime / 'lib/rime-plugins/librime-lua.dylib',
                 '-Xlinker', '-rpath', '-Xlinker', runtime / 'lib',
                 '-Xlinker', '-rpath', '-Xlinker', runtime / 'lib/rime-plugins', '-o', probe], self.base)
        for scheme, code in [('roarkt', 'huoxing'), ('roarkt_flypy', 'hoxk')]:
            command([probe, shared, self.target, build, scheme, code, '火星'], self.base)
            command([probe, shared, self.target, build, scheme, 'herdr', 'Herdr'], self.base)
        # Rewrite the settings-owned custom files with actual writer output.
        for name in customs:
            shutil.copy2(fixture / 'updated' / name, self.target / name)
        command([bin_dir / 'rime_deployer', '--build', self.target, shared, build], self.base)
        self.assertEqual(before, {n: (self.target / n).read_bytes() for n in personal.NAMES})
        for scheme, code in [('roarkt', 'huoxing'), ('roarkt_flypy', 'hoxk')]:
            deployed = yaml.safe_load((build / (scheme + '.schema.yaml')).read_text())
            self.assertFalse(deployed['english']['enable_completion'])
            self.assertEqual(deployed['ascii_composer']['switch_key']['Shift_L'], 'noop')
            command([probe, shared, self.target, build, scheme, code, '火星'], self.base)
            command([probe, shared, self.target, build, scheme, 'herdr', 'Herdr'], self.base)
        result = invoke('build-personal-dict.py', ['--rime-dir', self.target, '--rollback', token, '--apply', '--offline'])
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in customs:
            self.assertEqual((self.target / name).read_bytes(), (fixture / 'updated' / name).read_bytes())
        for name in personal.NAMES:
            self.assertFalse((self.target / name).exists())
        # Optional reference absent, including after removal from a previously built profile.
        command([bin_dir / 'rime_deployer', '--build', self.target, shared, build], self.base)
        for scheme in ['roarkt', 'roarkt_flypy']:
            deployed = yaml.safe_load((build / (scheme + '.schema.yaml')).read_text())
            self.assertEqual(deployed['translator']['dictionary'], 'roarkt_zh')
            self.assertEqual(deployed['english']['dictionary'], 'roarkt_en')

    def test_rollback_refuses_later_handwritten_change(self):
        result = invoke('build-personal-dict.py', self.args + ['--apply', '--offline'])
        self.assertEqual(result.returncode, 0, result.stderr)
        token = result.stdout.split('backup_id=')[1].split(';')[0]
        path = self.target / 'roarkt_personal.patch.yaml'
        changed = path.read_text() + '# later handwritten change\n'
        path.write_text(changed)
        result = invoke('build-personal-dict.py', ['--rime-dir', self.target, '--rollback', token, '--apply', '--offline'])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(path.read_text(), changed)
        self.assertTrue((self.target / 'roarkt_personal.dict.yaml').exists())

    def test_handwritten_customs_untouched_and_personal_conflict_refused(self):
        contents = {'roarkt.custom.yaml': 'patch: {menu/page_size: 5}\n',
                    'roarkt_flypy.custom.yaml': '# handwritten\npatch:\n  english/dictionary: handwritten\n'}
        for name, text in contents.items():
            (self.target / name).write_text(text)
        result = invoke('build-personal-dict.py', self.args + ['--apply', '--offline'])
        self.assertEqual(result.returncode, 0, result.stderr)
        for name, text in contents.items():
            self.assertEqual((self.target / name).read_text(), text)
        patch = self.target / 'roarkt_personal.patch.yaml'
        patch.write_text('# handwritten personal patch\npatch: {}\n')
        before = {name: (self.target / name).read_bytes() for name in personal.NAMES}
        result = invoke('build-personal-dict.py', self.args + ['--apply', '--offline'])
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(before, {name: (self.target / name).read_bytes() for name in personal.NAMES})


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='roarkt-migration-test-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.target = self.base / 'rime'; self.target.mkdir()
        self.bin = self.base / 'bin'; self.bin.mkdir()
        shutil.copy2(ROOT / 'InputMethod/bin/rime_dict_manager', self.bin / 'rime_dict_manager')
        (self.base / 'Frameworks').symlink_to(ROOT / 'InputMethod/lib')
        self.manager = self.bin / 'rime_dict_manager'
        self.args = ['--rime-dir', self.target, '--offline', '--manager', self.manager]
        self.seed = self.base / 'seed.txt'
        self.seed.write_text('發現\tfa xian\t7\n发现\tfa xian\t3\n頭髮\ttou fa\t5\n')
        command([self.manager, '-i', 'roarkt_zh', self.seed], self.target)
        (self.target / 'settings.yaml').write_text('synthetic: true\n')

    def test_directory_selection(self):
        home = self.base / 'home'; home.mkdir()
        default = home / 'Library/Application Support/RoarkT/Rime'
        default.mkdir(parents=True)
        legacy = home / 'Library/Rime'; legacy.mkdir()
        (legacy / 'sentinel').write_text('untouched')
        legacy_before = digest(legacy)
        override = self.base / 'environment profile'; override.mkdir()
        for target in [default, override]:
            shutil.copytree(self.target / 'roarkt_zh.userdb', target / 'roarkt_zh.userdb')
        env = {**os.environ, 'HOME': str(home)}
        for mode, target in [('default', default), ('environment', override), ('argument', self.target)]:
            with self.subTest(mode=mode):
                if mode == 'default':
                    env.pop('ROARKT_RIME_USER_DIR', None)
                else:
                    env['ROARKT_RIME_USER_DIR'] = str(override)
                args = self.args[2:]
                if mode == 'argument':
                    args += ['--rime-dir', target]
                before = {p: digest(p) for p in [default, override, self.target] if p != target}
                database_before = digest(target / 'roarkt_zh.userdb')
                result = invoke('migrate_userdb.py', args, env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('changed=2', result.stdout)
                self.assertEqual(before, {p: digest(p) for p in before})
                token = result.stdout.split('backup_id=')[1].strip()
                rollback = ['--offline', '--rollback', token]
                if mode == 'argument':
                    rollback += ['--rime-dir', target]
                if mode == 'default':
                    env['ROARKT_RIME_USER_DIR'] = ''
                result = invoke('migrate_userdb.py', rollback, env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(digest(target / 'roarkt_zh.userdb'), database_before)
        self.assertEqual(digest(legacy), legacy_before)

    def test_real_conversion_collision_repeat_and_rollback(self):
        before = digest(self.target / 'roarkt_zh.userdb')
        result = invoke('migrate_userdb.py', self.args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('entries=3 changed=2 collisions=1 output=2', result.stdout)
        self.assertNotIn('發現', result.stdout + result.stderr)
        token = result.stdout.split('backup_id=')[1].strip()
        # Inspect a copy, as even an export can rotate LevelDB logs.
        check = self.base / 'check'; check.mkdir()
        shutil.copytree(self.target / 'roarkt_zh.userdb', check / 'roarkt_zh.userdb')
        export = check / 'export.txt'
        command([self.manager, '-e', 'roarkt_zh', export], check)
        rows = [line for line in export.read_text().splitlines() if line and not line.startswith('#')]
        self.assertEqual(set(rows), {'发现\tfa xian\t10', '头发\ttou fa\t5'})
        second = invoke('migrate_userdb.py', self.args)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn('unchanged entries=2', second.stdout)
        result = invoke('migrate_userdb.py', ['--rime-dir', self.target, '--offline', '--rollback', token])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(digest(self.target / 'roarkt_zh.userdb'), before)
        self.assertEqual((self.target / 'roarkt-backups' / token / 'original/settings.yaml').read_text(), 'synthetic: true\n')

    def test_rollback_refuses_new_learning(self):
        result = invoke('migrate_userdb.py', self.args)
        self.assertEqual(result.returncode, 0, result.stderr)
        token = result.stdout.split('backup_id=')[1].strip()
        self.seed.write_text('新词\txin ci\t9\n')
        command([self.manager, '-i', 'roarkt_zh', self.seed], self.target)
        before = digest(self.target / 'roarkt_zh.userdb')
        result = invoke('migrate_userdb.py', ['--rime-dir', self.target, '--offline', '--rollback', token])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(digest(self.target / 'roarkt_zh.userdb'), before)

    def test_converter_failure_leaves_database(self):
        # Fail the system compiler invocation without adding a production override.
        before = digest(self.target / 'roarkt_zh.userdb')
        shim = self.base / 'failure-bin'; shim.mkdir()
        (shim / 'xcrun').write_text('#!/bin/sh\nexit 1\n')
        (shim / 'xcrun').chmod(0o700)
        env = {**os.environ, 'PATH': str(shim) + ':' + os.environ['PATH']}
        result = invoke('migrate_userdb.py', self.args, env)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(digest(self.target / 'roarkt_zh.userdb'), before)
        self.assertEqual(len(list((self.target / 'roarkt-backups').iterdir())), 1)

    def test_live_database_and_profile_symlink_refused(self):
        with (self.target / 'roarkt_zh.userdb/LOCK').open('r+') as lock:
            fcntl.lockf(lock, fcntl.LOCK_EX)
            result = invoke('migrate_userdb.py', self.args)
            self.assertEqual(result.returncode, 2)
            self.assertIn('database is in use', result.stderr)
        before = digest(self.target / 'roarkt_zh.userdb')
        (self.target / 'linked').symlink_to(self.seed)
        result = invoke('migrate_userdb.py', self.args)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(digest(self.target / 'roarkt_zh.userdb'), before)


if __name__ == '__main__':
    unittest.main(verbosity=2)
