"""Filters for synthetic or in-memory candidate counts; no content logging."""
import re
from collections import Counter

HAN = re.compile(r'[\u3400-\u9fff]{2,16}')
NUMERALS = '〇零一二三四五六七八九十百千万两'
MEASURES = ('个', '位', '名', '人', '件', '条', '项', '次', '回', '遍', '趟', '场', '局',
            '届', '期', '章', '节', '篇', '页', '行', '段', '句', '字', '词', '首', '本',
            '册', '卷', '部', '集', '季', '年', '个月', '月', '周', '星期', '天', '日',
            '小时', '分钟', '秒', '毫秒', '微秒', '岁', '元', '角', '分', '块', '米',
            '厘米', '毫米', '公里', '千米', '斤', '公斤', '克', '吨', '升', '毫升',
            '倍', '成', '份', '套', '台', '种', '类', '组', '级', '层', '步', '笔',
            '张', '只', '支', '双', '对', '颗', '口', '家', '所', '座', '间', '批', '轮')
NUMBER = re.compile(r'(?:第|约|近|上)?[' + NUMERALS + r']+(?:多|余|来)?(?:'
                    + '|'.join(sorted(MEASURES, key=len, reverse=True)) + r')*')


def composable(word, known):
    """At least two known >=2-character words, or such words plus one edge Han."""
    def parts(text):
        reached = {0}
        for end in range(2, len(text) + 1):
            if any(start in reached and text[start:end] in known
                   for start in range(end - 1)):
                reached.add(end)
        return len(text) in reached

    # Callers only pass words absent from known, so a whole-word match is not
    # possible. Single characters are allowed only at one outer edge.
    return parts(word) or (len(word) >= 3 and (parts(word[1:]) or parts(word[:-1])))


def chinese_candidates(counts, contexts, known, minimum):
    candidates = {word for word, count in counts.items()
                  if count >= minimum and HAN.fullmatch(word) and word not in known
                  and not NUMBER.fullmatch(word) and not composable(word, known)}
    embedded = {word: Counter() for word in candidates}
    for (word, left, right), count in contexts.items():
        if word not in candidates:
            continue
        parents = set()
        for before in range(min(len(left), 16 - len(word)) + 1):
            for after in range(min(len(right), 16 - len(word) - before) + 1):
                if before + after == 0:
                    continue
                parent = (left[-before:] if before else '') + word + right[:after]
                # A known full word can also explain a tokenizer fragment, even
                # when it is not itself emitted as a candidate on this occurrence.
                if parent in known or parent in counts:
                    parents.add(parent)
        for parent in parents:
            embedded[word][parent] += count
    return {word: counts[word] for word in candidates
            if not any(5 * count >= 4 * counts[word] for count in embedded[word].values())}
