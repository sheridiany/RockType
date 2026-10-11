"""Conservative English prose extraction; never split identifiers into words."""
import re
from collections import Counter, defaultdict

# Mixed-case brands are indistinguishable from identifiers by spelling alone.
# Keep this explicit list small; ordinary title-case names and acronyms need none.
BRANDS = frozenset('Herdr Magpie RockType OpenAI GitHub GitLab SwiftUI TypeScript JavaScript '
                   'macOS iOS PyTorch YouTube HuggingFace DeepSeek ChatGPT'.split())
CODE_WORDS = frozenset('''
    as associatedtype async await break case catch class const continue convenience
    defer deinit didset do dynamic else enum eval export extension extern fallthrough
    false fileprivate final finally for foreach from func function get guard if
    implements import in init inout interface internal is keyof lazy let malloc
    mutating namespace new nil nonisolated nonmutating null nullptr open operator
    override package private fileprivate protocol public readonly rethrows return
    self set sizeof some static struct subscript super switch synchronized then
    this throw throws true try typealias typeof undefined unowned var void weak
    where while willset yield
    abs all any append args argv array assert bool boolean byte bytes char chr
    close compactmap contains count decode dict double dropfirst droplast encode
    enumerate equals exit filter first flatmap float flush format hasnext hash
    insert int integer isalpha isdigit isempty isinstance iterator join keys last
    len length list log lower lstrip main map max min next object ord pop pow
    prefix print println push range read readline remove removeall replace repr require
    reversed round rstrip send setdefault slice sort sorted split startswith str
    string strip substring suffix sum tostring trim tuple type uint utf uuid
    values write zip
'''.split())


def markdown_prose(text):
    """Drop Markdown code/destinations, including unclosed fenced blocks.

    This is a conservative scanner, not a Markdown renderer: indented/list
    continuations and raw HTML may be omitted even when a renderer shows prose.
    """
    text = re.sub(r'\A---[ \t]*\n.*?(?:\n(?:---|\.\.\.)[ \t]*(?:\n|\Z)|\Z)', ' ', text, flags=re.S)
    text = re.sub(r'<!--.*?(?:-->|\Z)', ' ', text, flags=re.S)
    text = re.sub(r'<(pre|code|script|style)\b[^>]*>.*?(?:</\1\s*>|\Z)',
                  ' ', text, flags=re.S | re.I)
    lines, fence = [], None
    for line in text.splitlines():
        # Blockquote prefixes do not turn fenced/indented code into prose.
        line = re.sub(r'^(?: {0,3}> ?)+', '', line)
        if fence:
            if re.fullmatch(r' {0,3}' + re.escape(fence[0]) + '{' + str(fence[1]) + r',}\s*', line):
                fence = None
            continue
        opening = re.match(r'^\s*(?:[-+*] |\d+[.)] )?(`{3,}|~{3,})', line)
        if opening:
            run = opening.group(1)
            fence = (run[0], len(run))
            continue
        if line.startswith(('    ', '\t')) or re.match(r'^ {0,3}\[[^\]]+\]:', line):
            continue
        lines.append(line)
    text = '\n'.join(lines)
    # Match equal-length backtick delimiters; preserve no text inside code spans.
    text = re.sub(r'(?<!`)(`+)(?!`)[\s\S]*?(?<!`)\1(?!`)', ' ', text)
    text = re.sub(r'!\[[^\]]*\](?:\([^\n]*?\)|\[[^\]]*\])?', ' ', text)
    text = re.sub(r'\[([^\]]+)\]\([^\n]*?\)', r'\1 ', text)
    text = re.sub(r'\[([^\]]+)\]\[[^\]]*\]', r'\1 ', text)
    text = re.sub(r'<[^>]*>', ' ', text)
    # Remove a whole URL, email or path, not just its punctuation.
    text = re.sub(r'(?:[A-Za-z][A-Za-z0-9+.-]*://|www\.|mailto:)[^\s<>]+', ' ', text)
    text = re.sub(r'[^\s<>]*[/\\@][^\s<>]*', ' ', text)
    return text


def english_occurrences(text):
    prose = markdown_prose(text)
    boundary = 0
    for match in re.finditer(r"[A-Za-z0-9_./\\@:+#%?=&~'-]+", prose):
        token = match.group()
        word = token.rstrip('.')
        if not re.fullmatch(r'[A-Za-z]{2,48}', word):
            continue
        if word in BRANDS or (re.fullmatch(r'[A-Z]{2,}|[A-Z][a-z]+|[a-z]+', word)
                              and word not in CODE_WORDS):
            gap = prose[boundary:match.start()]
            sentence_start = boundary == 0 or bool(re.search(r'[.!?。！？\n]', gap))
            boundary = match.end() - (len(token) - len(word))
            yield word, sentence_start


class EnglishCounts:
    def __init__(self):
        self.totals = Counter()
        self.spellings = defaultdict(Counter)

    def add(self, word, sentence_start):
        key = word.casefold()
        self.totals[key] += 1
        # Sentence-initial title case contributes frequency, but not evidence
        # that a word is a proper name. Explicit brands/acronyms retain votes.
        if not sentence_start or not word.istitle() or word in BRANDS:
            self.spellings[key][word] += 1

    def merged(self):
        result = {}
        for key, count in self.totals.items():
            votes = self.spellings[key]
            spelling = min(votes, key=lambda word: (-votes[word], word != key, word)) if votes else key
            result[spelling] = count
        return result
