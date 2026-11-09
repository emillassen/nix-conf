"""Keep MisterZine Jellyfin on a MiSTer up to date with builds from public source.

Each run looks up the newest release on GitHub, builds the app (plexcrt) from
that release's public source, which has no supporter-code gate, packages it
with the release's own FPGA core, jfplay and ffmpeg, and installs it on the
MiSTer over SSH. Nothing is installed while the app is running.

  misterzine-jellyfin-update --setup-ssh    key login to the MiSTer (asks its password once)
  misterzine-jellyfin-update                install the newest release if the MiSTer lacks it
  misterzine-jellyfin-update --build-only   build the package, install nothing

The MiSTer's address comes from --host or $MISTERZINE_HOST. A systemd user
timer runs this every hour with --auto. Work files live in
~/.cache/misterzine-jellyfin-update.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile

REPO = 'matijaerceg/misterzine-jellyfin'
HOME = Path.home()
CACHE = Path(os.environ.get('XDG_CACHE_HOME') or HOME / '.cache') / 'misterzine-jellyfin-update'
KEY = HOME / '.ssh' / 'misterzine-jellyfin'
TAG = re.compile(r'v(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)')
UA = {'User-Agent': 'misterzine-jellyfin-update'}


class Skip(Exception):
    """Nothing to do now; not an error for background runs."""


class LoginRefused(Skip):
    pass


def say(*parts):
    print(*parts, flush=True)


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def run(cmd, **kw):
    return subprocess.run([str(c) for c in cmd], check=True, **kw)


def version_key(version):
    core, _, pre = version.partition('-')
    nums = tuple(int(x) for x in core.split('.'))
    if not pre:
        return nums + (1,)  # a stable release sorts after its pre-releases
    return nums + (0, tuple((0, int(p), '') if p.isdigit() else (1, 0, p) for p in pre.split('.')))


def load_json(path, default):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return default


def save_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_text(json.dumps(data, indent=2) + '\n')
    tmp.replace(path)


# ---------------------------------------------------------------- GitHub

def fetch(url, timeout=60):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout)


def find_release(tag=None):
    try:
        with fetch('https://api.github.com/repos/%s/releases?per_page=50' % REPO, 30) as r:
            releases = json.load(r)
    except (urllib.error.URLError, OSError, ValueError) as exc:
        raise Skip('Could not reach GitHub (%s).' % exc)
    found = []
    for r in releases:
        m = TAG.fullmatch(r.get('tag_name', ''))
        if r.get('draft') or not m or (tag and r['tag_name'] != tag):
            continue
        version = m.group(1)
        assets = {a['name']: a['browser_download_url'] for a in r.get('assets', [])}
        pattern = r'MisterZine-Jellyfin-(beta|public)-' + re.escape(version) + r'\.zip'
        package = next((n for n in assets if re.fullmatch(pattern, n)), None)
        if package and package + '.sha256' in assets:
            found.append({'tag': r['tag_name'], 'version': version, 'stable': not r.get('prerelease'),
                          'package': package, 'url': assets[package], 'sha_url': assets[package + '.sha256']})
    if not found:
        raise SystemExit('No usable release found' + (' for tag ' + tag if tag else '') + '.')
    return max(found, key=lambda x: version_key(x['version']))


def download(url, dest):
    tmp = dest.with_name(dest.name + '.part')
    with fetch(url) as r, open(tmp, 'wb') as f:
        shutil.copyfileobj(r, f)
    tmp.replace(dest)


# ---------------------------------------------------------------- build

def package_path(ident):
    return CACHE / 'packages' / ('MisterZine-Jellyfin-' + ident + '.zip')


def cached_package(ident):
    pkg = package_path(ident)
    stamp = pkg.with_name(pkg.name + '.sha256')
    if pkg.is_file() and stamp.is_file() and stamp.read_text().split()[:1] == [sha256(pkg)]:
        return pkg
    return None


def checkout(tag):
    repo = CACHE / 'repo'
    if not (repo / '.git').is_dir():
        shutil.rmtree(repo, ignore_errors=True)
        say('Downloading the source code (first run only)...')
        run(['git', 'clone', '-q', '--filter=blob:none', '--no-checkout', 'https://github.com/%s.git' % REPO, repo])
    run(['git', '-C', repo, 'fetch', '-q', '--force', '--tags', 'origin'])
    run(['git', '-C', repo, 'checkout', '-q', '--force', '--detach', 'refs/tags/' + tag])
    run(['git', '-C', repo, 'clean', '-q', '-fdx'])
    return repo


def build_app(repo, version, ident):
    m = re.search(r'^go (\d+)\.(\d+)', (repo / 'app/go.mod').read_text(), re.M)
    if not m:
        raise SystemExit('Could not read the Go version from app/go.mod.')
    env = dict(os.environ, GOPATH=str(CACHE / 'go'), GOCACHE=str(CACHE / 'go-build'), GOTOOLCHAIN='local')
    attr = 'go_%s_%s' % m.groups()
    probe = subprocess.run(['nix', 'eval', '--raw', 'nixpkgs#%s.version' % attr], capture_output=True)
    if probe.returncode != 0:
        attr, env['GOTOOLCHAIN'] = 'go', 'auto'  # let Go fetch the version go.mod asks for
    say('Building the app with Go %s.%s...' % m.groups())
    run(['nix', 'shell', 'nixpkgs#' + attr, '-c', sys.executable, '-I', repo / 'release/build_app.py',
         '--channel', 'development', '--version', version, '--id', ident], env=env)


def official_parts(rel, work):
    """Take the core, jfplay and ffmpeg from the release's official package.
    The official plexcrt (the only part with the code gate) is not used."""
    folder = CACHE / 'official' / rel['version']
    folder.mkdir(parents=True, exist_ok=True)
    zpath = folder / rel['package']
    stamp = folder / (rel['package'] + '.sha256')
    download(rel['sha_url'], stamp)
    expected = stamp.read_text().split()[0]
    if not zpath.is_file() or sha256(zpath) != expected:
        say('Downloading the official %s package for its core, jfplay and ffmpeg...' % rel['version'])
        download(rel['url'], zpath)
        if sha256(zpath) != expected:
            raise SystemExit('The official package failed its checksum; try again later.')
    with zipfile.ZipFile(zpath) as z:
        def read(name):
            return z.read('misterzine-jellyfin-beta/' + name)
        manifest = json.loads(read('manifest.json'))
        if manifest.get('version') != rel['version']:
            raise SystemExit('The official package is for a different version.')
        prov_bytes = read('provenance/quartus-rbf-manifest.json')
        rbf_name = json.loads(prov_bytes)['rbf']['name']
        if not re.fullmatch(r'[A-Za-z0-9_.-]+\.rbf', rbf_name):
            raise SystemExit('Unexpected core file name in the official package.')
        parts = {'jfplay': work / 'jfplay', 'ffmpeg': work / 'ffmpeg', 'H264.rbf': work / rbf_name}
        for name, dest in parts.items():
            data = read('payload/' + name)
            if hashlib.sha256(data).hexdigest() != manifest['files'][name]:
                raise SystemExit('The official package has a damaged ' + name + '.')
            dest.write_bytes(data)
    (work / 'quartus-rbf-manifest.json').write_bytes(prov_bytes)
    return parts


def build(rel):
    version = rel['version']
    ident = 'selfbuilt-' + version
    pkg = cached_package(ident)
    if pkg:
        return pkg, ident
    say('Building MisterZine Jellyfin %s from source...' % version)
    repo = checkout(rel['tag'])
    build_app(repo, version, ident)
    work = Path(tempfile.mkdtemp(prefix='build-', dir=CACHE))
    try:
        parts = official_parts(rel, work)
        source = work / 'source.zip'
        run(['git', '-C', repo, 'archive', '--format=zip', '-o', source, 'HEAD'])
        run([sys.executable, '-I', repo / 'release/build_package.py', '--out', work / 'out',
             '--id', ident, '--version', version, '--worker', parts['jfplay'], '--ffmpeg', parts['ffmpeg'],
             '--rbf', parts['H264.rbf'], '--rbf-manifest', work / 'quartus-rbf-manifest.json',
             '--source-archive', source], stdout=subprocess.DEVNULL)
        pkg = package_path(ident)
        pkg.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(work / 'out' / pkg.name), pkg)
        pkg.with_name(pkg.name + '.sha256').write_text(sha256(pkg) + '  ' + pkg.name + '\n')
    finally:
        shutil.rmtree(work, ignore_errors=True)
    prune()
    say('Built ' + str(pkg))
    return pkg, ident


def prune(keep=2):
    """Keep the newest two versions' packages and downloads."""
    pkgs = sorted((CACHE / 'packages').glob('MisterZine-Jellyfin-selfbuilt-*.zip'),
                  key=lambda p: version_key(p.name[len('MisterZine-Jellyfin-selfbuilt-'):-4]))
    for p in pkgs[:-keep]:
        p.unlink()
        p.with_name(p.name + '.sha256').unlink(missing_ok=True)
    official = sorted((p for p in (CACHE / 'official').glob('*') if TAG.fullmatch('v' + p.name)),
                      key=lambda p: version_key(p.name))
    for p in official[:-keep]:
        shutil.rmtree(p)


