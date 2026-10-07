#!/usr/bin/env python3
r"""Analyse and clean a zsh history file.

Reports by default; only writes with --apply. See SKILL.md for the workflow.

Two format facts drive the parser and must not be "simplified":

  * An entry may span several lines. A line whose text ends in a backslash
    continues into the next line -- that backslash escapes the newline that
    zsh embedded in the command. ANY trailing backslash continues the entry,
    not an odd number of them: a command that itself ended in `\` is stored
    as `\\`, which still continues. Verified against `fc -R`/`fc -l`.
  * Timestamps are optional per entry. With EXTENDED_HISTORY a line starts
    `: <epoch>:<elapsed>;`; with NO_EXTENDED_HISTORY it is the bare command.
    One file routinely holds both, because the option changed over time.

Consequence: never filter this file line-wise (grep -v, sed -i). Doing so
splits multi-line commands and leaves fragments behind as bogus entries.
"""

import argparse
import math
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from collections import Counter, defaultdict

TS_RE = re.compile(r'^: (\d+):(\d+);')
ASSIGN_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?\+?=')
PLAUSIBLE_NAME = re.compile(r'^[A-Za-z0-9_@.+:-]+$')
SHELL_META = re.compile(r'[|&;<>$(){}=/\\*?~]|--|\s-\w')
WRAPPERS = {'sudo', 'doas', 'command', 'nohup', 'env', 'time', 'exec',
            'builtin', 'stdbuf', 'nice', 'ionice', 'setsid'}


# ---------------------------------------------------------------- parsing

class Entry:
    __slots__ = ('lines', 'start', 'cmd', 'bucket', 'redactions')

    def __init__(self, lines, start):
        self.lines = lines
        self.start = start
        self.bucket = None
        self.redactions = []
        m = TS_RE.match(lines[0])
        head = lines[0][m.end():] if m else lines[0]
        self.cmd = '\n'.join([head] + lines[1:])

    @property
    def timestamped(self):
        return TS_RE.match(self.lines[0]) is not None

    def key(self):
        """Identity for de-duplication: the command, not its timestamp."""
        return '\n'.join(l.rstrip() for l in self.cmd.split('\n')).strip()

    def text(self):
        return '\n'.join(self.lines)


def trailing_backslashes(s):
    n = 0
    while n < len(s) and s[len(s) - 1 - n] == '\\':
        n += 1
    return n


def parse(raw):
    had_nl = raw.endswith('\n')
    lines = raw.split('\n')
    if lines and lines[-1] == '':
        lines.pop()
    entries, cur = [], None
    for i, ln in enumerate(lines):
        if cur is None:
            cur = [ln], i + 1
        else:
            cur[0].append(ln)
        if trailing_backslashes(ln) >= 1:
            continue
        entries.append(Entry(cur[0], cur[1]))
        cur = None
    if cur is not None:
        entries.append(Entry(cur[0], cur[1]))
    return entries, had_nl, len(lines)


def base_command(cmd):
    """First real command word, skipping VAR=val prefixes and sudo/env wrappers.

    Returns (name, kind) where kind is 'name', 'assignment' (a bare VAR=val,
    which is valid shell and must be kept) or 'empty'.
    """
    toks = cmd.split()
    if not toks:
        return None, 'empty'
    i = 0
    while i < len(toks) and ASSIGN_RE.match(toks[i]):
        i += 1
    if i >= len(toks):
        return None, 'assignment'
    while i < len(toks) and toks[i] in WRAPPERS:
        i += 1
        while i < len(toks) and toks[i].startswith('-'):
            i += 1
    if i >= len(toks):
        return None, 'empty'
    return toks[i].strip('"\'`'), 'name'


# ------------------------------------------------------- shell interrogation

