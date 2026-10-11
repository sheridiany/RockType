"""Offline conversion of the current RockType dictionary, never legacy profiles."""
import argparse
from collections import defaultdict
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
from personal_common import build_simplifier, simplify_words, add_rime_directory_argument, Refusal, require, plain, safe_tree, run, locked, backup, digest, database_lock

DB = 'roarkt_zh.userdb'


def entries(path):
    result = {}
    for line in path.read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        fields = line.split('\t')
        require(len(fields) == 3 and fields[0] and fields[1], 'invalid userdb export')
        word, code, count = fields
        require(count.isdecimal() and int(count) <= 2147483647, 'invalid commit count')
        key = (word, code.strip())
        require(key not in result, 'duplicate export key')
        result[key] = int(count)
    return result


def manager(tool, directory, option, file):
    run([tool, option, 'roarkt_zh', file], cwd=directory)


def rollback(target, token):
    require(token not in ('.', '..') and Path(token).name == token, 'backup ID required')
    saved = plain(target / 'roarkt-backups' / token)
    manifest = json.loads((saved / 'manifest.json').read_text())
    require(manifest['kind'] == 'simplified', 'wrong backup type')
    require(digest(target / DB) == manifest['after'], 'database changed since migration; rollback refused')
    source = plain(saved / 'original' / DB)
    require(digest(source) == manifest['before'], 'backup integrity failure')
    with tempfile.TemporaryDirectory(prefix='.roarkt-restore-', dir=target) as work:
        work = Path(work)
        shutil.copytree(source, work / DB)
        os.rename(target / DB, work / 'replaced')
        try:
            os.rename(work / DB, target / DB)
        except BaseException:
            os.rename(work / 'replaced', target / DB)
            raise
    print('rollback complete')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_rime_directory_argument(parser)
    parser.add_argument('--offline', action='store_true', help='confirm input method and settings writer are stopped')
    parser.add_argument('--manager', help='absolute rime_dict_manager executable')
    parser.add_argument('--rollback', help='backup ID from successful migration')
    args = parser.parse_args()
    os.umask(0o077)
    require(args.offline, '--offline required; stop input method first')
    target = plain(args.rime_dir)
    with locked(target):
        database = plain(target / DB)
        require(database.is_dir(), 'current RockType database missing')
        safe_tree(database)
        # LevelDB uses POSIX record locks, not flock. Never export the live DB.
        lock_path = plain(database / 'LOCK')
        require(lock_path.is_file(), 'LevelDB LOCK missing')
        with database_lock(lock_path):
            if args.rollback:
                rollback(target, args.rollback); return
            require(args.manager, 'manager required')
            tool = plain(args.manager)
            require(tool.is_file(), 'invalid manager')
            before = digest(database)
            saved = backup(target, 'simplified')
            original = saved / 'original'
            original.mkdir()
            # Profile data snapshot; root logs are disposable runtime output.
            for item in target.iterdir():
                if item.name in ('roarkt-backups', '.roarkt-personal.lock'):
                    continue
                if item.name == 'logs' and not item.is_symlink() and item.is_dir():
                    continue
                plain(item)
                if item.is_dir():
                    safe_tree(item); shutil.copytree(item, original / item.name)
                else:
                    require(item.is_file(), 'nonregular profile member')
                    shutil.copy2(item, original / item.name)
            require(digest(database) == before and digest(original / DB) == before, 'database changed during backup')
            with tempfile.TemporaryDirectory(prefix='.roarkt-migrate-', dir=target) as temporary:
                work = Path(temporary)
                source, fresh = work / 'source', work / 'fresh'
                source.mkdir(); fresh.mkdir()
                shutil.copytree(original / DB, source / DB)
                exported = work / 'export.txt'
                manager(tool, source, '-e', exported)
                rows = entries(exported)
                words = simplify_words(build_simplifier(work), (word for word, code in rows))
                merged = defaultdict(int)
                changed = 0
                for ((word, code), count), simplified in zip(rows.items(), words):
                    require(simplified and '\t' not in simplified, 'invalid converted phrase')
                    changed += word != simplified
                    merged[(simplified, code)] += count
                    require(merged[(simplified, code)] <= 2147483647, 'merged count overflow')
                if not changed:
                    print(f'unchanged entries={len(rows)} backup_id={saved.name}'); return
                imported = work / 'import.txt'
                imported.write_text(''.join(f'{word}\t{code}\t{count}\n' for (word, code), count in sorted(merged.items())))
                manager(tool, fresh, '-i', imported)
                checked = work / 'checked.txt'
                manager(tool, fresh, '-e', checked)
                require(entries(checked) == dict(merged), 'fresh database verification failed')
                after = digest(fresh / DB)
                (saved / 'manifest.json').write_text(json.dumps({'kind': 'simplified', 'before': before, 'after': after}))
                require(digest(database) == before, 'database changed before publish')
                os.rename(database, work / 'previous')
                try:
                    os.rename(fresh / DB, database)
                except BaseException:
                    os.rename(work / 'previous', database)
                    raise
            print(f'migrated entries={len(rows)} changed={changed} collisions={len(rows)-len(merged)} output={len(merged)} backup_id={saved.name}')

if __name__ == '__main__':
    try:
        main()
    except Refusal as error:
        print('refused: ' + str(error), file=sys.stderr); sys.exit(2)
    except Exception:
        print('failed: dependency, input format or filesystem error; original backup retained', file=sys.stderr); sys.exit(1)
