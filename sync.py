#!/usr/bin/env python3
"""omarchy-zen-sync renderer.

Renders Zen's userChrome.css from the active Omarchy theme, wires Zen
profiles (idempotent), and restarts Zen only when the rendered CSS changed.
Single code path used by Service.qml (plugin mode) and by the theme-set hook
(manual mode). Safe to run by hand.

Hardening notes:
- All filesystem access is descriptor-bound. Directory anchors are
  canonicalized once, then walked component-by-component with
  O_NOFOLLOW|O_DIRECTORY; the resulting directory descriptors are held and
  every read, temporary creation, publication (rename), link, and backup runs
  *at* those descriptors. A swapped or symlinked intermediate component makes
  the walk fail at use time instead of being silently followed.
- File reads open with O_NOFOLLOW|O_NONBLOCK and verify type/owner/size via
  fstat on the open descriptor before reading through that same descriptor.
- omarchy-theme-color never sees an on-disk path: the verified colors.toml
  bytes are handed over as a sealed-in-memory file (memfd) via /proc/self/fd.
- Theme keys/values are strictly data: keys must match [a-z0-9_]+, values an
  allowlisted color grammar; nothing from the theme becomes executable syntax.
- profiles.ini entries are component-validated (no absolute, empty, dot, or
  backslash segments) and walked from the profile-root descriptor.
- Every write is an O_CREAT|O_EXCL unpredictable temporary in the destination
  directory followed by an atomic renameat.
"""

import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import time

HOME = os.path.realpath(os.path.expanduser("~"))
UID = os.getuid()
MAX_INPUT_BYTES = 65536
MAX_USERJS_BYTES = 1 << 20
PREF_KEY = '"toolkit.legacyUserProfileCustomizations.stylesheets"'
PREF_LINE = f"user_pref({PREF_KEY}, true);"
OUT_NAME = "zen-userchrome.css"
BACKUP_NAME = "userChrome.css.pre-omarchy-zen-sync"

SELF_DIR = os.path.dirname(os.path.realpath(__file__))
THEME_DIR = os.path.join(HOME, ".local", "state", "omarchy", "current", "theme")
STATE_PARENT = os.path.join(HOME, ".local", "state")
OUT_DIR_NAME = "omarchy-zen-sync"
OUT_PATH = os.path.join(STATE_PARENT, OUT_DIR_NAME, OUT_NAME)

O_DIR = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
O_READ = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC
O_CREATE = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC

KEY_RE = re.compile(r"^[a-z0-9_]+$")
VALUE_RE = re.compile(
    r"^(#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?|[0-9]{1,3}(,[0-9]{1,3}){2}|light|dark)$"
)


def open_dir(path, require_uid=None):
    """Open an absolute, canonical directory path component-by-component with
    O_NOFOLLOW|O_DIRECTORY and return its descriptor. Any symlinked component
    fails the walk (ELOOP/ENOTDIR)."""
    if not os.path.isabs(path):
        raise ValueError(path)
    fd = os.open("/", O_DIR)
    try:
        for comp in [c for c in path.split("/") if c]:
            if comp in (".", ".."):
                raise OSError(f"bad component: {comp}")
            nfd = os.open(comp, O_DIR, dir_fd=fd)
            os.close(fd)
            fd = nfd
        if require_uid is not None and os.fstat(fd).st_uid != require_uid:
            raise OSError("unexpected owner")
        return fd
    except Exception:
        os.close(fd)
        raise


def open_subdir(base_fd, rel, require_uid=None):
    """Walk a validated relative path from an already-held directory fd."""
    fd = os.dup(base_fd)
    try:
        for comp in rel.split("/"):
            nfd = os.open(comp, O_DIR, dir_fd=fd)
            os.close(fd)
            fd = nfd
        if require_uid is not None and os.fstat(fd).st_uid != require_uid:
            raise OSError("unexpected owner")
        return fd
    except Exception:
        os.close(fd)
        raise