def zsh_names():
    """Every word the user's interactive shell can actually run.

    Includes zsh-abbr abbreviations: they expand at the prompt and zsh-abbr can
    push the *unexpanded* form into history, yet `whence` never finds them --
    so without this they look dead when they are not.
    """
    names = set()
    script = ('print -l ${(k)commands} ${(k)builtins} ${(k)aliases} '
              '${(k)functions} ${(k)reswords} 2>/dev/null')
    try:
        out = subprocess.run(['zsh', '-i', '-c', script],
                             capture_output=True, text=True, timeout=90).stdout
        names |= {l.strip() for l in out.splitlines() if l.strip()}
    except Exception as exc:
        print(f'warning: could not interrogate zsh ({exc}); '
              f'dead-command detection disabled', file=sys.stderr)
        return None
    for path in (os.environ.get('ABBR_USER_ABBREVIATIONS_FILE'),
                 os.path.expanduser('~/.config/zsh-abbr/user-abbreviations')):
        if path and os.path.exists(path):
            for line in open(path, errors='replace'):
                m = re.match(r'\s*abbr\s+(?:-{1,2}\S+\s+)*([^\s=]+)=', line)
                if m:
                    names.add(m.group(1).strip('\'"'))
    return names


def interactive_comments():
    try:
        out = subprocess.run(['zsh', '-i', '-c', 'setopt'],
                             capture_output=True, text=True, timeout=60).stdout
        return 'interactivecomments' in out.lower()
    except Exception:
        return False


# ------------------------------------------------------------- redaction

PLACEHOLDER = '<REDACTED:{}>'

