"""Synthetic fixtures only. Invoked by the SPM test target and scripts/test.sh."""
import fcntl
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


def invoke(script, args):
    return subprocess.run([sys.executable, '-B', str(SCRIPTS / script), *map(str, args)],
                          capture_output=True, text=True)


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
        (self.dicts / 'roarkt_en.dict.yaml').write_text('---\nname: roarkt_en\nversion: "1"\n...\nKnownWord\tknownword\t100\n')
        (self.source / 'note.md').write_text(('火星 QuasarToken KnownWord\n') * 4)
        (self.source / 'code.swift').write_text('let CodeOnlyToken = 1\n// CommentToken CommentToken CommentToken\nlet x = "StringToken StringToken StringToken"\n')
        for folder in ['.git', '.build', 'node_modules']:
            (self.source / folder).mkdir()
            (self.source / folder / 'private.md').write_text('ExcludedToken ' * 5)
        (self.base / 'outside.md').write_text('SymlinkToken ' * 5)
        (self.source / 'link.md').symlink_to(self.base / 'outside.md')
        self.args = ['--rime-dir', self.target, '--source', self.source, '--dictionary-dir', self.dicts]

    def test_source_lexer(self):
        text = personal.swift_text('let CodeToken = 0\n/* outer /* inner */ tail */\nlet a = #"raw word"#\nlet b = """multi\nline"""\nlet c = "skip \\(SecretCode)"')
        self.assertIn('inner', text)
        self.assertIn('raw word', text)
        self.assertIn('multi\nline', text)
        self.assertNotIn('CodeToken', text)
        self.assertNotIn('SecretCode', text)

    def test_patch_preserves_handwritten_and_settings(self):
        text = '# 由 RockType 生成；请通过 RockType 设置修改。\npatch:\n  "english/enable_completion": false # keep\n  "translator/enable_correction": true\n  "menu/page_size": 5\nother: yes\n'
        result = personal.patch(text)
        self.assertIn('false # keep', result)
        self.assertIn('other: yes', result)
        self.assertEqual(personal.patch(result), result)
        loaded, _ = personal.parse_yaml(result)
        self.assertEqual(loaded['patch']['translator/user_dict'], 'roarkt_zh')
        self.assertFalse(loaded['patch']['english/enable_completion'])

    def test_patch_conflicts(self):
        for text in ['patch: {x: 1}\n', 'patch:\n  translator/dictionary: custom\n',
                     'patch:\n  x: 1\n  x: 2\n', 'patch: &p\n  x: 1\nother: *p\n']:
            with self.assertRaises(Refusal):
                personal.patch(text)

    def test_authorization_and_symlink_rejected(self):
        result = invoke('build-personal-dict.py', ['--rime-dir', self.target])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(list(self.target.iterdir()), [])
        (self.base / 'target-link').symlink_to(self.target)
        result = invoke('build-personal-dict.py', ['--rime-dir', self.base / 'target-link'])
        self.assertEqual(result.returncode, 2)

    def test_build_idempotence_privacy_rollback_and_deploy(self):
        custom = '# handwritten\npatch:\n  "menu/page_size": 5 # retained\n'
        (self.target / 'roarkt.custom.yaml').write_text(custom)
        result = invoke('build-personal-dict.py', self.args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(list(self.target.iterdir())), 1)
        result = invoke('build-personal-dict.py', self.args + ['--apply', '--offline'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('QuasarToken', result.stdout + result.stderr)
        token = result.stdout.split('backup_id=')[1].split(';')[0]
        english = (self.target / 'roarkt_personal_en.dict.yaml').read_text()
        for included in ['QuasarToken', 'CommentToken', 'StringToken']:
            self.assertIn(included, english)
        for excluded in ['KnownWord\t', 'CodeOnlyToken', 'ExcludedToken', 'SymlinkToken']:
            self.assertNotIn(excluded, english)
        self.assertIn('火星', (self.target / 'roarkt_personal.dict.yaml').read_text())
        before = {n: (self.target / n).read_bytes() for n in personal.NAMES}
        result = invoke('build-personal-dict.py', self.args + ['--apply', '--offline'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('unchanged', result.stdout)
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
            command([probe, shared, self.target, build, scheme, 'quasartoken', 'QuasarToken'], self.base)
        result = invoke('build-personal-dict.py', ['--rime-dir', self.target, '--rollback', token, '--apply', '--offline'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.target / 'roarkt.custom.yaml').read_text(), custom)
        for name in personal.NAMES:
            if name != 'roarkt.custom.yaml':
                self.assertFalse((self.target / name).exists())

    def test_rollback_refuses_later_handwritten_change(self):
        result = invoke('build-personal-dict.py', self.args + ['--apply', '--offline'])
        self.assertEqual(result.returncode, 0, result.stderr)
        token = result.stdout.split('backup_id=')[1].split(';')[0]
        path = self.target / 'roarkt.custom.yaml'
        changed = path.read_text() + '# later handwritten change\n'
        path.write_text(changed)
        result = invoke('build-personal-dict.py', ['--rime-dir', self.target, '--rollback', token, '--apply', '--offline'])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(path.read_text(), changed)
        self.assertTrue((self.target / 'roarkt_personal.dict.yaml').exists())

    def test_conflict_preflight_leaves_both_files(self):
        a = 'patch:\n  menu/page_size: 5\n'
        b = 'patch:\n  english/dictionary: handwritten\n'
        (self.target / 'roarkt.custom.yaml').write_text(a)
        (self.target / 'roarkt_flypy.custom.yaml').write_text(b)
        result = invoke('build-personal-dict.py', self.args + ['--apply', '--offline'])
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual((self.target / 'roarkt.custom.yaml').read_text(), a)
        self.assertEqual((self.target / 'roarkt_flypy.custom.yaml').read_text(), b)
        self.assertFalse((self.target / 'roarkt_personal.dict.yaml').exists())


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
        self.opencc = Path(os.environ.get('ROARKT_TEST_OPENCC', ROOT / '.build/vendor/OpenCC/build/src/tools/opencc'))
        self.config = self.base / 'opencc'; self.config.mkdir()
        source = ROOT / '.build/vendor/OpenCC'
        if not self.opencc.is_file():
            self.fail('Real OpenCC required; follow scripts/personal/README.md test setup')
        config_source = Path(os.environ.get('ROARKT_TEST_T2S', source / 'data/config/t2s.json'))
        data_source = Path(os.environ.get('ROARKT_TEST_OPENCC_DATA', source / 'build/data'))
        shutil.copy2(config_source, self.config / 't2s.json')
        for path in data_source.glob('*.ocd2'):
            shutil.copy2(path, self.config / path.name)
        self.args = ['--rime-dir', self.target, '--offline', '--manager', self.manager,
                     '--opencc', self.opencc, '--t2s-config', self.config / 't2s.json']
        self.seed = self.base / 'seed.txt'
        self.seed.write_text('發現\tfa xian\t7\n发现\tfa xian\t3\n頭髮\ttou fa\t5\n')
        command([self.manager, '-i', 'roarkt_zh', self.seed], self.target)
        (self.target / 'settings.yaml').write_text('synthetic: true\n')

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
        before = digest(self.target / 'roarkt_zh.userdb')
        args = self.args.copy(); args[args.index('--opencc') + 1] = '/usr/bin/false'
        result = invoke('migrate_userdb.py', args)
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
