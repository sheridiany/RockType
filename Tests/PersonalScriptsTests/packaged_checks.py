"""Real build.sh bundle deployment; all profiles and source text are temporary."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PackagedPersonalTests(unittest.TestCase):
    def test_packaged_dictionaries_survive_personal_translators(self):
        bundle = (ROOT / 'dist/RockType Input.app/Contents').resolve()
        shared = bundle / 'SharedSupport'
        deployer = bundle / 'MacOS/rime_deployer'
        self.assertTrue(deployer.is_file(), 'Run scripts/build.sh before the packaged deployment test')
        fixture = Path(os.environ['ROARKT_SETTINGS_FIXTURE'])
        with tempfile.TemporaryDirectory(prefix='roarkt-personal-packaged-') as tmp:
            base = Path(tmp).resolve()
            plain = base / 'plain'; plain.mkdir()
            personal = base / 'personal'; personal.mkdir()
            source = base / 'source'; source.mkdir()
            english_only = base / 'english-only'; english_only.mkdir()
            empty = base / 'empty'; empty.mkdir()
            (source / 'synthetic.md').write_text(('批复 咨询 根因 Herdr\n') * 4)
            for profile in [plain, personal, english_only, empty]:
                for name in ['roarkt.custom.yaml', 'roarkt_flypy.custom.yaml']:
                    shutil.copy2(fixture / 'initial' / name, profile / name)
            def command(args):
                result = subprocess.run(list(map(str, args)), capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr[-1500:])
                return result
            command([sys.executable, '-B', ROOT / 'scripts/personal/build-personal-dict.py',
                     '--rime-dir', personal, '--source', source, '--dictionary-dir', shared,
                     '--apply', '--offline'])
            for profile, text in [(english_only, 'Herdr Herdr Herdr'), (empty, '')]:
                (source / 'synthetic.md').write_text(text)
                command([sys.executable, '-B', ROOT / 'scripts/personal/build-personal-dict.py',
                         '--rime-dir', profile, '--source', source, '--dictionary-dir', shared,
                         '--apply', '--offline'])
            tables = []
            for profile in [plain, personal, english_only, empty]:
                build = profile / 'build'; build.mkdir()
                result = command([deployer, '--build', profile, shared, build])
                self.assertNotIn('Encode failure', result.stdout + result.stderr)
                tables.append(build)
            for name in ['roarkt_zh.table.bin', 'roarkt_en.table.bin']:
                for build in tables[1:]:
                    self.assertEqual((tables[0] / name).stat().st_size, (build / name).stat().st_size)
                    self.assertEqual((tables[0] / name).read_bytes(), (build / name).read_bytes())
                print(f'Packaged table unchanged: {name} bytes={(tables[0] / name).stat().st_size}')
            import yaml
            for scheme in ['roarkt', 'roarkt_flypy']:
                original = yaml.safe_load((tables[0] / (scheme + '.schema.yaml')).read_text())
                patched = yaml.safe_load((tables[1] / (scheme + '.schema.yaml')).read_text())
                for section in ['translator', 'english']:
                    self.assertEqual(patched[section], original[section])
                self.assertEqual(patched['engine']['translators'][:len(original['engine']['translators'])],
                                 original['engine']['translators'])
            self.assertFalse((tables[2] / 'roarkt_personal.table.bin').exists())
            self.assertTrue((tables[2] / 'roarkt_personal_en.table.bin').exists())
            self.assertFalse((tables[3] / 'roarkt_personal.table.bin').exists())
            self.assertFalse((tables[3] / 'roarkt_personal_en.table.bin').exists())
            runtime = ROOT / 'InputMethod'
            probe = base / 'probe'
            command(['xcrun', 'swiftc', '-import-objc-header', ROOT / 'Tests/InputMethodTests/RimeBridge.h',
                     '-I', runtime / 'librime/src', ROOT / 'Tests/PersonalScriptsTests/CandidateProbe.swift',
                     bundle / 'Frameworks/librime.1.dylib', bundle / 'Frameworks/rime-plugins/librime-lua.dylib',
                     '-Xlinker', '-rpath', '-Xlinker', bundle / 'Frameworks',
                     '-Xlinker', '-rpath', '-Xlinker', bundle / 'Frameworks/rime-plugins', '-o', probe])
            for scheme, codes in [('roarkt', ['shuju', 'yonghu', 'gongsi']),
                                  ('roarkt_flypy', ['uuju', 'yshu', 'gssi'])]:
                for code in codes:
                    before = command([probe, shared, plain, tables[0], scheme, code, '--first']).stdout
                    after = command([probe, shared, personal, tables[1], scheme, code, '--first']).stdout
                    self.assertEqual(after, before)
            body = (personal / 'roarkt_personal.dict.yaml').read_text().split('...\n')[1]
            rows = [line.split('\t') for line in body.splitlines() if line]
            self.assertTrue(rows, 'Synthetic Chinese terms must be generated')
            for word, code, weight in rows:
                self.assertTrue(code, 'Every Chinese row needs an explicit reading')
                command([probe, shared, personal, tables[1], 'roarkt', code.replace(' ', ''), word])
                flypy = {'批复': 'pifu', '咨询': 'zixy', '根因': 'gfyb'}[word]
                command([probe, shared, personal, tables[1], 'roarkt_flypy', flypy, word])
            for scheme in ['roarkt', 'roarkt_flypy']:
                command([probe, shared, personal, tables[1], scheme, 'herdr', 'Herdr'])
            print('Packaged personal deployment passed: main tables and first candidates unchanged; explicit personal terms found.')