# Regions that look random but are not secrets. Masked before any entropy
# scan so nix store paths, hashes and public keys survive untouched.
NEVER = [
    re.compile(r'/nix/store/[a-z0-9]{32}-\S*'),
    re.compile(r'\b(?:sha256|sha512|sri)[-:][A-Za-z0-9+/=]{20,}'),
    re.compile(r'\bssh-(?:rsa|ed25519|dss)\s+[A-Za-z0-9+/=]+'),
    re.compile(r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'),
    re.compile(r'\b[0-9a-f]{7,40}\b'),
]

# Self-identifying tokens: the prefix alone is proof, so these are safe
# to match anywhere in the line.
VENDOR = [
    ('anthropic-key', re.compile(r'\bsk-ant-[A-Za-z0-9_\-]{16,}')),
    ('openai-key',    re.compile(r'\bsk-(?:proj-)?[A-Za-z0-9_\-]{20,}')),
    ('github-token',  re.compile(r'\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}')),
    ('github-pat',    re.compile(r'\bgithub_pat_[A-Za-z0-9_]{20,}')),
    ('gitlab-token',  re.compile(r'\bglpat-[A-Za-z0-9_\-]{16,}')),
    ('slack-token',   re.compile(r'\bxox[abprs]-[A-Za-z0-9-]{10,}')),
    ('aws-key-id',    re.compile(r'\b(?:AKIA|ASIA)[0-9A-Z]{16}\b')),
    ('google-key',    re.compile(r'\bAIza[0-9A-Za-z_\-]{35}\b')),
    ('stripe-key',    re.compile(r'\b(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}')),
    ('digitalocean',  re.compile(r'\bdo[po]_v1_[a-f0-9]{64}\b')),
    ('npm-token',     re.compile(r'\bnpm_[A-Za-z0-9]{36}\b')),
    ('hf-token',      re.compile(r'\bhf_[A-Za-z0-9]{30,}')),
    ('sendgrid-key',  re.compile(r'\bSG\.[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}')),
    ('jwt',           re.compile(r'\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}')),
    ('private-key',   re.compile(r'-----BEGIN [A-Z ]*PRIVATE KEY-----')),
]

_KW = (r'(?:api[_-]?keys?|apikey|access[_-]?token|auth[_-]?token|'
       r'refresh[_-]?token|bearer[_-]?token|client[_-]?secret|secret[_-]?key|'
       r'token|secret|passwords?|passwd|passphrase|credentials?)')

# The value is labelled by its own flag/variable/query name: redact the value,
# keep the label so the command still reads as itself.
LABELLED = [
    ('flag',     re.compile(r'(--' + _KW + r'[=\s]+)(["\']?)([^\s"\';|&]{6,})',
                            re.I), 3),
    ('env',      re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*_?' + _KW + r')=(["\']?)'
                            r'([^\s"\';|&]{6,})', re.I), 3),
    ('url-param', re.compile(r'([?&](?:' + _KW + r'|sig|signature)=)'
                             r'([^\s&"\';|]{6,})', re.I), 2),
    ('bearer',   re.compile(r'((?:Authorization:\s*)?\b(?:Bearer|Basic)\s+)'
                            r'([A-Za-z0-9+/=._\-]{16,})'), 2),
    ('url-auth', re.compile(r'(://[^\s:/@]+:)([^\s@/]{4,})(?=@)'), 2),
]

# Bare positional secrets (`immich login <url> <key>`, `docker login -u u p`).
# Entropy alone is far too eager, so it only runs on entries that are about
# authentication in the first place.
AUTH_CONTEXT = re.compile(
    r'\b(login|logout|auth|authenticate|signin|sign-in|token|secret|'
    r'credential|password|apikey|api[_-]key)\b', re.I)
TOKEN_CANDIDATE = re.compile(
    '(?<![A-Za-z0-9_\\-/.=:\x00])[A-Za-z0-9_\\-]{20,}'
    r'(?!\.[A-Za-z0-9]{1,5}\b)(?![A-Za-z0-9_\-])')


def shannon(s):
    if not s:
        return 0.0
    n = len(s)
    return -sum((c / n) * math.log2(c / n) for c in Counter(s).values())


def looks_random(tok):
    if len(tok) < 20:
        return False
    classes = sum([any(c.islower() for c in tok),
                   any(c.isupper() for c in tok),
                   any(c.isdigit() for c in tok)])
    if classes < 2:
        return False
    return shannon(tok) >= 3.2


def _sub_group(text, rx, kind, group, found):
    out, last = [], 0
    for m in rx.finditer(text):
        s, e = m.span(group)
        if s < 0:
            continue
        out.append(text[last:s])
        out.append(PLACEHOLDER.format(kind))
        found.append((kind, m.group(group)))
        last = e
    out.append(text[last:])
    return ''.join(out)


def redact(text, entropy=True):
    """Redact secret *values* in one line, preserving the surrounding command."""
    found = []
    for kind, rx in VENDOR:
        text = _sub_group(text, rx, kind, 0, found)
    for kind, rx, grp in LABELLED:
        text = _sub_group(text, rx, kind, grp, found)
    if entropy and AUTH_CONTEXT.search(text):
        store = []

        def stash(m):
            store.append(m.group(0))
            return '\x00%d\x00' % (len(store) - 1)

        masked = text
        for rx in NEVER:
            masked = rx.sub(stash, masked)
        out, last = [], 0
        for m in TOKEN_CANDIDATE.finditer(masked):
            tok = m.group(0)
            if not looks_random(tok):
                continue
            out.append(masked[last:m.start()])
            out.append(PLACEHOLDER.format('api-key'))
            found.append(('api-key', tok))
            last = m.end()
        out.append(masked[last:])
        masked = ''.join(out)
        text = re.sub(r'\x00(\d+)\x00', lambda m: store[int(m.group(1))], masked)
    return text, found


def redact_entry(entry, entropy=True):
    """Redact per *line* so the backslash/newline encoding is never rebuilt."""
    new_lines, found = [], []
    for i, ln in enumerate(entry.lines):
        prefix = ''
        if i == 0:
            m = TS_RE.match(ln)
            if m:
                prefix, ln = ln[:m.end()], ln[m.end():]
        red, f = redact(ln, entropy)
        new_lines.append(prefix + red)
        found.extend(f)
    if found:
        entry.lines = new_lines
        entry.redactions = found
        entry.__init__(new_lines, entry.start)
        entry.redactions = found
    return bool(found)


def preview(secret):
    if len(secret) <= 10:
        return '*' * len(secret)
    return f'{secret[:4]}\u2026{secret[-4:]}'


# ---------------------------------------------------------- classification

def classify(entries, known, drop_patterns, comments_ok):
    """Sort entries into removal buckets. Nothing is deleted here."""
    pats = [(p, re.compile(p, re.I)) for p in drop_patterns]
    for e in entries:
        cmd = e.cmd
        hit = next((p for p, rx in pats if rx.search(cmd)), None)
        if hit:
            e.bucket = f'pattern:{hit}'
            continue
        name, kind = base_command(cmd)
        if kind == 'empty':
            e.bucket = 'empty'
            continue
        if kind == 'assignment':
            continue                      # bare VAR=val is valid shell
        if '\x1b[200~' in cmd or cmd.startswith('[200~'):
            e.bucket = 'not-a-command'
            continue
        if name.startswith(('/', './', '../', '~', '$')):
            continue
        if known is None:
            continue
        if name in known:
            continue
        # A pasted block whose first line is a `#` note but whose later lines
        # are real commands is still useful; keep it unless comments are off
        # *and* nothing in it runs.
        if name.startswith('#'):
            rest = cmd.split('\n')[1:]
            if any((base_command(r)[0] or '') in known for r in rest):
                continue
            e.bucket = 'not-a-command'
            continue
        toks = cmd.split()
        if not PLAUSIBLE_NAME.match(name):
            e.bucket = 'not-a-command'
            continue
        # Pasted prose / program output rather than a command. Commands are
        # near-always lowercase and short, so require a capitalised word or a
        # sentence-length run before calling something prose -- otherwise
        # `terraform init` looks exactly like `FIX IMMICH ROLE`.
        if (len(toks) >= 3 and not SHELL_META.search(cmd) and name.isalpha()
                and (len(toks) >= 6
                     or any(t[:1].isupper() for t in toks if t[:1].isalpha()))):
            e.bucket = 'not-a-command'
            continue
        rest = toks[toks.index(name) + 1:] if name in toks else toks[1:]
        if not rest or (len(rest) == 1 and rest[0] in
                        {'--help', '-h', '--version', '-V', '-v'}):
            e.bucket = 'unresolved-bare'
        else:
            e.bucket = 'unresolved-args'
    return entries


# ---------------------------------------------------------------- reporting

def report(entries, total_lines, known, comments_ok, drop_patterns, args):
    n_ts = sum(1 for e in entries if e.timestamped)
    n_ml = sum(1 for e in entries if len(e.lines) > 1)
    print(f'file            : {args.history}')
    print(f'lines / entries : {total_lines} / {len(entries)}')
    print(f'timestamped     : {n_ts}   multi-line: {n_ml}')
    print(f'known commands  : {"unavailable" if known is None else len(known)}')
    print(f'interactive_comments: {"on" if comments_ok else "off"}'
          + ('' if comments_ok else "   ('#' entries error if re-run)"))

    buckets = defaultdict(list)
    for e in entries:
        if e.bucket:
            buckets[e.bucket].append(e)
    print('\nREMOVAL CANDIDATES  (nothing is dropped unless you pass --drop-bucket)')
    if not buckets:
        print('  none')
    for b in sorted(buckets, key=lambda k: -len(buckets[k])):
        print(f'  {b:<22} {len(buckets[b]):>6}')
        for e in buckets[b][:4]:
            head = (e.cmd.splitlines() or [''])[0]
            print(f'      L{e.start}: {head[:88]}')

    unresolved = [e for e in entries
                  if e.bucket in ('unresolved-bare', 'unresolved-args')]
    if unresolved:
        tally = Counter(base_command(e.cmd)[0] for e in unresolved)
        shape = defaultdict(lambda: [0, 0])
        for e in unresolved:
            shape[base_command(e.cmd)[0]][0 if e.bucket.endswith('bare') else 1] += 1
        print('\nUNRESOLVED COMMAND NAMES  (high count + no args == a removed alias;')
        print('                           low count + real args == an uninstalled tool)')
        for nm, c in tally.most_common(30):
            b, a = shape[nm]
            print(f'  {c:>6}  {nm:<26} bare:{b:<5} with-args:{a}')

    secrets = [(e, k, v) for e in entries for k, v in e.redactions]
    print(f'\nSECRETS  ({len(secrets)} value(s); the command itself is kept)')
    for e, k, v in secrets[:40]:
        print(f'  {k:<14} L{e.start}: {preview(v)}')
    if not secrets:
        print('  none found')

    keys = [e.key() for e in entries if not e.bucket and e.key()]
    dups = len(keys) - len(set(keys))
    print(f'\nDUPLICATES  {dups} exact repeat(s) among the entries that would survive')


# ------------------------------------------------------------------- apply

def dedup(entries, keep='last'):
    order = list(range(len(entries)))
    if keep == 'last':
        order.reverse()
    seen, keepset = set(), set()
    for i in order:
        k = entries[i].key()
        if not k:
            keepset.add(i)
            continue
        if k in seen:
            continue
        seen.add(k)
        keepset.add(i)
    return [e for i, e in enumerate(entries) if i in keepset]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--history', default=os.environ.get(
        'HISTFILE', os.path.expanduser('~/.zsh_history')))
    ap.add_argument('--apply', action='store_true',
                    help='write the file (default: report only)')
    ap.add_argument('--drop-pattern', action='append', default=[], metavar='RE',
                    help='drop entries matching this regex (repeatable)')
    ap.add_argument('--drop-bucket', action='append', default=[], metavar='NAME',
                    help='drop a bucket: empty, not-a-command, unresolved-bare, '
                         'unresolved-args, pattern:<re> (repeatable)')
    ap.add_argument('--drop-command', action='append', default=[], metavar='NAME')
    ap.add_argument('--keep-command', action='append', default=[], metavar='NAME')
    ap.add_argument('--no-redact', action='store_true')
    ap.add_argument('--no-entropy', action='store_true',
                    help='only redact labelled/vendor secrets, never by entropy')
    ap.add_argument('--dedup', action='store_true')
    ap.add_argument('--dedup-keep', choices=('first', 'last'), default='last')
    ap.add_argument('--backup-dir', default=None)
    ap.add_argument('--force', action='store_true',
                    help='allow removing more than 90%% of entries')
    args = ap.parse_args()

    path = os.path.expanduser(args.history)
    if not os.path.exists(path):
        sys.exit(f'no such history file: {path}')
    raw = open(path, 'rb').read().decode('utf-8', 'surrogateescape')
    entries, had_nl, total_lines = parse(raw)

    known = zsh_names()
    if known is not None:
        known |= set(args.keep_command)
        known -= set(args.drop_command)
    comments_ok = interactive_comments()
    classify(entries, known, args.drop_pattern, comments_ok)
    if not args.no_redact:
        for e in entries:
            redact_entry(e, entropy=not args.no_entropy)

    if not args.apply:
        report(entries, total_lines, known, comments_ok, args.drop_pattern, args)
        print('\n(report only -- pass --apply with --drop-bucket to write)')
        return

    drop = set(args.drop_bucket)
    kept = [e for e in entries if e.bucket not in drop and
            not (e.bucket and e.bucket.startswith('pattern:') and 'pattern' in drop)]
    removed = len(entries) - len(kept)
    before_dedup = len(kept)
    if args.dedup:
        kept = dedup(kept, args.dedup_keep)
    collapsed = before_dedup - len(kept)

    if not args.force and kept and len(kept) < 0.1 * len(entries):
        sys.exit(f'refusing to drop {len(entries)-len(kept)} of {len(entries)} '
                 f'entries without --force')
    if not kept:
        sys.exit('refusing to write an empty history file')

    stamp = time.strftime('%Y%m%d-%H%M%S')
    bdir = args.backup_dir or os.path.dirname(path) or '.'
    os.makedirs(bdir, exist_ok=True)
    backup = os.path.join(bdir, f'{os.path.basename(path)}.bak-{stamp}')
    shutil.copy2(path, backup)
    os.chmod(backup, 0o600)

    out = '\n'.join(e.text() for e in kept) + ('\n' if had_nl else '')
    tmp = f'{path}.tmp.{os.getpid()}'
    with open(tmp, 'wb') as fh:
        fh.write(out.encode('utf-8', 'surrogateescape'))
    os.chmod(tmp, os.stat(path).st_mode & 0o777)
    os.replace(tmp, path)

    n_red = sum(1 for e in kept if e.redactions)
    print(f'backup   : {backup}  (contains the ORIGINAL secrets -- see SKILL.md)')
    print(f'removed  : {removed}')
    print(f'collapsed: {collapsed} duplicate(s)')
    print(f'redacted : {n_red} entr(ies)')
    print(f'kept     : {len(kept)} entries -> {path}')

    try:
        cmd = (f'HISTSIZE=2000000; SAVEHIST=2000000; fc -R {shlex.quote(path)}; '
               f'fc -l -n 1 2000000')
        got = subprocess.run(['zsh', '-f', '-i', '-c', cmd],
                             capture_output=True, text=True, timeout=120)
        n = len(got.stdout.splitlines())
        ok = 'OK' if n == len(kept) else 'MISMATCH'
        print(f'verify   : zsh re-reads {n} entries ({ok})')
    except Exception as exc:
        print(f'verify   : skipped ({exc})')


if __name__ == '__main__':
    main()
