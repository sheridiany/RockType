"""Synthetic reading tables; no user dictionaries or content."""
from pathlib import Path
import tempfile
import unittest
from pinyin_readings import encode_words
from personal_common import Refusal


class PinyinTests(unittest.TestCase):
    def test_recursive_readings_weights_and_traditional_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            (root / 'roarkt_zh.dict.yaml').write_text('---\nname: roarkt_zh\nuse_preset_vocabulary: true\nimport_tables: [luna_pinyin, roarkt_ai]\n...\n')
            (root / 'luna_pinyin.dict.yaml').write_text('---\nname: luna_pinyin\nimport_tables: [nested]\n...\n重\tzhong\t90%\n重\tchong\t10%\n復\tfu\t20\n核\the\t10\n星\txing\t10\n')
            (root / 'nested.dict.yaml').write_text('---\nname: nested\nimport_tables: [luna_pinyin]\n...\n重核\tchong he\t10\n重核\tzhong he\t5\n')
            (root / 'roarkt_ai.dict.yaml').write_text('---\nname: roarkt_ai\n...\n星核\txing he\t50\n')
            (root / 'essay.txt').write_text('重\t1000\n')
            transform = lambda words: [word.replace('复', '復') for word in words]
            result = encode_words(root, ['重复', '重核', '星核', '复星', '龘星'], transform)
            self.assertEqual(result, {'重复': 'zhong fu', '重核': 'chong he',
                                      '星核': 'xing he', '复星': 'fu xing'})
            # A simplified table works without requiring traditional spellings.
            with (root / 'roarkt_ai.dict.yaml').open('a') as stream:
                stream.write('复\tfu\t80\n')
            self.assertEqual(encode_words(root, ['复星'], lambda words: words), {'复星': 'fu xing'})
            (root / 'nested.dict.yaml').unlink()
            with self.assertRaises(Refusal):
                encode_words(root, ['星核'], transform)

    def test_explicit_column_order_and_invalid_readings(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            (root / 'roarkt_zh.dict.yaml').write_text('---\nname: roarkt_zh\ncolumns: [code, text, weight]\n...\nxing\t星\t10\nhe\t核\t10\nmissing-code!\t龘\t999\n')
            self.assertEqual(encode_words(root, ['星核', '龘星'], lambda words: words), {'星核': 'xing he'})
