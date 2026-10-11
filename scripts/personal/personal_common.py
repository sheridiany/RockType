"""Local-only helpers; never log exception details or user content."""
import contextlib
import fcntl
import hashlib
import json
import math
import time
import os
from pathlib import Path
import subprocess
import tempfile
import sys
from datetime import datetime, timezone

class Refusal(Exception):
    pass

def require(ok, reason):
    if not ok:
        raise Refusal(reason)

def add_rime_directory_argument(parser):
    parser.add_argument(
        '--rime-dir',
        default=os.environ.get('ROARKT_RIME_USER_DIR') or str(
            Path.home() / 'Library/Application Support/RoarkT/Rime'),
        help='existing target directory (default: ROARKT_RIME_USER_DIR or '
             '~/Library/Application Support/RoarkT/Rime)')

def plain(path):
    path = Path(os.path.abspath(Path(path).expanduser()))
    # macOS /tmp and /var are system aliases; resolve parent aliases, but reject
    # links at user-selected leaves and every component below the canonical root.
    require(not path.is_symlink(), 'symlink refused')
    for parent in path.parents:
        if str(parent) not in ('/tmp', '/var'):
            require(not parent.is_symlink(), 'symlink ancestor refused')
    return path.resolve()

def safe_tree(path):
    for root, dirs, files in os.walk(path, followlinks=False):
        for name in dirs + files:
            p = Path(root) / name
            require(not p.is_symlink() and (p.is_dir() or p.is_file()), 'nonregular backup member refused')

def run(args, cwd=None, data=None):
    result = subprocess.run([str(a) for a in args], cwd=cwd, input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            env={**os.environ, 'GLOG_logtostderr': '1', 'GLOG_minloglevel': '3'})
    require(result.returncode == 0, 'external tool failed')
    return result.stdout

def build_simplifier(directory):
    binary = Path(directory) / 'simplify'
    run(['xcrun', 'swiftc', Path(__file__).with_name('simplify.swift'), '-o', binary])
    return binary


def simplify_words(binary, words, traditional=False):
    words = list(words)
    require(all(word and '\n' not in word and '\r' not in word for word in words), 'invalid phrase')
    converted = run([binary] + (['--traditional'] if traditional else []),
                    data=('\n'.join(words)).encode()).decode().splitlines()
    require(len(converted) == len(words), 'conversion row mismatch')
    return converted


@contextlib.contextmanager
def locked(directory):
    require(directory.is_dir(), 'target directory must already exist')
    lock = directory / '.roarkt-personal.lock'
    plain(lock)
    with lock.open('a') as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Refusal('another personal operation is running') from None
        yield

def backup(directory, kind):
    root = plain(directory / 'roarkt-backups')
    root.mkdir(mode=0o700, exist_ok=True)
    destination = root / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ') + '-' + kind)
    destination.mkdir(mode=0o700)
    return destination

def atomic(path, data):
    plain(path)
    fd, name = tempfile.mkstemp(prefix='.roarkt-write-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        if path.exists():
            # librime invalidates source caches using integer-second mtimes.
            stamp = max(math.floor(time.time()), math.floor(path.stat().st_mtime) + 1)
            os.utime(name, (stamp, stamp))
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)

def digest(path):
    plain(path)
    if not path.exists():
        return None
    if path.is_file():
        return hashlib.sha256(path.read_bytes()).hexdigest()
    safe_tree(path)
    h = hashlib.sha256()
    for item in sorted(path.rglob('*')):
        h.update(str(item.relative_to(path)).encode())
        if item.is_file():
            h.update(item.read_bytes())
    return h.hexdigest()

def publish(directory, changes, kind):
    """Back up exact bytes, stage all files, restore on ordinary write failure."""
    old = {}
    for name, data in changes.items():
        p = plain(directory / name)
        require(not p.exists() or p.is_file(), 'nonregular target refused')
        old[name] = p.read_bytes() if p.exists() else None
    if all(old[n] == data for n, data in changes.items()):
        return None
    dest = backup(directory, kind)
    for name, data in old.items():
        if data is not None:
            (dest / name).write_bytes(data)
    manifest = {'kind': kind, 'files': {n: {'old': old[n] is not None,
                'new': hashlib.sha256(data).hexdigest()} for n, data in changes.items()}}
    (dest / 'manifest.json').write_text(json.dumps(manifest))
    written = []
    try:
        for name, data in changes.items():
            p = plain(directory / name)
            require((p.read_bytes() if p.exists() else None) == old[name], 'target changed during operation')
            atomic(p, data)
            written.append(name)
    except BaseException:
        for name in reversed(written):
            if old[name] is None:
                (directory / name).unlink()
            else:
                atomic(directory / name, old[name])
        raise
    return dest.name

def restore_files(directory, token, names):
    require(token not in ('.', '..') and Path(token).name == token, 'backup ID required')
    dest = plain(directory / 'roarkt-backups' / token)
    data = json.loads((dest / 'manifest.json').read_text())
    require(set(data['files']) == set(names), 'wrong backup type')
    for name, state in data['files'].items():
        require(digest(directory / name) == state['new'], 'target changed since generation; rollback refused')
        if state['old']:
            require(plain(dest / name).is_file(), 'backup incomplete')
    for name, state in data['files'].items():
        if state['old']:
            atomic(directory / name, (dest / name).read_bytes())
        else:
            (directory / name).unlink()


@contextlib.contextmanager
def database_lock(path):
    # A separate process owns the POSIX lock: opening/closing LOCK during a
    # complete backup in this process must not accidentally release it.
    plain(path)
    require(path.is_file(), 'LevelDB LOCK missing')
    code = """import fcntl, sys
with open(sys.argv[1], 'r+') as lock:
    fcntl.lockf(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    sys.stdout.buffer.write(b'1')
    sys.stdout.buffer.flush()
    sys.stdin.buffer.read()
"""
    guard = subprocess.Popen([sys.executable, '-c', code, str(path)],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL)
    try:
        require(guard.stdout.read(1) == b'1', 'database is in use')
        yield
    finally:
        guard.stdin.close()
        guard.stdout.close()
        try:
            guard.wait(timeout=5)
        except subprocess.TimeoutExpired:
            guard.kill()
            guard.wait()