def read_at(dir_fd, name, limit):
    """Descriptor-bound read: O_NOFOLLOW|O_NONBLOCK open at dir_fd, fstat
    checks (regular, owned by us, non-empty, size-capped), then read through
    that same descriptor. Returns bytes or None."""
    try:
        fd = os.open(name, O_READ, dir_fd=dir_fd)
    except OSError:
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != UID:
            return None
        if not 0 < st.st_size <= limit:
            return None
        chunks = []
        remaining = limit
        while remaining > 0:
            chunk = os.read(fd, min(65536, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)
    finally:
        os.close(fd)


def write_at(dir_fd, name, data, mode=0o600):
    """Atomic write at dir_fd: unpredictable O_CREAT|O_EXCL temporary in the
    same directory, then renameat over the destination."""
    tmp = f".{name}.{secrets.token_hex(8)}"
    fd = os.open(tmp, O_CREATE, mode, dir_fd=dir_fd)
    try:
        view = memoryview(data)
        while view:
            written = os.write(fd, view)
            view = view[written:]
        os.fsync(fd)
    finally:
        os.close(fd)
    try:
        os.rename(tmp, name, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
    except OSError:
        os.unlink(tmp, dir_fd=dir_fd)
        raise


def lstat_at(dir_fd, name):
    try:
        return os.stat(name, dir_fd=dir_fd, follow_symlinks=False)
    except OSError:
        return None


# --- theme colors --------------------------------------------------------------


def theme_colors():
    """Read colors.toml descriptor-bound and run omarchy-theme-color against a
    sealed in-memory copy (memfd via /proc/self/fd), never an on-disk path."""
    theme_fd = open_dir(THEME_DIR, require_uid=UID)
    try:
        raw = read_at(theme_fd, "colors.toml", MAX_INPUT_BYTES)
    finally:
        os.close(theme_fd)
    if raw is None:
        return None

    mfd = os.memfd_create("omarchy-zen-sync-colors")
    try:
        os.write(mfd, raw)
        os.lseek(mfd, 0, os.SEEK_SET)
        os.set_inheritable(mfd, True)
        proc = subprocess.run(
            ["omarchy-theme-color", "--file", f"/proc/self/fd/{mfd}", "--all"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            pass_fds=(mfd,),
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    finally:
        os.close(mfd)
    if proc.returncode != 0:
        return None

    colors = {}
    for line in proc.stdout[:MAX_INPUT_BYTES].decode("utf-8", "replace").splitlines():
        key, sep, value = line.partition("\t")
        if not sep:
            continue
        if KEY_RE.fullmatch(key) and VALUE_RE.fullmatch(value):
            colors[key] = value
    return colors or None


def render_css(colors):
    self_fd = open_dir(SELF_DIR)
    try:
        tpl = read_at(self_fd, "zen-userchrome.css.tpl", MAX_INPUT_BYTES)
    finally:
        os.close(self_fd)
    if tpl is None:
        return None
    content = tpl.decode("utf-8", "replace")
    for key, value in colors.items():
        content = content.replace("{{ " + key + " }}", value)
    # A leftover token means a missing or rejected value: don't ship broken CSS.
    if "{{" in content:
        return None
    return content.encode("utf-8")


# --- output ---------------------------------------------------------------------


def publish_css(css):
    """Write the rendered CSS into the private state dir. Returns True if the
    published file changed."""
    parent_fd = open_dir(STATE_PARENT, require_uid=UID)
    try:
        try:
            os.mkdir(OUT_DIR_NAME, 0o700, dir_fd=parent_fd)
        except FileExistsError:
            pass
        out_fd = open_subdir(parent_fd, OUT_DIR_NAME, require_uid=UID)
    finally:
        os.close(parent_fd)
    try:
        os.fchmod(out_fd, 0o700)
        if read_at(out_fd, OUT_NAME, MAX_INPUT_BYTES) == css:
            return False
        write_at(out_fd, OUT_NAME, css)
        return True
    finally:
        os.close(out_fd)


# --- Zen profile wiring ---------------------------------------------------------


def parse_profiles_ini(text):
    rels = []
    is_relative = False
    path_value = None

    def flush():
        nonlocal is_relative, path_value
        if is_relative and path_value:
            rels.append(path_value)
        is_relative, path_value = False, None

    for line in text.splitlines():
        line = line.strip()
        if line.startswith("["):
            flush()
        elif line.startswith("IsRelative="):
            is_relative = line[len("IsRelative="):] == "1"
        elif line.startswith("Path="):
            path_value = line[len("Path="):]
    flush()
    return rels


def valid_rel(rel):
    if not rel or rel.startswith("/") or "\\" in rel:
        return False
    for comp in rel.split("/"):
        if not comp or comp.startswith(".") or ".." in comp:
            return False
    return True


def wire_profile(profile_fd):
    """All operations relative to the held profile directory descriptor."""
    st = lstat_at(profile_fd, "prefs.js")
    if st is None or not stat.S_ISREG(st.st_mode):
        return  # never-used placeholder profile

    # chrome/ directory
    st = lstat_at(profile_fd, "chrome")
    if st is None:
        try:
            os.mkdir("chrome", 0o755, dir_fd=profile_fd)
        except OSError:
            return
    elif not stat.S_ISDIR(st.st_mode):
        return
    try:
        chrome_fd = open_subdir(profile_fd, "chrome", require_uid=UID)
    except OSError:
        return

    try:
        st = lstat_at(chrome_fd, "userChrome.css")
        if st is not None and stat.S_ISREG(st.st_mode):
            # Back up once via linkat (fails on existing backup) + unlink.
            try:
                os.link(
                    "userChrome.css", BACKUP_NAME,
                    src_dir_fd=chrome_fd, dst_dir_fd=chrome_fd,
                    follow_symlinks=False,
                )
                os.unlink("userChrome.css", dir_fd=chrome_fd)
            except OSError:
                return
        elif st is not None and not stat.S_ISLNK(st.st_mode):
            return  # FIFO/device/dir in the way: leave it alone

        current = None
        try:
            current = os.readlink("userChrome.css", dir_fd=chrome_fd)
        except OSError:
            pass
        if current != OUT_PATH:
            tmp = f".userChrome.{secrets.token_hex(8)}"
            try:
                os.symlink(OUT_PATH, tmp, dir_fd=chrome_fd)
                os.rename(tmp, "userChrome.css", src_dir_fd=chrome_fd, dst_dir_fd=chrome_fd)
            except OSError:
                try:
                    os.unlink(tmp, dir_fd=chrome_fd)
                except OSError:
                    pass
                return
    finally:
        os.close(chrome_fd)

    # user.js
    st = lstat_at(profile_fd, "user.js")
    if st is None:
        try:
            write_at(profile_fd, "user.js", (PREF_LINE + "\n").encode())
        except OSError:
            pass
        return
    if not stat.S_ISREG(st.st_mode):
        return
    data = read_at(profile_fd, "user.js", MAX_USERJS_BYTES)
    if data is None:
        return
    lines = data.decode("utf-8", "replace").splitlines()
    if PREF_LINE in lines:
        return
    kept = [l for l in lines if PREF_KEY not in l]
    kept.append(PREF_LINE)
    try:
        write_at(profile_fd, "user.js", ("\n".join(kept) + "\n").encode(),
                 mode=stat.S_IMODE(st.st_mode))
    except OSError:
        pass


def wire_all_profiles():
    for base in (
        os.path.join(HOME, ".config", "zen"),
        os.path.join(HOME, ".zen"),
        os.path.join(HOME, ".var", "app", "app.zen_browser.zen", ".zen"),
    ):
        try:
            base_fd = open_dir(base, require_uid=UID)
        except OSError:
            continue
        try:
            ini = read_at(base_fd, "profiles.ini", MAX_INPUT_BYTES)
            if ini is None:
                continue
            for rel in parse_profiles_ini(ini.decode("utf-8", "replace")):
                if not valid_rel(rel):
                    continue
                try:
                    profile_fd = open_subdir(base_fd, rel, require_uid=UID)
                except OSError:
                    continue
                try:
                    wire_profile(profile_fd)
                finally:
                    os.close(profile_fd)
        finally:
            os.close(base_fd)


# --- Zen restart ----------------------------------------------------------------


def zen_running():
    return subprocess.run(
        ["pgrep", "-x", "zen-bin"], stdout=subprocess.DEVNULL
    ).returncode == 0


def restart_zen():
    if not zen_running():
        return
    subprocess.run(["pkill", "-TERM", "-x", "zen-bin"], stdout=subprocess.DEVNULL)
    for _ in range(50):
        if not zen_running():
            break
        time.sleep(0.1)
    # Launch via Hyprland so Zen gets the real session environment
    # (DBus/portal); a bare shell launch can lose it and the content
    # color-scheme goes light.
    try:
        done = subprocess.run(
            ["hyprctl", "dispatch", "exec", "zen-browser"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        ).returncode == 0
    except OSError:
        done = False
    if not done:
        subprocess.Popen(
            ["zen-browser"], start_new_session=True,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )


def main():
    if shutil.which("omarchy-theme-color") is None:
        return 0
    colors = theme_colors()
    if colors is None:
        return 0
    css = render_css(colors)
    if css is None:
        return 0
    changed = publish_css(css)
    wire_all_profiles()
    if changed:
        restart_zen()
    return 0


if __name__ == "__main__":
    sys.exit(main())