# ---------------------------------------------------------------- MiSTer side
# These run on the MiSTer with its own python3 (3.9 or newer), sent over SSH.

STATUS = r'''
import json, os, sys
card = sys.argv[1]
current = None
try:
    with open(os.path.join(card, 'misterzine-jellyfin', 'active.json')) as f:
        current = json.load(f).get('current')
except (OSError, ValueError):
    pass
running = []
for pid in os.listdir('/proc'):
    if pid.isdigit():
        try:
            with open('/proc/%s/cmdline' % pid, 'rb') as f:
                exe = f.read().split(b'\0')[0]
        except OSError:
            continue
        if os.path.basename(exe) in (b'plexcrt', b'jfplay'):
            running.append(exe.decode('utf-8', 'replace'))
st = os.statvfs(card)
print(json.dumps({'current': current, 'running': running, 'free': st.f_bavail * st.f_frsize,
                  'mister': os.path.exists('/dev/MiSTer_cmd')}))
'''

INSTALL = r'''
import hashlib, json, os, shutil, subprocess, sys, zipfile
card, stage, expected = sys.argv[1:4]
zpath = os.path.join(stage, 'package.zip')
try:
    h = hashlib.sha256()
    with open(zpath, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    if h.hexdigest() != expected:
        sys.exit('The upload was damaged (checksum mismatch); nothing was installed.')
    with zipfile.ZipFile(zpath) as z:
        for info in z.infolist():
            name = info.filename
            if not name.startswith('misterzine-jellyfin-beta/') or name.endswith('/'):
                continue
            parts = name.split('/')
            if '..' in parts or '\\' in name:
                sys.exit('Unsafe path in package; nothing was installed.')
            dest = os.path.join(stage, *parts)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with z.open(info) as src, open(dest, 'wb') as out:
                shutil.copyfileobj(src, out)
    package = os.path.join(stage, 'misterzine-jellyfin-beta')
    code = subprocess.call([sys.executable, os.path.join(package, 'manager.py'), 'install',
                            '--card', card, '--package', package])
    if code:
        sys.exit(code)
    # The folder a manual install of a self-built package leaves behind.
    old = os.path.join(card, 'misterzine-jellyfin-beta')
    try:
        with open(os.path.join(old, 'manifest.json')) as f:
            if str(json.load(f).get('id', '')).startswith('selfbuilt-'):
                shutil.rmtree(old)
                print('Removed the leftover misterzine-jellyfin-beta folder.')
    except (OSError, ValueError):
        pass
    # An official beta install points Update All at the beta channel.
    ini = os.path.join(card, 'downloader_misterzine_jellyfin.ini')
    try:
        with open(ini) as f:
            official = '[misterzine_jellyfin]' in f.read()
        if official:
            os.remove(ini)
            print('Removed downloader_misterzine_jellyfin.ini so Update All will not bring back the official beta.')
    except OSError:
        pass
finally:
    shutil.rmtree(stage, ignore_errors=True)
'''

# MiSTer Linux mounts / read-only, so ssh-copy-id cannot write the key, and it
# ships /root/.ssh group-writable, which makes sshd ignore any key in it. A
# MiSTer Linux update replaces the whole image, key included.
ADD_KEY = r'''
set -e
if grep -qE '^[^ ]+ / [^ ]+ ro[, ]' /proc/mounts; then
    mount -o remount,rw /
    trap 'sync; mount -o remount,ro /' EXIT
fi
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
grep -qxF {key} ~/.ssh/authorized_keys || echo {key} >> ~/.ssh/authorized_keys
'''


class Card:
    def __init__(self, host=None, user='root', local=None, batch=False):
        self.host, self.user, self.local = host, user, local
        self.target = '%s@%s' % (user, host)
        self.root = str(local) if local else '/media/fat'
        self.ssh = ['ssh', '-o', 'ConnectTimeout=10', '-o', 'StrictHostKeyChecking=accept-new',
                    '-o', 'ServerAliveInterval=15', '-o', 'ControlPath=' + str(CACHE / 'ssh-%C')]
        if KEY.is_file():
            self.ssh += ['-i', str(KEY), '-o', 'IdentitiesOnly=yes']
        if batch:
            self.ssh += ['-o', 'BatchMode=yes']
        self.opened = False

    def name(self):
        return self.local or self.host

    def open(self):
        """One shared connection, so a password is asked at most once. Its
        errors go to a file: a pipe would be held open by the background
        connection and stall the caller."""
        if self.local:
            return
        CACHE.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryFile() as err:
            r = subprocess.run(self.ssh + ['-o', 'ControlMaster=yes', '-o', 'ControlPersist=60', '-f', '-N', self.target],
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=err)
            err.seek(0)
            text = err.read().decode('utf-8', 'replace')
        if r.returncode == 0:
            self.opened = True
            return
        if 'Host key verification failed' in text or 'IDENTIFICATION HAS CHANGED' in text:
            raise SystemExit('The MiSTer at %s has a new SSH identity (reinstalled SD card?). If that is expected, run\n'
                             '  ssh-keygen -R %s\nand try again.' % (self.host, self.host))
        if 'Permission denied' in text:
            raise LoginRefused('The MiSTer at %s refused the login key (a MiSTer Linux update removes it). '
                               'Run: misterzine-jellyfin-update --setup-ssh' % self.host)
        raise Skip('The MiSTer at %s is not reachable (is it on?).' % self.host)

    def sh(self, script, **kw):
        # ControlMaster=no: use the shared connection, never start a lingering one.
        cmd = ['bash', '-c', script] if self.local else self.ssh + ['-o', 'ControlMaster=no', self.target, script]
        return subprocess.run(cmd, **kw)

    def py(self, code, *args, **kw):
        return self.sh('python3 - ' + ' '.join(shlex.quote(str(a)) for a in args), input=code, text=True, **kw)

    def close(self):
        if self.opened:
            subprocess.run(self.ssh + ['-O', 'exit', self.target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.opened = False


def deploy(card, pkg, ident, force=False):
    card.open()
    r = card.py(STATUS, card.root, capture_output=True)
    if r.returncode != 0:
        raise SystemExit('Could not read the MiSTer\'s state:\n' + r.stderr.strip())
    status = json.loads(r.stdout)
    if not card.local and not status['mister']:
        raise SystemExit('%s does not look like a MiSTer; nothing was installed.' % card.host)
    if status['current'] == ident and not force:
        say('The MiSTer already runs %s.' % ident)
        return False
    if status['running']:
        raise Skip('MisterZine Jellyfin is running on the MiSTer; it will be updated once it is closed.')
    if status['free'] < 3 * pkg.stat().st_size + (32 << 20):
        raise SystemExit('Not enough free space on the SD card.')
    say('Installing %s on %s...' % (ident, card.name()))
    stage = card.root + '/misterzine-jellyfin-update-staging'
    with open(pkg, 'rb') as f:
        q = shlex.quote(stage)
        card.sh('rm -rf %s && mkdir -p %s && cat > %s/package.zip' % (q, q, q), stdin=f, check=True)
    r = card.py(INSTALL, card.root, stage, sha256(pkg))
    if r.returncode != 0:
        raise SystemExit('The install on the MiSTer failed (see above). The previous version stays active.')
    return True


def setup_ssh(host, user):
    if not KEY.is_file():
        KEY.parent.mkdir(mode=0o700, exist_ok=True)
        # No passphrase: the timer runs with nobody there to type one.
        run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', 'misterzine-jellyfin-update', '-f', KEY])
    key = KEY.with_name(KEY.name + '.pub').read_text().strip()
    say('Adding a login key to the MiSTer. When asked for the password, type its root password (default: 1).')
    run(['ssh', '-o', 'ConnectTimeout=10', '-o', 'StrictHostKeyChecking=accept-new', '%s@%s' % (user, host),
         ADD_KEY.replace('{key}', shlex.quote(key))])
    card = Card(host, user, batch=True)
    try:
        card.open()
    finally:
        card.close()
    say('Key login works.')


def notify(text):
    if shutil.which('notify-send'):
        subprocess.run(['notify-send', 'MisterZine Jellyfin', text], stderr=subprocess.DEVNULL)


# ---------------------------------------------------------------- main

def main():
    sys.stdout.reconfigure(line_buffering=True)
    # prog: the Nix wrapper runs this as .misterzine-jellyfin-update-wrapped
    ap = argparse.ArgumentParser(prog='misterzine-jellyfin-update', description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--host', help='MiSTer address (default: $MISTERZINE_HOST)')
    ap.add_argument('--user', help='SSH user on the MiSTer (default: $MISTERZINE_USER, else root)')
    ap.add_argument('--tag', help='install this release tag instead of the newest, e.g. v0.1.0-beta.15')
    ap.add_argument('--build-only', action='store_true', help='build the package and stop')
    ap.add_argument('--force', action='store_true', help='reinstall even if the MiSTer already has this version')
    ap.add_argument('--setup-ssh', action='store_true', help='create a login key and add it to the MiSTer (asks its password once)')
    ap.add_argument('--auto', action='store_true', help=argparse.SUPPRESS)       # used by the timer
    ap.add_argument('--card-dir', type=Path, help=argparse.SUPPRESS)              # testing: a local folder as the SD card
    args = ap.parse_args()

    host = args.host or os.environ.get('MISTERZINE_HOST')
    user = args.user or os.environ.get('MISTERZINE_USER') or 'root'
    no_host = 'Tell me where the MiSTer is: --host <address>, or set MISTERZINE_HOST.'
    if args.setup_ssh:
        if not host:
            raise SystemExit(no_host)
        return setup_ssh(host, user)

    CACHE.mkdir(parents=True, exist_ok=True)
    with open(CACHE / 'lock', 'w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            say('Another update is already running.')
            return 0
        card = None
        state = load_json(CACHE / 'state.json', {})
        try:
            rel = find_release(args.tag)
            ident = 'selfbuilt-' + rel['version']
            if args.auto and not args.force and host and state.get(host) == ident:
                return 0  # installed earlier; a rollback on the MiSTer is left alone
            if rel['stable']:
                say('Note: %s is a stable release. Stable releases need no code, so the official installer '
                    '(MisterZine-Jellyfin-Install-Public.sh) is an option too; it updates itself.' % rel['version'])
            pkg, ident = build(rel)
            if args.build_only:
                say(str(pkg))
                return 0
            if args.card_dir:
                card = Card(local=args.card_dir.resolve())
            elif host:
                card = Card(host, user, batch=args.auto)
            else:
                raise SystemExit(no_host)
            installed = deploy(card, pkg, ident, args.force)
            if not card.local:
                state[host] = ident
                state.pop('warned', None)
                save_json(CACHE / 'state.json', state)
            if installed:
                say('Done. Start MisterZine Jellyfin from the MiSTer main menu.')
                if args.auto:
                    notify('Installed %s on the MiSTer.' % rel['version'])
            return 0
        except Skip as exc:
            say(str(exc))
            if isinstance(exc, LoginRefused) and args.auto and state.get('warned') != host:
                notify(str(exc))  # once, not every hour
                state['warned'] = host
                save_json(CACHE / 'state.json', state)
            return 0 if args.auto else 1
        except subprocess.CalledProcessError as exc:
            say('A step failed: ' + ' '.join(map(str, exc.cmd))[:300])
            return 1
        finally:
            if card:
                card.close()


if __name__ == '__main__':
    sys.exit(main())
